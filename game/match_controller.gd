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
## A vehicle drove over a crushable tile fast enough to flatten it (document 54).
signal tile_crushed(tile: Vector2i)
## A team gate object took over a tile / gave it back (document 56).
signal gate_created(gate: Gate)
signal gate_removed(gate: Gate)
## A vehicle carrying the other pool's flag stood on its home tile (document 57): the match is over.
signal match_over(winner_idx: int)
## The player has no vehicle left in stock and none alive (the original starts a game-over handler at 0x418390 when the last one is lost; what it shows is
## untraced, so this only reports it; document 73).
signal out_of_vehicles()
## A projectile ended on a vehicle or a target tile: the explosion record to play there (document 50).
signal impact_effect(record_addr: String, position: Vector2)
## Record address -> sound cue id(s), cross-referenced against tools/data/explosion_records.json's SOUND opcodes
## through the master index table at 0x44b9a0 (document 82/tools/data/sound_cues.json's "impact_effect_sound_map").
## A vehicle hit (0x444b68) originally REPEATs all four MetalHit variants in sequence; the port just picks one.
const IMPACT_SOUND_CUES := {
	"0x444740": "SmDirtHit", "0x444840": "DirtHit",
	"0x4445b8": "SmSplash", "0x4445e8": "Splash",
	"0x444968": "SmConcreteHit", "0x444a30": "ConcreteHit",
	"0x444ac8": "SmallBoom",
}
const IMPACT_SOUND_CUES_RANDOM := {
	"0x444b68": ["MetalHit1", "MetalHit2", "MetalHit3", "MetalHit4"],
}
## Coastal id -> sound cue for a tile's destroy effect (document 84), built the same way: every id here is a real
## destroy-effect record's first SOUND opcode via the master index table, not a guess. An id with no entry has no
## traced destroy-effect record at all, not an assumed "Boom".
const DESTROY_SOUND_CUES := {
	1: "SmallBoom", 2: "SmallBoom", 3: "SmallBoom", 4: "SmallBoom", 5: "SmallBoom", 6: "SmallBoom", 11: "SmallBoom",
	12: "Boom", 13: "Boom", 15: "Boom", 16: "Boom", 17: "Boom", 18: "Boom", 19: "Boom", 20: "Boom", 21: "Boom",
	22: "Boom", 23: "Boom", 24: "Boom", 25: "Boom", 26: "Boom", 27: "Boom", 28: "Boom", 29: "Boom", 30: "Boom",
	31: "Boom", 32: "Boom", 33: "Boom", 34: "Boom", 35: "Boom", 36: "Boom", 37: "Boom", 38: "Boom",
	39: "ExplLarge", 40: "ExplLarge", 41: "ExplLarge", 42: "ExplLarge",
	43: "Boom", 44: "Boom", 45: "Boom", 46: "Boom", 47: "BushCrush", 48: "BushCrush", 49: "Boom", 50: "Boom",
	54: "Boom", 55: "Boom", 56: "Boom", 57: "Boom", 58: "Boom", 59: "Boom", 60: "Boom", 62: "Boom", 63: "Boom",
	64: "SmDirtHit", 65: "SmDirtHit", 66: "SmDirtHit", 67: "SmDirtHit",
	68: "Boom", 69: "Boom", 70: "Boom", 71: "Boom", 72: "Boom",
	74: "Boom", 75: "Boom", 76: "Boom", 77: "Boom", 78: "Boom", 79: "Boom", 80: "Boom", 81: "Boom", 82: "Boom",
	83: "Boom", 84: "Boom", 85: "Boom", 86: "Boom", 87: "Boom", 88: "Boom", 89: "Boom", 90: "Boom",
}
## A vehicle laid a mine / a mine went off (document 60); the explosion drawn is record 0x445058.
signal mine_added(mine: Mine)
signal mine_exploded(position: Vector2)

var pack: Pack
var pack_path: String = ""       ## re-passed to each spawned Vehicle/EnemyVehicle, see below
var level: LevelData
var world: Node  ## parent for every node this controller spawns
var vehicle: Vehicle
var enemy_vehicles: Array = []   ## EnemyVehicle nodes
var pools: Dictionary = {}       ## pool_id (String) -> TargetPool
var _projectiles: Array = []     ## live Projectile nodes, for target hit-testing
var _player_spawn_px := Vector2.ZERO
var gates: Dictionary = {}       ## Vector2i -> Gate
var mines: Array = []            ## live Mine nodes
var _boxes: Array = []           ## live ExplosionBox damage boxes, each with the tiles it has already destroyed
var _box_tick_acc := 0.0
var flags: Dictionary = {}       ## pool index (0, 1) -> FlagMarker
var match_finished := false
## Players in the match (DAT_00442fbc): 1 here. Two players enable the MSV's mine layer and switch off the scattered mines (document 75).
var players := 1
## Tiles with a mine on them (tile word bit 31, set by FUN_00409e30, shown on the radar in colour 0xc9).
var mine_tiles: Dictionary = {}
## Vehicles the player can still deploy, by type index (Tank, Jeep, MSV, Heli) = the level's T, J, A, H (default 3, 8, 3, 3; FUN_00413f00 stores them
## at 0x443030..33; the per-player bytes are at 0x48c880 + player * 0xd0 + 0xb8 + type). 255 means unlimited. Creating a vehicle spends one
## (FUN_0040b6xx: `if (stock != 0xff && stock != 0) stock--`), a vehicle that docks at its base returns one (0x42f1c3: `if (stock != 0xff) stock++`);
## all four at 0 is the lost state. The port's use of these (V switching, respawn) is a PLACEHOLDER: the original's choice of vehicle at its base is untraced.
var vehicle_stock: Array[int] = [3, 8, 3, 3]
var winner_idx := -1
var _crushing: Dictionary = {}   ## tiles already flattened and waiting for their state change
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
	_place_start_mines()
	_setup_target_pools()
	impact_effect.connect(_on_impact_effect_sound)


func _on_impact_effect_sound(record_addr: String, _position: Vector2) -> void:
	if vehicle == null:
		return
	if IMPACT_SOUND_CUES.has(record_addr):
		vehicle.sound_cue.emit(IMPACT_SOUND_CUES[record_addr])
	elif IMPACT_SOUND_CUES_RANDOM.has(record_addr):
		var choices: Array = IMPACT_SOUND_CUES_RANDOM[record_addr]
		vehicle.sound_cue.emit(choices[randi() % choices.size()])


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
	vehicle.colour = level.side_colour(player_team)
	world.add_child(vehicle)
	vehicle.setup(pack)
	vehicle.level = level
	vehicle.blocked_test = vehicle_blocked
	vehicle.position = (Vector2(float(sp.get("x", 0)), float(sp.get("y", 0))) + Vector2(0.5, 0.5)) * tile
	vehicle.shot.connect(_on_vehicle_shot.bind(vehicle))
	vehicle.mine_dropped.connect(_on_mine_dropped.bind(vehicle))
	vehicle.aim_target = _pick_missile_target
	vehicle.dock_check = can_dock
	vehicle.dock_requested.connect(_begin_dock)
	vehicle.drowned.connect(_on_player_destroyed)
	vehicle.destroyed.connect(_on_player_destroyed)
	_player_spawn_px = vehicle.position
	var vp: Dictionary = level.vehicle_params
	# one stock per roster vehicle, from the level's VHCL letter or the roster's default (document 73; vehicles/roster.json)
	vehicle_stock = []
	for entry in pack.vehicle_roster:
		vehicle_stock.append(int(vp.get(String(entry.get("stock_key", "")), int(entry.get("default_stock", 0)))))
	_take_stock(vehicle.vehicle_type)   # the first vehicle is created like any other
	vehicle.mine_layer_enabled = vehicle.mine_layer_enabled or players > 1

	for other_sp in level.spawn_points:
		if int(other_sp.get("team", 0)) == player_team:
			continue
		var enemy := EnemyVehicle.new()
		enemy.pack_path = pack_path
		enemy.team = "tan" if int(other_sp.get("team", 0)) == 0 else "green"
		enemy.colour = level.side_colour(int(other_sp.get("team", 0)))
		world.add_child(enemy)
		enemy.setup(pack)
		enemy.level = level
		enemy.blocked_test = vehicle_blocked
		enemy.position = (Vector2(float(other_sp.get("x", 0)), float(other_sp.get("y", 0))) + Vector2(0.5, 0.5)) * tile
		enemy.target = vehicle
		enemy.shot.connect(_on_vehicle_shot.bind(enemy))
		enemy.destroyed.connect(_drop_carried_flags)
		enemy.drowned.connect(_drop_carried_flags)
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
## FUN_00415b00 (document 61): where the Jeep missile goes. In order: an enemy vehicle on the ground within 61.2
## units; else the last tile that blocked this vehicle, if it still has hit points and is within 61.2 units (its
## centre plus the decoration jitter); else a random point ahead. (The original also considers the last enemy
## object touched, state +0xa8; vehicle-vs-vehicle contact is not modelled.)
const MISSILE_RANGE := 0x3d3ab7 / 65536.0  ## 61.23 units


func _pick_missile_target(v: Vehicle) -> Vector2:
	var best := INF
	var target := Vector2.ZERO
	for o in [vehicle] + enemy_vehicles:
		if o == null or not is_instance_valid(o) or not o.alive or o.team == v.team:
			continue
		var d := v.position.distance_to(o.position)
		if d < MISSILE_RANGE and d < best:
			best = d
			target = o.position
	if best < INF:
		return target
	var t := v.last_blocked_tile
	if t.x >= 0 and t.y >= 0 and t.x < level.width and t.y < level.height and level.get_coastal_id(t.x, t.y) != 0:
		if _tile_hp.get(t, _initial_tile_hp(t)) > 0:
			var tsz := float(pack.tile_size_px)
			var c := (Vector2(t) + Vector2(0.5, 0.5)) * tsz
			var info := pack.get_coastal_shapes(level.get_coastal_id(t.x, t.y))
			if info.get("jitter", false):
				c += level.jitter_at(t.x, t.y)
			if v.position.distance_to(c) < MISSILE_RANGE:
				return c
	return v.random_aim_point()


## The missile came down (z < 0) without hitting anything: FUN_00415730 picks the landing record by what it fell on
## (0 ground, 1 water, 2 the pavement tiles 0x49-0x53).
func _missile_lands(p: Projectile) -> void:
	var tsz := float(pack.tile_size_px)
	var tx := int(floor(p.position.x / tsz))
	var ty := int(floor(p.position.y / tsz))
	# the impact table (document 50): 0x448970 for the Tank-shell-like types, 0x448988 for the rest; entry 0 ground,
	# 1 water, 2 pavement
	var shell_like: bool = (p.impact_table == "0x448970") and not p.lob
	var record := "0x444740" if shell_like else "0x444840"
	if Water.class_at(level, pack, p.position) != 0:
		record = "0x4445b8" if shell_like else "0x4445e8"  # water (shallow counts: FUN_0042f5b0 samples the class around)
	elif tx >= 0 and ty >= 0 and tx < level.width and ty < level.height:
		var art := level.get_art_id(tx, ty) & 0x7F
		if art > 0x48 and art < 0x54:
			record = "0x444968" if shell_like else "0x444a30"
	impact_effect.emit(record, p.position)


func _on_vehicle_shot(spec: Dictionary, shooter: Vehicle) -> void:
	var p := Projectile.new()
	p.shooter = shooter
	world.add_child(p)
	p.colour = String(spec.get("colour", ""))
	if spec.get("kind", "") == "missile":
		p.team = spec["team"]
		p.heading_deg = float(spec["heading"])
		p.start_lob(spec["position"], float(spec["z"]), spec["target"])
		_projectiles.append(p)
		projectile_spawned.emit(p)
		return
	p.configure(pack, int(spec["type"]))
	p.z = float(spec["z"])
	if spec.has("pitch_deg"):
		p.start_pitched(float(spec["pitch_deg"]), float(spec.get("bonus", 0.0)))
	p.team = spec["team"]
	p.heading_deg = float(spec["heading"])
	p.global_position = spec["position"]
	p.prev_checked = spec["position"]
	_projectiles.append(p)
	projectile_spawned.emit(p)


func _process(delta: float) -> void:
	_update_death(delta)
	_update_dock(delta)
	_update_flags(delta)
	_update_mines(delta)
	for v in [vehicle] + enemy_vehicles:
		if v != null and is_instance_valid(v) and v.alive:
			_update_zone(v, delta)
	for t in gates.keys():
		var g: Gate = gates[t]
		g.tick(delta, _vehicle_in_bars)
		if g.finished:
			_remove_gate(g)
	_projectiles = _projectiles.filter(func(p): return is_instance_valid(p))
	for p in _projectiles:
		if p.is_queued_for_deletion():
			continue
		var from: Vector2 = p.prev_checked
		var to: Vector2 = p.global_position
		p.prev_checked = to
		if _shell_hits_tile(p, from, to) or _shell_hits_vehicle(p, from, to):
			p.queue_free()
		elif (p.lob or p.vertical) and p.z < 0.0:
			_missile_lands(p)
			p.queue_free()


const MINE_THROW_CUES := ["ThrowGrenade1_a", "ThrowGrenade1_b", "ThrowGrenade1_c"]


func _on_mine_dropped(at: Vector2, dropper: Vehicle) -> void:
	var m := Mine.new()
	m.dropper = dropper
	mine_tiles[_tile_of(at)] = true
	world.add_child(m)
	m.position = at
	mines.append(m)
	mine_added.emit(m)
	if vehicle != null:
		m.beep.connect(vehicle.sound_cue.emit.bind("Button"))   # FUN_00409cd0's fuse beep, sound 0x44b580 (documents 50/60/82)
	if dropper != null:
		# PORT CHOICE, not traced: document 82's three "Throw Grenade1" descriptors (Sound/Throw1-3.SDT) are all
		# named identically and read as launch-sound variants for the MSV's mine layer, but which one plays when
		# (random? alternating? by mine index?) was not found -- picked uniformly at random here.
		dropper.sound_cue.emit(MINE_THROW_CUES[randi() % 3])


func _tile_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / pack.tile_size_px)), int(floor(p.y / pack.tile_size_px)))


## The player's own home pad, in world pixels (its spawn point: document 77's docking tolerance is measured from this tile's centre).
func home_position() -> Vector2:
	return _player_spawn_px


## FUN_0042a030 (document 75): the mines scattered at the start. `count` comes from the level: M when it is set (not 0, not 255), else 4 * LEVL
## when M is 255 and LEVL is above 5 (one player only; two players force M = 0). Candidates are tiles with no coastal id, outside the 3 x 3 tiles
## around home, whose terrain art has bit 3 clear and is below 0x54: an art of 0x49-0x53 always counts, land arts (0, 3, 0x34-0x48) only when the tile
## above, below, left or right is art 0x49-0x59 (a road or pad). Each mine lands at a random spot 6-30 units into a randomly chosen candidate tile and
## a candidate is used once per pass. When the road-side list runs out, a second list (FUN_0042a430: the same tiles without the road-side test) supplies the rest.
## UNTRACED: the random numbers (FUN_0041d3d0's sequence; a seeded generator here).
func _place_start_mines() -> void:
	var m := int(level.vehicle_params.get("M", 255))
	var count := 0
	if m != 0 and m != 255:
		count = m
	elif m == 255 and players == 1 and level.levl_value > 5:
		count = level.levl_value * 4
	if count <= 0:
		return
	var home := _tile_of(_player_spawn_px)
	var rng := RandomNumberGenerator.new()
	rng.seed = level.tile_seed
	for relaxed in [false, true]:   # the first pass (road-side tiles), then FUN_0042a430's relaxed list for what is left
		if count <= 0:
			break
		var cands: Array[Vector2i] = []
		for y in level.height:
			for x in level.width:
				if _mine_candidate(x, y, home, relaxed):
					cands.append(Vector2i(x, y))
		while count > 0 and not cands.is_empty():
			var i := rng.randi_range(0, cands.size() - 1)
			var t := cands[i]
			cands.remove_at(i)
			var at := Vector2(t.x * pack.tile_size_px + rng.randi_range(0, 24) + 6, t.y * pack.tile_size_px + rng.randi_range(0, 24) + 6)
			if Water.class_at(level, pack, at) == 2:   # FUN_00409e30 refuses deep water
				continue
			_on_mine_dropped(at, null)
			count -= 1


func _mine_candidate(x: int, y: int, home: Vector2i, relaxed := false) -> bool:
	if level.get_coastal_id(x, y) != 0:
		return false
	if not (x <= home.x - 2 or x >= home.x + 2 or y <= home.y - 2 or y >= home.y + 2):
		return false
	var art := level.get_art_id(x, y) & 0x7F
	if (art & 8) != 0 or art >= 0x54:
		return false
	if art >= 0x49:
		return true
	if art != 3 and art != 0 and art < 0x34:
		return false
	if relaxed:   # FUN_0042a430 with its last argument 0: any such land tile
		return true
	for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var n: Vector2i = Vector2i(x, y) + d
		if n.x < 0 or n.y < 0 or n.x >= level.width or n.y >= level.height:
			continue
		var na := level.get_art_id(n.x, n.y) & 0x7F
		if na > 0x48 and na < 0x5A:
			return true
	return false


## Document 60. Mines age and blink (game/mine.gd). A vehicle that MOVES while its shape touches a mine's 32 x 32
## trigger box sets it off (FUN_0042bd40 tests movers; FUN_00409dd0 detonates on a class-1 object). Its explosion
## is record 0x445058, which owns a damage box (game/explosion_box.gd).
func _update_mines(delta: float) -> void:
	var ticks := delta * Vehicle.TICK_HZ
	for m in mines.duplicate():
		m.advance(ticks)
	for v in [vehicle] + enemy_vehicles:
		if v == null or not is_instance_valid(v) or not v.alive or not v.moving:
			continue
		for m in mines.duplicate():
			if not m.armed:
				continue
			if not Collision.z_ranges_overlap(0.0, v.hit_z[1], Mine.Z_LO, Mine.Z_HI):
				continue
			if Collision.polygon_hits_box(v.hit_polygon(), m.position, Mine.TRIGGER_BOX):
				_detonate_mine(m)
	_update_boxes(ticks)


func _detonate_mine(m: Mine) -> void:
	mines.erase(m)
	mine_tiles.erase(_tile_of(m.position))   # PLACEHOLDER: the flag's clearing is assumed (FUN_00409dd0 not read for it)
	var at := m.position
	m.queue_free()
	_boxes.append({"box": ExplosionBox.new(pack.get_explosion("0x445058"), at), "destroyed": {}})
	mine_exploded.emit(at)
	if vehicle != null:
		vehicle.sound_cue.emit("ExplLarge")   # record 0x445058's script: SOUND 14 then SOUND 1 (document 84); only the first is reproduced


## Every whole tick a live damage box hurts what it overlaps: vehicles (layer 2, z 0..their height) get
## FUN_0040c460 with |rate| x ticks, and tiles with shapes get FUN_0042e8c0 with the same amount (document 44
## rule: max(1, whole damage) hit points). Mines are not touched (their masks lack the box's layer 0x20).
func _update_boxes(ticks: float) -> void:
	_box_tick_acc += ticks
	var n := floori(_box_tick_acc)
	_box_tick_acc -= n
	for entry in _boxes.duplicate():
		var b: ExplosionBox = entry["box"]
		if not b.advance(ticks):
			_boxes.erase(entry)
			continue
		if n < 1 or not b.active:
			continue
		var dmg := b.damage_per_tick * n
		for v in [vehicle] + enemy_vehicles:
			if v == null or not is_instance_valid(v) or not v.alive:
				continue
			if (b.mask & Vehicle.HIT_LAYER) == 0 or (Vehicle.HIT_MASK & 0x20) == 0:
				continue
			if not Collision.z_ranges_overlap(0.0, v.hit_z[1], b.z_lo, b.z_hi):
				continue
			if Collision.polygon_hits_box(v.hit_polygon(), b.position, b.box()):
				v.take_damage(dmg)
		_box_damage_tiles(entry, dmg)


func _box_damage_tiles(entry: Dictionary, dmg: float) -> void:
	var b: ExplosionBox = entry["box"]
	var tsz := float(pack.tile_size_px)
	var x0 := int(floor((b.position.x - b.half_x) / tsz)) - 1
	var x1 := int(floor((b.position.x + b.half_x) / tsz)) + 1
	var y0 := int(floor((b.position.y - b.half_y) / tsz)) - 1
	var y1 := int(floor((b.position.y + b.half_y) / tsz)) + 1
	var box_poly := PackedVector2Array([
		b.position + Vector2(-b.half_x, -b.half_y), b.position + Vector2(b.half_x, -b.half_y),
		b.position + Vector2(b.half_x, b.half_y), b.position + Vector2(-b.half_x, b.half_y)])
	for ty in range(y0, y1 + 1):
		for tx in range(x0, x1 + 1):
			var t := Vector2i(tx, ty)
			if t.x < 0 or t.y < 0 or t.x >= level.width or t.y >= level.height or entry["destroyed"].has(t):
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
				if (int(sh["layer"]) & b.mask) == 0 or (int(sh["mask"]) & 0x20) == 0:
					continue
				if not Collision.z_ranges_overlap(float(sh["z"][0]), float(sh["z"][1]), b.z_lo, b.z_hi):
					continue
				var origin: Vector2 = centre + Vector2(sh["off"][0], sh["off"][1])
				var hit := false
				if int(sh["type"]) == 2:
					hit = Collision.polygon_hits_box(box_poly, origin, sh["box"])
				elif int(sh["type"]) == 3:
					var poly := PackedVector2Array()
					for pt in sh["poly"]:
						poly.append(origin + Vector2(pt[0], pt[1]))
					hit = Collision.polygons_hit(box_poly, poly)
				if hit:
					if _damage_tile_amount(t, id, dmg):
						entry["destroyed"][t] = true
					break


## Document 53: a shell is a swept point (z 7 +- 1.5); a living vehicle other than its shooter is hit when the
## segment meets its collision polygon (FUN_00414e60 -> FUN_0040c460, document 47).
func _shell_hits_vehicle(p: Projectile, from: Vector2, to: Vector2) -> bool:
	var targets: Array = [vehicle] + enemy_vehicles
	for v in targets:
		if v == null or not is_instance_valid(v) or not v.alive or v == p.shooter:
			continue
		if not Collision.shell_collides_with(Vehicle.HIT_LAYER, Vehicle.HIT_MASK):
			continue
		if not Collision.shell_z_overlaps(p.z, v.hit_z[0] + v.z, v.hit_z[1] + v.z):
			continue
		if Collision.segment_hits_polygon(from, to, v.hit_polygon()):
			v.take_damage(p.damage)
			impact_effect.emit("0x444b68", to)  # surface 3, object hit
			return true
	return false


## FUN_0040c540 (document 55): while a vehicle stands still (`moving` false) it stays in the zone it entered as
## long as its shape still overlaps that zone's box, else the zone is forgotten; over a refuel zone (kind 1)
## the fuel rises by 0.5 per tick up to the tank's maximum. (Rearm, kind 2, refills the ammunition: Vehicle.rearm.
## Pick-up, kind 3, spawns a carried object: not modelled.) While moving nothing happens and the zone stays.
func _update_zone(v: Vehicle, delta: float) -> void:
	if v.zone_kind == 3:
		# Kind 3 (FUN_00432550, run whatever the vehicle is doing): a tile of the vehicle's own team turns into
		# a live gate object and the zone is forgotten.
		v.zone_kind = 0
		_create_gate(v)
		return
	if v.zone_kind == 0 or v.moving:
		return
	if not Collision.polygon_hits_box(v.hit_polygon(), v.zone_origin, v.zone_box):
		v.zone_kind = 0
		return
	if v.zone_kind == 1:
		v.fuel = minf(v.fuel_max, v.fuel + Vehicle.REFUEL_PER_TICK * delta * Vehicle.TICK_HZ)
	elif v.zone_kind == 2:
		v.rearm(delta)   # FUN_0040c540 kind 2 (document 72)


## FUN_00432550: only if the tile still has hit points and its variant bits equal the player index; the
## decoration is cleared (the gate object carries the id) and the vehicle is attached as the one that opens it.
func _create_gate(v: Vehicle) -> void:
	var t: Vector2i = v.zone_tile
	if gates.has(t):
		return
	var id := level.get_coastal_id(t.x, t.y)
	var gd: Dictionary = pack.gates.get(str(id), {})
	if gd.is_empty() or level.get_variant(t.x, t.y) != v.player_index() or _initial_tile_hp(t) <= 0:
		return
	var g := Gate.new()
	g.setup(t, id, gd, level.get_variant(t.x, t.y), float(pack.tile_size_px), v)
	g.colour = level.side_colour(g.variant)
	gates[t] = g
	level.set_coastal_id(t.x, t.y, 0)
	g.sound_cue.connect(v.sound_cue.emit)
	gate_created.emit(g)


## Debug-only (RF_DEBUG_GATE="x,y"): wake the gate on that tile for the player regardless of team.
func debug_open_gate(t: Vector2i) -> void:
	vehicle.zone_tile = t
	var id := level.get_coastal_id(t.x, t.y)
	var gd: Dictionary = pack.gates.get(str(id), {})
	if gd.is_empty() or gates.has(t):
		return
	var g := Gate.new()
	g.setup(t, id, gd, level.get_variant(t.x, t.y), float(pack.tile_size_px), vehicle)
	g.colour = level.side_colour(g.variant)
	gates[t] = g
	level.set_coastal_id(t.x, t.y, 0)
	g.sound_cue.connect(vehicle.sound_cue.emit)
	gate_created.emit(g)


func _remove_gate(g: Gate) -> void:
	gates.erase(g.tile)
	level.set_coastal_id(g.tile.x, g.tile.y, g.coastal_id)
	gate_removed.emit(g)


## A vehicle overlapping any of these bars (FUN_0042bd40 on the gate while it closes).
func _vehicle_in_bars(bars: Array) -> bool:
	for other in [vehicle] + enemy_vehicles:
		if other == null or not is_instance_valid(other) or not other.alive:
			continue
		for b in bars:
			if Collision.polygon_hits_box(other.hit_polygon(), b["origin"], b["box"]):
				return true
	return false


## Document 54 (FUN_0042c830 -> FUN_0042bd40 -> FUN_0042bb10): would this vehicle's shape overlap a tile shape
## or another vehicle at `at` / `heading`? Tiles first: the nine around it, each coastal id's shape chain
## placed as for shells; a shape only counts if the layer/mask and z rules pass, and then the coastal entry's
## own callback (`callback` in coastal_shapes.json) decides whether the vehicle is blocked, passes, or crushes
## the tile; a tile shape without a callback blocks (the vehicle class's tile callback FUN_0040c130 returns 1).
## Another living vehicle always blocks (FUN_0040c150 returns 5).
func vehicle_blocked(v: Vehicle, at: Vector2, heading_deg: float) -> bool:
	var poly := v.polygon_for(at, heading_deg)
	var tsz := float(pack.tile_size_px)
	var tx := int(floor(at.x / tsz))
	var ty := int(floor(at.y / tsz))
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
				if not Collision.vehicle_collides_with(Vehicle.HIT_LAYER, Vehicle.HIT_MASK, int(sh["layer"]), int(sh["mask"])):
					continue
				if not Collision.z_ranges_overlap(v.hit_z[0] + v.z, v.hit_z[1] + v.z, float(sh["z"][0]), float(sh["z"][1])):
					continue
				var origin: Vector2 = centre + Vector2(sh["off"][0], sh["off"][1])
				var hit := false
				if int(sh["type"]) == 2:
					hit = Collision.polygon_hits_box(poly, origin, sh["box"])
				elif int(sh["type"]) == 3:
					var tp := PackedVector2Array()
					for pt in sh["poly"]:
						tp.append(origin + Vector2(pt[0], pt[1]))
					hit = Collision.polygons_hit(poly, tp)
				if hit and _tile_blocks_vehicle(v, t, id, info, sh):
					v.last_blocked_tile = t
					return true
	for gt in gates:
		var g: Gate = gates[gt]
		if at.distance_to(g.centre) > 64.0:
			continue
		for b in g.bars():
			if Collision.polygon_hits_box(poly, b["origin"], b["box"]):
				return true
	for other in [vehicle] + enemy_vehicles:
		if other == null or other == v or not is_instance_valid(other) or not other.alive:
			continue
		if at.distance_to(other.position) > 40.0 or absf(other.z - v.z) > 12.0:
			continue
		if Collision.polygons_hit(poly, other.hit_polygon()):
			return true
	return false


## The coastal entry's tile callback for a vehicle (documents 54): FUN_00436640 (bushes), FUN_00436610 (rocks),
## FUN_004366f0 (zones), FUN_00436a50 (crates); 8 = pass through, 1/0 = blocked. Speeds are 0x8000 = 0.5
## units per tick in the original (31.25 px/s here).
func _tile_blocks_vehicle(v: Vehicle, t: Vector2i, id: int, info: Dictionary, sh: Dictionary) -> bool:
	var crush_speed := 0.5 * Vehicle.TICK_HZ
	match String(info.get("callback", "0x0")):
		"0x436640":
			if int(sh["mask"]) == 4:
				return false
			if v.vehicle_type == 1:
				return true
			if v.speed > crush_speed:
				_crush_tile(t, id)
				v.sound_cue.emit("BushCrush")   # document 54/82: 0x44b6b8
				return false
			return true
		"0x436610":
			return v.vehicle_type == 1
		"0x4366f0":
			# FUN_004366f0: a shape whose byte +8 has bit 1 is a zone a vehicle may enter; the vehicle remembers
			# it (state +0x68 tile, +0x6c shape) and byte +9 says what it is (1 refuel, 2 rearm, 3 pick-up)
			if (int(sh.get("b8", 0)) & 2) != 0:
				v.zone_kind = int(sh.get("b9", 0))
				v.zone_tile = t
				v.zone_origin = (Vector2(t) + Vector2(0.5, 0.5)) * pack.tile_size_px + Vector2(sh["off"][0], sh["off"][1])
				v.zone_box = sh["box"]
				return false
			return true
		"0x432d80":
			_ruin_grab(v, t)
			return true  # it answers 0: the tile's posts still block
		"0x436a50":
			if v.speed > crush_speed:
				_crush_tile(t, id)
				return false
			return true
	return true


## FUN_00432d80, the callback of coastal id 63 (document 54): when a Jeep's shape meets one of the ruin's four posts, a flag
## that sits on this tile (its grid cell is the tile), is not carried and has no "dropper" (flag +0x70) is attached to the Jeep,
## unless the Jeep already carries a flag. So the Jeep takes the flag by touching the ruin, without entering it.
func _ruin_grab(v: Vehicle, t: Vector2i) -> void:
	if v.vehicle_type != 1 or match_finished or _carrying_any(v):
		return
	for flag in flags.values():
		if flag.carrier != null or flag.dropper != null:
			continue
		var ft := Vector2i(int(floor(flag.position.x / pack.tile_size_px)), int(floor(flag.position.y / pack.tile_size_px)))
		if ft == t:
			_attach_flag(flag, v)
			return


## FUN_0042e8c0 with damage 100 (0x640000): every tile in the table has at most 6 hit points, so it is destroyed.
func _crush_tile(t: Vector2i, _id: int) -> void:
	if _crushing.has(t):
		return
	_crushing[t] = true
	_tile_hp.erase(t)
	tile_crushed.emit(t)


## No life system is traced yet (NEXT_STEPS): the player simply respawns at the start point.
## A vehicle that dies leaves the flag it carries where it hangs (document 57: "a Jeep that dies while carrying leaves the
## flag where it is"). This must happen at the moment of death: the player respawns at once, so waiting for the per-frame
## check would let the flag ride the new vehicle back to the home tile (and win the match).
func _drop_carried_flags(v: Vehicle) -> void:
	for f in flags.values():
		if f.carrier == v:
			f.carrier = null
			f.dropper = v


func _on_player_destroyed(v: Vehicle) -> void:
	_drop_carried_flags(v)
	if death_phase != 0:
		return  # already in the loss sequence (a drowning and a hit landing together)
	death_phase = 1
	_death_ticks = 0.0
	_death_acc = 0.0
	skull_scale_raw = SKULL_SCALE_START_RAW
	skull_angle_raw = 0
	skull_timer_raw = 0
	skull_alpha = 1.0


## The loss sequence (document 88), the player's mode state machine from `FUN_0040c7e0` (the wreck's init schedules it) to the vehicle choice. Whole ticks:
## 1 the wreck lies there for the type's delay (record +0x260: 120, the Heli 200); 2 the skull spins in over the live view for 30 (FUN_004184d0); 3 the view fades to black at
## 1310/65536 a tick and the skull laughs (`Laugh`) once it is dark (FUN_00418830); 4 the mouth animation runs 60 table steps at 0.3 a tick, 201 ticks (FUN_004188c0), then
## FUN_0040b260 asks whether any vehicle is left (none = the match is lost, at once); 5 the skull fades out at 0x11eb/65536 a tick (FUN_004189a0) and the choice opens
## (FUN_00418290 -> FUN_00417ad0), the same grid as after a dock (`_finish_player_death`). The "any vehicle left?" test is about JEEPS only (`_jeep_left`, document 95).
func _update_death(delta: float) -> void:
	if death_phase == 0:
		return
	_death_acc += delta * Vehicle.TICK_HZ
	while _death_acc >= 1.0 - 1e-6 and death_phase != 0:
		_death_acc = maxf(_death_acc - 1.0, 0.0)
		_death_tick()


func _death_tick() -> void:
	if death_phase == 1:
		_death_ticks += 1.0
		if _death_ticks >= float(pack.vehicle_value(vehicle.vehicle_type, "stats.death_wait_ticks", 120)):
			death_phase = 2
			_death_ticks = 0.0
		return
	_skull_step()
	if death_phase == 2:
		_death_ticks += 1.0
		if _death_ticks > DEATH_SKULL_LEAD_TICKS:
			death_phase = 3
	elif death_phase == 3:
		view_fade = maxf(view_fade - DEATH_DARKEN_PER_TICK, 0.0)
		if view_fade <= 0.0:
			death_phase = 4
			vehicle.sound_cue.emit("Laugh")   # FUN_00418830: `PUSH 0x44b790; CALL FUN_004232d0`, the moment the darkening ends
	elif death_phase == 4:
		skull_timer_raw += SKULL_TIMER_RATE_RAW
		if skull_timer_raw > 0x3bffff:
			if not _jeep_left():
				death_phase = 0
				match_finished = true
				winner_idx = -2
				vehicle.frozen = true
				out_of_vehicles.emit()
				return
			skull_timer_raw = 0
			skull_alpha = 1.0
			death_phase = 5
	elif death_phase == 5:
		skull_alpha -= DEATH_SKULL_FADE_PER_TICK
		if skull_alpha <= 0.0:
			skull_alpha = 0.0
			death_phase = 0
			_finish_player_death()


## FUN_00418510's per-tick state: the scale grows 0x666 a tick to 0x13333 (1.2) and the angle turns 0x28000 of 0x400000 a tick until the scale is full, then the turn ends
## upright (angle 0) at the first wrap.
func _skull_step() -> void:
	if skull_scale_raw < SKULL_SCALE_MAX_RAW:
		skull_scale_raw = mini(skull_scale_raw + SKULL_SCALE_STEP_RAW, SKULL_SCALE_MAX_RAW)
	if skull_scale_raw != SKULL_SCALE_MAX_RAW or skull_angle_raw != 0:
		var a := skull_angle_raw + SKULL_SPIN_RAW
		if a < 0x400000 or skull_scale_raw < SKULL_SCALE_MAX_RAW:
			skull_angle_raw = a & 0x3fffff
		else:
			skull_angle_raw = 0


## The skull's mouth-open frame (1 closed .. 7 widest): the traced table indexed by the animation timer's whole part.
func skull_frame() -> int:
	return SKULL_FRAMES[mini(skull_timer_raw >> 16, SKULL_FRAMES.size() - 1)]


## The skull's screen rotation in degrees: the whole part of the angle is one of 64 steps.
func skull_angle_deg() -> float:
	return float(skull_angle_raw >> 16) * 5.625


func skull_scale() -> float:
	return float(skull_scale_raw) / 65536.0


## FUN_0040b260's one-player answer (document 95): the player is not lost while they have a Jeep, in stock (byte +0xb9, 255 = unlimited) or alive under them, because only a
## Jeep can carry the flag home (document 57); Tanks, MSVs and Helis left do not count. The dead vehicle is not counted (the check runs after it is gone).
func _jeep_left() -> bool:
	return vehicle_stock[1] != 0


## The end of the loss sequence (document 95): FUN_00418290, installed by phase 5, opens the vehicle CHOICE (FUN_00417ad0) on the black screen, the cursor on the first type
## with stock left (FUN_00418290 scans the four stock bytes; `_open_selection` does the same). The dead vehicle's stock was already spent when it was created, so nothing
## is taken here; `confirm_selection` spends the chosen one and runs the same undock script and rise as after a dock. The wreck's own object is not modelled separately
## (the vehicle body is reused), so it disappears at this point, under the black screen.
func _finish_player_death() -> void:
	var t := _tile_of(_player_spawn_px)
	_pad_centre = (Vector2(t) + Vector2(0.5, 0.5)) * pack.tile_size_px
	vehicle.respawn(_pad_centre)
	vehicle.z = DOCK_MIN_DEPTH   # held under the pad like a docked vehicle until the choice is confirmed
	vehicle.docked = true
	view_fade = 0.0
	_open_selection()


## Spends one vehicle of type `t` (false when none is left; 255 is unlimited and never counts down).
func _take_stock(t: int) -> bool:
	if t < 0 or t >= vehicle_stock.size():
		return true   # not a roster vehicle (a mod's extra definition): no stock to count
	if vehicle_stock[t] == 255:
		return true
	if vehicle_stock[t] <= 0:
		return false
	vehicle_stock[t] -= 1
	return true


func _return_stock(t: int) -> void:
	if t >= 0 and t < vehicle_stock.size() and vehicle_stock[t] != 255:
		vehicle_stock[t] = mini(vehicle_stock[t] + 1, 254)


## Document 53: the tile under the shell and its eight neighbours are tested (FUN_0042bd40 / FUN_0042bf30);
## each coastal id's first descriptor carries collision shapes placed at the tile centre (plus the decoration
## jitter and the shape's own offset). A hit ends the shell (FUN_00414dd0) and damages the tile
## (FUN_0042e8c0), with no other test of what counts as a "target": every tile with a shape can be shot.
func _shell_hits_tile(p: Projectile, from: Vector2, to: Vector2) -> bool:
	for gt in gates:
		var g: Gate = gates[gt]
		if to.distance_to(g.centre) > 64.0:
			continue
		if not Collision.shell_z_overlaps(p.z, 0.0, 16.0):
			continue
		for b in g.bars():
			if Collision.segment_hits_box(from, to, b["origin"], b["box"]):
				impact_effect.emit("0x444ac8", to)
				_damage_tile(g.tile, g.coastal_id, p)
				return true
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
				if not Collision.shell_z_overlaps(p.z, float(sh["z"][0]), float(sh["z"][1])):
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
	_damage_tile_amount(t, id, p.damage)


## Returns true when the tile was destroyed by this call.
func _damage_tile_amount(t: Vector2i, id: int, damage: float) -> bool:
	var hp: int = _tile_hp.get(t, _initial_tile_hp(t))
	if hp <= 0:
		return false
	var dmg := maxi(int(damage), 1)
	if hp > dmg:
		_tile_hp[t] = hp - dmg
		return false
	_tile_hp.erase(t)
	if vehicle != null and DESTROY_SOUND_CUES.has(id):
		vehicle.sound_cue.emit(DESTROY_SOUND_CUES[id])
	if gates.has(t):
		_remove_gate(gates[t])  # FUN_00432460: the decoration returns, then the tile is destroyed as usual
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
		return true
	tile_destroyed.emit(t)
	return true


## The scene calls this once a crushed tile's state has changed.
func tile_state_applied(t: Vector2i) -> void:
	_crushing.erase(t)
	_tile_hp.erase(t)


func _initial_tile_hp(tile: Vector2i) -> int:
	var id := level.get_coastal_id(tile.x, tile.y)
	if gates.has(tile):
		id = (gates[tile] as Gate).coastal_id
	var d := pack.get_coastal_damage(id)
	return maxi(int(d.get("hp", 0)), 0)


## Phase 4 step 7 (first pass): spawns the flag-marker fallthrough (see the call site's
## comment and game/flag_marker.gd's docstring) at the position of the pool's last-destroyed
## target. Purely visual -- see flag_marker.gd for exactly what this isn't yet.
func _spawn_flag(pool_id: String, at_position: Vector2) -> void:
	var idx := 0 if pool_id == "a" else 1
	if flags.has(idx):
		return
	var flag := FlagMarker.new()
	flag.owner_idx = idx
	flag.colour = level.side_colour(idx)
	flags[idx] = flag
	world.add_child(flag)
	flag.setup(pack)
	flag.position = at_position
	flag.last_safe = at_position  # DAT_00459a20: the spawn position is the first "last safe position"
	flag_spawned.emit(flag, pool_id)
	if _debug_target_log:
		print("frame=%d pool=%s FLAG SPAWNED at=%s" % [
			Engine.get_process_frames(), pool_id, at_position])


## ---- The flag (document 57) ----------------------------------------------------------------------------------
## Class 12 (0x44e3c0). Only a Jeep (vehicle type 1) can take it: the flag's object-collision callback
## FUN_00432d00 and the ruin tile's FUN_00432d80 both test `record[0] == 1`, and the grab action FUN_00432e40 is
## wired only to the Jeep's third weapon slot. Contact with a Jeep that carries nothing attaches the flag; the
## flag then hangs from it at (3.75, 6.75) in its own frame (+x right, +y behind); the action button drops it (or
## takes one that is touching); and a Jeep carrying the OTHER pool's flag that stands on its home tile (art 90 for
## player 0, 91 for player 1) ends the match (FUN_0040d990 -> FUN_004225d0).
const FLAG_BOX := [-3.0, -4.0, 5.0, 4.0]  ## the flag's shape at 0x440448: z 0-8, layer 1, mask 6
const FLAG_CARRY_OFFSET := Vector2(3.75, 6.75)
const HOME_ART_BASE := 90


func _flag_touching(flag: FlagMarker, v: Vehicle) -> bool:
	return Collision.vehicle_collides_with(Vehicle.HIT_LAYER, Vehicle.HIT_MASK, 1, 6) \
			and Collision.z_ranges_overlap(v.hit_z[0], v.hit_z[1], 0.0, 8.0) \
			and Collision.polygon_hits_box(v.hit_polygon(), flag.position, FLAG_BOX)


func _carrying_any(v: Vehicle) -> bool:
	for f in flags.values():
		if f.carrier == v:
			return true
	return false


func _attach_flag(flag: FlagMarker, v: Vehicle) -> void:
	flag.carrier = v
	flag.dropper = null


## FUN_0042f730 answers 0 ("land") for terrain art 0 or 3 and everything above 0x33; the flag records its position on such
## tiles as its last safe position.
func _land_tile_at(p: Vector2) -> bool:
	var tx := int(floor(p.x / pack.tile_size_px))
	var ty := int(floor(p.y / pack.tile_size_px))
	if tx < 0 or ty < 0 or tx >= level.width or ty >= level.height:
		return false
	var art := level.get_art_id(tx, ty) & 0x7F
	return art == 0 or art == 3 or art > 0x33


func _update_flags(delta: float) -> void:
	if match_finished:
		return
	for idx in flags.keys():
		var flag: FlagMarker = flags[idx]
		if flag.carrier != null:
			var c: Vehicle = flag.carrier
			if not is_instance_valid(c) or not c.alive:
				flag.carrier = null  # the carrier died: the flag stays where it is
				continue
			var rad := deg_to_rad(c.heading_deg)
			var fwd := Vector2(cos(rad), sin(rad))
			var right := Vector2(-fwd.y, fwd.x)
			flag.position = c.position + right * FLAG_CARRY_OFFSET.x + fwd * -FLAG_CARRY_OFFSET.y
			if _land_tile_at(flag.position):
				flag.last_safe = flag.position
			flag.advance_frames(c.speed > 0.0, delta)
			flag.advance_heading(delta)
			continue
		# dropped: on land it stays and records the spot, in water it drifts back toward the last safe position
		if Water.class_at(level, pack, flag.position) == 0:
			flag.drift_speed = 0.0
			if _land_tile_at(flag.position):
				flag.last_safe = flag.position
		else:
			var ticks := delta * Vehicle.TICK_HZ
			flag.drift_speed = move_toward(flag.drift_speed, FlagMarker.DRIFT_MAX, FlagMarker.DRIFT_ACCEL * ticks)
			var to := flag.last_safe - flag.position
			if to.length() > 0.001:
				var step_idx := floori(fposmod(rad_to_deg(to.angle()) + 90.0, 360.0) / 5.625)  # a 64-step heading, rounded down
				var h := deg_to_rad(step_idx * 5.625 - 90.0)
				flag.position += Vector2(cos(h), sin(h)) * flag.drift_speed * ticks
		flag.advance_frames(true, delta)
		flag.advance_heading(delta)
		if flag.dropper != null and (not is_instance_valid(flag.dropper) or not _flag_touching(flag, flag.dropper)):
			flag.dropper = null
		for v in [vehicle] + enemy_vehicles:
			if v == null or not is_instance_valid(v) or not v.alive or v.vehicle_type != 1:
				continue
			if v == flag.dropper or _carrying_any(v):
				continue
			if _flag_touching(flag, v):
				_attach_flag(flag, v)
				break
	for v in [vehicle] + enemy_vehicles:
		if v != null and is_instance_valid(v) and v.alive and v.vehicle_type == 1:
			_check_capture(v)
			_update_compass_chime(v)


## The Jeep's compass value (document 71), FUN_0040d990's `state + 0x5c`, -16..16. The target is the other pool's flag while the Jeep is not
## carrying it, else home (also when the flag lies more than 90 degrees to the side). The value only says how well the Jeep points at the target
## (no left/right): within 11.25 degrees 16, else 15 falling to 12 at 90 degrees (`(0x10000 - (angle >> 6)) >> 12`, angle in 22-bit turns);
## behind, a flag target falls back to home, and a home target shows 0. A flag target is negative, a home target positive.
## UNTRACED: the home position is taken as the player's spawn (the original reads a pointer at 0x48c8b4 + player * 0x34).
func compass_value(v: Vehicle) -> int:
	var flag: FlagMarker = flags.get(v.player_index() ^ 1)
	if flag != null and flag.carrier != v:
		var m := _compass_magnitude(v, flag.position)
		if m >= 0:
			return -m
	return maxi(_compass_magnitude(v, _player_spawn_px), 0)


## 16 aligned, 15..12 within 90 degrees, -1 beyond (the original's iVar4).
func _compass_magnitude(v: Vehicle, target: Vector2) -> int:
	var to := target - v.position
	var steps := floori(fposmod(rad_to_deg(to.angle()), 360.0) / 5.625)   # FUN_00422e70 rounds the heading down to 64 steps
	var diff := fposmod(steps * 5.625 - v.heading_deg, 360.0)             # 0..360
	var turn := int(diff / 360.0 * 4194304.0) & 0x3FFFFF                 # 22-bit turns
	if (turn & 0x3E0000) == 0:
		return 16
	if turn > 0x1FFFFF:
		turn = (-turn) & 0x3FFFFF
	if turn < 0x100000:
		return mini((0x10000 - (turn >> 6)) >> 12, 15)
	return -1


var _compass_aligned: Dictionary = {}   ## Vehicle -> bool, FUN_0040d990's state+0x60 (document 71/82): plays a chime the first tick the compass reads -16


## FUN_0040d990: "state + 0x60 = (value == -16); play 0x44b928 the first time it becomes -16" (document 71).
func _update_compass_chime(v: Vehicle) -> void:
	var aligned := compass_value(v) == -16
	if aligned and not _compass_aligned.get(v, false):
		v.sound_cue.emit("DumbDirect")
	_compass_aligned[v] = aligned


## FUN_0040d990: the Jeep carries the flag of the other pool and stands on its own home tile.
func _check_capture(v: Vehicle) -> void:
	var own := v.player_index()
	var flag: FlagMarker = flags.get(own ^ 1)
	if flag == null or flag.carrier != v:
		return
	var t := Vector2i(int(floor(v.position.x / pack.tile_size_px)), int(floor(v.position.y / pack.tile_size_px)))
	if t.x < 0 or t.y < 0 or t.x >= level.width or t.y >= level.height:
		return
	if (level.get_art_id(t.x, t.y) & 0x7F) == HOME_ART_BASE + own:
		match_finished = true
		winner_idx = own
		for x in [vehicle] + enemy_vehicles:
			if x != null and is_instance_valid(x):
				x.frozen = true
		match_over.emit(own)


## FUN_00432e40, from the Jeep's action button: for the vehicle's own pool first, then the other: a flag it
## carries is let go (and cannot be re-taken until it stops touching it); a free flag that touches it is taken.
func flag_action(v: Vehicle) -> void:
	if match_finished or v.vehicle_type != 1:
		return
	for idx in [v.player_index(), v.player_index() ^ 1]:
		var flag: FlagMarker = flags.get(idx)
		if flag == null:
			continue
		if flag.carrier == v:
			flag.carrier = null
			flag.dropper = v
			return
		if flag.carrier == null and not _carrying_any(v) and _flag_touching(flag, v):
			_attach_flag(flag, v)
			return


## The vehicle choice at the base (documents 76, 78). The original docks the vehicle, then a selection state (FUN_00418290 -> FUN_00417ad0) shows the four
## types in a 2 x 2 hangar picture: top row Heli, Tank; bottom row MSV, Jeep. The cursor starts on the first type (in order Tank, Jeep, MSV, Heli) whose stock is not 0 and
## moves by the neighbour table at 0x4491c0 (+0x24..0x27 = up, down, left, right per type; document 78 corrects document 76's order); a target with no stock is skipped by
## trying that target's other-axis neighbours, and if none is in stock the cursor stays. The view fades in over about 14 ticks and only then can a fire button confirm: the vehicle
## is created and one is taken from its stock, and the type's confirm script runs (the picture slides onto the lift, the lift rises, the view fades out; SelectorAnim).
## PORT-ONLY: the keys are the arrows and Space / Enter, M shows the map (the original's other buttons lead to the map window, state 0x4180d0), and no cancel exists.
const SELECT_NEIGHBOURS := [[0, 1, 3, 0], [0, 1, 2, 1], [3, 2, 2, 1], [3, 2, 3, 0]]   ## [up, down, left, right] for Tank, Jeep, MSV, Heli
var select_anim: SelectorAnim = null
var undocking := false      ## the confirm script is playing; the new vehicle is on the pad but held (`state +0x70 = 1`) until it ends
var map_open := false       ## the map window of state 0x4180d0 (the level's radar bitmap in a 144 x 144 frame)
var view_fade := 1.0        ## the game view's own fade-in after the choice (0x4183e0, 0.07 a tick)
## The loss sequence (document 88): phase 0 none, 1 the wreck lies, 2 the skull spins in, 3 the view darkens, 4 the skull laughs, 5 the skull fades.
## The wait before it is the vehicle definition's stats.death_wait_ticks (record +0x260: 120, 120, 120, 200).
const DEATH_SKULL_LEAD_TICKS := 30.0                     ## FUN_00418440: `+0xc8 = now + 0x1e`
const DEATH_DARKEN_PER_TICK := 1310.0 / 65536.0          ## FUN_00418830
const DEATH_SKULL_FADE_PER_TICK := 4587.0 / 65536.0      ## FUN_004189a0: 0x11eb
const SKULL_SCALE_START_RAW := 0x28f
const SKULL_SCALE_STEP_RAW := 0x666
const SKULL_SCALE_MAX_RAW := 0x13333
const SKULL_SPIN_RAW := 0x28000
const SKULL_TIMER_RATE_RAW := 0x4ccc                     ## DAT_00449268
## FUN_00418510's mouth table (bytes at 0x449270, one per whole timer step): frame 1 closed .. 7 widest.
const SKULL_FRAMES := [1, 2, 2, 3, 3, 4, 4, 5, 6, 6, 6, 5, 5, 5, 6, 6, 5, 4, 5, 6, 7, 7, 6, 5, 4, 5, 6, 7, 7, 6,
		4, 5, 6, 7, 6, 5, 3, 4, 5, 7, 7, 7, 6, 6, 6, 5, 5, 4, 4, 3, 3, 2, 2, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0]
var death_phase := 0
var skull_scale_raw := SKULL_SCALE_START_RAW
var skull_angle_raw := 0
var skull_timer_raw := 0
var skull_alpha := 1.0
var _death_ticks := 0.0
var _death_acc := 0.0
var selecting := false
var selection := 0
signal selection_changed()


## Docking and undocking (document 77, corrected in document 81). The original: a vehicle standing STILL on its own pad (tile art 90 / 91), within the record's
## tolerance of the tile centre (+0x254: Tank and MSV 4 units, Jeep 9, Heli 32), that gets a fire button is docked (Tank, MSV: at once; Jeep: after returning its
## own team's flag if it carries it; Heli: an automatic landing first). Docking gives one vehicle back to the stock (an MSV's unused mines go to a reserve). A dock
## object then carries the vehicle's own model and VISIBLY SINKS -- FUN_0042efc0/0042f054, disassembled again for document 81 -- at a continuous 0x4ccc/65536
## (0.3) units a tick: once past -16 units the view starts fading out, and the object is destroyed only once it has both reached -32 units AND a separate 70-tick
## timer has run out (the slower of the two: -32 units at 0.3/tick takes ~107 ticks, so in practice the depth, not the timer, decides). A confirm then creates the
## new vehicle on the pad at once, heading 180 degrees (the Heli 135), and the view fades in.
## The dock tolerance is the vehicle definition's stats.dock_tolerance (record +0x254: 4, 9, 4, 32).
const DOCK_SINK_RATE := 0x4CCC / 65536.0        ## units of depth a tick (FUN_0042efc0/0042f054's shared constant)
const DOCK_FADE_DEPTH := -16.0                  ## the view starts fading out once the object passes this depth
const DOCK_MIN_DEPTH := -32.0                   ## the object is not removed above this depth even if the timer has run out
const DOCK_SINK_TICKS := 70.0                   ## the dock object's timer (+0x68 = 0x46): the OTHER of the two conditions, usually the faster one
const HELI_LAND_RATE := 0.5                     ## units of height a tick during the automatic landing (0x40ec30: dt << 15)
var dock_state := 0                             ## 0 none, 1 the Heli landing, 2 sinking into the base
var mine_reserve := 0                           ## the player's reserve of mines (player struct +0xbc); only filled here, not yet used (document 75)
var _dock_timer := 0.0
var _pad_centre := Vector2.ZERO
var _land_from := Vector2.ZERO
var _land_heading_from := 0.0
var _land_z0 := 1.0
## PORT-ONLY option (kept from the earlier placeholder): the `V` key docks and opens the choice at once without the sinking, on the pad.
var quick_swap_enabled := true

## The pad's pit and hatch (document 89). While a lift object exists (docked, choosing, confirming, rising) the pad tile's art is 0x5c (92, fully transparent:
## FUN_0042f110 at 0x42f225 and 0x42ef0a write it, FUN_0042ec50 restores 90 / 91) and the object draws a pit with a two-leaf lid. The leaves are drawn
## `0.3 * age + 5` units either side of the centre and not at all once `0.3 * age >= 18` (FUN_0042ea10). The dock counts its 70-tick timer DOWN (the leaves
## slide shut over the sinking vehicle); the undock counts UP from the moment the confirm script releases the hold (they slide apart while the vehicle rises
## from -32 to 0 at the same 0.3 a tick, ~107 ticks: FUN_0042ef20).
const PAD_HOLE_ART := 0x5c                      ## the tile art the pad has while open
const PAD_LEAF_START := 5.0                     ## FUN_0042ea10: 0x50000
const PAD_LEAF_HIDE := 18.0                     ## FUN_0042ea10: 0x120000
const PAD_RISE_START := -32.0                   ## FUN_0042eef0: 0xffe00000
signal pad_art_changed(tile: Vector2i)
var pad_open := false                           ## the pad tile is a hole and the pit is drawn
var pad_age := 0.0                              ## the lift object's `+0x68`, in ticks (down while docking, up while rising)
var pad_rising := false                         ## the undocked vehicle is rising out of the pit


func can_dock(v: Vehicle) -> bool:
	if v != vehicle or v.moving or not v.alive or dock_state != 0 or selecting or undocking or match_finished:
		return false
	var t := _tile_of(v.position)
	if (level.get_art_id(t.x, t.y) & 0x7F) != HOME_ART_BASE + v.player_index():
		return false
	var centre := (Vector2(t) + Vector2(0.5, 0.5)) * pack.tile_size_px
	var d := v.position - centre
	var tol := float(pack.vehicle_value(v.vehicle_type, "stats.dock_tolerance", 4.0))
	return d.x >= -tol and d.x <= tol and d.y >= -tol and d.y <= tol


func _begin_dock() -> void:
	if dock_state != 0:
		return
	_pad_centre = (Vector2(_tile_of(vehicle.position)) + Vector2(0.5, 0.5)) * pack.tile_size_px
	if vehicle.vehicle_type == 3:
		# the automatic landing (FUN_0040eb00 -> 0x40eb40 -> 0x40ec30): height falls 0.5 a tick while position and heading slide to the pad centre and
		# heading 135 degrees; the rotor spin-down (0x40ecd0) and the gear stage (0x40ede0), dock_state 3/4 below, follow once the fall is done (2026-09-23).
		dock_state = 1
		_land_from = vehicle.position
		_land_heading_from = vehicle.heading_deg
		_land_z0 = maxf(vehicle.z, 0.001)
		vehicle.frozen = true
		return
	_do_dock()


func _do_dock() -> void:
	# Jeep: FUN_0040e090 first returns its own team's flag if it carries it (sound 0x44b670, FUN_00432600); the port's only flag is the enemy's, so nothing to do
	_return_stock(vehicle.vehicle_type)               # 0x42f110: stock++ (unless 255) ...
	if vehicle.vehicle_type == 2:
		mine_reserve += vehicle.ammo[1]                # ... and an MSV's unused mines join the reserve
	_drop_carried_flags(vehicle)                       # PLACEHOLDER: a flag still carried is dropped here (the original's dock of a Jeep with the enemy flag is untraced)
	vehicle.frozen = true
	vehicle.speed = 0.0
	dock_state = 2
	_dock_timer = DOCK_SINK_TICKS
	pad_age = DOCK_SINK_TICKS
	_set_pad_open(true)
	vehicle.sound_cue.emit("Raise")   # dock.handler = 0x42efc0; dock.timer = 0x46; sound 0x44b7d8 (document 82)


func _update_dock(delta: float) -> void:
	var ticks := delta * Vehicle.TICK_HZ
	if selecting and select_anim != null:
		select_anim.fade_in(ticks)
	elif undocking:
		select_anim.step(ticks)
		if select_anim.finished:
			undocking = false
			view_fade = 0.0
			_begin_pad_rise()
			selection_changed.emit()
	elif view_fade < 1.0 and dock_state == 0 and death_phase == 0:
		view_fade = minf(view_fade + SelectorAnim.FADE_PER_TICK * ticks, 1.0)
	if pad_rising:
		# FUN_0042ef20: z += 0.3 a tick until it reaches 0; then FUN_0042ec50 restores the pad art and the real vehicle is released
		vehicle.z = minf(vehicle.z + DOCK_SINK_RATE * ticks, 0.0)
		pad_age += ticks
		if vehicle.z >= 0.0:
			pad_rising = false
			vehicle.frozen = false
			_set_pad_open(false)
	if dock_state == 0:
		return
	if dock_state == 1:
		vehicle.z = maxf(vehicle.z - HELI_LAND_RATE * ticks, 0.0)
		var f := vehicle.z / _land_z0
		vehicle.position = _pad_centre + (_land_from - _pad_centre) * f
		vehicle.heading_deg = fposmod(45.0 + wrapf(_land_heading_from - 45.0, -180.0, 180.0) * f, 360.0)
		if vehicle.z <= 0.0:
			vehicle.position = _pad_centre
			vehicle.heli_landing_gear_progress = 1.0
			dock_state = 3
		return
	if dock_state == 3:
		# FUN_0040ecd0: the rotor spins down (the same rate as the start-up ramp, reversed) once
		# actually on the ground, not during the descent -- confirmed by the transition condition
		# in the descent's own tail (0x40ec5e) firing only once the fall timer itself is spent.
		if vehicle.process_heli_landing_rotor(delta):
			dock_state = 4
		return
	if dock_state == 4:
		# FUN_0040ede0: a second timer, the same rate as the start-up's own silent-phase timer,
		# reversed -- "the gear stage" (NEXT_STEPS' own name for it, document 77's open item).
		if vehicle.process_heli_landing_gear(delta):
			_do_dock()
		return
	# dock_state == 2: FUN_0042efc0 / 0042f054 -- the vehicle visibly sinks at a constant rate; the view starts
	# fading once it passes -16, and it is only removed once BOTH it has reached -32 AND the 70-tick timer is spent.
	vehicle.z -= DOCK_SINK_RATE * ticks
	_dock_timer = maxf(_dock_timer - ticks, 0.0)
	pad_age = _dock_timer
	if vehicle.z <= DOCK_FADE_DEPTH:
		view_fade = maxf(view_fade - SelectorAnim.FADE_PER_TICK * ticks, 0.0)
	if vehicle.z <= DOCK_MIN_DEPTH and _dock_timer <= 0.0:
		vehicle.z = DOCK_MIN_DEPTH
		vehicle.docked = true
		dock_state = 0
		_open_selection()


## Swaps the pad tile between the hole (0x5c) and the team's own pad art (0x5b - (team == 0): 90 / 91), and tells the terrain view to redraw it.
func _set_pad_open(open: bool) -> void:
	pad_open = open
	var t := _tile_of(_pad_centre)
	level.set_art_id(t.x, t.y, PAD_HOLE_ART if open else HOME_ART_BASE + vehicle.player_index())
	pad_art_changed.emit(t)


func pad_position() -> Vector2:
	return _pad_centre


func _begin_pad_rise() -> void:
	_set_pad_open(true)   # already open after a dock; the port-only quick swap (V) skips the dock, so open it here
	pad_age = 0.0
	pad_rising = true
	vehicle.z = PAD_RISE_START


## The lid's leaf offset from the centre in units (FUN_0042ea10), or -1 while the leaves are not drawn (retracted, or no pit).
func pad_leaf_offset() -> float:
	if not pad_open:
		return -1.0
	var off := DOCK_SINK_RATE * pad_age
	return -1.0 if off >= PAD_LEAF_HIDE else off + PAD_LEAF_START


func switch_player_vehicle() -> void:
	if not quick_swap_enabled or vehicle == null or match_finished or vehicle.moving or selecting or undocking or dock_state != 0:
		return
	var t := _tile_of(vehicle.position)
	if (level.get_art_id(t.x, t.y) & 0x7F) != HOME_ART_BASE + vehicle.player_index():
		return
	_pad_centre = (Vector2(t) + Vector2(0.5, 0.5)) * pack.tile_size_px
	_return_stock(vehicle.vehicle_type)   # the docking's stock return, without the sinking
	if vehicle.vehicle_type == 2:
		mine_reserve += vehicle.ammo[1]
	_open_selection()


func _open_selection() -> void:
	selection = 0
	for i in 4:
		if vehicle_stock[i] != 0:
			selection = i
			break
	selecting = true
	map_open = false
	select_anim = SelectorAnim.new()
	select_anim.sound_cue.connect(vehicle.sound_cue.emit)
	vehicle.frozen = true
	selection_changed.emit()


## dir: 0 up, 1 down, 2 left, 3 right (the input word's bits 0x40000000, 0x80000000, 0x10000000, 0x20000000; document 78).
func select_move(dir: int) -> void:
	if not selecting:
		return
	var cur := selection
	var cand: int = SELECT_NEIGHBOURS[cur][dir]
	if vehicle_stock[cand] == 0:
		var alt: Array = [2, 3] if dir < 2 else [0, 1]   # a vertical move falls back to the target's left / right, a horizontal one to its up / down
		var first: int = SELECT_NEIGHBOURS[cand][alt[0]]
		var c2 := first
		if first == cand:
			c2 = SELECT_NEIGHBOURS[cand][alt[1]]
		cand = c2
		if vehicle_stock[cand] == 0:
			cand = cur
	if cand != selection:
		selection = cand
		selection_changed.emit()
		vehicle.sound_cue.emit("GClick")   # document 76: "each change plays sound 0x44b640" (document 82)


func confirm_selection() -> void:
	if not selecting or vehicle_stock[selection] == 0 or map_open:
		return
	if select_anim != null and select_anim.fade < 1.0:
		return   # the confirm only counts once the view has faded in (FUN_00417ad0 tests the fade value against 1.0)
	_take_stock(selection)
	vehicle.set_vehicle_type(selection)   # a new vehicle object: full hit points, fuel and ammunition
	vehicle.position = _pad_centre        # FUN_0040b1c0 creates it on the pad, heading 180 degrees (the Heli 135); the port's heading is the original's minus 90
	vehicle.heading_deg = 45.0 if selection == 3 else 90.0
	vehicle.z = 0.0
	vehicle.speed = 0.0
	vehicle.moving = false
	vehicle.docked = false                # held on the pad (frozen) until the script has run
	selecting = false
	undocking = true
	var sel: Dictionary = pack.selector_data
	if sel.is_empty():
		select_anim.finished = true
	else:
		select_anim.start_script(sel["scripts"][String(pack.vehicle_value(selection, "selector.script", ""))])
	selection_changed.emit()


func toggle_map() -> void:
	if selecting:
		map_open = not map_open
		selection_changed.emit()


## Debug convenience (not in the original): become vehicle type `t` (0 Tank, 1 Jeep, 2 MSV, 3 Heli) anywhere, at once, with
## fresh hit points and fuel. A flag carried by a non-Jeep is dropped, since only a Jeep can carry one (document 57).
func debug_swap_vehicle(t: int) -> void:
	if vehicle == null or match_finished or t == vehicle.vehicle_type:
		return
	for f in flags.values():
		if f.carrier == vehicle and t != 1:
			f.carrier = null
	vehicle.set_vehicle_type(t)


func _unhandled_input(event: InputEvent) -> void:
	if selecting and event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_UP: select_move(0)
			KEY_DOWN: select_move(1)
			KEY_LEFT: select_move(2)
			KEY_RIGHT: select_move(3)
			KEY_M: toggle_map()
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER: confirm_selection()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and vehicle != null:
		if event.keycode == KEY_B:
			vehicle.toggle_swim()
		elif event.keycode == KEY_X:
			vehicle.toggle_heli_slot()
		elif event.keycode >= KEY_F1 and event.keycode <= KEY_F4:
			debug_swap_vehicle(event.keycode - KEY_F1)
		elif event.keycode == KEY_V:
			switch_player_vehicle()
		elif event.keycode == KEY_F:
			flag_action(vehicle)
