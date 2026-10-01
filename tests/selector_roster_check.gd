# The vehicle-select hangar with an arbitrary roster (PORTING_PLAN.md 2.7.3 step 6, alexdia25/openfire#15), on the
# engine's synthetic fixture (3 vehicles): the hangar always shows exactly 4 bays (user direction, 2026-09-28); which
# vehicle_type sits in each bay comes from the level's effective roster (MatchController.selector_roster/_bay_type),
# not a bay == vehicle_type assumption; a roster of more than 4 pages through them with select_next_page(); and a
# roster with an entry removed leaves that bay empty with no stock. Moved from openfire's tools/tests (issue
# alexdia25/openfire#65). Run (see tests/README.md):
#   godot --headless --path .harness --script res://addons/openfire_engine/tests/selector_roster_check.gd
extends SceneTree

const Fixture := preload("fixtures/synthetic_pack.gd")

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _mc(pack: Pack, level: LevelData, dir: String) -> MatchController:
	var root := Node2D.new()
	get_root().add_child(root)
	var mc := MatchController.new()
	root.add_child(mc)
	mc.setup(pack, level, dir, root)
	return mc


func _mod(name: String, roster: Dictionary, extra_vehicles: Array) -> String:
	var mod := ProjectSettings.globalize_path("user://selector_roster_check").path_join(name)
	if DirAccess.dir_exists_absolute(mod):
		OS.move_to_trash(mod)
	PackWriter.write_json(mod.path_join("pack.json"), {"id": name, "name": "selector roster test", "base_pack": Fixture.ID})
	for i in extra_vehicles.size():
		var id: String = extra_vehicles[i]
		PackWriter.write_json(mod.path_join("vehicles").path_join(id).path_join("vehicle.json"), Fixture.vehicle_def(id, id.get_extension().capitalize(), 10 + i))
	PackWriter.write_json(mod.path_join("levels/LEVEL01/level.override.json"), {"roster": roster})
	return mod


func _init() -> void:
	var base_dir := Fixture.build("user://packs")
	ProjectSettings.set_setting(EngineConfig.BASE_PACK, base_dir)

	# a mod adds two vehicles to LEVEL01's roster, so the effective roster (5) genuinely exceeds the 4 bays
	var mod := _mod("selectormod", {"selectormod.extra1": {"default_stock": 2}, "selectormod.extra2": {"default_stock": 1}},
			["selectormod.extra1", "selectormod.extra2"])
	var m := Pack.new()
	_check(m.load_from(mod), "the mod loads")
	var level := LevelData.new()
	_check(level.load_from(m.level_dir("LEVEL01"), m.level_override_paths("LEVEL01")), "the level loads")
	var extra1 := m.vehicle_index("selectormod.extra1")
	var extra2 := m.vehicle_index("selectormod.extra2")

	var mc := _mc(m, level, mod)
	mc._open_selection()
	_check(mc.selector_roster == [0, 1, 2, extra1, extra2], "the effective roster, in order: %s" % [mc.selector_roster])
	_check(mc.selector_page_count() == 2, "5 entries need 2 pages of 4")
	_check(mc.selector_page == 0 and mc._bay_type(mc.selection) >= 0, "opens on page 0, on a stocked bay")
	_check(mc._bay_type(0) == 0 and mc._bay_type(1) == 1 and mc._bay_type(2) == 2 and mc._bay_type(3) == extra1,
			"page 0's 4 bays are the first four roster entries, in order")

	mc.select_next_page()
	_check(mc.selector_page == 1, "select_next_page moves to page 1")
	_check(mc._bay_type(0) == extra2, "bay 0 of page 1 is the 5th entry")
	_check(mc._bay_type(1) < 0 and mc._bay_type(2) < 0 and mc._bay_type(3) < 0, "the other 3 bays on page 1 are empty")
	_check(mc.selection == 0, "the cursor landed on the only stocked bay on the new page")

	for i in 30:   # let the view's fade-in finish -- confirm_selection only counts once it has (document 78)
		await process_frame
	mc.confirm_selection()
	_check(not mc.selecting and mc.vehicle.vehicle_type == extra2,
			"confirming on page 1's bay 0 creates the 5th vehicle, not vehicle_type 0")
	mc.get_parent().queue_free()

	# a roster with one of the base's 3 removed: still 4 bays, the removed one's now empty, with no stock
	var mod2 := _mod("selectormod2", {"fx.copter": null}, [])
	var m2 := Pack.new()
	_check(m2.load_from(mod2), "the second mod loads")
	var level2 := LevelData.new()
	level2.load_from(m2.level_dir("LEVEL01"), m2.level_override_paths("LEVEL01"))
	var mc2 := _mc(m2, level2, mod2)
	mc2._open_selection()
	var copter := m2.vehicle_index("fx.copter")
	_check(mc2.selector_roster == [0, 1], "2-entry roster (the copter removed): %s" % [mc2.selector_roster])
	_check(mc2.selector_page_count() == 1, "fits on one page")
	_check(mc2._bay_type(2) < 0 and mc2._bay_type(3) < 0, "bays 2 and 3 are empty")
	_check(mc2.vehicle_stock[copter] == 0, "the removed vehicle keeps its index but has no stock")

	print("selector_roster_check: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)
