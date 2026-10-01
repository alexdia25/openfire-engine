# The level list labels ("NN - Title", user direction 2026-09-28) in both places that list levels, the game's own
# LevelSelectScreen and the editor's MapViewPanel, on the engine's synthetic fixture. Its level.json files are written
# with sorted keys (as anything the mod tool saves), so "name" is not near the top: the name lookup
# (LevelData.peek_name) must still find it. Moved from openfire's tools/tests (issue alexdia25/openfire#65). Run:
#   godot --headless --path .harness --script res://addons/openfire_engine/tests/level_number_label_check.gd
extends SceneTree

const Fixture := preload("fixtures/synthetic_pack.gd")

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _init() -> void:
	_check(LevelSelectScreen._level_number("RFMAP117") == "117", "the number in an id ending in digits (RFMAP117: 117)")
	_check(LevelSelectScreen._level_number("LEVEL01") == "01", "and in LEVEL01, 01")
	_check(LevelSelectScreen._level_number("mymod.custom_level") == "mymod.custom_level", "an id with no trailing digits falls back to the whole id")
	_check(MapViewPanel._level_number("LEVEL02") == "02", "the editor's list numbers levels the same way")

	var base := Fixture.build("user://packs")
	var pack := Pack.new()
	_check(pack.load_from(base), "the fixture loads")
	var head := FileAccess.get_file_as_string(pack.level_dir("LEVEL02").path_join("level.json")).left(600)
	_check(not head.contains("\"name\""), "LEVEL02's name is not in its first 600 bytes (sorted keys, a long decorations list)")
	_check(LevelSelectScreen._peek_name(pack.level_dir("LEVEL02")) == "Second Wind", "but the name is still found")
	_check(MapViewPanel._peek_name(pack.level_dir("LEVEL01")) == "First Light", "by the editor's list too")
	var named := ProjectSettings.globalize_path("user://level_number_label_check/levels/X1")
	PackWriter.write_json(named.path_join("level.json"), {"width": 1, "height": 1})
	_check(LevelData.peek_name(named) == "", "a level with no name has an empty one, not an error")

	var s := LevelSelectScreen.new()
	get_root().add_child(s)
	await process_frame
	s.setup(pack)
	var list: ItemList = null
	for c in s.find_children("*", "ItemList", true, false):
		list = c
	_check(list != null and list.get_item_text(0) == "01 - First Light" and list.get_item_text(1) == "02 - Second Wind",
			"the level select list shows the format: %s" % [[list.get_item_text(0), list.get_item_text(1)] if list else "?"])

	print("level_number_label_check: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)
