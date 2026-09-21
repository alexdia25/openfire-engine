class_name ExplosionBox
extends RefCounted
## The damage box of an explosion record (op 13 DAMAGE_BOX, FUN_0042d640, and op 14 BOX_EXTENT, FUN_0042d710;
## document 60): a collision shape (type 2, layer 0x20, mask from the op) owned by the explosion object. The
## script ops are `DAMAGE_BOX z_lo z_hi width height mask damage`: the box starts +-width/2 by +-height/2 with z from
## z_lo to z_hi, and BOX_EXTENT n makes it +-n on all three axes. It lives until the explosion's progress reaches the
## record's duration (FUN_0042dca0 frees it). Every tick it overlaps something it calls that object's hit callback
## (FUN_0042dd20) with |damage| x (ticks since the last call), and the tile callback (FUN_0042dcd0) with the same.
## Progress and script stepping mirror game/explosion_effect_3d.gd.

var position := Vector2.ZERO
var half_x := 0.0
var half_y := 0.0
var z_lo := 0.0
var z_hi := 0.0
var mask := 0
var damage_per_tick := 0.0   ## positive, the record's signed whole units negated
var active := false          ## the DAMAGE_BOX op has run
var finished := false

var _record: Dictionary
var _progress := 0.0
var _pc := 0
var _script_done := false


func _init(record: Dictionary, at: Vector2) -> void:
	_record = record
	position = at


## Steps `ticks` original ticks; returns false once the explosion is over.
func advance(ticks: float) -> bool:
	if finished:
		return false
	_progress += float(_record.get("rate_per_tick", 0.25)) * ticks
	if _progress >= float(_record.get("duration", 1.0)):
		finished = true
		active = false
		return false
	var script: Array = _record.get("script", [])
	while not _script_done and _pc < script.size():
		var op: Array = script[_pc]
		match op[0]:
			"END":
				_script_done = true
			"STOP":
				_pc += 1
				return true
			"WAIT":
				if _progress < float(op[1]):
					return true
				_pc += 1
			"DAMAGE_BOX":
				z_lo = float(op[1])
				z_hi = float(op[2])
				half_x = float(op[3]) * 0.5
				half_y = float(op[4]) * 0.5
				mask = int(op[5])
				damage_per_tick = -float(op[6])
				active = true
				_pc += 1
			"BOX_EXTENT":
				half_x = float(op[1])
				half_y = float(op[1])
				z_lo = -float(op[1])
				z_hi = float(op[1])
				_pc += 1
			_:
				_pc += 1
	return true


func box() -> Array:
	return [-half_x, -half_y, half_x, half_y]
