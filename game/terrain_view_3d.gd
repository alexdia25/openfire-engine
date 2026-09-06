extends Node3D
## Phase 1 of the rendering-migration plan (PORTING_PLAN.md section 2.2, section 4 item 13):
## scaffolding for the new 3D scene, built *alongside* the existing flat game/terrain_view.gd
## (which keeps working unchanged -- this file does not replace it yet, per the plan's own
## "keep every step playable" rule). Proves the one thing Phase 1 is scoped to prove: a
## Camera3D at the real, RE-confirmed fixed tilt (section 1.10 point 6 -- exactly 45 degrees,
## hardcoded once in RFIRE.BIN and never rewritten) can translate in X/Z to follow a moving
## target the same way terrain_view.gd's Camera2D already does, edge-clamped to the level's
## real bounds and smoothed instead of snapping.
##
## Deliberately NOT here yet (later phases, not gaps in this one):
## - Real vehicle art. The tracked object is a plain box -- billboard Sprite3D vehicles
##   (reusing Vehicle._frame_for_heading() unchanged) are Phase 3.
## - The exact effective height/FOV. Section 1.10 point 6 explicitly left this for
##   screenshot-matching once Phase 2 has real terrain art to match against -- camera_height_px
##   below is a reasonable placeholder for this phase's own verification, not a traced value.
##
## Degrees of freedom (user direction, 2026-09-06): tilt and zoom (height) are exposed as
## adjustable properties, not baked-in constants, so a future debug control or gameplay need
## can vary them -- even though RFIRE.BIN itself hardcodes both and never changes either
## (section 1.10 point 6). Rotation/yaw is NOT exposed at all, and never will be from this
## scaffolding: that absence isn't "unused so far," it's structural -- FUN_00408d60 (the real
## terrain blitter) has no rotation term to read in the first place, only the two fixed values
## reproduced below. Nothing in this file computes or applies a yaw angle anywhere.

## Section 1.10 point 6: RFIRE.BIN hardcodes this exactly once, in the shared object
## constructor, and never rewrites it. Kept adjustable here (not a const) so tilt can be
## tuned/animated later without changing this file -- the value below is just the default,
## matching the confirmed original.
@export var camera_tilt_deg: float = 45.0

## Default matches the placeholder noted above -- how high above the tracked point the camera
## sits, in the same pixel-as-Godot-unit scale the flat 2D scene already uses (tile_size_px
## etc). Doubles as the "zoom" control: lower = closer/more zoomed in, higher = further back.
## At a 45-degree tilt the horizontal pull-back needed to keep the tracked point centred on
## screen equals the height exactly (tan(45) == 1) -- if camera_tilt_deg is ever changed from
## 45, _camera_target_position()'s pull-back math below must change from a 1:1 ratio to
## height / tan(camera_tilt_deg).
@export var camera_height_px: float = 260.0

## Same follow-smoothing speed terrain_view.gd's Camera2D uses (position_smoothing_speed)
## -- Camera3D has no built-in equivalent, so this scene hand-rolls the same exponential
## approach-to-target every frame.
const CAMERA_SMOOTHING_SPEED := 6.0

## Phase 1 placeholder movement for the tracked box -- NOT Vehicle.gd's real movement code.
## Vehicle extends Node2D and draws itself via _draw(), which has no meaningful place in a
## pure-3D scene (Phase 3 is what actually reuses Vehicle._frame_for_heading() unchanged,
## feeding a Sprite3D instead of draw_texture_rect_region). This exists only so Phase 1 has
## something moving to prove the camera-follow/edge-clamp math against, the same way Phase 4
## step 3's original verification drove the real vehicle in a straight line to the map edge.
const PLACEHOLDER_MAX_SPEED := 220.0
const PLACEHOLDER_ACCEL := 260.0
const PLACEHOLDER_TURN_RATE_DEG := 160.0

@export var pack_path: String = "res://packs/original_pc"
@export var level_id: String = "RFMAP001"

var pack: Pack
var level: LevelData
var camera: Camera3D
var tracked: Node3D
var _map_size_px: Vector2 = Vector2.ZERO

var _heading_deg: float = 0.0
var _speed: float = 0.0

## Debug-only, same convention/env-var names as vehicle.gd and terrain_view.gd -- never
## affects a normal run (env vars unset).
var _debug_drive: bool = OS.get_environment("RF_DEBUG_DRIVE") == "1"


func _ready() -> void:
	pack = Pack.new()
	if not pack.load_from(pack_path):
		push_error("TerrainView3D: failed to load pack at %s" % pack_path)
		return

	level = LevelData.new()
	if not level.load_from(pack_path.path_join("levels").path_join(level_id)):
		push_error("TerrainView3D: failed to load level %s" % level_id)
		return

	get_window().title = "Return Fire 3D scaffold -- %s (%s)" % [level.level_name, level_id]
	_map_size_px = Vector2(level.width, level.height) * pack.tile_size_px

	# Debug-only overrides for the two adjustable camera properties (tilt/zoom -- see the
	# file header's "degrees of freedom" note), so headless verification can try values other
	# than the defaults without editing this file. Never affects a normal run (env vars unset).
	var tilt_env := OS.get_environment("RF_DEBUG_CAMERA_TILT_DEG")
	if tilt_env != "":
		camera_tilt_deg = float(tilt_env)
	var height_env := OS.get_environment("RF_DEBUG_CAMERA_HEIGHT_PX")
	if height_env != "":
		camera_height_px = float(height_env)

	_build_terrain_ground()
	_spawn_tracked_box()
	_build_light()
	_build_camera()

	var screenshot_path := OS.get_environment("RF_DEBUG_SCREENSHOT")
	if screenshot_path != "":
		var wait_frames := 2
		var wait_env := OS.get_environment("RF_DEBUG_SCREENSHOT_DELAY_FRAMES")
		if wait_env != "":
			wait_frames = int(wait_env)
		for i in wait_frames:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(screenshot_path)
		get_tree().quit()


## Phase 2 of the rendering-migration plan (section 2.2, section 4 item 13): the real terrain
## art, not a placeholder colour -- game/terrain_tile_renderer.gd (Phase 2's extraction of
## terrain_view.gd's own tile-drawing loop, byte-for-byte unchanged) draws into a SubViewport
## at the level's native pixel resolution, and that viewport's texture becomes the ground
## plane's albedo. Godot's own camera then does the perspective projection on this baked
## texture -- no hand-ported scanline math, exactly the rationale section 2.2 recorded for
## choosing this architecture in the first place.
func _build_terrain_ground() -> void:
	var sub_vp := SubViewport.new()
	sub_vp.size = Vector2i(int(_map_size_px.x), int(_map_size_px.y))
	# The terrain art never changes after a level loads (no animated tiles anywhere in this
	# project's tile pipeline) -- render once and stop, instead of re-drawing an identical
	# image every frame.
	sub_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(sub_vp)

	var tile_renderer := TerrainTileRenderer.new()
	sub_vp.add_child(tile_renderer)
	tile_renderer.setup(pack, level)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	# Sized to the level's real world dimensions (plan section 2.2's own phrasing for this
	# step), matching the SubViewport's resolution exactly -- one texel per source pixel, no
	# stretching. NOTE (honest, not yet fixed): at this camera's height/tilt relative to a
	# 4096px map, near-horizontal rays can reach past this mesh's edge before hitting the
	# horizon, showing background void in a corner of the frame -- the same real, finite-mesh
	# artifact Phase 1 hit and deliberately routed around with an oversized placeholder plane.
	# Doing that here would mean texturing the overhang with something other than real terrain
	# (there is no real art beyond the level's actual bounds), so this phase accepts the
	# artifact rather than paper over it -- worth a skybox/fallback-colour backdrop in a later
	# pass, not a blocker for verifying the terrain projection itself.
	plane.size = _map_size_px
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = sub_vp.get_texture()
	# The source art is hard-edged pixel art (tools/convert_car.py's atlas, section 2.4.2) --
	# nearest filtering keeps tile edges crisp instead of linear-blurring them.
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	ground.material_override = mat
	# PlaneMesh is centred on its own origin; the 2D scenes place (0,0) at the level's
	# top-left corner with +X right/+Y down, so shift this node to match: world X -> node X,
	# world Y (2D "down") -> node Z ("forward").
	ground.position = Vector3(_map_size_px.x * 0.5, 0.0, _map_size_px.y * 0.5)
	add_child(ground)


## Plain box standing in for a real billboard Sprite3D vehicle (Phase 3). Spawns at the
## level's team-0 point the same way terrain_view.gd's real Vehicle does, falling back to
## map centre if the level has none.
func _spawn_tracked_box() -> void:
	tracked = Node3D.new()
	add_child(tracked)
	var visual := CSGBox3D.new()
	visual.size = Vector3(24, 20, 24)
	visual.position.y = 10.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.82, 0.71, 0.55)  # tan, section 4 item 5's team-0 colour
	visual.material = mat
	tracked.add_child(visual)

	var spawn_px := _map_size_px * 0.5
	if not level.spawn_points.is_empty():
		var sp: Dictionary = level.spawn_points[0]
		spawn_px = (Vector2(float(sp.get("x", 0)), float(sp.get("y", 0))) + Vector2(0.5, 0.5)) * pack.tile_size_px
	tracked.position = Vector3(spawn_px.x, 0.0, spawn_px.y)


## Placeholder-only stand-in for real level lighting (not an RE finding -- RFIRE.BIN's own
## lighting model, if any, hasn't been investigated). Without this every StandardMaterial3D
## surface renders pure black; a single fixed directional light is enough for Phase 1's own
## purpose (confirm the camera geometry looks right), nothing more.
func _build_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.light_energy = 1.1
	add_child(sun)


func _build_camera() -> void:
	camera = Camera3D.new()
	add_child(camera)
	_apply_tilt()
	_place_camera_immediately()
	camera.current = true


## Sets the camera's *entire* orientation, always, from camera_tilt_deg alone -- rotation.y
## (yaw) and rotation.z (roll) are never touched anywhere in this file, not just left at their
## default. This is the actual mechanism behind the file header's "tilt and zoom, not rotate"
## rule: an earlier version of this function used look_at() aimed at the tracked object
## instead, which seemed simpler (it sidesteps ever having to hand-derive Godot's
## rotation-axis sign convention) but was wrong -- look_at() implicitly introduces yaw
## whenever the camera's clamped position drifts off-axis from the tracked point (verified by
## driving straight to a map edge: the clamp holds the camera's X still while the tracked box
## keeps moving, and the box visibly stayed centred on screen instead of sliding off -- the
## camera was quietly panning to compensate, which is exactly the rotation this scaffolding
## must not do). Re-called every frame; cheap, and correct even if camera_tilt_deg changes
## live. rotation_degrees.x = -camera_tilt_deg was verified empirically (screenshot) to tilt
## the view down toward the ground, not up and away from it.
func _apply_tilt() -> void:
	camera.rotation_degrees = Vector3(-camera_tilt_deg, 0.0, 0.0)


func _place_camera_immediately() -> void:
	camera.position = _camera_target_position(Vector2(tracked.position.x, tracked.position.z))


## Same X/Z position a fully-smoothed camera converges to for a given tracked-point position:
## directly above-and-behind by however far camera_height_px and camera_tilt_deg say the
## pull-back needs to be to keep the tracked point centred on screen, then clamped so the
## camera itself never sits past the ground plane's real edges -- the 3D equivalent of
## terrain_view.gd's Camera2D limit_left/top/right/bottom. (Like that existing clamp, this
## means the tracked point stops being screen-centred near an edge -- consistent with, not a
## regression from, the flat scene's existing behaviour.) The margin reuses the pull-back
## distance as a placeholder stand-in for "however far the tilted view actually reaches,"
## which Phase 2's screenshot-matching will replace with a real derived value.
func _camera_target_position(look_at_px: Vector2) -> Vector3:
	var pull_back := camera_height_px / tan(deg_to_rad(clampf(camera_tilt_deg, 1.0, 89.0)))
	var margin := pull_back
	var desired_x := look_at_px.x
	var desired_z := look_at_px.y + pull_back
	var x := clampf(desired_x, margin, maxf(_map_size_px.x - margin, margin))
	var z := clampf(desired_z, margin, maxf(_map_size_px.y - margin, margin))
	return Vector3(x, camera_height_px, z)


func _process(delta: float) -> void:
	if tracked == null or camera == null:
		return

	var turn := 0.0
	var thrust := 0.0
	if _debug_drive:
		var turn_env := OS.get_environment("RF_DEBUG_DRIVE_TURN")
		turn = float(turn_env) if turn_env != "" else -1.0
		thrust = 1.0

	_heading_deg = fposmod(_heading_deg + turn * PLACEHOLDER_TURN_RATE_DEG * delta, 360.0)
	if thrust > 0.0:
		_speed = minf(_speed + PLACEHOLDER_ACCEL * delta, PLACEHOLDER_MAX_SPEED)
	else:
		_speed = move_toward(_speed, 0.0, PLACEHOLDER_ACCEL * delta)

	var rad := deg_to_rad(_heading_deg)
	tracked.position += Vector3(cos(rad), 0.0, sin(rad)) * _speed * delta
	tracked.rotation_degrees.y = -_heading_deg

	var tracked_px := Vector2(tracked.position.x, tracked.position.z)
	var target_cam_pos := _camera_target_position(tracked_px)
	camera.position = camera.position.lerp(target_cam_pos, 1.0 - exp(-CAMERA_SMOOTHING_SPEED * delta))
	_apply_tilt()

	if OS.get_environment("RF_DEBUG_CAMERA_LOG") == "1" and Engine.get_process_frames() % 30 == 0:
		print("frame=%d tracked_pos=%s camera_pos=%s map_size=%s" % [
			Engine.get_process_frames(), tracked.position, camera.position, _map_size_px])
