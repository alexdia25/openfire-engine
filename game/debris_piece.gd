class_name DebrisPiece
extends RefCounted
## One piece of flying wreckage: the original's class 3 "FWall" (table 0x44abb0; init FUN_0042b1f0, tick FUN_0042b290, draw FUN_0042a7b0), made by
## FUN_0042b4e0 from a body part of a wreck that has landed hard (Wreck.debris; issue #81, wiki document 119). Whole 16 ms ticks, as in the original.
##
## A piece is a flat quad (the part's sprite and corners, centred on the part's centroid) that flies outward from the body's centre and is run by a
## small script (pack `world/debris.json`): `progress` rises by the record's `rate` a tick; each op runs while its `start <= floor(progress) <= end`
## and the piece ends at `duration`. The ops that records use:
##   speed      the outward speed eases to a target (FUN_0042aad0); the direction is the part's centroid, normalised
##   gravity    from the first tick it runs the fall starts from the direction's height times the speed (`launch`), then 0x51e a tick, at most 1.0
##   yaw_spin / roll_spin   a random spin (the sum of two draws, either sign) the angle follows (FUN_0042abc0, 0042aca0)
##   tint       shade toward a colour as progress passes (FUN_0042a950; PORT CHOICE: the palette is not read, the piece darkens)
##   bounce     gravity, then the four corners are kept above the ground; with `settle_end` the piece ends once all four lie on it (FUN_0042b030)
##   land       once at or below the ground, play the surface's effect record and end (FUN_0042b0e0)
##   drag       slows drift words that nothing sets (FUN_0042afa0): a no-op, not run
## `frames` (a record field) swaps the sprite for the burn-out frames while progress is in range (FUN_0042ad80). From `fade_start` the piece fades.
## Not built: the piece's collision test while it moves (FUN_0042c830), and the 60-tick removal of an undrawn piece.

signal effect(record: String, position: Vector2)

const GRAVITY := 0x51e / 65536.0
const FALL_LIMIT := 1.0
const ANGLE_UNIT := 360.0 / 0x400000   ## degrees in one raw angle unit

var position := Vector2.ZERO
var z := 0.0
var dir := Vector3.ZERO        ## unit, (x, y) on the ground and z up
var speed := 0.0
var vz := 0.0
var airborne := false          ## flag 0x1000000: the gravity op took over the height
var yaw := 0.0                 ## degrees (obj +0x4c)
var yaw_rate := 0.0
var roll := 0.0                ## degrees (obj +0x68)
var roll_rate := 0.0
var progress := 0.0
var tint := 0.0                ## 0..1
var sprite_id := ""            ## the part's own sprite
var frame_id := ""             ## the burn-out frame while one is shown
var offsets: Array[Vector3] = []   ## the four corners about the centre, (x, up, z) in world axes
var finished := false
var offsets_changed := false   ## the bounce op moved a corner: the view rebuilds the quad

var _rec: Dictionary
var _surface: Callable          ## position -> effect record address
var _acc := 0.0
var _slots: Array = []
var _first := true


func _init(record: Dictionary, surface: Callable) -> void:
	_rec = record
	_surface = surface
	_slots.resize((record.get("ops", []) as Array).size())
	_slots.fill(null)


func fade_alpha() -> float:
	var n := floori(progress)
	var fs := int(_rec.get("fade_start", 0))
	var dur := int(_rec.get("duration", 1))
	if n < fs:
		return 1.0
	return floorf(clampf(1.0 - float(n - fs + 1) / float(dur - fs + 1), 0.0, 1.0) * 16.0) / 16.0   # 16 translucency levels (FUN_00423060)


func tick(ticks: float) -> void:
	_acc += ticks
	while _acc >= 1.0 and not finished:
		_acc -= 1.0
		_step()



func _step() -> void:
	if _first:
		progress = 1.0    # the creation flag 0x40: the first tick starts at 1.0
		_first = false
	else:
		progress += float(_rec.get("rate", 0.1))
		if progress >= float(_rec.get("duration", 1)):
			finished = true
			return
	var n := floori(progress)
	var d := Vector3.ZERO   # DAT_00458d58 / 5c / 60: this tick's movement
	var moved := false
	var ops: Array = _rec.get("ops", [])
	for i in ops.size():
		var op: Dictionary = ops[i]
		if n < int(op["start"]) or n > int(op["end"]):
			continue
		match String(op["op"]):
			"land":
				if _slots[i] == null and z <= 0.0:
					_slots[i] = 0.0
					effect.emit(String(_surface.call(position)), position)
					finished = true
					return
			"speed":
				if _slots[i] == null:
					var target := float(op["target"])
					var low := float(op.get("low", 0.0))
					if low != 0.0:
						target = float(randi() % maxi(int((target - low) * 65536.0) >> 4, 1) * 16) / 65536.0 + low   # rand((t - low) >> 4) * 16 + low
					_slots[i] = target
					if op.get("initial") != null:
						speed = float(op["initial"])
				speed = move_toward(speed, float(_slots[i]), float(op["rate"]))
				d.x += dir.x * speed
				d.y += dir.y * speed
				if not airborne:
					d.z += dir.z * speed
				moved = true
			"gravity":
				d.z += _gravity(op, i)
				moved = true
			"bounce":
				d.z += _gravity(op, i)
				moved = true
				if _settle(z + d.z) and bool(op.get("settle_end", false)):
					finished = true
					return
			"yaw_spin":
				yaw_rate = _spin(op, i, yaw_rate)
				yaw = fposmod(yaw + yaw_rate, 360.0)
			"roll_spin":
				roll_rate = _spin(op, i, roll_rate)
				roll = fposmod(roll + roll_rate, 360.0)
			"tint":
				tint = float(n - int(op["start"]) + 1) / float(int(op["end"]) - int(op["start"]) + 1)
	var fr: Dictionary = _rec.get("frames", {})
	frame_id = ""
	if not fr.is_empty() and n >= int(fr["start"]) and n - int(fr["start"]) < int(fr["count"]):
		frame_id = String((fr["sprites"] as Array)[n - int(fr["start"])])
	if moved:
		if z + d.z < 0.0:
			d.z = -z
		position += Vector2(d.x, d.y)
		z += d.z


## FUN_0042aeb0: from the first tick the fall starts from the direction's height times the speed (`launch`), then 0x51e a tick down to the limit.
func _gravity(op: Dictionary, i: int) -> float:
	if _slots[i] == null:
		_slots[i] = 0.0
		if bool(op.get("launch", false)):
			vz = dir.z * speed
		airborne = true
	vz = maxf(vz - GRAVITY, -FALL_LIMIT)
	return vz


## FUN_0042b030 after its gravity call: `height` is the centre's height after this tick's fall. A centre at or below the ground (under one raw
## unit) lowers every corner by that much first and measures them from the ground; each corner that would then lie below it is set on it (and stays:
## the corner's own height is rewritten). A wall therefore folds its lower edge into the ground while its top edge falls, and a flat piece ends flat.
## True when all four corners lie on the ground.
func _settle(height: float) -> bool:
	var base := height
	var shift := 0.0
	if height < 1.0 / 65536.0:
		base = 0.0
		shift = height
	var on_ground := 0
	for k in offsets.size():
		var o := offsets[k]
		var up := o.y + shift
		if up + base < 0.0:
			up = -base
			on_ground += 1
		if up != o.y:
			offsets[k] = Vector3(o.x, up, o.z)
			offsets_changed = true
	return on_ground > 3


## FUN_0042abc0: the first time, a random target spin (the sum of two draws over ((high - low) + 0x20000) >> 9, times 0x100, plus low, either sign;
## raw angle units, 0x400000 a turn); then the spin approaches it at `rate` a tick.
func _spin(op: Dictionary, i: int, spin: float) -> float:
	if _slots[i] == null:
		var lo := int(roundf(float(op["low"]) / ANGLE_UNIT))
		var hi := int(roundf(float(op["high"]) / ANGLE_UNIT))
		var target := float(hi)
		if lo != hi:
			var span := ((hi - lo) + 0x20000) >> 9
			target = float((randi() % span + randi() % span) * 0x100 + lo)
			if (randi() % 4) & 1:
				target = -target
		else:
			target = float(lo)
		_slots[i] = target * ANGLE_UNIT
		if op.get("initial") != null:
			spin = float(op["initial"])
	return move_toward(spin, float(_slots[i]), float(op["rate"]))
