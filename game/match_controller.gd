class_name MatchController
extends Node
## Phase 4 of the rendering-migration plan (PORTING_PLAN.md section 2.2, section 4 item 13):
## pulls terrain_view.gd's *gameplay* logic -- vehicle/enemy spawn, projectile spawn-on-fire,
## target-pool hit-testing, the flag-spawn trigger -- out of that one scene and into a shared,
## rendering-agnostic node. Same "extract, don't duplicate" reasoning as
## game/terrain_tile_renderer.gd (Phase 2, document 29) and game/vehicle_billboard_3d.gd
## (Phase 3, document 30): two copies of hit-testing/pool logic could silently drift the way
## this project's own classify_bulk.py auto-numbering bug once did. This node owns none of the
## *drawing* -- it spawns real, unmodified gameplay nodes (Vehicle, EnemyVehicle, Projectile,
## FlagMarker) as children of whatever `world` node setup() is given, and emits signals when it
## does, so a rendering scene (2D or 3D) can pair its own presentation layer with each one --
## exactly the seam Phase 3 already established for the vehicle alone (VehicleBillboard3D
## pairs with a real, invisible Vehicle). game/terrain_view.gd (flat 2D) uses this controller
## and lets each spawned node draw itself directly; game/terrain_view_3d.gd (Phase 4) uses the
## same controller and instead pairs a 3D presentation node with each signal.
##
## All of the actual game rules here (candidate-pool replacement, the flag-spawn trigger,
## hit-test radius) are unchanged from terrain_view.gd's own prior implementation -- this is a
## pure extraction, not a rules change. See TargetPool's own docstring and document 26 for what
## these rules trace back to in RFIRE.BIN.

## Phase 4 step 5 (first pass): how close a projectile must get to an active target's tile
## centre to destroy it. RFIRE.BIN's real hit-detection geometry (and target hitpoints -- these
## targets die in one hit here) haven't been traced (Phase 3 backlog: "Building and target
## hitpoints, destruction rules") -- a placeholder, not a reverse-engineered value.
const TARGET_HIT_RADIUS_PX := 24.0

## Phase 4 step 7 (first pass): which marker.capture_flag.<colour> family a pool spawns from
## when it goes silent -- UNCONFIRMED which, if either, physical pool a real team's flag
## actually belongs to (game/flag_marker.gd's docstring); an arbitrary but fixed choice so the
## two pools in a level render visibly differently.
const POOL_FLAG_COLOURS := {
	"a": "red",
	"b": "green",
}

## Emitted right after a new Projectile is added as a child of `world` -- a scene wanting a
## non-default visual presentation (3D billboard, etc) connects here instead of polling.
signal projectile_spawned(projectile: Projectile)
## Emitted right after a new FlagMarker is added as a child of `world`.
signal flag_spawned(flag: FlagMarker, pool_id: String)
## Emitted whenever a pool's active target is destroyed (whether or not a replacement
## activates) -- game/debug_marker_renderer.gd's overlay uses this to know when to redraw.
signal target_hit(pool_id: String, tile: Vector2i)

var pack: Pack
var pack_path: String = ""       ## re-passed to each spawned Vehicle/EnemyVehicle, see below
var level: LevelData
var world: Node  ## parent for every node this controller spawns
var vehicle: Vehicle
var enemy_vehicles: Array = []   ## EnemyVehicle nodes
var pools: Dictionary = {}       ## pool_id (String) -> TargetPool
var _projectiles: Array = []     ## live Projectile nodes, for target hit-testing

var _debug_target_log: bool = OS.get_environment("RF_DEBUG_TARGET_LOG") == "1"


## `shared_pack`/`shared_level` must already be loaded. `shared_pack_path` is the same
## res://-relative path used to load them -- Vehicle re-derives its own art from it (see
## vehicle.gd's own `pack_path` export), so this controller needs it too, not just the already-
## loaded Pack object. `world_root` is where every spawned node (vehicle, enemies, projectiles,
## flags) is added as a child -- pass the scene itself so spawned Node2D/Node3D-cousins land in
## whatever coordinate space that scene already uses (both current scenes treat
## position.x/position.y as the same flat world-pixel plane regardless of whether the node is a
## Node2D or, via a 3D pairing, presented in 3D).
func setup(shared_pack: Pack, shared_level: LevelData, shared_pack_path: String, world_root: Node) -> void:
	pack = shared_pack
	level = shared_level
	pack_path = shared_pack_path
	world = world_root
	_spawn_vehicle_and_enemies()
	_setup_target_pools()


## Phase 4 step 3 (single-viewport half): spawn the player vehicle at the level's team-0 spawn
## point (falls back to leaving `vehicle` null if the level has none -- callers already handle
## "no spawn point" as a whole-map-overview case of their own). Phase 4 step 6: spawn an
## EnemyVehicle at every other spawn point, matching terrain_view.gd's prior behaviour exactly.
func _spawn_vehicle_and_enemies() -> void:
	if level.spawn_points.is_empty():
		return

	var tile := pack.tile_size_px
	var sp: Dictionary = level.spawn_points[0]
	var player_team := int(sp.get("team", 0))

	vehicle = Vehicle.new()
	vehicle.pack_path = pack_path
	vehicle.team = "tan" if player_team == 0 else "green"
	world.add_child(vehicle)
	vehicle.setup(pack)
	vehicle.position = (Vector2(float(sp.get("x", 0)), float(sp.get("y", 0))) + Vector2(0.5, 0.5)) * tile
	vehicle.fired.connect(_on_vehicle_fired)

	for other_sp in level.spawn_points:
		if int(other_sp.get("team", 0)) == player_team:
			continue
		var enemy := EnemyVehicle.new()
		enemy.pack_path = pack_path
		enemy.team = "tan" if int(other_sp.get("team", 0)) == 0 else "green"
		world.add_child(enemy)
		enemy.setup(pack)
		enemy.position = (Vector2(float(other_sp.get("x", 0)), float(other_sp.get("y", 0))) + Vector2(0.5, 0.5)) * tile
		enemy.target = vehicle
		enemy.fired.connect(_on_vehicle_fired)
		enemy_vehicles.append(enemy)


## Phase 4 step 5 (first pass): one TargetPool per pool id in the level file (section 1.5's
## pool A / pool B), each picking its own initial active target at construction -- matching
## RFIRE.BIN doing this once, at level load, for every non-empty pool.
func _setup_target_pools() -> void:
	for pool_id in level.candidate_pools:
		var positions: Array = []
		for c in level.candidate_pools[pool_id]:
			positions.append(Vector2i(int(c.get("x", 0)), int(c.get("y", 0))))
		pools[pool_id] = TargetPool.new(positions)
		if _debug_target_log:
			var pool: TargetPool = pools[pool_id]
			print("pool=%s candidates=%d budget=%d active=%s" % [
				pool_id, pool.candidates.size(), pool.budget, pool.get_active_position()])


## Phase 4 step 4 (first pass): spawn a projectile as a sibling of the firing vehicle in
## `world` -- not a child of it -- so its transform is independent of the vehicle's own
## position/rotation once launched.
func _on_vehicle_fired(muzzle_position: Vector2, heading_deg: float, team: String) -> void:
	var p := Projectile.new()
	world.add_child(p)
	p.team = team
	p.heading_deg = heading_deg
	p.global_position = muzzle_position
	_projectiles.append(p)
	projectile_spawned.emit(p)


func _process(_delta: float) -> void:
	_projectiles = _projectiles.filter(func(p): return is_instance_valid(p))
	_check_target_hits()


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
				target_hit.emit(pool_id, active_tile)
				if _debug_target_log:
					print("frame=%d pool=%s destroyed tile=%s budget=%d new_active=%s" % [
						Engine.get_process_frames(), pool_id, active_tile, pool.budget,
						pool.get_active_position() if reactivated else "none (silent)"])
				if not reactivated:
					# Phase 4 step 7 (first pass): the pool just went silent for good --
					# RFIRE.BIN's FUN_00432710 falls through to spawn its dedicated flag
					# object in exactly this case (section 4 item 1). destroy_active() only
					# ever returns false once per pool (it stays silent afterward), matching
					# the real function's own guard against spawning a second flag while
					# one's already tracked.
					_spawn_flag(pool_id, active_px)
				break  # this target is gone; don't test the same projectile against it again


## Phase 4 step 7 (first pass): spawns the flag-marker fallthrough (see the call site's
## comment and game/flag_marker.gd's docstring) at the position of the pool's last-destroyed
## target. Purely visual -- see flag_marker.gd for exactly what this isn't yet.
func _spawn_flag(pool_id: String, at_position: Vector2) -> void:
	var flag := FlagMarker.new()
	world.add_child(flag)
	flag.setup(pack, POOL_FLAG_COLOURS.get(pool_id, "red"))
	flag.position = at_position
	flag_spawned.emit(flag, pool_id)
	if _debug_target_log:
		print("frame=%d pool=%s FLAG SPAWNED at=%s" % [
			Engine.get_process_frames(), pool_id, at_position])
