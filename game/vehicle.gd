class_name Vehicle
extends Node2D
## Phase 4 step 2: a player-controlled vehicle with *playable* movement -- not yet
## authentic movement. RFIRE.BIN's real acceleration/turn-rate constants haven't been
## traced (the .RFM "vehicle_params" fields decode to unlabeled values A/H/J/M/T/unk4,
## almost always "default" -- section 1.5 never identified what they tune), so this
## uses reasonable placeholder physics, not reverse-engineered ones. Flagged honestly
## rather than presented as authentic; tightening this is a real, separate follow-up.
##
## Rendering is also a deliberate simplification of section 1.10/2.2's finding that the
## original does real perspective-projected-quad rendering across 64 discrete headings.
## This uses the 8-9 real rotation frames per team (cels 218-240) covering one quarter
## turn, mirrored into the other three quadrants -- a flat-rotation approximation
## (section 2.2's "knowingly accept a simpler visual target" option), not the projected-
## quad technique. Good enough to prove movement; revisit for visual fidelity later.

const MAX_SPEED := 220.0
const ACCEL := 260.0
const BRAKE := 220.0
const REVERSE_MAX_SPEED := 90.0
const FRICTION := 140.0
const TURN_RATE_DEG := 160.0

@export var pack_path: String = "res://packs/original_pc"
@export var team: String = "tan"  ## "tan" or "green" -- section 4 item 5

var pack: Pack
var _frames: Array[String] = []
var heading_deg: float = 0.0  ## 0 = facing +X (screen right), increases clockwise
var speed: float = 0.0


func setup(shared_pack: Pack) -> void:
	pack = shared_pack
	var prefix := "vehicle.hovercraft.rotation.%s." % team
	for id in pack.sprites.keys():
		if id.begins_with(prefix):
			_frames.append(id)
	_frames.sort()


## Debug-only: RF_DEBUG_DRIVE=1 replaces real input with a fixed forward+turn
## sequence, so headless/automated runs can verify movement actually works without
## a keyboard. Never affects a normal run (env var unset).
var _debug_drive: bool = OS.get_environment("RF_DEBUG_DRIVE") == "1"


func _process(delta: float) -> void:
	if pack == null or _frames.is_empty():
		return

	var turn := -1.0 if _debug_drive else Input.get_axis("ui_left", "ui_right")
	heading_deg = fposmod(heading_deg + turn * TURN_RATE_DEG * delta, 360.0)

	var thrust := 1.0 if _debug_drive else Input.get_axis("ui_down", "ui_up")
	if thrust > 0.0:
		speed = minf(speed + ACCEL * delta, MAX_SPEED)
	elif thrust < 0.0:
		speed = maxf(speed - BRAKE * delta, -REVERSE_MAX_SPEED)
	else:
		speed = move_toward(speed, 0.0, FRICTION * delta)

	var rad := deg_to_rad(heading_deg)
	position += Vector2(cos(rad), sin(rad)) * speed * delta
	queue_redraw()


## Folds any heading into the one real quarter-turn (0-90 deg) this vehicle has actual
## art for, plus the horizontal/vertical mirror needed to reconstruct the other three
## quadrants. Returns [sprite_id, flip_h, flip_v].
func _frame_for_heading(h: float) -> Array:
	var a := fposmod(h, 360.0)
	var flip_h := false
	var flip_v := false
	if a >= 270.0:
		a = 360.0 - a
	elif a >= 180.0:
		a = a - 180.0
		flip_h = true
		flip_v = true
	elif a >= 90.0:
		a = 180.0 - a
		flip_h = true
	else:
		flip_v = true
	var t := a / 90.0
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
