extends VehicleModule
## Rotor flight: the Heli's drive handler FUN_0040e0e0 (document 63), with its start-up (document 79) and its landing at
## the pad (the special handler 0x40eb00 at record +0x258; document 86), since all three drive the same rotor state.
##  - the speed changes like the ground vehicles' (accelerate, brake, friction; record +0x168..0x174) but there is no
##    terrain factor; the heading turns by an angular velocity `heli_omega` (steps of 5.625 degrees per tick) that follows
##    +-turn rate (record +0x178) at `turn_up` per tick per tick when it is building up and `turn_down` when it is slowing
##    or reversing (0x445498 / 0x44549c);
##  - the flight direction is the heading rounded down to one of 64 steps; two more keys strafe sideways at `strafe` units
##    a tick (only while not turning), and the velocity the vehicle actually moves with follows the sum of those at
##    `velocity_rate` units per tick per tick (state +0x98 / +0x9c);
##  - it climbs `climb` a tick to `ceiling` and stays there;
##  - it banks (state +0x88) toward +-`bank_steps` while turning or strafing, at `bank_rise` a tick and back at
##    `bank_fall`, the turn bank scaled by the speed below 1.0 (none while hovering); its nose pitch (obj +0x70) is 1.5 x
##    its speed in steps (Vehicle.pitch_deg). Both tilt the drawing (FUN_0041b590; document 63).
## Start-up (document 79): every time the vehicle is created the record's state handler runs first: FUN_0040e8c0 accumulates
## state+0x58 by `startup_rate_a` a tick (silent) then plays sound 0x44b550 ("Heli") and switches to FUN_0040e930, which
## ramps state+0x84 -- the live rotor's spin -- by `startup_rate_b` a tick to `rotor_full`; only then does flight begin.
## Landing (document 86), the reverse, run by the match once the automatic descent reaches the pad: FUN_0040ecd0 spins the
## rotor down at `startup_rate_b` to `landing_floor` (then "Servo"), and FUN_0040ede0 runs a timer from 1.0 down at
## `startup_rate_a`. The blade's own resting-angle alignment is not reproduced (a port choice).

const SCHEMA := {
	"slot": "drive", "doc": "Rotor flight with start-up and landing (FUN_0040e0e0, FUN_0040e8c0/0040e930, FUN_0040ecd0/0040ede0)",
	"params": {
		"ceiling": {"type": "float", "unit": "units", "default": 50.0, "provenance": "traced:63"},
		"climb": {"type": "float", "unit": "units/tick", "default": 0x8000 / 65536.0, "provenance": "traced:63"},
		"turn_up": {"type": "float", "unit": "steps/tick^2", "default": 0x7ae / 65536.0, "provenance": "traced:63 (0x445498)"},
		"turn_down": {"type": "float", "unit": "steps/tick^2", "default": 0x1eb8 / 65536.0, "provenance": "traced:63 (0x44549c)"},
		"strafe": {"type": "float", "unit": "units/tick", "default": 0xcccc / 65536.0, "provenance": "traced:63"},
		"velocity_rate": {"type": "float", "unit": "units/tick^2", "default": 0x7ae / 65536.0, "provenance": "traced:63"},
		"bank_steps": {"type": "float", "unit": "steps", "default": 3.0, "provenance": "traced:63"},
		"bank_rise": {"type": "float", "unit": "steps/tick", "default": 0x147a / 65536.0, "provenance": "traced:63"},
		"bank_fall": {"type": "float", "unit": "steps/tick", "default": 0x28f4 / 65536.0, "provenance": "traced:63"},
		"startup_rate_a": {"type": "float", "unit": "per tick", "default": 1179.0 / 65536.0, "provenance": "traced:79"},
		"startup_rate_b": {"type": "float", "unit": "steps/tick", "default": 1638.0 / 65536.0, "provenance": "traced:79"},
		"rotor_full": {"type": "float", "unit": "steps/tick", "default": 4.0, "provenance": "traced:63"},
		"landing_floor": {"type": "float", "unit": "steps/tick", "default": 0.5, "provenance": "traced:86"},
	},
	"channels": ["heading_deg", "speed", "position", "z", "bank_steps", "rotor_speed_steps", "heli_spinup_stage", "_heli_spinup_progress"],
}

const TICK_HZ := 62.5
## Weapons and the dock check run before the flight step (FUN_0040e0e0's order), not after it as on the ground.
const WEAPONS_FIRST := true


func start(v: Vehicle) -> void:
	v.heli_spinup_stage = 1
	v._heli_spinup_progress = 0.0
	v.rotor_speed_steps = 0.0


## Stages 1 and 2 of the start-up: grounded and still, no weapons, no dock check (the state handler alone runs). Stage 3,
## the climb, is the flight step's own climb once this reports done. Returns true while it is still running.
func tick_startup(v: Vehicle, delta: float) -> bool:
	if v.heli_spinup_stage == 0:
		return false
	var ticks := delta * TICK_HZ
	if v.heli_spinup_stage == 1:
		v._heli_spinup_progress += f("startup_rate_a") * ticks
		if v._heli_spinup_progress >= 1.0:
			v.heli_spinup_stage = 2
			v.sound_cue.emit("Heli")   # FUN_0040e8c0 -> FUN_0040e930, sound 0x44b550 (document 82)
	else:
		v.rotor_speed_steps = minf(v.rotor_speed_steps + f("startup_rate_b") * ticks, f("rotor_full"))
		if v.rotor_speed_steps >= f("rotor_full"):
			v.heli_spinup_stage = 0
	return true


func landing_rotor(v: Vehicle, delta: float) -> bool:
	var floor_steps := f("landing_floor")
	if v.rotor_speed_steps <= floor_steps:
		return true
	v.rotor_speed_steps = maxf(v.rotor_speed_steps - f("startup_rate_b") * delta * TICK_HZ, floor_steps)
	if v.rotor_speed_steps <= floor_steps:
		v.sound_cue.emit("Servo")
	return false


func landing_gear(v: Vehicle, delta: float) -> bool:
	v.heli_landing_gear_progress = maxf(v.heli_landing_gear_progress - f("startup_rate_a") * delta * TICK_HZ, 0.0)
	return v.heli_landing_gear_progress <= 0.0


func _dir_for(heading: float, offset_steps: int = 0) -> Vector2:
	var idx := floori(fposmod(heading + 90.0, 360.0) / 5.625) + offset_steps
	var h := deg_to_rad(idx * 5.625 - 90.0)
	return Vector2(cos(h), sin(h))


func tick(v: Vehicle, delta: float) -> void:
	var ticks := delta * TICK_HZ
	var controls := v._get_controls()
	var strafe := 0.0
	if not v._debug_drive:
		var ak := v._aim_keys()
		strafe = float(ak[1]) - float(ak[0])
	var thrust := controls.y
	if thrust > 0.0:
		v.speed = minf(v.speed + v.accel * delta, v.max_speed)
	elif thrust < 0.0:
		v.speed = maxf(v.speed - v.brake * delta, -v.reverse_max_speed)
	else:
		v.speed = move_toward(v.speed, 0.0, v.friction * delta)
	# turning, or else strafing
	var bank_max := f("bank_steps")
	var target_omega := 0.0
	var bank_target := 0.0
	var strafe_steps := 0
	var turn := controls.x
	if turn > 0.0:
		target_omega = v.turn_rate_deg / 5.625 / TICK_HZ
		bank_target = -bank_max
	elif turn < 0.0:
		target_omega = -v.turn_rate_deg / 5.625 / TICK_HZ
		bank_target = bank_max
	elif strafe != 0.0:
		strafe_steps = 16 if strafe > 0.0 else -16
		bank_target = -bank_max if strafe > 0.0 else bank_max
	var fast := (target_omega >= 0.0 and v.heli_omega < 1.0 / 65536.0) or (target_omega < 1.0 / 65536.0 and v.heli_omega > 0.0)
	v.heli_omega = move_toward(v.heli_omega, target_omega, (f("turn_down") if fast else f("turn_up")) * ticks)
	v.heading_deg = fposmod(v.heading_deg + v.heli_omega * 5.625 * ticks, 360.0)
	# bank
	var speed_units := v.speed / TICK_HZ
	if bank_target != 0.0 and strafe_steps == 0 and absf(speed_units) < 1.0:
		bank_target *= speed_units
	if bank_target != 0.0:
		v.bank_steps = move_toward(v.bank_steps, bank_target, f("bank_rise") * ticks)
	else:
		v.bank_steps = move_toward(v.bank_steps, 0.0, f("bank_fall") * ticks)
	# velocity toward forward speed plus strafe
	var want := _dir_for(v.heading_deg) * speed_units
	if strafe_steps != 0:
		want += _dir_for(v.heading_deg, strafe_steps) * f("strafe")
	v.heli_vel.x = move_toward(v.heli_vel.x, want.x, f("velocity_rate") * ticks)
	v.heli_vel.y = move_toward(v.heli_vel.y, want.y, f("velocity_rate") * ticks)
	# climb
	if v.z < f("ceiling"):
		v.z = minf(v.z + f("climb") * ticks, f("ceiling"))
	# move (only tall things can stop it, and only while it is low)
	v.moving = v.heli_vel != Vector2.ZERO or v.heli_omega != 0.0
	if v.speed != 0.0:
		v.fuel -= absf(v.speed) * delta / 32.0
		if v.fuel <= 0.0:
			v.fuel = 0.0
			v._die()
			return
	var target := v.position + v.heli_vel * ticks
	if v.blocked_test.is_valid() and v.blocked_test.call(v, target, v.heading_deg):
		return
	v.position = target
