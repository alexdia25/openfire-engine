class_name VehicleBillboard3D
extends Node3D
## Phase 3 of the rendering-migration plan (PORTING_PLAN.md section 2.2, section 4 item 13):
## a real 3D presence standing in for game/vehicle.gd's flat draw_texture_rect_region call.
## Deliberately a *separate* node rather than teaching Vehicle to draw itself in 3D -- the
## real Vehicle instance still runs completely unmodified (movement integration, input,
## firing, and above all Vehicle._frame_for_heading()'s quadrant-mirror frame selection, fixed
## and tested in document 25) as an invisible logic-only Node2D; this node just mirrors its
## position/heading into a real 3D presentation every frame. Same "extract, don't duplicate"
## choice as game/terrain_tile_renderer.gd (Phase 2, document 29) for the same reason: two
## copies of frame-selection logic could silently drift out of sync the way this project's own
## classify_bulk.py auto-numbering bug once did.
##
## Vehicle keeps running its own _process() untouched (Node process callbacks fire regardless
## of CanvasItem.visible) -- only its own _draw() output is suppressed, by setting
## Vehicle.visible = false in setup() below, so nothing 2D composites onto the 3D scene.
##
## DEFAULT MODE, as of 2026-09-06: GROUND_DECAL, not BILLBOARD. A user-reported "the tank
## looks like it's always facing the same way" complaint led to a precise diagnosis (document
## 31: heading 0 and 180 render pixel-identical, since Vehicle._frame_for_heading()'s
## quadrant-flip mirroring can't fix a symmetric base frame) and a prototype (document 32)
## that settled it empirically across three rendering techniques tried on the *same* real art:
## billboard-always-faces-camera (the original Phase 3 choice) produced disconnected slivers
## at 90/270 degrees; combining real per-heading textures with real 3D rotation
## (GROUND_DECAL_MULTI) made that specific failure *worse*, not better (the discrete frames'
## own built-in thinning compounds with added geometric foreshortening); a single canonical
## texture laid flat like a ground decal and rotated by the vehicle's real, continuous heading
## (GROUND_DECAL) won decisively -- coherent at every heading, using fewer source images than
## either alternative. See documents 31-32 for the full comparisons.

## Small fixed height off the ground, matching terrain_view_3d.gd's Phase 1 placeholder box --
## not a traced value (no vehicle-height RE finding exists), just enough that the sprite's
## quad doesn't clip into the ground plane.
const HEIGHT_PX := 10.0

## See _process()'s own comment at the one place this is used: GROUND_DECAL's rotation used
## to assume _frames[0]'s raw art already faces vehicle.gd's own "0 = +X" convention. It
## doesn't -- confirmed by direct atlas inspection and by the user noticing driving forward
## moved the vehicle 90 degrees away from its visible front. This scope is deliberately
## GROUND_DECAL-only: BILLBOARD and GROUND_DECAL_MULTI (debug-only, not used in normal play)
## go through Vehicle._frame_for_heading() instead of this rotation formula, so they likely
## carry the same underlying mismatch unaddressed -- not fixed here.
const FACING_OFFSET_DEG := 90.0

## GROUND_DECAL (the default): lays the textured quad flat, like a decal on the ground (the
## same orientation the terrain plane already uses), and gives it a *real* Node3D yaw matching
## the vehicle's continuous heading, instead of billboarding to face the camera -- Godot's own
## tilted camera then foreshortens it exactly like everything else in the scene, with no
## hand-ported projection math. Uses ONE canonical texture rather than Vehicle._frame_for_
## heading()'s discrete quadrant-flip selection: the two rotation mechanisms would
## double-count (the flip logic already reorients content for its own quadrant; adding a full
## heading_deg yaw on top of that would rotate it twice).
##
## BILLBOARD: the original Phase 3 choice, a Sprite3D that always faces the camera, using
## Vehicle._frame_for_heading()'s real quadrant-mirror frame selection unchanged. Kept as a
## debug-only alternative (`RF_DEBUG_VEHICLE_QUAD_MODE=billboard`) for comparison, not the
## default -- see document 32 for why GROUND_DECAL won.
##
## GROUND_DECAL_MULTI: the same real continuous yaw as GROUND_DECAL, but the *texture* cycles
## through all 9 real per-heading frames via _frame_for_heading()'s quadrant-folded index
## (never its flip flags -- same double-counting risk as above). Tested and rejected (document
## 32): worse than either alternative, since the discrete frames' own built-in thinning
## compounds with the added geometric foreshortening right at 90/270 degrees. Debug-only,
## `RF_DEBUG_VEHICLE_QUAD_MODE=ground_decal_multi`.
enum QuadMode { BILLBOARD, GROUND_DECAL, GROUND_DECAL_MULTI }
var quad_mode: QuadMode = QuadMode.GROUND_DECAL

var vehicle: Vehicle
var pack: Pack
var sprite: Sprite3D


func setup(shared_vehicle: Vehicle, shared_pack: Pack) -> void:
	vehicle = shared_vehicle
	pack = shared_pack
	vehicle.visible = false  # logic only -- see file header

	# Debug-only override for comparison against the GROUND_DECAL default -- never affects a
	# normal run (env var unset). "ground_decal" is accepted too, even though it's already the
	# default, so an explicit override always does what it says regardless of future defaults.
	var mode_env := OS.get_environment("RF_DEBUG_VEHICLE_QUAD_MODE")
	if mode_env == "billboard":
		quad_mode = QuadMode.BILLBOARD
	elif mode_env == "ground_decal":
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
		# (see the file header's "would double-count" note).
		#
		# FACING_OFFSET_DEG (2026-09-08, user-reported): this used to be plain
		# `-vehicle.heading_deg`, whose sign was only ever checked against a Phase 1
		# placeholder box's own rotation for internal consistency -- never against what
		# _frames[0]'s actual pixels depict. They depict the vehicle's front-indicator nub
		# pointing toward the *bottom* of the raw, unrotated cel, not toward the cel's own
		# right edge -- confirmed by direct atlas inspection (`vehicle.hovercraft.rotation.
		# tan.01`, cel 218) and by the user, who noticed driving forward moved the vehicle 90
		# degrees away from where its front visibly pointed. The +90 correction was found by
		# comparing a straight (turn=0) RF_DEBUG_DRIVE run's real movement direction against
		# the rendered nub direction, then confirmed across a curving turning path too -- not
		# derived analytically. Get the sign wrong and the mismatch just moves from "-90" to
		# "+90" without looking obviously more wrong at a glance, so a real reference (an
		# actual known movement direction) is what settled it, the same way document 30's own
		# billboard-vs-position test needed a real comparison rather than reasoning about it.
		rotation_degrees.y = -vehicle.heading_deg + FACING_OFFSET_DEG
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
