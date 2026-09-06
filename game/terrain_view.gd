extends Node2D
## Phase 4 step 1 proof: load a pack, render one level's terrain + spawn/candidate
## markers. Everything is read through Pack/LevelData -- never build/ or *.RFM/*.CAR
## directly (PORTING_PLAN.md section 2.4). Replaces the placeholder boot scene until
## a real menu (section 2.6) picks a pack + level instead of these two exports.
##
## Superseded rule (2026-09-06, user direction; see PORTING_PLAN.md section 2.2 and
## docs/process/NEXT_STEPS.md): this scene is no longer required to track every future
## 3D-side change -- it's left as-is, functional, until the rendering-migration plan's Phase 4
## (this file) finishes, then gets retired as a whole. All of the actual gameplay logic below
## now lives in game/match_controller.gd (extracted so game/terrain_view_3d.gd can reuse it
## unchanged, the same "extract, don't duplicate" pattern as the tile renderer and vehicle
## billboard) -- this file is now just that controller's original 2D presentation.

@export var pack_path: String = "res://packs/original_pc"
@export var level_id: String = "RFMAP001"

var pack: Pack
var level: LevelData
var camera: Camera2D
var _terrain_tiles: TerrainTileRenderer
var _markers: DebugMarkerRenderer2D
var controller: MatchController


func _ready() -> void:
	pack = Pack.new()
	if not pack.load_from(pack_path):
		push_error("TerrainView: failed to load pack at %s" % pack_path)
		return

	level = LevelData.new()
	if not level.load_from(pack_path.path_join("levels").path_join(level_id)):
		push_error("TerrainView: failed to load level %s" % level_id)
		return

	get_window().title = "Return Fire -- %s (%s)" % [level.level_name, level_id]
	# Phase 2 of the rendering-migration plan (section 2.2): the tile-grid draw loop now lives
	# in its own reusable node (game/terrain_tile_renderer.gd), shared unchanged with the new
	# 3D scaffold's baked-texture ground plane. z_index keeps it under the markers/vehicle/
	# projectiles this scene still draws directly (see this file's own _draw(), below) --
	# same stacking order as when the loop was inline here.
	_terrain_tiles = TerrainTileRenderer.new()
	_terrain_tiles.z_index = -1
	add_child(_terrain_tiles)
	_terrain_tiles.setup(pack, level)

	controller = MatchController.new()
	add_child(controller)
	controller.setup(pack, level, pack_path, self)

	_markers = DebugMarkerRenderer2D.new()
	add_child(_markers)
	_markers.setup(pack, level, controller)

	_setup_camera()

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


## Phase 4 step 3 (single-viewport half): a smoothed camera that follows the player vehicle
## (spawned by MatchController) and never scrolls past the map edges, or -- if the level has
## no spawn points at all -- a fixed whole-map overview instead. Split-screen (multiple
## viewports, needed once the 4-player goal or a second local player exists, section 4 item 7)
## is NOT done -- this is a single Camera2D/Viewport setup only.
func _setup_camera() -> void:
	var tile := pack.tile_size_px
	camera = Camera2D.new()
	add_child(camera)

	if controller.vehicle == null:
		var map_px := Vector2(level.width, level.height) * tile
		var viewport_size := get_viewport_rect().size
		camera.zoom = Vector2.ONE * minf(viewport_size.x / map_px.x, viewport_size.y / map_px.y)
		camera.position = map_px * 0.5
		camera.make_current()
		return

	camera.zoom = Vector2.ONE * 2.0
	camera.position = controller.vehicle.position
	# Never show past the map edge, and smooth the follow instead of snapping each frame --
	# the two concrete, cheap parts of "camera, scrolling" (Phase 4 step 3) a single vehicle
	# actually needs. limit_smoothed keeps the smoothing itself from overshooting past the
	# same edges the hard limit enforces.
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(level.width * tile)
	camera.limit_bottom = int(level.height * tile)
	camera.limit_smoothed = true
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	camera.make_current()


func _process(_delta: float) -> void:
	if controller != null and controller.vehicle != null and camera != null:
		camera.position = controller.vehicle.position
		if OS.get_environment("RF_DEBUG_CAMERA_LOG") == "1" and Engine.get_process_frames() % 30 == 0:
			print("frame=%d vehicle_pos=%s camera_global=%s limits=[%d,%d,%d,%d]" % [
				Engine.get_process_frames(), controller.vehicle.position, camera.get_screen_center_position(),
				camera.limit_left, camera.limit_top, camera.limit_right, camera.limit_bottom])
