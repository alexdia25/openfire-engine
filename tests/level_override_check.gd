# A map's roster override (PORTING_PLAN.md 2.7.3, step 6), at the pack/level layer: a mod's own
# levels/<id>/level.override.json patches the base pack's default roster and a level's side colours for one map,
# without shipping a copy of level.json/art.bin, without touching the base, and without moving any definition's own
# vehicle_type index. (What a match then does with the effective roster -- MatchController's stock -- needs a playable
# pack and is checked by the games built on the engine.) Run (tests/README.md):
#   godot --headless --path .harness --script res://addons/openfire_engine/tests/level_override_check.gd
extends SceneTree

const Fixture := preload("fixtures/synthetic_pack.gd")

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _init() -> void:
	var base_dir := Fixture.build("user://packs")
	var pack := Pack.new()
	_check(pack.load_from(base_dir), "the base pack loads")

	var mod := ProjectSettings.globalize_path("user://level_override_check/mod")
	if DirAccess.dir_exists_absolute(mod):
		OS.move_to_trash(mod)
	PackWriter.write_json(mod.path_join("pack.json"), {"id": "overridemod", "name": "level override test", "base_pack": Fixture.ID})
	# a new vehicle, so the override can offer it on the map without touching the roster of any other map
	PackWriter.write_json(mod.path_join("vehicles/overridemod.scout/vehicle.json"), Fixture.vehicle_def("overridemod.scout", "Scout", 9))
	# the override itself: no level.json/art.bin here at all -- just the patch
	PackWriter.write_json(mod.path_join("levels/LEVEL01/level.override.json"), {
		"side_colours": ["red", "blue"],
		"roster": {"fx.copter": null, "fx.tank": {"stock_key": "T", "default_stock": 9}, "overridemod.scout": {"default_stock": 2}},
		"flow": {"intro": "briefing"}})

	var m := Pack.new()
	_check(m.load_from(mod), "the mod loads")
	_check(m.level_dir("LEVEL01") == base_dir.path_join("levels/LEVEL01"),
			"level_dir still resolves to a real level.json (the base's): the override-only folder is not mistaken for it")
	_check(m.level_override_paths("LEVEL01").size() == 1, "exactly one layer's override.json is found")

	var level := LevelData.new()
	_check(level.load_from(m.level_dir("LEVEL01"), m.level_override_paths("LEVEL01")), "the level loads with the override applied")
	_check(level.side_colours == ["red", "blue"], "side_colours came from the override")
	_check(level.roster_override.get("fx.copter", "missing") == null and level.roster_override["fx.tank"]["default_stock"] == 9.0,
			"roster_override carries the raw per-id entries")
	_check(level.flow.get("intro", "") == "briefing", "flow (PORTING_PLAN.md 2.8) is carried the same way (an intro scene id, here)")

	var roster := m.roster_for(level)
	var ids: Array = roster.map(func(e): return e["id"])
	_check(ids == ["fx.tank", "fx.buggy", "overridemod.scout"], "the effective roster: copter removed, the scout added, order kept: %s" % [ids])
	var tank_entry: Dictionary = roster[ids.find("fx.tank")]
	_check(tank_entry["default_stock"] == 9.0 and tank_entry["stock_key"] == "T", "the tank's stock and stock_key are overridden")
	_check(m.vehicle_roster.size() == 3 and m.vehicle_roster.map(func(e): return e["id"]).has("fx.copter"), "the pack's own default roster is untouched")
	_check(m.vehicle_index("fx.copter") == pack.vehicle_index("fx.copter"), "removing a vehicle from one map's roster never moves its vehicle_type index")
	_check(m.vehicle_index("overridemod.scout") >= 0, "the new vehicle has an index of its own")

	# a second level of the same pack is unaffected (no override.json for it)
	var level2 := LevelData.new()
	_check(level2.load_from(m.level_dir("LEVEL02"), m.level_override_paths("LEVEL02")), "a level without its own override loads")
	_check(level2.roster_override.is_empty() and level2.side_colours == ["tan", "green"], "and is not affected by LEVEL01's override")
	_check(m.roster_for(level2) == m.vehicle_roster, "so its effective roster is just the pack default")

	print("level_override_check: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)
