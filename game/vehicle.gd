class_name Vehicle
extends Node2D
## Phase 4 step 2: a player-controlled vehicle. Movement constants are the ORIGINAL's, traced
## from RFIRE.BIN (document 45): the Tank type record (0x4456b8) holds max forward speed, max
## reverse speed, acceleration, friction and turn rate at +0x168..+0x178, read by the per-vehicle
## drive function FUN_0040c190. All are per-tick values in 16.16 fixed point; the game's tick is
## one unit of `timeGetTime() >> 4` = 16 ms (62.5 Hz, FUN_00401110) and every step is multiplied by
## the number of ticks elapsed since the last frame, so this is frame-rate independent like the
## original. World units are 1/32 tile = 1 px here. Only the Tank's record is traced; Jeep/MSV/
## Heli values are in their own records and this class (shared by all ground vehicles) still uses
## the Tank's. The 1.2x road speed cap (FUN_0040c390: tile art ids 0x49-0x59, the pavement
## cels) is applied when `level` is set. Not modelled yet: the 0.25/0.75x cap for vehicles whose
## state +0x70 is set (looks like "in water"; what sets it is untraced), auto-steer.
##
## Phase 4 step 6: also the base class for game/enemy_vehicle.gd's EnemyVehicle --
## _get_controls()/_wants_to_fire() are the seam a non-player controller overrides,
## everything else (movement integration, rendering, firing) is shared.
##
## Rendering is also a deliberate simplification of section 1.10/2.2's finding that the
## original does real perspective-projected-quad rendering across 64 discrete headings.
## This uses the 8-9 real rotation frames per team (cels 218-240) covering one quarter
## turn, mirrored into the other three quadrants -- a flat-rotation approximation
## (section 2.2's "knowingly accept a simpler visual target" option), not the projected-
## quad technique. Good enough to prove movement; revisit for visual fidelity later.

const TICK_HZ := 62.5  ## 1000 ms / 16 ms (timeGetTime() >> 4)
const MAX_SPEED := 1.05 * TICK_HZ           ## 0x10ccc/65536 units/tick = 65.6 px/s (~2 tiles/s)
const ACCEL := 0.05 * TICK_HZ * TICK_HZ     ## 0x0ccc/65536 units/tick^2 (also used for braking)
const BRAKE := ACCEL
const REVERSE_MAX_SPEED := 0.4 * TICK_HZ    ## 0xffff999a = -0.4 units/tick
const FRICTION := 0.025 * TICK_HZ * TICK_HZ ## 0x0666/65536 units/tick^2 when no throttle
## Heading is 22-bit: 0x400000 = 360 deg = 64 steps of 5.625 deg; the Tank turns 0.25 step/tick.
const ROAD_SPEED_SCALE := 1.2  ## 0x13333/65536
const TURN_RATE_DEG := 0.25 * 5.625 * TICK_HZ  ## 87.9 deg/s

## Phase 4 step 4: firing. The Tank's cooldown is traced (weapon slot at record +0x194, +0x10 =
## 20 ticks = 0.32 s; FUN_0040d240 -- document 45). Ammo (150 rounds, refilled on rearm tiles)
## is not modelled; the muzzle offset is traced (below).
const FIRE_COOLDOWN_SEC := 20.0 / TICK_HZ
## Muzzle position, traced (document 52): FUN_0040d240 builds it with FUN_00402bf0 from the point
## (0, -6.75, 0) rotated by the gun's pitch about the pivot (0, -5.25, 7): at level fire 12 units
## in front of the vehicle's centre (the hull's front edge) and 7 units up.
const MUZZLE_OFFSET_PX := 12.0
const MUZZLE_HEIGHT_PX := 7.0

## Hit points and armour, traced (document 47): the Tank record's `+0x28` = 22.0 is its hit points
## and `+0x24` = 0.3 its armour; FUN_0040c460 ignores a hit whose damage does not exceed the armour
## and otherwise subtracts (damage - armour). At zero the original spawns a wreck object; here the
## vehicle just stops (`alive = false`). Its collision shape is traced (document 53): a convex polygon
## 15 wide and 22.5 long (+-7.5 x +-11.25 about the centre, turned with the heading), z 0 to 10,
## layer 2, mask 0x27.
const MAX_HP := 22.0
const ARMOR := 0.3
const HIT_HALF_WIDTH := 7.5
const HIT_HALF_LENGTH := 11.25
const HIT_Z := [0.0, 10.0]
const HIT_LAYER := 2
const HIT_MASK := 0x27

## One shot leaving a weapon: {type: projectile type, position: Vector2 (world, xy), z: height, heading: degrees,
## team: String, flash: {record: String, offset: Vector3 (x right, y forward, z up, world units)}}.
signal shot(spec: Dictionary)
## The MSV lays a mine at this world position (document 60).
signal mine_dropped(position: Vector2)
## A trigger pull with the weapon slot empty (FUN_004232d0 with sound 0x44b988, "the empty click"; documents 61, 63, 72). See also `sound_cue`.
signal empty_click()
## Fired at a traced sound-cue trigger point (document 82); `id` is a key of tools/data/sound_cues.json / packs/*/audio/audio.json, e.g. "OutAmmo", "Heli".
signal sound_cue(id: String)
## The player pressed a fire button while standing still on the centre of their base pad (FUN_0040b980 tail, test `state+8 & 0x920`, document 77).
signal dock_requested()
signal destroyed(vehicle: Vehicle)
signal type_changed(vehicle: Vehicle)

@export var pack_path: String = "res://packs/original_pc"
@export var team: String = "tan"  ## "tan" or "green" -- section 4 item 5

var pack: Pack
var level: LevelData  ## optional: enables the terrain speed scale
var _frames: Array[String] = []
var heading_deg: float = 0.0  ## 0 = facing +X (screen right), increases clockwise
var speed: float = 0.0
var _fire_cooldown_remaining: float = 0.0
const MINE_COOLDOWN_SEC := 140.0 / TICK_HZ
var _mine_cooldown_remaining := 0.0
var _debug_mine: bool = OS.get_environment("RF_DEBUG_MINE") == "1"
const MSV_SALVO_X := [-1.5, 0.0, 1.5]
var _salvo_index := 0
var _salvo_reload := 0.0
var hp: float = MAX_HP
## Per-type values, from tools/data/vehicle_types.json (document 57); the constants above are the Tank's and
## remain the defaults when no pack data exists.
var max_speed := MAX_SPEED
var reverse_max_speed := REVERSE_MAX_SPEED
var accel := ACCEL
var brake := BRAKE
var friction := FRICTION
var turn_rate_deg := TURN_RATE_DEG
var max_hp := MAX_HP
var armor := ARMOR
var fuel_max := FUEL_MAX
## Ammunition of the two weapon slots (state +0x30 and +0x40, document 72) and what each starts with (record +0x1a8 / +0x1dc): Tank 150 / 0,
## Jeep 16 / 0, MSV 100 rockets / 10 mines, Heli 100 / 50. One is spent per shot; the rearm zone refills it (`rearm`).
var ammo: Array[int] = [0, 0]
var ammo_max: Array[int] = [0, 0]
var weapon_cooldown_ticks: Array[int] = [20, 0]
## PLACEHOLDER (not traced): the enemy placeholder vehicles fire without limit, since nothing rearms them.
var infinite_ammo := false
var _rearm_acc := 0.0
## Set by the match controller: (Vehicle) -> bool, true when this vehicle stands still on its own pad within the type's tolerance of the tile centre.
var dock_check := Callable()
## The vehicle is inside the base (docked, or the dock object is sinking): not drawn.
var docked := false
## The MSV's mine layer works only with two players: FUN_0040d820 starts with `if ((keys & 0x60) != 0 && 1 < DAT_00442fbc)` (document 75). The controller sets
## this from its player count (1 today); RF_DEBUG_MINES=1 forces it on for testing.
var mine_layer_enabled := OS.get_environment("RF_DEBUG_MINES") == "1"
var hit_half_width := HIT_HALF_WIDTH
var hit_half_length := HIT_HALF_LENGTH
var hit_z: Array = HIT_Z
var hit_poly_local: PackedVector2Array = PackedVector2Array()
## Vehicle type index in the original's table (0 Tank, 1 Jeep, 2 MSV, 3 Heli): tile callbacks treat the Jeep
## differently (document 54). Only the Tank is played here.
var vehicle_type := 0
## Fuel, traced (document 55): the Tank starts with 400 (record +0x210) and burns |speed| x dt / 32 each tick it
## moves (one unit per 32 world units driven, even when blocked); at 0 it is destroyed like at 0 hit points.
## It is refilled 0.5 per tick while the vehicle stands still over a refuel zone.
const FUEL_MAX := 400.0
const REFUEL_PER_TICK := 0.5
var fuel: float = FUEL_MAX
## FUN_0040b980's panel tick (2026-09-22): plays FuelWarn (0x44b688) on a 120-tick cooldown while
## fuel is below `fuel_max >> 3` -- the traced comparison is `fuel_max << 13` against the raw
## 16.16 fuel value, which is exactly `(fuel_max << 16) / 8`, i.e. one eighth of a full tank.
var _fuel_warn_ticks := 0.0
var moving := false  ## FUN_0040b980's flag: speed != 0 or the heading changed this tick
var zone_kind := 0   ## kind (b9) of the zone shape the last collision test entered: 1 refuel, 2 rearm, 3 pick-up
var zone_origin := Vector2.ZERO
var zone_tile := Vector2i.ZERO
var zone_box: Array = []
## Set by the match: Callable(vehicle, position, heading_deg) -> bool, true when the vehicle's shape would
## overlap something solid there (document 54). Null = no collision.
var blocked_test: Callable = Callable()
var alive: bool = true
var frozen := false  ## the match is over: no input, no movement


func setup(shared_pack: Pack) -> void:
	pack = shared_pack
	_apply_type()
	var prefix := "vehicle.hovercraft.rotation.%s." % team
	for id in pack.sprites.keys():
		if id.begins_with(prefix):
			_frames.append(id)
	_frames.sort()


## Debug-only: RF_DEBUG_DRIVE=1 replaces real input with a fixed forward+turn
## sequence, so headless/automated runs can verify movement actually works without
## a keyboard. Never affects a normal run (env var unset).
var _debug_drive: bool = OS.get_environment("RF_DEBUG_DRIVE") == "1"


## Debug-only: RF_DEBUG_HEADING pins heading_deg to a fixed value every frame (speed
## stays 0) so specific angles can be screenshotted directly, without depending on
## drive-simulation timing. Never affects a normal run (env var unset).
var _debug_heading: String = OS.get_environment("RF_DEBUG_HEADING")


## Debug-only: RF_DEBUG_FIRE=1 fires every cooldown tick regardless of real input, so
## headless/automated runs can verify projectile spawning without a keyboard. Never
## affects a normal run (env var unset).
var _debug_fire: bool = OS.get_environment("RF_DEBUG_FIRE") == "1"


## Overridable so a non-player controller (EnemyVehicle) can drive this same movement/
## rendering/firing code with its own decision logic instead of real input -- the default
## here is exactly what step 2 always did: RF_DEBUG_DRIVE, else real player input.
## Returns (turn, thrust), both in [-1, 1], same meaning as Input.get_axis.
func _get_controls() -> Vector2:
	var turn := 0.0
	if _debug_drive:
		var turn_env := OS.get_environment("RF_DEBUG_DRIVE_TURN")
		turn = float(turn_env) if turn_env != "" else -1.0
	else:
		turn = Input.get_axis("ui_left", "ui_right")
	var thrust := 1.0 if _debug_drive else Input.get_axis("ui_down", "ui_up")
	return Vector2(turn, thrust)


## Overridable the same way _get_controls() is -- default is step 4's real-input-or-debug
## behaviour.
func _wants_mine() -> bool:
	return _debug_mine or Input.is_key_pressed(KEY_M)


## The MSV's mine layer (record slot 1, handler FUN_0040d820; document 60): one mine every 140 ticks, placed at
## (x + dirx * 0, y + diry * 5.0) where (dirx, diry) is the unit heading vector and 0 / 5.0 are the slot's two offset
## fields at +4 / +8. As coded that moves it only along y (in front of a north- or south-facing vehicle, on top of
## an east- or west-facing one). Not modelled: the ammo (10), the deep-water refusal (FUN_0042f410 == 2; water is
## untraced) and the key bits (the original reads button C, here `M`).
func _drop_mine() -> void:
	var rad := deg_to_rad(heading_deg)
	var at := position + Vector2(0.0, sin(rad) * 5.0)
	# FUN_0040d820 / FUN_00409e30: no mine while the vehicle's water state or the drop point is deep water (2)
	if water_class == 2 or (level != null and pack != null and Water.class_at(level, pack, at) == 2):
		return
	if ammo[1] < 1 and not infinite_ammo:   # FUN_0040d820: `st[+0xc] > 0` is a condition, there is no click
		return
	if not infinite_ammo:
		ammo[1] -= 1
	_mine_cooldown_remaining = MINE_COOLDOWN_SEC
	mine_dropped.emit(at)


## FUN_0040b980: when the vehicle stands still on its pad, any of the three fire buttons (bits 0x20, 0x100, 0x800 of the input word) docks it and the
## weapon dispatch is skipped for the tick (document 77).
func _dock_pressed() -> bool:
	if not dock_check.is_valid():
		return false
	var buttons := _wants_to_fire() or _wants_raised() or (vehicle_type == 2 and _wants_mine())
	if buttons and dock_check.call(self):
		dock_requested.emit()
		return true
	return false


func _wants_to_fire() -> bool:
	return _debug_fire or Input.is_action_pressed("ui_accept")


## Loads this vehicle's traced numbers (speed, acceleration, friction, turn rate, hit points, armour, fuel, the
## collision polygon and its height) from the pack's vehicle table.
func _apply_type() -> void:
	var t: Dictionary = pack.vehicle_types.get(str(vehicle_type), {})
	if t.is_empty():
		return
	max_speed = float(t["max_forward_per_tick"]) * TICK_HZ
	reverse_max_speed = -float(t["max_reverse_per_tick"]) * TICK_HZ
	accel = float(t["accel_per_tick2"]) * TICK_HZ * TICK_HZ
	brake = accel
	friction = float(t["friction_per_tick2"]) * TICK_HZ * TICK_HZ
	turn_rate_deg = float(t["turn_steps_per_tick"]) * 5.625 * TICK_HZ
	max_hp = float(t["hit_points"])
	armor = float(t["armor"])
	fuel_max = float(t["fuel"])
	hit_z = [float(t["shape"]["z"][0]), float(t["shape"]["z"][1])]
	sink_depth = float(t.get("sink_depth", 14.0))
	hit_poly_local = PackedVector2Array()
	for pt in t["shape"]["poly"]:
		hit_poly_local.append(Vector2(pt[0], pt[1]))
	hp = max_hp
	fuel = fuel_max
	var am: Array = t.get("ammo", [0, 0])
	var cd: Array = t.get("weapon_cooldown_ticks", [20, 0])
	for i in 2:
		ammo_max[i] = int(am[i])
		ammo[i] = ammo_max[i]
		weapon_cooldown_ticks[i] = int(cd[i])
	if vehicle_type == 3:
		_start_heli_spinup()
		sound_cue.emit("Servo")   # FUN_0040b980's panel-activation block reads a per-type "created" sound from record+0x240 (0x44b808 for the Heli) -- fires at creation, distinct from and earlier than the "Heli" chime at stage 1->2 (document 79)
	else:
		rotor_speed_steps = 0.0
	if vehicle_type == 1:
		sound_cue.emit("JeepStart")   # same record+0x240 mechanism, 0x44b910 for the Jeep; document 82


## Spends one round of `slot` (the handlers' `ammo -= 1`). False, with the empty click and the slot's cooldown, when it is empty
## (`if (ammo < 1) { click; ready = now + cooldown; return }`, FUN_0040d240 / 0040d520 / 0040df00 / 0040e600).
func _spend_ammo(slot: int) -> bool:
	if infinite_ammo:
		return true
	if ammo[slot] < 1:
		empty_click.emit()
		sound_cue.emit("OutAmmo")
		return false
	ammo[slot] -= 1
	return true


## FUN_0040c540, kind 2 (document 55, 72): one call per tick over a rearm zone. Each weapon slot in turn gains `max(1, dt / 2)` (dt = whole ticks
## since the last call, 1 here) up to its cap; a slot that reaches its cap passes the same tick's gain on to the next one.
## Also plays the looping sound every 40 ticks while in the zone (document 72's "Ding", document 82) -- the phase is not
## reset on leaving/re-entering a zone, since that lifecycle detail isn't traced either way.
var _rearm_sound_ticks := 0.0
func rearm(delta: float) -> void:
	_rearm_acc += delta * TICK_HZ
	while _rearm_acc >= 1.0:
		_rearm_acc -= 1.0
		for i in 2:
			if ammo_max[i] <= 0:
				break
			ammo[i] += 1
			if ammo[i] < ammo_max[i]:
				break
			ammo[i] = ammo_max[i]
	_rearm_sound_ticks += delta * TICK_HZ
	if _rearm_sound_ticks >= 40.0:
		_rearm_sound_ticks -= 40.0
		sound_cue.emit("Ding")


## The Tank's gun is traced (documents 45, 52); the Jeep's machine gun (its slot handler FUN_0040df00 ->
## FUN_00415b00) is not, so only the Tank fires.
## The Tank's turret and gun elevation (FUN_0040d460, FUN_0040d240, FUN_00402dc0; document 64).
##  - state +0x58 is the turret's angle from the hull's heading (clockwise), free over the full circle; while the turret-left
##    (0x4000) or turret-right (0x8000) input is held it moves 0.3 steps (1.69 degrees) a tick; any other of the bits
##    0xd000 (0x1000) sends it back to 0; with none of them held it keeps its angle. Shots leave along heading + angle.
##  - state +0x50 is the gun's elevation (raised 25 degrees at most) and follows state +0x54, its target, at the same rate.
##    The first fire button (level) sets the target 0, the second (raised) sets it to 25 degrees; a shot needs the gun to be
##    exactly at 0 (pitch 0) or at 25 (pitch 40 degrees up, shell type 0), otherwise the request waits (state +0x60) and is
##    made again the tick the gun arrives. The gun STAYS raised until a level shot is asked for.
const TANK_TURN_STEPS := 0x4ccc / 65536.0     ## 0.3 steps a tick
const TANK_RAISE_DEG := 25.0                  ## 0x3b8e39 = 335 degrees: 25 up
const TANK_RAISED_PITCH_DEG := 40.0           ## DAT_00445484 = 0x38e38f: 40 up
var turret_deg := 0.0
var gun_elev_deg := 0.0
var _turret_target := 0.0
var _gun_target := 0.0
var _fire_pending := false


## Seams a non-player controller overrides (like _get_controls): the turret-left / turret-right / recentre inputs
## (bits 0x4000 / 0x8000 / 0x1000) and the second, raised, fire button.
func _aim_keys() -> Array:
	return [Input.is_key_pressed(KEY_Q), Input.is_key_pressed(KEY_E), Input.is_key_pressed(KEY_R)]


func _wants_raised() -> bool:
	return Input.is_key_pressed(KEY_Z)


## A point (x, y, z), y = minus forward, turned by `a` radians about the lateral axis with the matrix of FUN_0041ae10
## ([1 0 0; 0 c s; 0 -s c] on a row vector): positive is downward.
func _pitch_point(p: Vector3, a: float) -> Vector3:
	return Vector3(p.x, p.y * cos(a) - p.z * sin(a), p.y * sin(a) + p.z * cos(a))


func _tank_tick(delta: float) -> void:
	var ticks := delta * TICK_HZ
	var step := TANK_TURN_STEPS * 5.625 * ticks
	var keys := _aim_keys() if vehicle_type == 0 else [false, false, false]
	var left: bool = keys[0]
	var right: bool = keys[1]
	var recentre: bool = keys[2]
	if left != right or recentre:
		if left and not recentre:
			_turret_target = turret_deg - step
		elif right and not recentre:
			_turret_target = turret_deg + step
		else:
			_turret_target = 0.0
	var d := wrapf(_turret_target - turret_deg, -180.0, 180.0)
	turret_deg = fposmod(turret_deg + clampf(d, -step, step), 360.0)
	gun_elev_deg = move_toward(gun_elev_deg, _gun_target, step)
	if _fire_pending and gun_elev_deg == _gun_target:
		_fire_pending = false
		_tank_trigger(_gun_target > 0.0)


## One press of a fire button (FUN_0040d240). `raised` is the second button.
func _tank_trigger(raised: bool) -> void:
	_gun_target = TANK_RAISE_DEG if raised else 0.0
	if gun_elev_deg != 0.0 and gun_elev_deg != TANK_RAISE_DEG:
		_fire_pending = true
		return
	if gun_elev_deg != _gun_target:
		_fire_pending = true  # the gun has to move first
		return
	if _fire_cooldown_remaining <= 0.0:
		_fire_pending = false
		_fire()


func fire_enabled() -> bool:
	return vehicle_type == 0 or vehicle_type == 1 or vehicle_type == 2


## Set by the match controller: (Vehicle) -> Vector2, the point the Jeep missile is lobbed at.
var aim_target := Callable()
## The last tile that blocked this vehicle (state +0xa4, set by FUN_0040c130); the Jeep missile aims at it if it is
## still destructible and within 61.2 units.
var last_blocked_tile := Vector2i(-1, -1)


## FUN_00415b00's fallback when there is nothing to aim at: a point 48-62 units away along the heading turned by
## -4..+3 steps of 5.625 degrees (FUN_0041d3d0(8) and FUN_0041d3d0(15) are random 0..7 and 0..14).
func random_aim_point() -> Vector2:
	var step := floori(fposmod(heading_deg + 90.0, 360.0) / 5.625) + randi_range(0, 7) - 4
	var h := deg_to_rad(step * 5.625 - 90.0)
	return position + Vector2(cos(h), sin(h)) * float(0x30 + randi_range(0, 14))


## Rockets fired in the current salvo (0-2): the original's state +0x58 (document 59), which the MSV's draw uses.
func salvo_index() -> int:
	return _salvo_index


## Ticks left of the launcher reload (40 down to 0).
func salvo_reload_remaining() -> float:
	return _salvo_reload


## One trigger pull. Tank: FUN_0040d240 (documents 45, 52). MSV: FUN_0040d520 in level fire (document 58): rockets
## (projectile type 8) leave three launcher positions in turn from (x, -8.96, 10.54) in its own frame, 30 ticks
## apart, with a back-blast at (x, +7.53, 11.05); after the third the launcher reloads for 6.0 / 0.15 = 40 ticks
## (FUN_0040d790). The elevated variant (type 9) needs the gun-raise state and is not modelled.
func _fire() -> void:
	var rad := deg_to_rad(heading_deg)
	var fwd := Vector2(cos(rad), sin(rad))
	var right := Vector2(-fwd.y, fwd.x)
	var spec := {"team": team, "heading": heading_deg}
	if vehicle_type == 2 and _salvo_reload > 0.0:
		return
	if not _spend_ammo(0):
		_fire_cooldown_remaining = float(weapon_cooldown_ticks[0]) / TICK_HZ   # ready = now + the slot's cooldown
		return
	if vehicle_type == 0:
		_fire_cooldown_remaining = FIRE_COOLDOWN_SEC
		sound_cue.emit("Cannon")   # FUN_0040d240, document 64/82: the Tank's turret fire
		# FUN_0040d240 (document 64): the shot goes along the hull heading plus the turret angle (state +0x58). The muzzle is
		# the point (0, -6.75, 0) turned by the shot's pitch (a raised gun: -40 degrees, i.e. 40 degrees up) plus (0, -5.25, 7).
		var h := heading_deg + turret_deg
		var hr := deg_to_rad(h)
		var shot_fwd := Vector2(cos(hr), sin(hr))
		var raised := gun_elev_deg > 0.0
		var reach := 12.0
		var height := MUZZLE_HEIGHT_PX
		if raised:
			var pr := deg_to_rad(TANK_RAISED_PITCH_DEG)
			reach = 6.75 * cos(pr) + 5.25
			height = 6.75 * sin(pr) + 7.0
			spec["pitch_deg"] = -TANK_RAISED_PITCH_DEG
		spec["heading"] = h
		spec["type"] = 0
		spec["position"] = position + shot_fwd * reach
		spec["z"] = height + z
		spec["flash"] = {"record": "0x445138", "yaw": turret_deg,
				"offset": Vector3(reach * sin(deg_to_rad(turret_deg)), reach * cos(deg_to_rad(turret_deg)), height + z)}
	elif vehicle_type == 2:
		var x: float = MSV_SALVO_X[_salvo_index]
		_fire_cooldown_remaining = 30.0 / TICK_HZ
		# FUN_0040d520 (document 64): the two points (0, -15, -1) (rocket) and (0, 1.5, -1) (back-blast) are turned by the
		# shot's pitch (level: 1.744 degrees down; raised: 40 degrees up), then the salvo's offset (x, 6, 12) is added.
		# The rocket type is 8, or 9 when raised; FUN_00415480 then turns its (x, y, 0) by the pitch's TABLE row (a step of
		# 5.625 degrees, -45 for the raised gun) and adds the height again, so the raised rocket leaves from (x, 4.3 ahead, 25.2).
		var raised := gun_elev_deg > 0.0
		var a := deg_to_rad(-TANK_RAISED_PITCH_DEG if raised else 1.744)
		var p0 := _pitch_point(Vector3(0.0, -15.0, -1.0), a) + Vector3(x, 6.0, 12.0)
		var p1 := _pitch_point(Vector3(0.0, 1.5, -1.0), a) + Vector3(x, 6.0, 12.0)
		var launch_y := p0.y
		var launch_z := p0.z
		if raised:
			var row := deg_to_rad(-45.0)  # table row 56 (0x38e38f >> 16)
			launch_z = p0.y * sin(row) + p0.z
			launch_y = p0.y * cos(row)
			spec["pitch_deg"] = -TANK_RAISED_PITCH_DEG
		spec["type"] = 9 if raised else 8
		spec["position"] = position + fwd * -launch_y + right * x
		spec["z"] = launch_z + z
		spec["flash"] = {"record": "0x4450d8", "offset": Vector3(x, -p1.y, p1.z + z)}
		_salvo_index += 1
		if _salvo_index >= 3 or ammo[0] < 1:   # the last rocket of the stock also starts the reload (FUN_0040d520)
			_salvo_index = 0
			_salvo_reload = 40.0
	elif vehicle_type == 1:
		# FUN_0040df00 / FUN_00415b00 / FUN_004159a0 (document 61): a lobbed missile from the vehicle's own position,
		# 5 units up, every 30 ticks; the target point comes from FUN_00415b00's rules (the controller's aim_target).
		_fire_cooldown_remaining = 30.0 / TICK_HZ
		spec["kind"] = "missile"
		spec["type"] = -1
		spec["position"] = position
		spec["z"] = 5.0
		spec["target"] = aim_target.call(self) if aim_target.is_valid() else random_aim_point()
	shot.emit(spec)
	if _debug_fire:
		print("frame=%d shot %s" % [Engine.get_process_frames(), spec])



## FUN_0040b980's movement step (document 54). The turn is already applied to `heading_deg` and the speed
## updated; the displacement is speed x the new heading. Standing still, a turn that would overlap something
## is undone. Moving, if the new place overlaps: undo the turn and try the same displacement with the old
## heading; if that also overlaps, do not move and bounce back at a quarter of the speed (-speed >> 2).
func _move(heading_before: float, delta: float) -> void:
	moving = speed != 0.0 or heading_deg != heading_before
	if speed != 0.0:
		fuel -= absf(speed) * delta / 32.0
		if fuel <= 0.0:
			fuel = 0.0
			if alive:
				alive = false
				destroyed.emit(self)
			return
	var rad := deg_to_rad(heading_deg)
	var step := Vector2(cos(rad), sin(rad)) * speed * delta
	var target := position + step
	if not blocked_test.is_valid():
		position = target
		return
	if speed == 0.0:
		if heading_deg != heading_before and blocked_test.call(self, position, heading_deg):
			heading_deg = heading_before
		return
	if not blocked_test.call(self, target, heading_deg):
		position = target
		return
	if heading_deg != heading_before and not blocked_test.call(self, target, heading_before):
		heading_deg = heading_before
		position = target
		return
	heading_deg = heading_before
	speed = -speed * 0.25


## FUN_0040c460: returns true if the hit did anything.
## Water (document 62). `water_class` is FUN_0042f280's answer for the tile under the vehicle (0 land, 1 shallow,
## 2 deep), recomputed every frame. A vehicle in deep water sinks (`z` falls 0.4 a tick from 0) and is lost when it
## is deeper than `sink_depth` (record +0x158: 14 units, the Jeep 13) unless it is a Jeep in swim mode; in shallow
## water or on land it comes back up. The Jeep's swim mode is the flag `swim_target` (state +0x84, 0 or 1) that
## `swim_amount` (state +0x80) follows at 1092/65536 a tick, about one second; while they differ it cannot
## accelerate or turn (FUN_0040d990).
signal drowned(vehicle: Vehicle)
var z := 0.0
var water_class := 0
var swim_target := 0.0
var swim_amount := 0.0
var sink_depth := 14.0
var _sinking := false
const SWIM_RAMP_PER_TICK := 1092.0 / 65536.0
const SINK_PER_TICK := 0x6666 / 65536.0  ## 0.4


## FUN_0040dfe0, the Jeep's second button: enter swim mode while in water (either kind) and not yet swimming; leave
## it when not in deep water. Anything else does nothing.
func toggle_swim() -> void:
	if vehicle_type != 1 or not alive:
		return
	if water_class != 0 and swim_target == 0.0:
		swim_target = 1.0
	elif water_class != 2 and swim_target == 1.0:
		swim_target = 0.0


## FUN_0040b980, the panel tick: `if (fuel_max << 13 > fuel) and now >= next_allowed_tick: play FuelWarn; next_allowed_tick = now + 120`.
## `fuel_max << 13` is `(fuel_max << 16) / 8`, so this is a plain one-eighth-of-a-tank threshold, not a per-type fraction.
func _process_fuel_warn(delta: float) -> void:
	_fuel_warn_ticks = maxf(_fuel_warn_ticks - delta * TICK_HZ, 0.0)
	if fuel < fuel_max / 8.0 and _fuel_warn_ticks <= 0.0:
		_fuel_warn_ticks = 120.0
		sound_cue.emit("FuelWarn")


func _update_water(delta: float) -> void:
	if level == null or pack == null:
		return
	if vehicle_type == 3:
		water_class = 0  # the Heli's record has no water handler (+0x4c is 0): FUN_0042f280 is never asked for it
		return
	var ticks := delta * TICK_HZ
	var _water_class_before := water_class
	water_class = Water.class_at(level, pack, position, hit_polygon(), z)
	if _water_class_before == 0 and water_class != 0:
		sound_cue.emit("TireIn")   # PORT CHOICE, untraced trigger: Sound/Tirein.SDT on the land->water transition (document 82)
	elif _water_class_before != 0 and water_class == 0:
		sound_cue.emit("TireOut")  # PORT CHOICE, untraced trigger: Sound/Tireout.SDT on the water->land transition (document 82)
	if swim_amount != swim_target:
		swim_amount = move_toward(swim_amount, swim_target, SWIM_RAMP_PER_TICK * ticks)
	var swimming := vehicle_type == 1 and swim_target == 1.0
	if not _sinking:
		if water_class == 2 and not swimming:
			_sinking = true
		return
	if water_class == 0:
		_sinking = false
		z = 0.0
	elif water_class == 1 or swimming:
		z += SINK_PER_TICK * ticks
		if z >= 0.0:
			z = 0.0
			_sinking = false
	else:
		z -= SINK_PER_TICK * ticks
		if floorf(z) <= -floorf(sink_depth):
			z = 1.0 - sink_depth
			alive = false
			_sinking = false
			drowned.emit(self)


## After a hit the original draws the vehicle in variant 2 (the "yellow" cels) until `state+0x4c` = hit tick + 10
## runs out (documents 47, 59).
const HIT_FLASH_SEC := 10.0 / TICK_HZ
var hit_flash_remaining := 0.0


func flashing() -> bool:
	return hit_flash_remaining > 0.0


func take_damage(damage: float) -> bool:
	if not alive or damage <= armor:
		return false
	hp -= damage - armor
	hit_flash_remaining = HIT_FLASH_SEC
	if hp <= 0.0:
		alive = false
		destroyed.emit(self)
	return true


## The collision polygon in world coordinates (the Tank's shape at 0x43e8f8).
func hit_polygon() -> PackedVector2Array:
	return polygon_for(position, heading_deg)


## The collision polygon at `at` / `heading`: the type's shape (the Tank's is at 0x43e8f8, document 53) with its
## y axis pointing along the heading (forward is -y in the original's shape coordinates).
func polygon_for(at: Vector2, heading: float) -> PackedVector2Array:
	var rad := deg_to_rad(heading)
	var fwd := Vector2(cos(rad), sin(rad))
	var right := Vector2(-fwd.y, fwd.x)
	var out := PackedVector2Array()
	if hit_poly_local.is_empty():
		for c in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2(1, -1)]:
			out.append(at + fwd * (c.x * hit_half_length) + right * (c.y * hit_half_width))
		return out
	for pt in hit_poly_local:
		# local (x lateral, y forward-negative): forward is -y, so world = at + fwd * (-y) + right * x
		out.append(at + fwd * -pt.y + right * pt.x)
	return out


static func polygon_at(at: Vector2, heading: float) -> PackedVector2Array:
	var rad := deg_to_rad(heading)
	var fwd := Vector2(cos(rad), sin(rad))
	var right := Vector2(-fwd.y, fwd.x)
	return PackedVector2Array([
		at + fwd * -HIT_HALF_LENGTH + right * -HIT_HALF_WIDTH,
		at + fwd * -HIT_HALF_LENGTH + right * HIT_HALF_WIDTH,
		at + fwd * HIT_HALF_LENGTH + right * HIT_HALF_WIDTH,
		at + fwd * HIT_HALF_LENGTH + right * -HIT_HALF_WIDTH,
	])


## The player index of the original (0 tan, 1 green): compared with a tile's variant bits by pick-ups.
func player_index() -> int:
	return 0 if team == "tan" else 1


func respawn(at: Vector2) -> void:
	position = at
	hp = max_hp
	fuel = fuel_max
	for i in 2:
		ammo[i] = ammo_max[i]
	zone_kind = 0
	speed = 0.0
	_reset_water()
	if vehicle_type == 3:
		_start_heli_spinup()
	alive = true


## Port-only convenience (the original picks a vehicle at the base, FUN_0040b400; document 57): become another
## type in place, with that type's numbers and full hit points and fuel.
func _reset_water() -> void:
	turret_deg = 0.0
	gun_elev_deg = 0.0
	_turret_target = 0.0
	_gun_target = 0.0
	_fire_pending = false
	heli_omega = 0.0
	heli_vel = Vector2.ZERO
	bank_steps = 0.0
	z = 0.0
	water_class = 0
	swim_target = 0.0
	swim_amount = 0.0
	_sinking = false


func set_vehicle_type(t: int) -> void:
	vehicle_type = t
	_apply_type()
	speed = 0.0
	_reset_water()
	_salvo_index = 0
	_salvo_reload = 0.0
	_fire_cooldown_remaining = 0.0
	_mine_cooldown_remaining = 0.0
	hit_flash_remaining = 0.0
	type_changed.emit(self)


func _process(delta: float) -> void:
	hit_flash_remaining = maxf(hit_flash_remaining - delta, 0.0)
	if alive:
		_update_water(delta)
	if pack == null or _frames.is_empty() or not alive or frozen:
		return
	_process_fuel_warn(delta)

	if _debug_heading != "":
		heading_deg = float(_debug_heading)
		queue_redraw()
		return

	if vehicle_type == 3:
		_process_heli(delta)
		queue_redraw()
		return

	var controls := _get_controls()
	if vehicle_type == 1 and controls.y == 0.0 and controls.x != 0.0:
		# the Jeep's own drive handler (FUN_0040db80, document 62): turning without a throttle key accelerates
		controls.y = 1.0
	var turn := controls.x
	var turn_before := heading_deg
	heading_deg = fposmod(heading_deg + turn * turn_rate_deg * delta, 360.0)

	var thrust := controls.y
	var terrain_scale := _terrain_speed_scale()
	if thrust > 0.0:
		speed = minf(speed + accel * delta, max_speed * terrain_scale)
	elif thrust < 0.0:
		speed = maxf(speed - brake * delta, -reverse_max_speed * terrain_scale)
	else:
		speed = move_toward(speed, 0.0, friction * delta)

	_move(turn_before, delta)

	_fire_cooldown_remaining = maxf(_fire_cooldown_remaining - delta, 0.0)
	_salvo_reload = maxf(_salvo_reload - delta * TICK_HZ, 0.0)
	if _dock_pressed():
		queue_redraw()
		return
	if vehicle_type == 0 or vehicle_type == 2:
		_tank_tick(delta)
		if _wants_to_fire():
			_tank_trigger(false)
		elif _wants_raised():
			_tank_trigger(true)
	elif fire_enabled() and _wants_to_fire() and _fire_cooldown_remaining <= 0.0:
		_fire()
	_mine_cooldown_remaining = maxf(_mine_cooldown_remaining - delta, 0.0)
	if vehicle_type == 2 and mine_layer_enabled and _wants_mine() and _mine_cooldown_remaining <= 0.0:
		_drop_mine()

	queue_redraw()


## The Heli (vehicle type 3; its drive handler FUN_0040e0e0, document 63). Flight, as traced:
##  - the speed changes like the ground vehicles' (accelerate, brake, friction; record +0x168..0x174) but there is
##    no terrain factor; the heading turns by an angular velocity `heli_omega` (steps of 5.625 degrees per tick) that
##    follows +-0.75 (record +0x178) at 0.03 per tick per tick when it is building up and 0.12 when it is slowing or
##    reversing (0x445498 / 0x44549c);
##  - the flight direction is the heading rounded down to one of 64 steps; two more keys strafe sideways at 0.8
##    units a tick (only while not turning), and the velocity the vehicle actually moves with follows the sum of
##    those at 0.03 units per tick per tick (state +0x98 / +0x9c);
##  - it climbs 0.5 a tick to a height of 50 and stays there;
##  - it banks (state +0x88) toward +-3 steps while turning or strafing, at 0.02 a tick and back at 0.16, the turn
##    bank scaled by the speed below 1.0 (none while hovering); its nose pitch (obj +0x70) is 1.5 x its speed in
##    steps. Both tilt the drawing (FUN_0041b590; the matrices at 0x458c38 / 0x458c60 make positive pitch dip the nose and
##    a negative bank, the one a right turn sets, lower the right side: traced, document 63).
const HELI_CEILING := 50.0
const HELI_CLIMB_PER_TICK := 0x8000 / 65536.0
const HELI_TURN_UP := 0x7ae / 65536.0
const HELI_TURN_DOWN := 0x1eb8 / 65536.0
const HELI_STRAFE := 0xcccc / 65536.0
const HELI_VEL_RATE := 0x7ae / 65536.0
const HELI_BANK_STEPS := 3.0
const HELI_BANK_RISE := 0x147a / 65536.0
const HELI_BANK_FALL := 0x28f4 / 65536.0
var heli_omega := 0.0            ## heading change, steps per tick
var heli_vel := Vector2.ZERO     ## world velocity, units per tick
var bank_steps := 0.0


## Nose-down tilt in degrees: obj+0x70 = 1.5 x the speed (units per tick), as a count of 5.625-degree steps.
func pitch_deg() -> float:
	return speed / TICK_HZ * 1.5 * 5.625


func bank_deg() -> float:
	return bank_steps * 5.625


func _dir_for(heading: float, offset_steps: int = 0) -> Vector2:
	var idx := floori(fposmod(heading + 90.0, 360.0) / 5.625) + offset_steps
	var h := deg_to_rad(idx * 5.625 - 90.0)
	return Vector2(cos(h), sin(h))


## The Heli's start-up (document 79): every time a Heli object is created (initial spawn, undocking, or this port's in-place respawn) the record's
## state handler runs a short sequence before the drive handler (FUN_0040e0e0) gets normal control: FUN_0040e8c0 accumulates state+0x58 by 1179/65536
## a tick (silent, ~55.6 ticks = 0.89 s) then plays sound 0x44b550 and switches to FUN_0040e930, which ramps state+0x84 -- **the same field that drives
## the live rotor's spin, document 63's "4 steps of 5.625 degrees a tick"** -- from 0 up by 1638/65536 a tick (~160 ticks = 2.56 s) to 4.0; only then
## does FUN_0040e9c0 hand over to the steady per-tick rotor updater FUN_0040eab0 and the climb to hover height (already modelled: HELI_CLIMB_PER_TICK)
## can proceed, since nothing raises state+0x48 (z) before that. So the whole thing is: silence, then the rotor visibly spins up, then it climbs.
const HELI_SPINUP_A_RATE := 1179.0 / 65536.0    ## state+0x58 a tick (stage 1, silent)
const HELI_SPINUP_B_RATE := 1638.0 / 65536.0    ## state+0x84 a tick (stage 2, the rotor ramps up)
var heli_spinup_stage := 0        ## 0 done/flying, 1 blade accel (silent), 2 rotor ramp-up
var _heli_spinup_progress := 0.0  ## stage 1's accumulator (0..1)
var rotor_speed_steps := 4.0      ## the renderer's rotor speed (document 63's constant 4.0), ramped by stage 2


func _start_heli_spinup() -> void:
	heli_spinup_stage = 1
	_heli_spinup_progress = 0.0
	rotor_speed_steps = 0.0


## Stage 1's own accumulator (0..1, state+0x58) -- read by the renderer (document 85 addendum) to
## animate the two folded blades scissoring apart during the silent phase.
func heli_spinup_progress() -> float:
	return _heli_spinup_progress


## The Heli's weapons (FUN_0040e600 and FUN_0040e7a0; document 63). Two slots, picked by `toggle_heli_slot()` (the third
## button): 0 fires projectile type 7 every 15 ticks, 1 type 6 (a ballistic bomb) every 30. Either of two fire buttons
## fires the selected slot from alternating left and right mounts at (+-9.35, 6.8 ahead, 0) of the Heli. The first
## button (`Space`) is the downward one: guns fire 39.4 degrees down (pitch step 7) toed in by 0.5 step, bombs level; the
## second (`Z`) fires level with no toe-in. The launcher's forward speed is added to the shot's. Not modelled: ammo (gun
## 100, bomb 50), the sounds.
const HELI_SLOT_COOLDOWN := [15.0, 30.0]
var _heli_slot := 0
var _heli_mount_left := false
var _heli_ready := [0.0, 0.0]


func toggle_heli_slot() -> void:
	if vehicle_type == 3 and alive:
		_heli_slot = 1 - _heli_slot
		sound_cue.emit("HeliClick")   # FUN_0040e7a0, document 63/82: "toggles bit 28 and plays a sound" (0x44b970)


## Which weapon is currently selected (0 gun, 1 bomb) -- obj+0xc bit 0x10000000 in the original
## (FUN_0040e600/FUN_0040e7a0, document 63), also read by the panel's weapon-select icons (document 83).
func heli_weapon_slot() -> int:
	return _heli_slot


func _heli_weapons(delta: float) -> void:
	for i in 2:
		_heli_ready[i] = maxf(_heli_ready[i] - delta, 0.0)
	if _heli_ready[_heli_slot] > 0.0:
		return
	var down := _debug_fire or Input.is_action_pressed("ui_accept")
	var level := _wants_raised()
	if not (down or level):
		return
	_heli_ready[_heli_slot] = float(HELI_SLOT_COOLDOWN[_heli_slot]) / TICK_HZ
	if not _spend_ammo(_heli_slot):
		return   # the empty click; the cooldown just set keeps it from repeating every frame
	var type := 7 if _heli_slot == 0 else 6
	var mount := Vector2(-9.35 if _heli_mount_left else 9.35, 6.8)  # (x right, y ahead)
	var toe := 0.0
	var pitch := 0.0
	if down:
		toe = 0.5 * 5.625 if _heli_mount_left else -0.5 * 5.625
		pitch = 7.0 * 5.625 if type == 7 else 0.0
	var h := heading_deg + toe
	var rad := deg_to_rad(h)
	var fwd := Vector2(cos(rad), sin(rad))
	var right := Vector2(-fwd.y, fwd.x)
	var spec := {"team": team, "heading": h, "type": type, "z": z,
			"position": position + fwd * mount.y + right * mount.x, "pitch_deg": pitch,
			"bonus": maxf(speed, 0.0) / TICK_HZ}
	if type == 6:
		# the bomb's launch flash, record 0x445168, at the mount's second triple (x, 2.55 ahead, 0)
		spec["flash"] = {"record": "0x445168", "offset": Vector3(mount.x, 2.55, z)}
	_heli_mount_left = not _heli_mount_left
	shot.emit(spec)


## Stages 1 and 2 of the start-up (see above): grounded and still, no weapons, no dock check (the original's state handler alone runs; the drive
## handler FUN_0040e0e0 is not reached). Stage 3 (the climb to hover height) needs nothing extra: `_process_heli`'s own climb runs once this returns
## to 0, and z is already 0 here.
func _process_heli_spinup(delta: float) -> void:
	var ticks := delta * TICK_HZ
	if heli_spinup_stage == 1:
		_heli_spinup_progress += HELI_SPINUP_A_RATE * ticks
		if _heli_spinup_progress >= 1.0:
			heli_spinup_stage = 2
			sound_cue.emit("Heli")   # FUN_0040e8c0 -> FUN_0040e930, sound 0x44b550 (document 82)
	else:
		rotor_speed_steps = minf(rotor_speed_steps + HELI_SPINUP_B_RATE * ticks, 4.0)
		if rotor_speed_steps >= 4.0:
			heli_spinup_stage = 0


func _process_heli(delta: float) -> void:
	if heli_spinup_stage != 0:
		_process_heli_spinup(delta)
		return
	if _dock_pressed():
		return
	_heli_weapons(delta)
	var ticks := delta * TICK_HZ
	var controls := _get_controls()
	var strafe := 0.0
	if not _debug_drive:
		var ak := _aim_keys()
		strafe = float(ak[1]) - float(ak[0])
	var thrust := controls.y
	if thrust > 0.0:
		speed = minf(speed + accel * delta, max_speed)
	elif thrust < 0.0:
		speed = maxf(speed - brake * delta, -reverse_max_speed)
	else:
		speed = move_toward(speed, 0.0, friction * delta)
	# turning, or else strafing
	var target_omega := 0.0
	var bank_target := 0.0
	var strafe_steps := 0
	var turn := controls.x
	if turn > 0.0:
		target_omega = turn_rate_deg / 5.625 / TICK_HZ
		bank_target = -HELI_BANK_STEPS
	elif turn < 0.0:
		target_omega = -turn_rate_deg / 5.625 / TICK_HZ
		bank_target = HELI_BANK_STEPS
	elif strafe != 0.0:
		strafe_steps = 16 if strafe > 0.0 else -16
		bank_target = -HELI_BANK_STEPS if strafe > 0.0 else HELI_BANK_STEPS
	var fast := (target_omega >= 0.0 and heli_omega < 1.0 / 65536.0) or (target_omega < 1.0 / 65536.0 and heli_omega > 0.0)
	heli_omega = move_toward(heli_omega, target_omega, (HELI_TURN_DOWN if fast else HELI_TURN_UP) * ticks)
	heading_deg = fposmod(heading_deg + heli_omega * 5.625 * ticks, 360.0)
	# bank
	var speed_units := speed / TICK_HZ
	if bank_target != 0.0 and strafe_steps == 0 and absf(speed_units) < 1.0:
		bank_target *= speed_units
	if bank_target != 0.0:
		bank_steps = move_toward(bank_steps, bank_target, HELI_BANK_RISE * ticks)
	else:
		bank_steps = move_toward(bank_steps, 0.0, HELI_BANK_FALL * ticks)
	# velocity toward forward speed plus strafe
	var want := _dir_for(heading_deg) * speed_units
	if strafe_steps != 0:
		want += _dir_for(heading_deg, strafe_steps) * HELI_STRAFE
	heli_vel.x = move_toward(heli_vel.x, want.x, HELI_VEL_RATE * ticks)
	heli_vel.y = move_toward(heli_vel.y, want.y, HELI_VEL_RATE * ticks)
	# climb
	if z < HELI_CEILING:
		z = minf(z + HELI_CLIMB_PER_TICK * ticks, HELI_CEILING)
	# move (only tall things can stop it, and only while it is low)
	moving = heli_vel != Vector2.ZERO or heli_omega != 0.0
	if speed != 0.0:
		fuel -= absf(speed) * delta / 32.0
		if fuel <= 0.0:
			fuel = 0.0
			alive = false
			destroyed.emit(self)
			return
	var target := position + heli_vel * ticks
	if blocked_test.is_valid() and blocked_test.call(self, target, heading_deg):
		return
	position = target


## FUN_0040c390: the tile under the vehicle scales its speed caps -- 1.2x on pavement (art ids
## 0x49-0x59 exclusive of both ends' neighbours, i.e. 73..89), else 1.0.
func _terrain_speed_scale() -> float:
	if z > 1.0:
		return 1.0
	if water_class != 0:
		# FUN_0040c390: 0.75 in any water, 0.25 for a Jeep that has finished entering swim mode
		return 0.25 if (vehicle_type == 1 and swim_amount >= 1.0) else 0.75
	if vehicle_type == 1 and swim_amount >= 1.0:
		return 0x28f / 65536.0  # swim mode on dry land: nearly stuck (press the swim button to leave it)
	if level == null or pack == null:
		return 1.0
	var t := Vector2i((position / pack.tile_size_px).floor())
	if t.x < 0 or t.y < 0 or t.x >= level.width or t.y >= level.height:
		return 1.0
	var art := level.get_art_id(t.x, t.y)
	return ROAD_SPEED_SCALE if art > 0x48 and art < 0x5a else 1.0


## Folds any heading into the one real quarter-turn (0-90 deg) this vehicle has actual
## art for, plus the horizontal/vertical mirror needed to reconstruct the other three
## quadrants. Returns [sprite_id, flip_h, flip_v].
##
## The four quadrants must mirror consistently around the two axes -- quadrant 2 is
## quadrant 1 flipped left-right, quadrant 4 is quadrant 1 flipped top-bottom, and
## quadrant 3 (both flips = a 180-degree point reflection) is quadrant 1 turned around.
## An earlier version of this function got that pairing wrong (flipped the *base*
## quadrant unnecessarily and left the last quadrant unflipped), which produced a
## visibly wrong/discontinuous sprite as soon as the vehicle turned far enough to
## cross a quadrant boundary -- exactly the "sprite looks very wrong after moving" bug.
func _frame_for_heading(h: float) -> Array:
	var a := fposmod(h, 360.0)
	var flip_h := false
	var flip_v := false
	var quadrant_angle := a
	if a <= 90.0:
		quadrant_angle = a
	elif a <= 180.0:
		quadrant_angle = 180.0 - a
		flip_h = true
	elif a <= 270.0:
		quadrant_angle = a - 180.0
		flip_h = true
		flip_v = true
	else:
		quadrant_angle = 360.0 - a
		flip_v = true
	var t := quadrant_angle / 90.0
	var idx := int(round(t * (_frames.size() - 1)))
	return [_frames[idx], flip_h, flip_v]


func _draw() -> void:
	if pack == null or _frames.is_empty():
		return
	var result := _frame_for_heading(heading_deg)
	var sprite_id: String = result[0]
	var flip_h: bool = result[1]
	var flip_v: bool = result[2]

	var s := pack.get_sprite(sprite_id)
	if s.is_empty():
		return
	var tex := pack.get_texture(int(s.get("page", 0)))
	if tex == null:
		return
	var w: float = s.get("w", 0)
	var h: float = s.get("h", 0)
	var src := Rect2(s.get("x", 0), s.get("y", 0), w, h)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1.0 if flip_h else 1.0, -1.0 if flip_v else 1.0))
	draw_texture_rect_region(tex, Rect2(-w * 0.5, -h * 0.5, w, h), src)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
