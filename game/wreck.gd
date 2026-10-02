class_name Wreck
extends RefCounted
## What a destroyed vehicle becomes while it falls, slides and lands: the original's class 6 "Destroyed Vehicle" (table 0x4453e8; documents 87 and 118).
## TRACED: FUN_0040c7e0 (init), FUN_0040cc50 / 0040cca0 / 0040cd00 (its three behaviours, run in that order) and FUN_0040c8f0 (the per-tick update).
## Every number is in whole 16 ms ticks, as in the original; `tick()` feeds them in from the frame's time.
##
## The chain document 87's "Step 4" took for a contradiction is not one: FUN_0042c290 copies the class's `+0x1c` (0) into the object's `+0x18`
## and THEN calls the class's init, and the init (FUN_0040c7e0) sets `+0x18 = FUN_0040cc50` itself. So a fresh wreck does have a mover.
##
## One tick, in the original's order:
##  1. the water class under it (0 if it is more than 1.0 up);
##  2. the behaviour: first tick plays the type's death explosion (not when the vehicle ran out of fuel), then waits 8 ticks, then (from the
##     tick after) slows the forward speed by the type's friction and gives up after 720 ticks;
##  3. at rest (speed 0, height 0, not over deep water) it is `settled` and nothing else happens;
##  4. else gravity 0x51e per tick, falling speed capped at 1.0, drifts forward along its heading at its speed, and if the fall would pass the
##     ground it stops there and sets the "landed" bit (the `0x2000000` flag document 87 never found read: FUN_0040c8f0 reads it further down);
##  5. a landed (or overkilled: hit points below -40 when it was made) wreck plays the explosion again and would burst into FWall pieces
##     (not built; issue #81) and then, over land, becomes the flat decal; over water it splashes and goes.
## A settled wreck whose shape is the decal's (none) turns into a `Stay` mark (FUN_0040ad10) and the object goes; a wreck of a vehicle that ran
## out of fuel keeps the body's shape (a hulk with a footprint), so there a crewman climbs out instead (FUN_0040cd00; document 116) and the
## hulk is removed after 720 ticks.

signal effect(record: String, position: Vector2)   ## an explosion record is played here (FUN_0042e080)
signal crew_out(wreck: Wreck)                       ## the crewman leaves a settled hulk (FUN_00434950)
signal debris(wreck: Wreck)                         ## the landing bursts the body into FWall pieces (FUN_0042b4e0), not built yet

enum Phase { BODY, DECAL }

const GRAVITY := 0x51e / 65536.0          ## DAT_0044a318, units per tick per tick
const TERMINAL := 1.0                      ## DAT_0044a31c: the fastest it falls, units per tick
const SETTLE_TICKS := 8                    ## FUN_0040cca0 waits this long before the descriptor changes
const LIFETIME_TICKS := 0x2d0              ## FUN_0040cd00: the object is removed this long after it was made
const OVERKILL_HP := -40.0                 ## FUN_0040c460: hit points below this set the landing bit at once
const STEP_DEG := 5.625

var position := Vector2.ZERO
var z := 0.0
var heading_deg := 0.0
var speed := 0.0               ## forward speed, units per tick (negative = backwards); the vehicle's speed when it died
var vz := 0.0                  ## vertical speed, units per tick (negative = down)
var team := "tan"
var colour := ""               ## art colour (the side's)
var vehicle_type := 0
var fuel_out := false          ## flag 0x1000000: the vehicle's fuel was below 1 (FUN_0040c7e0)
var landed_flag := false       ## flag 0x2000000
var settled := false           ## flag 0x4000000
var phase := Phase.BODY
var finished := false          ## the object is gone (the decal, if any, stays as a mark: `mark`)
var mark := false              ## it became a `Stay` mark: the decal stays, the object is gone
var polygon := PackedVector2Array()
var age := 0                   ## ticks since it was made (state +0x64)
var sunk := false

var _cfg: Dictionary
var _water: Callable           ## (position, z) -> 0 land / 1 shallow / 2 deep
var _sink_depth := 14.0
var _stage := 0                ## 0 = FUN_0040cc50, 1 = FUN_0040cca0, 2 = FUN_0040cd00, 3 = no behaviour
var _wait := 0
var _acc := 0.0
var _crew_done := false


## `info` is Vehicle._die()'s snapshot; `cfg` the vehicle definition's `wreck` table; `water` answers the class under a point.
func _init(info: Dictionary, cfg: Dictionary, water: Callable) -> void:
	_cfg = cfg
	_water = water
	position = info["position"]
	z = float(info.get("z", 0.0))
	heading_deg = float(info.get("heading_deg", 0.0))
	speed = float(info.get("speed", 0.0))
	team = String(info.get("team", "tan"))
	colour = String(info.get("colour", team))
	vehicle_type = int(info.get("vehicle_type", 0))
	fuel_out = bool(info.get("fuel_out", false))
	polygon = info.get("polygon", PackedVector2Array())
	_sink_depth = float(info.get("sink_depth", 14.0))
	landed_flag = float(info.get("hp", 0.0)) < f("overkill_hp", OVERKILL_HP)


func f(key: String, fallback: float) -> float:
	return float(_cfg.get(key, fallback))


## The direction one step of the heading names (the original's 64-entry table at 0x481390: the heading rounded down to 5.625 degrees).
static func step_dir(heading: float) -> Vector2:
	var idx := floori(fposmod(heading + 90.0, 360.0) / STEP_DEG)
	var a := deg_to_rad(idx * STEP_DEG - 90.0)
	return Vector2(cos(a), sin(a))


func tick(ticks: float) -> void:
	if finished:
		return
	_acc += ticks
	while _acc >= 1.0 and not finished:
		_acc -= 1.0
		_step()


## Where the drawn height is while the body falls (the ground is 0).
func height() -> float:
	return maxf(z, 0.0)


func _class_here() -> int:
	if z > 1.0 or not _water.is_valid():
		return 0
	return int(_water.call(position, z))


func _step() -> void:
	age += 1
	var cat := _class_here()
	# the behaviour (FUN_0040cc50 -> 0040cca0 -> 0040cd00)
	match _stage:
		0:
			if not fuel_out:
				effect.emit(String(_cfg.get("explosion", "")), position)
			_wait = 0
			_stage = 1
		1:
			_wait += 1
			if _wait > int(f("settle_ticks", SETTLE_TICKS)) - 1:
				# FUN_0040cca0: the descriptor becomes the record's +0x160 (the decal; the body again after a fuel death). The Heli's +0x160 is
				# 0x440bd0, not the decal (its +0x164 is): a shape-carrying descriptor whose drawing is not decoded, so the port keeps its body
				if not fuel_out and bool(_cfg.get("mid_descriptor_is_decal", true)):
					phase = Phase.DECAL
				_stage = 2
		2:
			_behave(cat)
		_:
			finished = true
			return
	# at rest
	if speed == 0.0 and z <= 0.0 and cat != 2:
		settled = true
		return
	# gravity, the fall, the drift
	vz = maxf(vz - f("gravity", GRAVITY), -f("terminal_velocity", TERMINAL))
	var dz := vz
	var move := step_dir(heading_deg) * speed
	if z <= 0.0:
		if cat != 2:
			dz = 0.0
	elif z <= -dz:
		dz = -z
		landed_flag = true
	position += move
	z += dz
	# sunk (the Jeep's +0x158 depth): FUN_0040c8f0 removes it with the splash 0x444ee8
	if floorf(z) <= -floorf(_sink_depth):
		sunk = true
		effect.emit(String(_cfg.get("sink_splash", "0x444ee8")), position)
		finished = true
		return
	if landed_flag:
		effect.emit(String(_cfg.get("explosion", "")), position)
		debris.emit(self)
		if cat != 0:
			effect.emit(String(_cfg.get("landing_splash", "0x444618")), position)
			finished = true
			return
		if z > 0.0:
			finished = true
			return
		landed_flag = false
		phase = Phase.DECAL


## FUN_0040cd00.
func _behave(_cat: int) -> void:
	if speed != 0.0:
		speed = move_toward(speed, 0.0, f("friction", 0x1999 / 65536.0))
	if age > int(f("lifetime_ticks", LIFETIME_TICKS)):
		_stage = 3
	if not settled:
		return
	if phase == Phase.DECAL:
		# no footprint: the decal stays as a Stay mark and the object goes
		mark = true
		finished = true
		_stage = 3
	elif fuel_out and not _crew_done:
		_crew_done = true
		crew_out.emit(self)
