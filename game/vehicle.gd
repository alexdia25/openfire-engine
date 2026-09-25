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
## everything else (movement integration, firing) is shared.
##
## Simulation only: this node draws nothing. The 3D renderers (VehicleBoxRender3D, VehicleRender3D) read it each
## frame; the old flat 2D view and this class's own sprite drawing were removed on 2026-09-24.

const TICK_HZ := 62.5  ## 1000 ms / 16 ms (timeGetTime() >> 4)
const MAX_SPEED := 1.05 * TICK_HZ           ## 0x10ccc/65536 units/tick = 65.6 px/s (~2 tiles/s)
const ACCEL := 0.05 * TICK_HZ * TICK_HZ     ## 0x0ccc/65536 units/tick^2 (also used for braking)
const BRAKE := ACCEL
const REVERSE_MAX_SPEED := 0.4 * TICK_HZ    ## 0xffff999a = -0.4 units/tick
const FRICTION := 0.025 * TICK_HZ * TICK_HZ ## 0x0666/65536 units/tick^2 when no throttle
## Heading is 22-bit: 0x400000 = 360 deg = 64 steps of 5.625 deg; the Tank turns 0.25 step/tick.
const ROAD_SPEED_SCALE := 1.2  ## 0x13333/65536
const TURN_RATE_DEG := 0.25 * 5.625 * TICK_HZ  ## 87.9 deg/s

## Firing, turning the turret, flying, swimming and the rest of each vehicle's own behaviour are behaviour modules
## (game/vehicle_modules/, PORTING_PLAN.md 2.7.2 step 4) that the vehicle definition names; this class holds the state
## they act on (the original's per-player state block) and the parts every vehicle shares.

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
## A snapshot at the exact moment of death (document 87), for spawning the falling wreck: `destroyed`
## itself is unsafe for that when the listener order lets a respawn reset this same node's fields
## (`position`/`z`/etc.) before a later listener reads them, since the player's vehicle is one
## persistent node reused across lives, not a fresh object per life.
signal wrecked(info: Dictionary)
signal type_changed(vehicle: Vehicle)

@export var pack_path: String = "res://packs/original_pc"
@export var team: String = "tan"  ## the side: "tan" (player 0) or "green" (player 1) -- section 4 item 5; game logic keys on this
## The colour the vehicle is drawn in (PORTING_PLAN.md 2.7.7), set by the match from LevelData.side_colours; "" = the side's
## own original colour. Art only: nothing in the simulation reads it.
var colour := ""


func art_colour() -> String:
	return colour if colour != "" else team

var pack: Pack
var level: LevelData  ## optional: enables the terrain speed scale
var heading_deg: float = 0.0  ## 0 = facing +X (screen right), increases clockwise
var speed: float = 0.0
var _fire_cooldown_remaining: float = 0.0
var _mine_cooldown_remaining := 0.0
var _debug_mine: bool = OS.get_environment("RF_DEBUG_MINE") == "1"
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

## The behaviour modules the vehicle definition names (PORTING_PLAN.md 2.7.2, step 4; game/vehicle_modules/): one per slot
## of the original's vehicle-type record. `aim` and `water` may be null (the Jeep has no gun mount; the Heli never asks
## about water); `weapons` is the record's weapon slots in order (slot 0 is the primary, fired through `aim` if there is one).
var drive: VehicleModule
var aim: VehicleModule
var weapons: Array[VehicleModule] = []
var water: VehicleModule


func setup(shared_pack: Pack) -> void:
	pack = shared_pack
	_apply_type()


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


## FUN_0040b980: when the vehicle stands still on its pad, any of the three fire buttons (bits 0x20, 0x100, 0x800 of the input word) docks it and the
## weapon dispatch is skipped for the tick (document 77).
func _dock_pressed() -> bool:
	if not dock_check.is_valid():
		return false
	var buttons := _wants_to_fire() or _wants_raised() or (has_module("mine_layer") and _wants_mine())
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
	_build_modules()
	if drive != null and drive.has_method("start"):
		drive.start(self)   # the record's state handler runs a start-up first (the Heli's rotor, document 79)
	else:
		rotor_speed_steps = 0.0
	# FUN_0040b980's panel-activation block plays the record's "created" sound (+0x240, document 82): the definition's
	# events.on_create.sound -- the Jeep's JeepStart, the Heli's Servo (earlier than its "Heli" chime at stage 1->2,
	# document 79). The Tank's and MSV's descriptor 0x44b520 is not a traced cue, so they stay silent.
	var created: Variant = pack.vehicle_value(vehicle_type, "events.on_create.sound")
	if created != null:
		sound_cue.emit(String(created))


## The modules of the current definition (drive.model, aim.model, weapons.slots[n].handler, water.model, each with its
## parameters over the module's traced defaults).
func _build_modules() -> void:
	var def := pack.vehicle_def(vehicle_type)
	drive = VehicleModules.create(String(def.get("drive", {}).get("model", "ground")), def.get("drive", {}).get("params", {}))
	aim = VehicleModules.create(String(def.get("aim", {}).get("model", "none")), def.get("aim", {}).get("params", {}))
	water = VehicleModules.create(String(def.get("water", {}).get("model", "hull_water")), def.get("water", {}).get("params", {}))
	weapons.clear()
	for slot in def.get("weapons", {}).get("slots", []):
		var w := VehicleModules.create(String(slot.get("handler", "")), slot.get("params", {}))
		if w != null:
			weapons.append(w)


## True if one of the vehicle's modules is `name` (e.g. "mine_layer").
func has_module(name: String) -> bool:
	for m in [drive, aim, water] + weapons:
		if m != null and m.get_script() == VehicleModules.MODULES.get(name):
			return true
	return false


func _module(name: String) -> VehicleModule:
	for m in [drive, aim, water] + weapons:
		if m != null and m.get_script() == VehicleModules.MODULES.get(name):
			return m
	return null


## A raised shot's pitch (degrees up): the gun mount's, or 0 without one.
func raised_pitch_deg() -> float:
	return aim.raised_pitch_deg() if aim != null else 0.0


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


## The gun mount's state (game/vehicle_modules/gun_mount.gd, document 64): the turret's angle from the hull (state +0x58),
## the gun's elevation (+0x50) and its target (+0x54), and a shot waiting for the gun to arrive (+0x60).
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


## Whether the vehicle has a weapon fired by the primary button (not the self-driven kinds, the Heli's guns or a mine layer).
func fire_enabled() -> bool:
	return not weapons.is_empty() and not weapons[0].SELF_DRIVEN


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


## One trigger pull of the primary weapon (the record's slot 0 handler: the cannon, rocket salvo or lobbed missile module).
## An empty slot clicks and sets the slot's cooldown (`if (ammo < 1) { click; ready = now + cooldown; return }`).
func _fire() -> void:
	if weapons.is_empty() or weapons[0].SELF_DRIVEN:
		return
	var w := weapons[0]
	if not w.can_fire(self):
		return
	if not _spend_ammo(0):
		_fire_cooldown_remaining = float(weapon_cooldown_ticks[0]) / TICK_HZ   # ready = now + the slot's cooldown
		return
	var spec := {"team": team, "colour": art_colour(), "heading": heading_deg}
	w.fill_shot(self, spec)
	shot.emit(spec)
	if _debug_fire:
		print("frame=%d shot %s" % [Engine.get_process_frames(), spec])


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


## The second button of a vehicle that can swim (the Jeep, FUN_0040dfe0): toggles swim mode (game/vehicle_modules/hull_water.gd).
func toggle_swim() -> void:
	if water != null and alive:
		water.toggle_swim(self)


## True for a vehicle whose water module can swim (the Jeep).
func _swims() -> bool:
	return water != null and water.b("can_swim")


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
	if water == null:
		water_class = 0  # no water handler (the Heli's +0x4c is 0): FUN_0042f280 is never asked
		return
	water.update(self, delta)


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
		_die()
	return true


## FUN_0040c460's death branch (document 47) always takes the same path regardless of cause (hit
## points or, per document 55's fuel comment, running dry): spawn a wreck object (class `0x4453e8`)
## at the vehicle's own position/height and destroy the vehicle itself at once. `wrecked` carries a
## value snapshot so the wreck's fall (document 87) is unaffected by whatever a `destroyed` listener
## does to this same node afterwards (the player's vehicle respawns in place).
func _die() -> void:
	wrecked.emit({"position": position, "heading_deg": heading_deg, "team": team, "colour": art_colour(), "vehicle_type": vehicle_type, "z": z})
	alive = false
	destroyed.emit(self)


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
	if drive != null and drive.has_method("start"):
		drive.start(self)
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
	if pack == null or not alive or frozen:
		return
	_process_fuel_warn(delta)

	if _debug_heading != "":
		heading_deg = float(_debug_heading)
		return

	if drive == null:
		return
	if drive.has_method("tick_startup") and drive.tick_startup(self, delta):
		return   # the record's state handler runs alone until its start-up is done (the Heli, document 79)
	if drive.get("WEAPONS_FIRST"):
		# the rotor drive handler FUN_0040e0e0: the dock check and the weapons come before the flight step. The shared fire
		# cooldown and salvo reload count down here too: the Heli's own guns keep their own cooldowns and never read them, but a
		# ground weapon on a rotor vehicle (a mod's recombination) needs them to become ready again.
		_fire_cooldown_remaining = maxf(_fire_cooldown_remaining - delta, 0.0)
		_salvo_reload = maxf(_salvo_reload - delta * TICK_HZ, 0.0)
		if _dock_pressed():
			return
		_weapons_tick(delta)
		drive.tick(self, delta)
		return
	drive.tick(self, delta)
	_fire_cooldown_remaining = maxf(_fire_cooldown_remaining - delta, 0.0)
	_salvo_reload = maxf(_salvo_reload - delta * TICK_HZ, 0.0)
	if _dock_pressed():
		return
	_weapons_tick(delta)


## The weapons for one tick: a gun mount turns and elevates and fires the primary weapon when a fire button asks (level or
## raised), else the primary fires straight from the fire button; then the self-driven weapons (the Heli's guns, a mine
## layer) run themselves.
func _weapons_tick(delta: float) -> void:
	if aim != null:
		aim.tick(self, delta)
		if _wants_to_fire():
			aim.trigger(self, false)
		elif _wants_raised():
			aim.trigger(self, true)
	elif fire_enabled() and _wants_to_fire() and _fire_cooldown_remaining <= 0.0:
		_fire()
	for w in weapons:
		if w.SELF_DRIVEN:
			w.tick(self, delta)


## Rotor flight state (game/vehicle_modules/rotor_drive.gd, document 63): angular velocity, velocity, bank (state +0x88).
var heli_omega := 0.0            ## heading change, steps per tick
var heli_vel := Vector2.ZERO     ## world velocity, units per tick
var bank_steps := 0.0


## Nose-down tilt in degrees: obj+0x70 = 1.5 x the speed (units per tick), as a count of 5.625-degree steps.
func pitch_deg() -> float:
	return speed / TICK_HZ * 1.5 * 5.625


func bank_deg() -> float:
	return bank_steps * 5.625


## The rotor's start-up and landing state (rotor_drive.gd; documents 79, 86).
var heli_spinup_stage := 0        ## 0 done/flying, 1 blade accel (silent), 2 rotor ramp-up
var _heli_spinup_progress := 0.0  ## stage 1's accumulator (0..1)
var rotor_speed_steps := 4.0      ## the renderer's rotor speed (document 63's constant 4.0), ramped by stage 2
var heli_landing_gear_progress := 1.0

## The landing at the pad (run by the match once the descent is down; rotor_drive.gd, document 86): the rotor spin-down,
## then the gear timer. Each returns true when its stage is done.
func process_heli_landing_rotor(delta: float) -> bool:
	return drive.landing_rotor(self, delta) if drive != null and drive.has_method("landing_rotor") else true


func process_heli_landing_gear(delta: float) -> bool:
	return drive.landing_gear(self, delta) if drive != null and drive.has_method("landing_gear") else true


## The definition's rules and capabilities (PORTING_PLAN.md 2.7.2): e.g. rule("terrain.blocked_by_bushes") -- the tile
## callbacks FUN_00436640 / FUN_00436610 test the Jeep's type itself, the definition names what that test means.
func rule(path: String) -> bool:
	return bool(pack.vehicle_value(vehicle_type, path, false)) if pack != null else false


## True for a vehicle that picks up, carries and captures the flag (the Jeep; documents 54, 65).
func carries_flags() -> bool:
	return rule("flags.carries_flag")


## True for a vehicle that lands on the pad before it docks (the rotor drive; the record's +0x258 is 0x40eb00).
func lands_before_docking() -> bool:
	return drive != null and drive.has_method("landing_rotor")


## Stage 1's own accumulator (0..1, state+0x58) -- read by the renderer (document 85 addendum) to
## animate the two folded blades scissoring apart during the silent phase.
func heli_spinup_progress() -> float:
	return _heli_spinup_progress


## The Heli's weapon state (heli_guns.gd, document 63): the selected slot (obj+0xc bit 0x10000000), which mount fires next,
## and each slot's cooldown.
var _heli_slot := 0
var _heli_mount_left := false
var _heli_ready := [0.0, 0.0]


func toggle_heli_slot() -> void:
	var guns := _module("heli_guns")
	if guns != null and alive:
		guns.toggle(self)   # FUN_0040e7a0, document 63/82: "toggles bit 28 and plays a sound" (0x44b970)


## Which weapon is currently selected (0 gun, 1 bomb) -- obj+0xc bit 0x10000000 in the original
## (FUN_0040e600/FUN_0040e7a0, document 63), also read by the panel's weapon-select icons (document 83).
func heli_weapon_slot() -> int:
	return _heli_slot


var _road_mask := 0   ## DAT_0048c7b0: the direction mask of the road piece the Jeep was last driven on (game/road_assist.gd)


## FUN_0040c390's other output: the road mask of the tile under the vehicle, 0 in the air, in water, in swim mode or off the roads.
func _road_mask_here() -> int:
	if z > 1.0 or water_class != 0 or (_swims() and swim_amount >= 1.0) or level == null or pack == null:
		return 0
	var t := Vector2i((position / pack.tile_size_px).floor())
	if t.x < 0 or t.y < 0 or t.x >= level.width or t.y >= level.height:
		return 0
	return RoadAssist.mask_for_tile(level.get_art_id(t.x, t.y), level.get_coastal_id(t.x, t.y))


## FUN_0040c390: the tile under the vehicle scales its speed caps -- 1.2x on pavement (art ids
## 0x49-0x59 exclusive of both ends' neighbours, i.e. 73..89), else 1.0.
func _terrain_speed_scale() -> float:
	if z > 1.0:
		return 1.0
	if water_class != 0:
		# FUN_0040c390: 0.75 in any water, 0.25 for a Jeep that has finished entering swim mode
		return 0.25 if (_swims() and swim_amount >= 1.0) else 0.75
	if _swims() and swim_amount >= 1.0:
		return 0x28f / 65536.0  # swim mode on dry land: nearly stuck (press the swim button to leave it)
	if level == null or pack == null:
		return 1.0
	var t := Vector2i((position / pack.tile_size_px).floor())
	if t.x < 0 or t.y < 0 or t.x >= level.width or t.y >= level.height:
		return 1.0
	return ROAD_SPEED_SCALE if RoadAssist.mask_for_tile(level.get_art_id(t.x, t.y), level.get_coastal_id(t.x, t.y)) != 0 else 1.0
