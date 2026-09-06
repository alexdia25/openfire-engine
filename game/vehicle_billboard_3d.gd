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

var vehicle: Vehicle
var pack: Pack
var sprite: Sprite3D


func setup(shared_vehicle: Vehicle, shared_pack: Pack) -> void:
	vehicle = shared_vehicle
	pack = shared_pack
	vehicle.visible = false  # logic only -- see file header

	sprite = Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false  # pre-rendered flat art, not something to relight
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST  # hard-edged pixel art
	sprite.pixel_size = 1.0  # 1 texture pixel = 1 world unit, matching the flat scene's scale
	add_child(sprite)
	_refresh()


func _process(_delta: float) -> void:
	if vehicle == null:
		return
	global_position = Vector3(vehicle.position.x, HEIGHT_PX, vehicle.position.y)
	_refresh()


## Re-reads Vehicle's current heading through its own, unmodified frame-selection method every
## call -- this is the one and only place this file touches vehicle art, and it's the exact
## same [sprite_id, flip_h, flip_v] result the flat 2D scene's Vehicle._draw() already computes.
func _refresh() -> void:
	if vehicle == null or vehicle.pack == null or vehicle._frames.is_empty():
		return
	var result := vehicle._frame_for_heading(vehicle.heading_deg)
	var sprite_id: String = result[0]
	var flip_h: bool = result[1]
	var flip_v: bool = result[2]

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
