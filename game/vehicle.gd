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
	hit_poly_local = PackedVector2Array()
	for pt in t["shape"]["poly"]:
		hit_poly_local.append(Vector2(pt[0], pt[1]))
	hp = max_hp
	fuel = fuel_max


## The Tank's gun is traced (documents 45, 52); the Jeep's machine gun (its slot handler FUN_0040df00 ->
## FUN_00415b00) is not, so only the Tank fires.
func fire_enabled() -> bool:
	return vehicle_type == 0 or vehicle_type == 2


## One trigger pull. Tank: FUN_0040d240 (documents 45, 52). MSV: FUN_0040d520 in level fire (document 58): rockets
## (projectile type 8) leave three launcher positions in turn from (x, -8.96, 10.54) in its own frame, 30 ticks
## apart, with a back-blast at (x, +7.53, 11.05); after the third the launcher reloads for 6.0 / 0.15 = 40 ticks
## (FUN_0040d790). The elevated variant (type 9) needs the gun-raise state and is not modelled.
func _fire() -> void:
	var rad := deg_to_rad(heading_deg)
	var fwd := Vector2(cos(rad), sin(rad))
	var right := Vector2(-fwd.y, fwd.x)
	var spec := {"team": team, "heading": heading_deg}
	if vehicle_type == 0:
		_fire_cooldown_remaining = FIRE_COOLDOWN_SEC
		spec["type"] = 0
		spec["position"] = position + fwd * MUZZLE_OFFSET_PX
		spec["z"] = MUZZLE_HEIGHT_PX
		spec["flash"] = {"record": "0x445138", "offset": Vector3(0.0, MUZZLE_OFFSET_PX, MUZZLE_HEIGHT_PX)}
	elif vehicle_type == 2:
		if _salvo_reload > 0.0:
			return
		var x: float = MSV_SALVO_X[_salvo_index]
		_fire_cooldown_remaining = 30.0 / TICK_HZ
		spec["type"] = 8
		spec["position"] = position + fwd * 8.96 + right * x
		spec["z"] = 10.54
		spec["flash"] = {"record": "0x4450d8", "offset": Vector3(x, -7.53, 11.05)}
		_salvo_index += 1
		if _salvo_index >= 3:
			_salvo_index = 0
			_salvo_reload = 40.0
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
func take_damage(damage: float) -> bool:
	if not alive or damage <= armor:
		return false
	hp -= damage - armor
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
	zone_kind = 0
	speed = 0.0
	alive = true


## Port-only convenience (the original picks a vehicle at the base, FUN_0040b400; document 57): become another
## type in place, with that type's numbers and full hit points and fuel.
func set_vehicle_type(t: int) -> void:
	vehicle_type = t
	_apply_type()
	speed = 0.0
	type_changed.emit(self)


func _process(delta: float) -> void:
	if pack == null or _frames.is_empty() or not alive or frozen:
		return

	if _debug_heading != "":
		heading_deg = float(_debug_heading)
		queue_redraw()
		return

	var controls := _get_controls()
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
	if fire_enabled() and _wants_to_fire() and _fire_cooldown_remaining <= 0.0:
		_fire()

	queue_redraw()


## FUN_0040c390: the tile under the vehicle scales its speed caps -- 1.2x on pavement (art ids
## 0x49-0x59 exclusive of both ends' neighbours, i.e. 73..89), else 1.0.
func _terrain_speed_scale() -> float:
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
