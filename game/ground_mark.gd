class_name GroundMark
extends RefCounted
## A mark on the ground that stays a while and goes: the original's class 17 "Stay" (descriptor 0x4438b0, FUN_0040ad10 makes one). The only
## one built is the body a soldier leaves when it is crushed or shot on land (FUN_00433ce0: variant = 2 * rand(3) + team, six sprites,
## 120 ticks); the wreck's own mark (a 720-tick Stay made when the wreck has no footprint) is not. Pure logic: SoldierView-style views draw it.

var position := Vector2.ZERO
var variant := 0            ## which of the pack's `corpse_sprites`
var ticks_left := 120.0
var finished := false


func _init(at: Vector2, lifetime: int, which: int) -> void:
	position = at
	ticks_left = float(lifetime)
	variant = which


func tick(ticks: float) -> void:
	ticks_left -= ticks
	if ticks_left <= 0.0:
		finished = true
