# The dev level switcher: `]` / PageDown load the next level and `[` / PageUp the previous one, wrapping, by reloading
# the scene (a standalone run only; under GameFlow the keys do nothing, which game_flow_check covers). On the engine's
# synthetic fixture, whose two levels make the wrap visible. Moved from openfire's tools/tests (issue
# alexdia25/openfire#65). Run (see tests/README.md):
#   godot --headless --path .harness --script res://addons/openfire_engine/tests/dev_level_switch_check.gd
extends SceneTree

const Fixture := preload("fixtures/synthetic_pack.gd")

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _done(name: String) -> void:
	print("%s: %s" % [name, "PASS" if _failures == 0 else "%d FAILED" % _failures])
	quit(0 if _failures == 0 else 1)


func _view() -> Node:
	var view: Node = load("res://addons/openfire_engine/game/terrain_view_3d.tscn").instantiate()
	get_root().add_child(view)
	current_scene = view
	for i in 3:
		await process_frame
	return view


func _init() -> void:
	ProjectSettings.set_setting(EngineConfig.BASE_PACK, Fixture.build("user://packs"))
	var view: Node = await _view()
	_check(view.level_id == "LEVEL01", "starts on the pack's first level")
	var seen := []
	for key in [KEY_BRACKETRIGHT, KEY_BRACKETRIGHT, KEY_BRACKETLEFT, KEY_PAGEUP]:
		var ev := InputEventKey.new()
		ev.keycode = key
		ev.pressed = true
		view._unhandled_input(ev)
		await process_frame
		await process_frame
		view = current_scene
		seen.append(view.level_id)
	_check(seen == ["LEVEL02", "LEVEL01", "LEVEL02", "LEVEL01"], "] ] [ PageUp walk the level list and wrap: %s" % [seen])
	_done("dev_level_switch_check")
