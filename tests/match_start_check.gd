# How a match starts (alexdia25/openfire#63): through the vehicle-choice hangar if the pack has one, otherwise with the
# first vehicle already out and the view visible. The synthetic fixture has no hangar screen (no hud/selector.json),
# so a level must start playable, not black -- and a manifest's explicit spawn_through_hangar still decides. Run:
#   godot --headless --path .harness --script res://addons/openfire_engine/tests/match_start_check.gd
extends SceneTree

const Fixture := preload("fixtures/synthetic_pack.gd")

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _match(pack: Pack) -> MatchController:
	var level := LevelData.new()
	level.load_from(pack.level_dir("LEVEL01"))
	var root := Node2D.new()
	get_root().add_child(root)
	var mc := MatchController.new()
	root.add_child(mc)
	mc.setup(pack, level, pack.pack_dir, root)
	return mc


func _init() -> void:
	var base := Fixture.build("user://packs")
	var pack := Pack.new()
	_check(pack.load_from(base), "the fixture loads")
	_check(pack.selector_data.is_empty(), "it has no hangar screen")
	var mc := _match(pack)
	_check(not mc.selecting and not mc.vehicle.frozen and mc.view_fade == 1.0, "so the match starts with the vehicle out and the view visible")
	_check(mc.vehicle_stock[mc.vehicle.vehicle_type] == 2, "and the first vehicle is taken from the stock (3 -> 2)")

	# the manifest's own setting wins: a pack asking for the hangar start gets it (here, with no screen to draw it)
	var mod := ProjectSettings.globalize_path("user://match_start_check/mod")
	if DirAccess.dir_exists_absolute(mod):
		OS.move_to_trash(mod)
	PackWriter.write_json(mod.path_join("pack.json"), {"id": "startmod", "name": "start test", "base_pack": Fixture.ID, "spawn_through_hangar": true})
	var forced := Pack.new()
	_check(forced.load_from(mod), "a mod asking for the hangar start loads")
	var mc2 := _match(forced)
	_check(mc2.selecting and mc2.vehicle.frozen and mc2.view_fade == 0.0, "its match opens the vehicle choice first")

	print("match_start_check: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)
