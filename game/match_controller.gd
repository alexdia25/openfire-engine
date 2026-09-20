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

## Projectile hits are the original's swept-shape tests (document 53, game/collision.gd); tile hit points and
## damage are traced (document 45). No placeholder hit radius remains.

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
## A tile that is not a pool's active target ran out of hit points (document 53).
signal tile_destroyed(tile: Vector2i)
## A projectile ended on a vehicle or a target tile: the explosion record to play there (document 50).
signal impact_effect(record_addr: String, position: Vector2)

var pack: Pack
var pack_path: String = ""       ## re-passed to each spawned Vehicle/EnemyVehicle, see below
var level: LevelData
var world: Node  ## parent for every node this controller spawns
var vehicle: Vehicle
var enemy_vehicles: Array = []   ## EnemyVehicle nodes
var pools: Dictionary = {}       ## pool_id (String) -> TargetPool
var _projectiles: Array = []     ## live Projectile nodes, for target hit-testing
var _player_spawn_px := Vector2.ZERO
var _tile_hp: Dictionary = {}    ## Vector2i -> remaining hit points of a damaged pool target

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
	vehicle.level = level
	vehicle.position = (Vector2(float(sp.get("x", 0)), float(sp.get("y", 0))) + Vector2(0.5, 0.5)) * tile
	vehicle.fired.connect(_on_vehicle_fired.bind(vehicle))
	vehicle.destroyed.connect(_on_player_destroyed)
	_player_spawn_px = vehicle.position

	for other_sp in level.spawn_points:
		if int(other_sp.get("team", 0)) == player_team:
			continue
		var enemy := EnemyVehicle.new()
		enemy.pack_path = pack_path
		enemy.team = "tan" if int(other_sp.get("team", 0)) == 0 else "green"
		world.add_child(enemy)
		enemy.setup(pack)
		enemy.level = level
		enemy.position = (Vector2(float(other_sp.get("x", 0)), float(other_sp.get("y", 0))) + Vector2(0.5, 0.5)) * tile
		enemy.target = vehicle
		enemy.fired.connect(_on_vehicle_fired.bind(enemy))
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
func _on_vehicle_fired(muzzle_position: Vector2, heading_deg: float, team: String, shooter: Vehicle) -> void:
	var p := Projectile.new()
	p.shooter = shooter
	world.add_child(p)
	p.team = team
	p.heading_deg = heading_deg
	p.global_position = muzzle_position
	p.prev_checked = muzzle_position
	_projectiles.append(p)
	projectile_spawned.emit(p)


func _process(_delta: float) -> void:
	_projectiles = _projectiles.filter(func(p): return is_instance_valid(p))
	for p in _projectiles:
		if p.is_queued_for_deletion():
			continue
		var from: Vector2 = p.prev_checked
		var to: Vector2 = p.global_position
		p.prev_checked = to
		if _shell_hits_tile(p, from, to) or _shell_hits_vehicle(p, from, to):
			p.queue_free()


## Document 53: a shell is a swept point (z 7 +- 1.5); a living vehicle other than its shooter is hit when the
## segment meets its collision polygon (FUN_00414e60 -> FUN_0040c460, document 47).
func _shell_hits_vehicle(p: Projectile, from: Vector2, to: Vector2) -> bool:
	var targets: Array = [vehicle] + enemy_vehicles
	for v in targets:
		if v == null or not is_instance_valid(v) or not v.alive or v == p.shooter:
			continue
		if not Collision.shell_collides_with(Vehicle.HIT_LAYER, Vehicle.HIT_MASK):
			continue
		if not Collision.shell_z_overlaps(Projectile.SHELL_Z, Vehicle.HIT_Z[0], Vehicle.HIT_Z[1]):
			continue
		if Collision.segment_hits_polygon(from, to, v.hit_polygon()):
			v.take_damage(p.damage)
			impact_effect.emit("0x444b68", to)  # surface 3, object hit
			return true
	return false


## No life system is traced yet (NEXT_STEPS): the player simply respawns at the start point.
func _on_player_destroyed(_v: Vehicle) -> void:
	vehicle.respawn(_player_spawn_px)


## Document 53: the tile under the shell and its eight neighbours are tested (FUN_0042bd40 / FUN_0042bf30);
## each coastal id's first descriptor carries collision shapes placed at the tile centre (plus the decoration
## jitter and the shape's own offset). A hit ends the shell (FUN_00414dd0) and damages the tile
## (FUN_0042e8c0), with no other test of what counts as a "target": every tile with a shape can be shot.
func _shell_hits_tile(p: Projectile, from: Vector2, to: Vector2) -> bool:
	var tsz := float(pack.tile_size_px)
	var tx := int(floor(to.x / tsz))
	var ty := int(floor(to.y / tsz))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var t := Vector2i(tx + dx, ty + dy)
			if t.x < 0 or t.y < 0 or t.x >= level.width or t.y >= level.height:
				continue
			var id := level.get_coastal_id(t.x, t.y)
			if id == 0:
				continue
			var info := pack.get_coastal_shapes(id)
			if info.is_empty():
				continue
			var centre := (Vector2(t) + Vector2(0.5, 0.5)) * tsz
			if info.get("jitter", false):
				centre += level.jitter_at(t.x, t.y)
			for sh in info["shapes"]:
				if not Collision.shell_collides_with(int(sh["layer"]), int(sh["mask"])):
					continue
				if not Collision.shell_z_overlaps(Projectile.SHELL_Z, float(sh["z"][0]), float(sh["z"][1])):
					continue
				var origin: Vector2 = centre + Vector2(sh["off"][0], sh["off"][1])
				var hit := false
				if int(sh["type"]) == 2:
					hit = Collision.segment_hits_box(from, to, origin, sh["box"])
				elif int(sh["type"]) == 3:
					var poly := PackedVector2Array()
					for pt in sh["poly"]:
						poly.append(origin + Vector2(pt[0], pt[1]))
					hit = Collision.segment_hits_polygon(from, to, poly)
				if hit:
					impact_effect.emit("0x444ac8", to)  # surface 4, tile hit
					_damage_tile(t, id, p)
					return true
	return false


## FUN_0042e8c0 with the coastal table's armour 0 and multiplier 0 (document 44): a tile with 0 hit points
## is indestructible (the shell is still stopped); otherwise the hit removes max(1, whole damage) and the tile
## is destroyed when its hit points are <= that. A pool's active target goes through TargetPool
## (FUN_00432710); any other tile just changes state (the scene applies it).
func _damage_tile(t: Vector2i, id: int, p: Projectile) -> void:
	var hp: int = _tile_hp.get(t, _initial_tile_hp(t))
	if hp <= 0:
		return
	var dmg := maxi(int(p.damage), 1)
	if hp > dmg:
		_tile_hp[t] = hp - dmg
		return
	_tile_hp.erase(t)
	var tile_px := (Vector2(t) + Vector2(0.5, 0.5)) * pack.tile_size_px
	for pool_id in pools:
		var pool: TargetPool = pools[pool_id]
		var active_tile = pool.get_active_position()
		if active_tile == null or active_tile != t:
			continue
		var reactivated := pool.destroy_active()
		target_hit.emit(pool_id, t)
		if _debug_target_log:
			print("frame=%d pool=%s destroyed tile=%s budget=%d new_active=%s" % [
				Engine.get_process_frames(), pool_id, t, pool.budget,
				pool.get_active_position() if reactivated else "none (silent)"])
		if not reactivated:
			# The pool went silent for good: FUN_00432710 falls through to spawn its flag object
			# (section 4 item 1); destroy_active() only returns false once per pool.
			_spawn_flag(pool_id, tile_px)
		return
	tile_destroyed.emit(t)


func _initial_tile_hp(tile: Vector2i) -> int:
	var d := pack.get_coastal_damage(level.get_coastal_id(tile.x, tile.y))
	return maxi(int(d.get("hp", 0)), 0)


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
