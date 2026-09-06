class_name VehicleBillboard3D
extends Node3D
## Phase 3 of the rendering-migration plan (PORTING_PLAN.md section 2.2, section 4 item 13):
## a real billboard Sprite3D standing in for game/vehicle.gd's flat draw_texture_rect_region
## call. Deliberately a *separate* node rather than teaching Vehicle to draw itself in 3D --
## the real Vehicle instance still runs completely unmodified (movement integration, input,
## firing, and above all Vehicle._frame_for_heading()'s quadrant-mirror frame selection, fixed
## and tested in document 25) as an invisible logic-only Node2D; this node just mirrors its
## position/heading into a real 3D billboard every frame. Same "extract, don't duplicate"
## choice as game/terrain_tile_renderer.gd (Phase 2, document 29) for the same reason: two
## copies of frame-selection logic could silently drift out of sync the way this project's own
## classify_bulk.py auto-numbering bug once did.
##
## Vehicle keeps running its own _process() untouched (Node process callbacks fire regardless
## of CanvasItem.visible) -- only its own _draw() output is suppressed, by setting
## Vehicle.visible = false in setup() below, so nothing 2D composites onto the 3D scene.

## Small fixed height off the ground, matching terrain_view_3d.gd's Phase 1 placeholder box --
## not a traced value (no vehicle-height RE finding exists), just enough that the sprite's
## billboard quad doesn't clip into the ground plane.
const HEIGHT_PX := 10.0

## Prototype (2026-09-06, user-directed): tests whether the "90/270 degree frames look like
## disconnected little triangles" complaint is a rendering-technique gap rather than missing
## art. RFIRE.BIN's own vehicle rendering (section 1.10 points 3-4) projects real 3D corner
## points and warps a texture onto the resulting quad -- our billboard mode instead always
## faces the camera dead-on, which never lets the camera's own 45-degree tilt foreshorten the
## art the way it foreshortens everything else in this scene (terrain, the ground plane).
## "ground_decal" mode tests the cheap, Godot-native version of that idea: lay the textured
## quad flat (like a decal on the ground, the same orientation the terrain plane already uses)
## and give it a *real* Node3D yaw matching the vehicle's heading, instead of billboarding --
## Godot's own camera then foreshortens it exactly like everything else, with no hand-ported
## projection math. Deliberately uses ONE canonical texture rotated continuously, not
## Vehicle._frame_for_heading()'s discrete quadrant-flip selection: the two rotation
## mechanisms would double-count (the flip logic already reorients content for its own
## quadrant; adding a full heading_deg yaw on top of that would rotate it twice). This is
## exactly the trade this mode is testing -- real continuous 3D rotation of fewer source
## images, versus discrete image-swapping with no true rotation at all.
##
## "ground_decal_multi" (2026-09-06, follow-up) combines both ideas instead of choosing
## between them: still a real continuous yaw (never Vehicle._frame_for_heading()'s flip
## flags -- flip and yaw would still double-count exactly as above), but the *texture*
## cycles through all 9 real per-heading frames using that same function's quadrant-folded
## index, so whatever shading/perspective detail the original artist actually drew into each
## of the 9 frames still shows up somewhere in the rotation, instead of one frame doing all
## 360 degrees alone.
enum QuadMode { BILLBOARD, GROUND_DECAL, GROUND_DECAL_MULTI }
var quad_mode: QuadMode = QuadMode.BILLBOARD

var vehicle: Vehicle
var pack: Pack
var sprite: Sprite3D


func setup(shared_vehicle: Vehicle, shared_pack: Pack) -> void:
	vehicle = shared_vehicle
	pack = shared_pack
	vehicle.visible = false  # logic only -- see file header

	var mode_env := OS.get_environment("RF_DEBUG_VEHICLE_QUAD_MODE")
	if mode_env == "ground_decal":
		quad_mode = QuadMode.GROUND_DECAL
	elif mode_env == "ground_decal_multi":
		quad_mode = QuadMode.GROUND_DECAL_MULTI

	sprite = Sprite3D.new()
	sprite.shaded = false  # pre-rendered flat art, not something to relight
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST  # hard-edged pixel art
	sprite.pixel_size = 1.0  # 1 texture pixel = 1 world unit, matching the flat scene's scale
	if quad_mode != QuadMode.BILLBOARD:
		sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		# Sprite3D's un-billboarded plane stands vertical, facing -Z, by default -- tip it back
		# 90 degrees around X so it lies flat in the XZ plane instead, matching the ground
		# plane's own orientation.
		sprite.rotation_degrees.x = -90.0
	else:
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(sprite)
	_refresh()


func _process(_delta: float) -> void:
	if vehicle == null:
		return
	global_position = Vector3(vehicle.position.x, HEIGHT_PX, vehicle.position.y)
	if quad_mode != QuadMode.BILLBOARD:
		# The real, continuous heading -- not vehicle.gd's discrete quadrant-flip selection
		# (see the file header's "would double-count" note). Sign empirically matched against
		# tracked.rotation_degrees.y in terrain_view_3d.gd's Phase 1 placeholder.
		rotation_degrees.y = -vehicle.heading_deg
	_refresh()


## Re-reads Vehicle's current heading every call. In BILLBOARD mode this is the exact same
## [sprite_id, flip_h, flip_v] result the flat 2D scene's Vehicle._draw() already computes --
## the only place this file touches vehicle art in that mode. GROUND_DECAL always shows one
## canonical texture and lets the real 3D yaw set in _process() supply the rotation.
## GROUND_DECAL_MULTI still gets its texture from _frame_for_heading(), but discards the flip
## flags -- the real yaw already set in _process() is what makes it face the right way, so a
## 2D flip on top would double-count the same rotation twice (see the file header).
func _refresh() -> void:
	if vehicle == null or vehicle.pack == null or vehicle._frames.is_empty():
		return

	var sprite_id: String
	var flip_h := false
	var flip_v := false
	if quad_mode == QuadMode.GROUND_DECAL:
		sprite_id = vehicle._frames[0]  # the fullest real frame, e.g. rotation.tan.01
	elif quad_mode == QuadMode.GROUND_DECAL_MULTI:
		var result := vehicle._frame_for_heading(vehicle.heading_deg)
		sprite_id = result[0]  # flip_h/flip_v deliberately discarded -- see this function's header
	else:
		var result := vehicle._frame_for_heading(vehicle.heading_deg)
		sprite_id = result[0]
		flip_h = result[1]
		flip_v = result[2]

	var s := pack.get_sprite(sprite_id)
	if s.is_empty():
		return
	var tex := pack.get_texture(int(s.get("page", 0)))
	if tex == null:
		return

	sprite.texture = tex
	sprite.region_enabled = true
	sprite.region_rect = Rect2(s.get("x", 0), s.get("y", 0), s.get("w", 0), s.get("h", 0))
	sprite.flip_h = flip_h
	sprite.flip_v = flip_v
