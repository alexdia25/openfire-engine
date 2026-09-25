extends VehicleModule
## A gun (or launcher) that turns and/or elevates before it fires: the Tank's turret and gun (FUN_0040d460, FUN_0040d240,
## FUN_00402dc0; document 64), and the MSV's launcher, which elevates the same way but has no turret keys.
##  - state +0x58 is the turret's angle from the hull's heading (clockwise), free over the full circle; while the turret-left
##    (0x4000) or turret-right (0x8000) input is held it moves `turn_steps` a tick; any other of the bits 0xd000 (0x1000)
##    sends it back to 0; with none of them held it keeps its angle. Shots leave along heading + angle.
##  - state +0x50 is the gun's elevation (raised `raise_deg` at most) and follows state +0x54, its target, at the same rate.
##    The first fire button (level) sets the target 0, the second (raised) sets it to `raise_deg`; a shot needs the gun to be
##    exactly at 0 or at `raise_deg` (the weapon then fires at `raised_pitch_deg`), otherwise the request waits (state +0x60)
##    and is made again the tick the gun arrives. The gun STAYS raised until a level shot is asked for.

const SCHEMA := {
	"slot": "aim", "doc": "Turret and / or gun elevation, firing only at level or fully raised (FUN_0040d460 / FUN_0040d240)",
	"params": {
		"turret": {"type": "bool", "default": true, "provenance": "traced:64", "doc": "The turret keys turn it (the Tank); off, it only elevates (the MSV)"},
		"turn_steps": {"type": "float", "unit": "steps/tick", "default": 0x4ccc / 65536.0, "provenance": "traced:64"},
		"raise_deg": {"type": "float", "unit": "degrees", "default": 25.0, "provenance": "traced:64 (0x3b8e39)"},
		"raised_pitch_deg": {"type": "float", "unit": "degrees", "default": 40.0, "provenance": "traced:64 (DAT_00445484)"},
	},
	"channels": ["turret_deg", "gun_elev_deg"],
}

const TICK_HZ := 62.5


func tick(v: Vehicle, delta: float) -> void:
	var ticks := delta * TICK_HZ
	var step := f("turn_steps") * 5.625 * ticks
	var keys := v._aim_keys() if b("turret") else [false, false, false]
	var left: bool = keys[0]
	var right: bool = keys[1]
	var recentre: bool = keys[2]
	if left != right or recentre:
		if left and not recentre:
			v._turret_target = v.turret_deg - step
		elif right and not recentre:
			v._turret_target = v.turret_deg + step
		else:
			v._turret_target = 0.0
	var d := wrapf(v._turret_target - v.turret_deg, -180.0, 180.0)
	v.turret_deg = fposmod(v.turret_deg + clampf(d, -step, step), 360.0)
	v.gun_elev_deg = move_toward(v.gun_elev_deg, v._gun_target, step)
	if v._fire_pending and v.gun_elev_deg == v._gun_target:
		v._fire_pending = false
		trigger(v, v._gun_target > 0.0)


## One press of a fire button (FUN_0040d240). `raised` is the second button.
func trigger(v: Vehicle, raised: bool) -> void:
	var raise := f("raise_deg")
	v._gun_target = raise if raised else 0.0
	if v.gun_elev_deg != 0.0 and v.gun_elev_deg != raise:
		v._fire_pending = true
		return
	if v.gun_elev_deg != v._gun_target:
		v._fire_pending = true  # the gun has to move first
		return
	if v._fire_cooldown_remaining <= 0.0:
		v._fire_pending = false
		v._fire()


## The pitch a raised shot leaves at (the weapons ask), in degrees up.
func raised_pitch_deg() -> float:
	return f("raised_pitch_deg")
