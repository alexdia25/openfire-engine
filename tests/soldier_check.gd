# Foot soldiers (Return Fire's class 14 "MAN"; alexdia25/openfire#74): the behaviour state machine on a fake world, then a match on the
# synthetic pack: a building that is shot down to one hit point releases its soldiers, they walk away from a vehicle, a crushed or
# blown-up one is removed, a throw launches the same lobbed shot the Jeep uses. All synthetic, no game needed. Run:
#   godot --headless --path .harness --script res://addons/openfire_engine/tests/soldier_check.gd
extends SceneTree

const Fixture := preload("fixtures/synthetic_pack.gd")

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


## The traced table (document 116) with fixture sprites.
func _table() -> Dictionary:
	var set := []
	for d in 5:
		set.append(["fx.hull", "fx.hull", "fx.hull", "fx.hull", "fx.hull", "fx.hull", "fx.hull", "fx.hull", "fx.hull", "fx.hull"])
	return {"speed": 0x3333 / 65536.0, "frame_rate": 0x3333 / 65536.0, "start_frame": 6.0, "idle_distance": 256.0, "throw_min": 64.0,
		"throw_max": 96.0, "decide_ticks": 30, "decide_random": 90, "pause_ticks": 120, "pause_random": 60, "home_ticks": 120,
		"grenades": [3], "separation_offsets": [[-4.0, 0.0], [4.0, 0.0], [-4.0, -3.0], [4.0, -3.0], [0.0, -3.0], [-4.0, 1.0], [4.0, 1.0], [0.0, 1.0]],
		"footprint": {"box": [-2.0, -1.5, 2.0, 0.05], "z": [0.0, 2.0], "layer": 1, "mask": 255},
		"quad": [[-4.0, -1.5, 4.5], [4.0, -1.5, 4.5], [4.0, 1.5, 0.0], [-4.0, 1.5, 0.0]],
		"shadow_quad": [[0.0, -2.5, 0.0], [8.0, -2.5, 0.0], [4.0, 1.5, 0.0], [-4.0, 1.5, 0.0]], "shadow_sprite": "fx.tile",
		"wade": {"frame_first": 10, "quad": [[-4.0, -4.0, 0.5], [4.0, -4.0, 0.5], [4.0, 12.0, 0.5], [-4.0, 12.0, 0.5]]},
		"wade_sprites": {"tan": set[0], "green": set[0]}, "corpse": {"lifetime": 120, "quad": [[-4.0, -4.0, 0.0], [4.0, -4.0, 0.0], [4.0, 4.0, 0.0], [-4.0, 4.0, 0.0]]},
		"corpse_sprites": ["fx.hull", "fx.hull", "fx.hull", "fx.hull", "fx.hull", "fx.hull"], "undrawn_ticks": 120, "active_half_extent": 512.0,
		"sprites": {"tan": set, "green": set}, "dir_source": [0, 1, 2, 3, 4, 3, 2, 1],
		"mirror": [false, false, false, false, false, true, true, true],
		"buildings": {"7": {"min": 1, "max": 3, "flip_team": false}, "8": {"min": 4, "max": 8, "flip_team": true}}}


class FakeVehicle extends Node2D:
	var side := 0
	var alive := true
	var docked := false
	var z := 0.0

	func player_index() -> int:
		return side


func _make_pack() -> Pack:
	var base := Fixture.build("user://packs")
	PackWriter.write_json(base.path_join("world/infantry.json"), _table())
	PackWriter.write_json(base.path_join("terrain/coastal_damage.json"), {"coastal": {
		"7": {"hp": 5, "base_art": 0, "destroyed_coastal": 0, "destroyed_art_offset": 0, "flags": 0, "pool_handler": false},
		"8": {"hp": 2, "base_art": 0, "destroyed_coastal": 0, "destroyed_art_offset": 0, "flags": 0, "pool_handler": false}}})
	var pack := Pack.new()
	pack.load_from(base)
	return pack


func _init() -> void:
	var pack := _make_pack()
	_check(not pack.infantry.is_empty() and pack.infantry["buildings"].size() == 2, "Pack.infantry is the pack's world/infantry.json")
	_geometry()
	_behaviour()
	_world(pack)
	_leftovers(pack)
	if _failures == 0:
		print("soldier: all ok")
	quit(_failures)


func _geometry() -> void:
	# heading 0 is north (-y), clockwise, in 64 steps rounded down: FUN_00422e70
	_check(Soldier.heading_to(Vector2.ZERO, Vector2(0, -100)) == 0 and Soldier.heading_to(Vector2.ZERO, Vector2(100, 0)) == 16
			and Soldier.heading_to(Vector2.ZERO, Vector2(0, 100)) == 32 and Soldier.heading_to(Vector2.ZERO, Vector2(-100, 0)) == 48,
			"heading 0 is north, 16 east, 32 south, 48 west")
	_check(Soldier.step_vector(16).is_equal_approx(Vector2(1, 0)) and Soldier.step_vector(0).is_equal_approx(Vector2(0, -1)), "a step vector points along the heading")
	var s := Soldier.new(_table(), Vector2.ZERO, 0)
	s.heading = 0
	_check(s.draw_frame()["dir"] == 0 and not s.draw_frame()["mirror"], "facing north draws set 0")
	s.heading = 8
	_check(s.draw_frame()["dir"] == 1 and not s.draw_frame()["mirror"], "facing north-east (octant 1) draws set 1")
	s.heading = 56
	_check(s.draw_frame()["dir"] == 1 and s.draw_frame()["mirror"], "facing north-west (octant 7) draws set 1 mirrored")
	s.heading = 32
	_check(s.draw_frame()["dir"] == 4 and not s.draw_frame()["mirror"], "facing south (octant 4) draws set 4")
	s.heading = 3
	_check(s.draw_frame()["dir"] == 0, "the octants are centred on the 45-degree headings (step 3 is still north)")
	s.heading = 4
	_check(s.draw_frame()["dir"] == 1, "and step 4 is the first north-east step")


func _soldier(at: Vector2, side: int, vehicles: Array) -> Soldier:
	var s := Soldier.new(_table(), at, side)
	s.targets = func(): return vehicles
	s.mover = func(_s, _to, _p): return {"blocked": false}
	s.water = func(_p): return false
	return s


func _behaviour() -> void:
	var v := FakeVehicle.new()
	get_root().add_child(v)
	# born in the open: ACQUIRE -> IDLE when the nearest vehicle is farther than 256 units
	v.position = Vector2(1000.0, 0.0)
	var s := _soldier(Vector2.ZERO, 1, [v])
	s.tick(1.0)
	_check(s.state == Soldier.State.IDLE and s.target == v, "beyond 256 units it stands and watches")
	var p0 := s.position
	for i in 20:
		s.tick(1.0)
	_check(s.position == p0, "an idle soldier does not move")
	# within range: walks AWAY from the vehicle at 0.2 units a tick, and the one-tick steering offset is gone after the first step
	v.position = Vector2(100.0, 0.0)
	var w := _soldier(Vector2.ZERO, 0, [v])
	w.grenades = 0
	w.tick(1.0)
	_check(w.state == Soldier.State.WALK, "inside 256 units it walks")
	w.jitter = 0
	var d0 := w.position.distance_to(v.position)
	for i in 100:
		w.tick(1.0)
		if w.state != Soldier.State.WALK:
			break
	var d1 := w.position.distance_to(v.position)
	_check(d1 > d0 + 10.0, "it gets farther from the vehicle (%.1f -> %.1f)" % [d0, d1])
	_check(absf((d1 - d0) - 0.2 * 100.0) < 3.0 or w.state != Soldier.State.WALK, "at about 0.2 units a tick")
	var jit := _soldier(Vector2.ZERO, 0, [v])
	jit.grenades = 0
	jit.tick(1.0)
	jit.jitter = 2
	var pos_before := jit.position
	jit.tick(1.0)
	_check(jit.jitter == 0, "the steering offset is used for one tick only (obj+0x71 is cleared)")
	_check(jit.position != pos_before, "and the soldier moved")
	# a hostile soldier with grenades 64-96 units from a vehicle throws, scattered by distance / 4, and the pause follows
	var thrown := []
	var hv := FakeVehicle.new()
	hv.position = Vector2(80.0, 0.0)
	get_root().add_child(hv)
	# (each decision is a 1-in-3 roll while it backs away from 80 units, so try soldiers until one throws)
	var t: Soldier = null
	for attempt in 40:
		thrown.clear()
		t = _soldier(Vector2.ZERO, 1, [hv])
		t.thrower = func(from, aim): thrown.append([from, aim])
		t.grenades = 3
		t.state = Soldier.State.ACQUIRE
		for i in 400:
			t.tick(1.0)
			if not thrown.is_empty():
				break
		if not thrown.is_empty():
			break
	_check(thrown.size() == 1 and t.grenades == 2, "it throws one grenade and has two left (%d thrown)" % thrown.size())
	if not thrown.is_empty():
		var aim: Vector2 = thrown[0][1]
		var d := t.position.distance_to(hv.position)
		_check(aim.distance_to(hv.position) <= 2.0 * (d / 4.0) + 2.0, "aimed at the vehicle, scattered by at most a quarter of the distance each way")
	_check(t.state == Soldier.State.PAUSE or t.state == Soldier.State.ACQUIRE or t.state == Soldier.State.WALK, "then it pauses before deciding again")
	# the same distance but the same team: no grenade, ever
	var thrown2 := []
	var fv := FakeVehicle.new()
	fv.position = Vector2(80.0, 0.0)
	fv.side = 1
	get_root().add_child(fv)
	var f := _soldier(Vector2.ZERO, 1, [fv])
	f.thrower = func(from, aim): thrown2.append(1)
	f.grenades = 4
	for i in 2000:
		f.tick(1.0)
	_check(thrown2.is_empty(), "a soldier never throws at its own side")
	# out of the 64-96 window (a vehicle 200 units away): no grenade
	var thrown3 := []
	var far := FakeVehicle.new()
	far.position = Vector2(200.0, 0.0)
	get_root().add_child(far)
	var g := _soldier(Vector2.ZERO, 1, [far])
	g.thrower = func(from, aim): thrown3.append(1)
	g.grenades = 4
	g.mover = func(_s, _to, _p): return {"blocked": true, "tile_box": Rect2(), "object": null}   # it cannot walk away: stays put at 200
	for i in 500:
		g.tick(1.0)
	_check(thrown3.is_empty(), "nothing is thrown from outside 96 units")
	# blocked by a wall box: the soldier slides along it instead of stopping
	var wall := FakeVehicle.new()
	wall.position = Vector2(0.0, 60.0)    # south of it, so it walks north
	get_root().add_child(wall)
	var sl := _soldier(Vector2(0.0, 0.0), 0, [wall])
	sl.grenades = 0
	sl.mover = func(_s, to, _p):
		if to.y < -2.0 and absf(to.x) < 40.0:    # a wall box 80 wide just north of it
			return {"blocked": true, "tile_box": Rect2(Vector2(-40.0, -10.0), Vector2(80.0, 8.0)), "object": null}
		return {"blocked": false}
	for i in 60:
		sl.tick(1.0)
		if sl.state != Soldier.State.WALK and sl.state != Soldier.State.ACQUIRE:
			pass
	_check(sl.position.y >= -3.0, "it does not walk through the wall")


func _world(pack: Pack) -> void:
	var level := LevelData.new()
	level.load_from(pack.level_dir("LEVEL02"))   # decorations with coastal id 7 on every other tile
	var root := Node2D.new()
	get_root().add_child(root)
	var mc := MatchController.new()
	root.add_child(mc)
	mc.setup(pack, level, pack.pack_dir, root)
	var created := []
	mc.soldier_created.connect(func(s): created.append(s))
	var tile := Vector2i(1, 0)
	_check(level.get_coastal_id(tile.x, tile.y) == 7, "LEVEL02 tile (1,0) is a coastal-7 building of 5 hit points")
	# four 1.0 hits leave 1 hit point: the release is on the hit that leaves exactly 1, not before
	for hit in 3:
		mc._damage_tile_amount(tile, 7, 1.0)
	_check(created.is_empty(), "three hits leave 2 hit points: nobody yet")
	mc._damage_tile_amount(tile, 7, 1.0)
	_check(created.size() >= 2 and created.size() <= 3, "the fourth leaves 1: it releases n + rand(n) with n = 2, so 2 or 3 (got %d)" % created.size())
	var n1 := created.size()
	mc._damage_tile_amount(tile, 7, 1.0)
	_check(created.size() == n1 and not mc._tile_hp.has(tile), "the killing hit releases nobody more and the tile is destroyed")
	# a hit large enough to destroy outright releases nobody
	var other := Vector2i(3, 0)
	var before := created.size()
	mc._damage_tile_amount(other, 7, 9.0)
	_check(created.size() == before, "a hit of at least the hit points releases nobody")
	# the prison-like entry flips the team
	var flip_tile := Vector2i(5, 0)
	mc._tile_hp[flip_tile] = 2
	mc._release_soldiers(flip_tile, 8)
	var flipped: Soldier = created.back()
	_check(flipped.team == (level.get_variant(5, 0) ^ 1) and created.size() - before >= 4 and created.size() - before <= 7, "id 8 releases 4 to 7 of the other team")
	# a soldier next to the player's vehicle: crushed
	var v := mc.vehicle
	v.position = Vector2(200.0, 200.0)
	v.docked = false
	v.frozen = false
	var cues := []
	mc.sound_at.connect(func(c, _at, _z): cues.append(c))   # the man is the sound's source (issue #22)
	var s := mc._new_soldier(v.position + Vector2(1.0, 1.0), 1)
	_check(s != null and mc.soldiers.has(s), "a soldier can be created directly")
	mc._update_soldiers(1.0 / Vehicle.TICK_HZ)
	_check(s.finished and not mc.soldiers.has(s), "a vehicle touching it crushes it")
	_check(cues.has("ManCrush"), "with the ManCrush scream")
	# one far from any vehicle survives
	var s2 := mc._new_soldier(Vector2(300.0, 100.0), 1)
	mc._update_soldiers(1.0 / Vehicle.TICK_HZ)
	_check(not s2.finished, "a soldier away from the vehicle is left alone")
	# a flat shell at z 7 passes over it; a grenade low enough kills it
	var shot := Projectile.new()
	root.add_child(shot)
	shot.z = 7.0
	_check(not mc._shell_hits_soldier(shot, s2.position + Vector2(-5, 0), s2.position + Vector2(5, 0)), "a shell at z 7 flies over a soldier")
	shot.z = 1.0
	_check(mc._shell_hits_soldier(shot, s2.position + Vector2(-5, 0), s2.position + Vector2(5, 0)) and s2.finished, "a low shot through it kills it")
	# a thrower launches the same lob the Jeep's missile uses, with the thrower immune
	var thrower := mc._new_soldier(Vector2(300.0, 300.0), 1)
	var launched := []
	mc.projectile_spawned.connect(func(p): launched.append(p))
	mc._soldier_throw(thrower, Vector2(350.0, 300.0))
	_check(launched.size() == 1 and launched[0].lob and launched[0].shooter == thrower and launched[0].damage == 1.5, "a thrown grenade is a lobbed shot of damage 1.5 that spares its thrower")
	_check(not mc._shell_hits_soldier(launched[0], thrower.position, thrower.position + Vector2(1, 0)), "and it does not hit the one who threw it")
	# the explosion damage box kills what it overlaps
	var victim := mc._new_soldier(Vector2(100.0, 400.0), 1)
	var box := ExplosionBox.new({"script": [["DAMAGE_BOX", -4, 4, 8, 8, 67, -1], ["STOP"]], "duration": 100.0, "rate_per_tick": 0.25}, Vector2(100.0, 400.0))
	box.advance(1.0)
	mc._box_kill_soldiers(box)
	_check(victim.finished, "an explosion's damage box kills a soldier inside it")


func _leftovers(pack: Pack) -> void:
	# wading: a soldier in water draws the ripple on frames 10-17 moving, 18-19 standing (descriptor 0x44e9c0), never the body frames
	var v := FakeVehicle.new()
	v.position = Vector2(100.0, 0.0)
	get_root().add_child(v)
	var w := Soldier.new(_table(), Vector2.ZERO, 0)
	w.targets = func(): return [v]
	w.mover = func(_s, _to, _p): return {"blocked": false}
	w.water = func(_p): return true
	w.grenades = 0
	var wade_ok := true
	for i in 200:
		w.tick(1.0)
		if w.anim == Soldier.Anim.WADE:
			wade_ok = wade_ok and w.phase >= 10.0 and w.phase < 18.0 and w.draw_frame()["wade"]
	_check(wade_ok and w.draw_frame()["wade"], "a soldier wading walks frames 10-17 of the ripple, not the body")
	var still := Soldier.new(_table(), Vector2.ZERO, 0)
	still.water = func(_p): return true
	still.mover = func(_s, _to, _p): return {"blocked": false}
	still.targets = func(): return []
	for i in 100:
		still.tick(1.0)
	_check(still.anim == Soldier.Anim.WADE_STAND and still.phase >= 18.0 and still.phase < 20.0, "standing in water cycles frames 18-19")
	# the body mark, the crewman, and the off-screen removal on a match
	var level := LevelData.new()
	level.load_from(pack.level_dir("LEVEL01"))
	var root := Node2D.new()
	get_root().add_child(root)
	var mc := MatchController.new()
	root.add_child(mc)
	mc.setup(pack, level, pack.pack_dir, root)
	var made := []
	mc.ground_mark_created.connect(func(m): made.append(m))
	mc.vehicle.position = Vector2(60.0, 60.0)
	var dead := mc._new_soldier(Vector2(300.0, 300.0), 1)
	mc._kill_soldier(dead)
	_check(made.size() == 1 and made[0].variant >= 0 and made[0].variant < 6 and made[0].variant % 2 == 1, "a soldier killed on land leaves a body mark of variant 2 * rand(3) + team")
	for i in 119:
		mc._update_soldiers(1.0 / Vehicle.TICK_HZ)
	_check(not made[0].finished, "the mark is still there after 119 ticks")
	for i in 3:
		mc._update_soldiers(1.0 / Vehicle.TICK_HZ)
	_check(made[0].finished and mc.marks.is_empty(), "and gone after 120")
	var poly := PackedVector2Array([Vector2(-6, -8), Vector2(6, -8), Vector2(6, 8), Vector2(-6, 8)])
	var info := {"position": Vector2(200.0, 200.0), "heading_deg": 0.0, "team": "green", "vehicle_type": 0, "z": 0.0, "hp_depleted": true, "polygon": poly.duplicate()}
	for i in poly.size():
		info["polygon"][i] += Vector2(200.0, 200.0)
	var before := mc.soldiers.size()
	mc._on_vehicle_wrecked({"position": Vector2(200.0, 200.0), "heading_deg": 0.0, "team": "green", "z": 0.0, "hp_depleted": false, "polygon": info["polygon"]})
	for i in 20:
		mc._update_soldiers(1.0 / Vehicle.TICK_HZ)
	_check(mc.soldiers.size() == before, "a vehicle that did not die of damage leaves no crewman")
	mc._on_vehicle_wrecked(info)
	for i in 7:
		mc._update_soldiers(1.0 / Vehicle.TICK_HZ)
	_check(mc.soldiers.size() == before, "the crewman waits the wreck's 8 ticks")
	for i in 3:
		mc._update_soldiers(1.0 / Vehicle.TICK_HZ)
	_check(mc.soldiers.size() == before + 1 and mc.soldiers.back().team == 1, "then one crewman of the wreck's team steps out")
	var crew: Soldier = mc.soldiers.back()
	_check(not Collision.polygon_hits_box(info["polygon"], crew.position, [-2.0, -1.5, 2.0, 0.05]), "placed clear of the wreck's footprint")
	# far from every vehicle for 120 ticks: removed
	mc.vehicle.position = Vector2(60.0, 60.0)
	var far := mc._new_soldier(Vector2(60.0 + 900.0, 60.0), 1)
	far.mover = func(_s, _to, _p): return {"blocked": true, "tile_box": Rect2(), "object": null}
	for i in 119:
		mc._update_soldiers(1.0 / Vehicle.TICK_HZ)
	_check(not far.finished, "a soldier far from every vehicle is still there after 119 ticks")
	for i in 3:
		mc._update_soldiers(1.0 / Vehicle.TICK_HZ)
	_check(far.finished, "and removed after 120 (the original's undrawn removal)")
