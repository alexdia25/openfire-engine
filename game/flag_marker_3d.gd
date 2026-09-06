class_name FlagMarker3D
extends Node3D
## Phase 4 of the rendering-migration plan (PORTING_PLAN.md section 2.2, section 4 item 13):
## pairs a real, unmodified, invisible FlagMarker (game/flag_marker.gd -- frame-cycling
## animation logic only) with a 3D ground-decal presentation, reusing document 32's winning
## technique for the vehicle (game/vehicle_billboard_3d.gd's GROUND_DECAL mode): a flat,
## unbillboarded quad lying in the ground plane. Unlike the vehicle, the flag never turns
## (FlagMarker's own docstring: "this one doesn't move at all") and never moves after it
## spawns, so unlike VehicleBillboard3D/ProjectileBillboard3D there is no per-frame position or
## rotation to maintain here -- only which of FlagMarker's cycling frames to show changes over
## time, exactly like the flat 2D scene's own _draw() re-reading FlagMarker's current frame.
##
## Reaches into FlagMarker's underscore-prefixed `_frames`/`_frame_index` directly rather than
## adding a new public accessor -- the same precedent VehicleBillboard3D already set by calling
## Vehicle._frame_for_heading() across this exact "logic node paired with a 3D presentation"
## seam.

const HEIGHT_PX := 2.0  ## just above the ground plane -- a flat decal, not a standing sprite

var flag: FlagMarker
var pack: Pack
var sprite: Sprite3D


func setup(shared_flag: FlagMarker, shared_pack: Pack) -> void:
	flag = shared_flag
	pack = shared_pack
	flag.visible = false  # logic only -- see file header

	sprite = Sprite3D.new()
	sprite.shaded = false
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.pixel_size = 1.0
	sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sprite.rotation_degrees.x = -90.0
	add_child(sprite)

	global_position = Vector3(flag.position.x, HEIGHT_PX, flag.position.y)
	_refresh()
	# FlagMarker is never freed by anything in this project yet (it's a fire-and-forget spawn,
	# per its own docstring) -- this connection is here defensively, matching the same pattern
	# ProjectileBillboard3D needs for real, in case that ever changes.
	flag.tree_exited.connect(queue_free)


func _process(_delta: float) -> void:
	if not is_instance_valid(flag):
		queue_free()
		return
	_refresh()


func _refresh() -> void:
	if flag._frames.is_empty():
		return
	var sprite_id: String = flag._frames[flag._frame_index]
	var s := pack.get_sprite(sprite_id)
	if s.is_empty():
		return
	var tex := pack.get_texture(int(s.get("page", 0)))
	if tex == null:
		return
	sprite.texture = tex
	sprite.region_enabled = true
	sprite.region_rect = Rect2(s.get("x", 0), s.get("y", 0), s.get("w", 0), s.get("h", 0))
