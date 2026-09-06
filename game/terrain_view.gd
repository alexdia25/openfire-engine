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

## Phase 4 step 5 (first pass): how close a projectile must get to an active target's tile
## centre to destroy it. RFIRE.BIN's real hit-detection geometry (and target hitpoints --
## these targets die in one hit here) haven't been traced (Phase 3 backlog: "Building and
## target hitpoints, destruction rules") -- a placeholder, not a reverse-engineered value.
const TARGET_HIT_RADIUS_PX := 24.0

@export var pack_path: String = "res://packs/original_pc"
@export var level_id: String = "RFMAP001"

var pack: Pack
var level: LevelData
var vehicle: Vehicle
var camera: Camera2D
var pools: Dictionary = {}       ## pool_id (String) -> TargetPool
var _projectiles: Array = []     ## live Projectile nodes, for target hit-testing


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
	_setup_target_pools()
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
	_projectiles.append(p)


## Phase 4 step 5 (first pass): one TargetPool per pool id in the level file (section 1.5's
## pool A / pool B), each picking its own initial active target at construction -- matching
## RFIRE.BIN doing this once, at level load, for every non-empty pool.
func _setup_target_pools() -> void:
	for pool_id in level.candidate_pools:
		var positions: Array = []
		for c in level.candidate_pools[pool_id]:
			positions.append(Vector2i(int(c.get("x", 0)), int(c.get("y", 0))))
		pools[pool_id] = TargetPool.new(positions)
		if OS.get_environment("RF_DEBUG_TARGET_LOG") == "1":
			var pool: TargetPool = pools[pool_id]
			print("pool=%s candidates=%d budget=%d active=%s" % [
				pool_id, pool.candidates.size(), pool.budget, pool.get_active_position()])


## Phase 4 step 5 (first pass): a projectile within TARGET_HIT_RADIUS_PX of a pool's active
## target destroys it, triggering TargetPool's replacement-or-go-silent logic. No collision
## with terrain or the vehicle itself yet -- just the one interaction step 5 needs to prove:
## the candidate-pool mechanism actually drives what a projectile can destroy.
func _check_target_hits() -> void:
	var tile := pack.tile_size_px
	var consumed := []  # queue_free() is deferred -- don't let one projectile hit two pools this frame
	for pool_id in pools:
		var pool: TargetPool = pools[pool_id]
		var active_tile = pool.get_active_position()
		if active_tile == null:
			continue
		var active_px: Vector2 = (Vector2(active_tile) + Vector2(0.5, 0.5)) * tile
		for p in _projectiles:
			if not is_instance_valid(p) or consumed.has(p):
				continue
			if p.global_position.distance_to(active_px) <= TARGET_HIT_RADIUS_PX:
				consumed.append(p)
				p.queue_free()
				var reactivated := pool.destroy_active()
				if OS.get_environment("RF_DEBUG_TARGET_LOG") == "1":
					print("frame=%d pool=%s destroyed tile=%s budget=%d new_active=%s" % [
						Engine.get_process_frames(), pool_id, active_tile, pool.budget,
						pool.get_active_position() if reactivated else "none (silent)"])
				queue_redraw()
				break  # this target is gone; don't test the same projectile against it again


func _process(_delta: float) -> void:
	_projectiles = _projectiles.filter(func(p): return is_instance_valid(p))
	_check_target_hits()

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

	# Phase 4 step 5 (first pass): intact-but-not-active candidates as a thin hollow outline
	# (unchanged from step 1), a destroyed-and-not-replaced candidate as a dim X (the pool
	# spent that slot and, once its budget/candidates run out, will never revisit it), and
	# the pool's one currently-live target as a bright filled square -- the thing a
	# projectile can actually destroy right now.
	for pool_id in pools:
		var colour: Color = POOL_COLOURS.get(pool_id, Color.WHITE)
		var pool: TargetPool = pools[pool_id]
		for i in pool.candidates.size():
			var top_left := Vector2(pool.candidates[i]) * tile
			var rect := Rect2(top_left, Vector2(tile, tile))
			if i == pool.active_index:
				draw_rect(rect, colour, true)
			elif pool.intact[i]:
				draw_rect(rect, colour, false, 2.0)
			else:
				var dim := Color(colour, 0.35)
				draw_line(rect.position, rect.position + rect.size, dim, 2.0)
				draw_line(rect.position + Vector2(rect.size.x, 0), rect.position + Vector2(0, rect.size.y), dim, 2.0)
