extends Node2D
## Phase 4 step 1 proof: load a pack, render one level's terrain + spawn/candidate
## markers. Everything is read through Pack/LevelData -- never build/ or *.RFM/*.CAR
## directly (PORTING_PLAN.md section 2.4). Replaces the placeholder boot scene until
## a real menu (section 2.6) picks a pack + level instead of these two exports.

## Team colours per PORTING_PLAN.md section 4 item 5 (user-confirmed 2026-09-06,
## cross-checked against art): team 0 is tan, team 1 is green. The actual colouring
## *mechanism* is still open -- these are just marker colours for this debug view.
const TEAM_COLOURS := {
	0: Color(0.82, 0.71, 0.55),
	1: Color(0.30, 0.55, 0.30),
}
const POOL_COLOURS := {
	"a": Color.CYAN,
	"b": Color.MAGENTA,
}

@export var pack_path: String = "res://packs/original_pc"
@export var level_id: String = "RFMAP001"

var pack: Pack
var level: LevelData
var vehicle: Vehicle
var camera: Camera2D


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
	_spawn_vehicle()
	queue_redraw()

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


## Phase 4 step 3 (single-viewport half): spawn the player vehicle at the level's
## team-0 spawn point (falls back to a whole-map overview if the level has none), with
## a smoothed camera that follows it and never scrolls past the map edges. Split-screen
## (multiple viewports, needed once the 4-player goal or a second local player exists,
## section 4 item 7) is NOT done -- this is a single Camera2D/Viewport setup only.
func _spawn_vehicle() -> void:
	var tile := pack.tile_size_px
	camera = Camera2D.new()
	add_child(camera)

	if level.spawn_points.is_empty():
		var map_px := Vector2(level.width, level.height) * tile
		var viewport_size := get_viewport_rect().size
		camera.zoom = Vector2.ONE * minf(viewport_size.x / map_px.x, viewport_size.y / map_px.y)
		camera.position = map_px * 0.5
		camera.make_current()
		return

	var sp: Dictionary = level.spawn_points[0]
	vehicle = Vehicle.new()
	vehicle.pack_path = pack_path
	vehicle.team = "tan" if int(sp.get("team", 0)) == 0 else "green"
	add_child(vehicle)
	vehicle.setup(pack)
	vehicle.position = (Vector2(float(sp.get("x", 0)), float(sp.get("y", 0))) + Vector2(0.5, 0.5)) * tile
	vehicle.fired.connect(_on_vehicle_fired)

	camera.zoom = Vector2.ONE * 2.0
	camera.position = vehicle.position
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


## Phase 4 step 4 (first pass): spawn a projectile as a sibling of the vehicle -- not a
## child of it -- so its transform is independent of the vehicle's own position/rotation
## once launched.
func _on_vehicle_fired(muzzle_position: Vector2, heading_deg: float, team: String) -> void:
	var p := Projectile.new()
	add_child(p)
	p.team = team
	p.heading_deg = heading_deg
	p.global_position = muzzle_position


func _process(_delta: float) -> void:
	if vehicle != null and camera != null:
		camera.position = vehicle.position
		if OS.get_environment("RF_DEBUG_CAMERA_LOG") == "1" and Engine.get_process_frames() % 30 == 0:
			print("frame=%d vehicle_pos=%s camera_global=%s limits=[%d,%d,%d,%d]" % [
				Engine.get_process_frames(), vehicle.position, camera.get_screen_center_position(),
				camera.limit_left, camera.limit_top, camera.limit_right, camera.limit_bottom])


func _draw() -> void:
	if pack == null or level == null:
		return

	var tile := pack.tile_size_px
	for y in level.height:
		for x in level.width:
			var art_id := level.get_art_id(x, y)
			var sprite_id := pack.get_tile_sprite_id(art_id)
			if sprite_id == "":
				continue
			var sprite := pack.get_sprite(sprite_id)
			if sprite.is_empty():
				continue
			var tex := pack.get_texture(int(sprite.get("page", 0)))
			if tex == null:
				continue
			var src := Rect2(sprite.get("x", 0), sprite.get("y", 0), sprite.get("w", 0), sprite.get("h", 0))
			var dst := Rect2(x * tile, y * tile, tile, tile)
			draw_texture_rect_region(tex, dst, src)

	for sp in level.spawn_points:
		var team := int(sp.get("team", 0))
		var colour: Color = TEAM_COLOURS.get(team, Color.WHITE)
		var centre := Vector2(float(sp.get("x", 0)) + 0.5, float(sp.get("y", 0)) + 0.5) * tile
		draw_circle(centre, tile * 0.6, colour)

	for pool_id in level.candidate_pools:
		var colour: Color = POOL_COLOURS.get(pool_id, Color.WHITE)
		for c in level.candidate_pools[pool_id]:
			var top_left := Vector2(float(c.get("x", 0)), float(c.get("y", 0))) * tile
			draw_rect(Rect2(top_left, Vector2(tile, tile)), colour, false, 2.0)
