# Flying wreckage (Return Fire's class 3 "FWall"; alexdia25/openfire#81, wiki document 119): one DebrisPiece run through its script on a fake ground,
# then a wreck's landing bursting a synthetic vehicle's marked parts into pieces through a MatchController. Run:
#   godot --headless --path .harness --script res://addons/openfire_engine/tests/debris_check.gd
extends SceneTree

const Fixture := preload("fixtures/synthetic_pack.gd")

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


## The traced piece record (0x44a850 / 0x44a890 shape) with fixture frame ids.
func _record(rate: float) -> Dictionary:
	var f := 65536.0
	var deg := 360.0 / 0x400000
	return {"rate": rate, "duration": 19, "fade_start": 14, "ops": [
		{"op": "land", "start": 1, "end": 100, "always": true},
		{"op": "speed", "start": 1, "end": 3, "initial": 0.0, "target": 0x3333 / f, "rate": 1.0, "low": 0.0},
		{"op": "speed", "start": 4, "end": 100, "initial": 0.0, "target": 0x3333 / f, "rate": 1.0, "low": 0.0},
		{"op": "gravity", "start": 2, "end": 100, "launch": true},
		{"op": "yaw_spin", "start": 3, "end": 100, "initial": 0.0, "rate": 0x10000 * deg, "low": 0xccc * deg, "high": 0x8000 * deg},
		{"op": "roll_spin", "start": 3, "end": 100, "initial": 0.0, "rate": 0x10000 * deg, "low": 0xccc * deg, "high": 0x8000 * deg},
		{"op": "tint", "start": 3, "end": 10, "colour_cel": 1917, "colour_index": 2}],
		"frames": {"start": 11, "count": 8, "cel_first": 1917, "sprites": ["f0", "f1", "f2", "f3", "f4", "f5", "f6", "f7"]}}


func _surface(_p: Vector2) -> String:
	return "land"


func _init() -> void:
	_piece()
	_bounce()
	_in_a_match()
	_tile_collapse()
	print("debris_check: %d failures" % _failures)
	quit(_failures)


func _piece() -> void:
	var p := DebrisPiece.new(_record(0x5111 / 65536.0), _surface)
	p.position = Vector2(100.0, 100.0)
	p.z = 20.0
	p.dir = Vector3(1.0, 0.0, 0.0)
	var log := []
	p.effect.connect(func(r, _a): log.append(r))
	p.tick(1.0)
	_check(p.progress == 1.0, "the first tick starts the progress at 1.0 (the creation flag 0x40)")
	_check(p.speed > 0.19 and p.speed < 0.21 and p.position.x > 100.0 and p.z == 20.0, "it flies outward at 0.2 units a tick, level, before the gravity op")
	while floori(p.progress) < 2:
		p.tick(1.0)
	_check(p.airborne and p.vz < 0.0 and p.z < 20.0, "from progress 2 gravity takes over the height")
	var yaw0 := p.yaw
	for i in 6:
		p.tick(1.0)
	_check(p.yaw != yaw0 and p.roll != 0.0 and p.tint > 0.0, "from progress 3 it spins about both axes and darkens")
	var lowest := 0.0
	var ended := 0
	while not p.finished and ended < 200:
		p.tick(1.0)
		ended += 1
		lowest = minf(lowest, p.vz)
	_check(lowest >= -1.0 - 1e-9, "the fall is no faster than 1.0 a tick")
	_check(log == ["land"] and p.z <= 0.0, "it lands once, plays the surface's record at the ground, and ends")
	var hold := DebrisPiece.new(_record(0x5111 / 65536.0), _surface)
	hold.z = 5000.0
	hold.dir = Vector3.RIGHT
	var frames := 0
	var ticks := 0
	while not hold.finished and ticks < 200:
		hold.tick(1.0)
		ticks += 1
		if hold.frame_id != "":
			frames += 1
	_check(hold.finished and ticks >= 56 and ticks <= 60, "a low-row piece (rate 0x5111) lasts about 58 ticks (%d)" % ticks)
	_check(frames >= 24 and frames <= 28, "and shows the 8 burn-out frames for 8 progress units, about 25 ticks (%d)" % frames)
	var slow := DebrisPiece.new(_record(0x2888 / 65536.0), _surface)
	slow.z = 5000.0
	var t2 := 0
	while not slow.finished and t2 < 400:
		slow.tick(1.0)
		t2 += 1
	_check(t2 >= 113 and t2 <= 117, "a high-row piece (rate 0x2888) lasts about 115 ticks: it starts at progress 1 and ends at 19 (%d)" % t2)
	var fade := DebrisPiece.new(_record(0x5111 / 65536.0), _surface)
	fade.z = 5000.0
	var early := true
	var late := 1.0
	while not fade.finished:
		fade.tick(1.0)
		if floori(fade.progress) < 14:
			early = early and fade.fade_alpha() == 1.0
		else:
			late = minf(late, fade.fade_alpha())
	_check(early and late < 0.5, "it is opaque until fade_start (14) and fades after")


## The tile-collapse records (0x44a998 shape: bounce from 5, tint 40-80, ends at 90 a tick each) on a wall and on a flat roof.
func _bounce_record(settle_end: bool) -> Dictionary:
	return {"rate": 1.0, "duration": 90, "fade_start": 40, "ops": [
		{"op": "bounce", "start": 5, "end": 100, "launch": true, "settle_end": settle_end},
		{"op": "tint", "start": 40, "end": 80, "colour_cel": 1917, "colour_index": 2}]}


func _piece_with(rec: Dictionary, corners: Array[Vector3], z: float) -> DebrisPiece:
	var p := DebrisPiece.new(rec, _surface)
	p.z = z
	for c in corners:
		p.offsets.append(c)
	return p


func _bounce() -> void:
	var wall_corners: Array[Vector3] = [Vector3(-8, 5, 0), Vector3(8, 5, 0), Vector3(8, -5, 0), Vector3(-8, -5, 0)]
	var wall := _piece_with(_bounce_record(false), wall_corners, 5.0)
	for i in 4:
		wall.tick(1.0)
	_check(wall.z == 5.0 and not wall.airborne, "the bounce op waits until progress 5 (the first tick is 1.0)")
	wall.tick(1.0)
	_check(wall.airborne and wall.z < 5.0 and wall.z > 4.9, "then the piece starts to fall")
	_check(wall.offsets_changed and is_equal_approx(wall.offsets[2].y, -wall.z) and is_equal_approx(wall.offsets[0].y, 5.0), "the lower corners stay on the ground, the upper ones fall with the centre")
	for i in 15:
		wall.tick(1.0)
	_check(wall.z > 0.0 and is_equal_approx(wall.offsets[0].y, 5.0), "the upper corners keep their height above the centre while it falls")
	for i in 25:
		wall.tick(1.0)
	_check(wall.z == 0.0 and wall.offsets[0].y == 0.0 and wall.offsets[2].y == 0.0 and not wall.finished, "once the centre is down the speed carries the upper corners to the ground too: the wall lies flat")
	var ticks_to_end := 0
	while not wall.finished and ticks_to_end < 100:
		wall.tick(1.0)
		ticks_to_end += 1
	_check(wall.finished and ticks_to_end > 40 and ticks_to_end < 50, "and, with no settle_end, lies there until the record's duration, 90 ticks in all (%d more)" % ticks_to_end)
	var gone := _piece_with(_bounce_record(true), wall_corners, 5.0)
	var n := 0
	while not gone.finished and n < 100:
		gone.tick(1.0)
		n += 1
	_check(n > 25 and n < 45, "with settle_end the piece is removed the tick the last corner touches down (%d)" % n)
	var roof := _piece_with(_bounce_record(true), [Vector3(-8, 0, -8), Vector3(8, 0, -8), Vector3(8, 0, 8), Vector3(-8, 0, 8)], 10.0)
	var ticks := 0
	while not roof.finished and ticks < 200:
		roof.tick(1.0)
		ticks += 1
	_check(ticks > 10 and ticks < 40, "a flat piece with settle_end ends the tick all four corners lie on the ground (%d)" % ticks)
	var stays := _piece_with(_bounce_record(false), [Vector3(-8, 0, -8), Vector3(8, 0, -8), Vector3(8, 0, 8), Vector3(-8, 0, 8)], 10.0)
	ticks = 0
	while not stays.finished and ticks < 200:
		stays.tick(1.0)
		ticks += 1
	_check(ticks >= 88 and ticks <= 90 and stays.z == 0.0, "without it the piece lies there until the duration (%d)" % ticks)


func _in_a_match() -> void:
	var base := Fixture.build("user://packs")
	var rec := _record(0x5111 / 65536.0)
	PackWriter.write_json(base.path_join("world/debris.json"), {"rows": {"high": {"1": "a", "2": "b"}, "low": {"1": "a", "2": "b"}},
		"records": {"a": rec, "b": rec}, "landing": {"land": "land", "water": "water", "pavement": "pave", "pavement_first_art": 73, "pavement_last_art": 83}})
	var pack := Pack.new()
	pack.load_from(base)
	_check(pack.debris.has("records") and pack.debris["rows"]["low"]["1"] == "a", "Pack.debris is the pack's world/debris.json")
	var level := LevelData.new()
	level.load_from(pack.level_dir("LEVEL01"))
	var root := Node2D.new()
	get_root().add_child(root)
	var mc := MatchController.new()
	root.add_child(mc)
	mc.setup(pack, level, pack.pack_dir, root)
	# mark two of the first vehicle's parts: class 1 and class 2, and leave the rest (flags 8 and 0x308 make none)
	var def: Dictionary = pack.vehicle_def(0)
	var parts: Array = def["render"]["parts"]
	var made: Array = []
	mc.debris_created.connect(func(p): made.append(p))
	var effects: Array = []
	mc.impact_effect.connect(func(r, _a): effects.append(r))
	parts[0]["flags"] = 0x108
	parts[1]["flags"] = 0x208
	mc._on_vehicle_wrecked({"position": Vector2(100.0, 100.0), "heading_deg": -90.0, "team": "tan", "vehicle_type": 0, "z": 0.0, "speed": 0.5, "hp": -50.0,
		"fuel_out": false, "sink_depth": 14.0})
	mc._update_wrecks(1.0 / Vehicle.TICK_HZ)
	_check(made.size() == 2 and mc.debris.size() == 2, "a landing wreck bursts its two marked parts into pieces")
	_check(made[0].offsets.size() == 4 and made[0].sprite_id != "", "each piece has its part's four corners and sprite")
	_check(is_equal_approx(made[0].dir.length(), 1.0) or made[0].dir == Vector3.ZERO, "and a unit direction out of the body's centre")
	for i in 120:
		mc._update_debris(1.0 / Vehicle.TICK_HZ)
	_check(mc.debris.is_empty() and effects.has("land"), "the pieces land, play the land record, and are gone")


## Op 17 of a tile's collapse script: the tile's decoration breaks into a piece per marked part (FUN_0042d790 -> FUN_0042b4e0).
func _tile_collapse() -> void:
	var base := Fixture.build("user://packs")
	var wall := _bounce_record(true)
	var keep := _bounce_record(false)
	PackWriter.write_json(base.path_join("world/debris.json"), {"rows": {"high": {}, "low": {}}, "records": {"settle": wall, "keep": keep},
		"tile_rows": {"4": {"1": "settle", "2": "keep"}}, "landing": {}})
	var pack := Pack.new()
	pack.load_from(base)
	var level := LevelData.new()
	level.load_from(pack.level_dir("LEVEL02"))
	var root := Node2D.new()
	get_root().add_child(root)
	var mc := MatchController.new()
	root.add_child(mc)
	mc.setup(pack, level, pack.pack_dir, root)
	var quad := [[-8.0, 0.0, 10.0], [8.0, 0.0, 10.0], [8.0, 0.0, 0.0], [-8.0, 0.0, 0.0]]
	pack.decoration_types[str(Fixture.DECORATION_ID)] = [
		{"sprite_id": "fx.turret", "flags": 0x100, "corners": quad, "offset": [4.0, -2.0], "zoff": 1.0},
		{"sprite_id": "fx.turret", "flags": 0x208, "corners": quad},
		{"sprite_id": "fx.turret", "flags": 0x308, "corners": quad},   # class 3 makes none
		{"sprite_id": "fx.turret", "flags": 0x10, "corners": quad}]    # a plain part makes none
	var made: Array = []
	mc.debris_created.connect(func(p): made.append(p))
	var tile := Vector2i(3, 2)
	mc.shatter_tile(4, tile, Fixture.DECORATION_ID)
	var tsz := float(pack.tile_size_px)
	var centre := (Vector2(tile) + Vector2(0.5, 0.5)) * tsz
	_check(made.size() == 2 and mc.debris.size() == 2, "a collapsing tile breaks its class 1 and 2 parts into pieces and no others")
	_check(made[0].position.is_equal_approx(centre + Vector2(4.0, -2.0)) and is_equal_approx(made[0].z, 1.0 + 5.0), "a piece starts at the tile's centre plus the part's offset, at the part's height")
	_check(made[0].offsets.size() == 4 and is_equal_approx(made[0].offsets[0].y, 5.0) and is_equal_approx(made[0].offsets[2].y, -5.0), "with the part's corners about its centre")
	_check(made[0].sprite_id == "fx.turret", "and the part's sprite")
	mc.shatter_tile(9, tile, Fixture.DECORATION_ID)
	_check(made.size() == 2, "a row the pack does not have makes nothing")
	for i in 150:
		mc._update_debris(1.0 / Vehicle.TICK_HZ)
	_check(mc.debris.is_empty(), "the pieces are gone after their duration")
	print("debris_check: tile collapse done")

