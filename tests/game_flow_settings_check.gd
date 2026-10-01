# GameFlow's front end with no game around it (the synthetic fixture as the base pack): the title is the pack's own
# manifest title, and a game can put its own entries on the Settings screen (GameFlow.add_settings_entry), shown
# above "Back" and wired to the game's action, with the engine's own "Not built yet." only when there are none.
# Run (see tests/README.md):
#   godot --headless --path .harness --script res://addons/openfire_engine/tests/game_flow_settings_check.gd
extends SceneTree

const Fixture := preload("fixtures/synthetic_pack.gd")

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _texts(node: Node, cls: String) -> Array:
	var out := []
	for c in node.find_children("*", cls, true, false):
		out.append(c.text)
	return out


func _button(node: Node, text: String) -> Button:
	for b in node.find_children("*", "Button", true, false):
		if b.text == text:
			return b
	return null


func _init() -> void:
	ProjectSettings.set_setting(EngineConfig.BASE_PACK, Fixture.build("user://packs"))
	var flow: GameFlow = load("res://addons/openfire_engine/game/game_flow.tscn").instantiate()
	get_root().add_child(flow)
	await process_frame
	_check("FIXTURE" in _texts(flow, "Label"), "the title screen shows the pack's own title")

	flow._show_settings()
	await process_frame   # the previous screen is queue_free()d: gone once the frame ends
	_check("Not built yet." in _texts(flow, "Label") and _texts(flow, "Button") == ["Back"], "no game entries: the engine's placeholder")

	var pressed := [0]
	GameFlow.add_settings_entry("Game files...", func(): pressed[0] += 1)
	GameFlow.add_settings_entry("Game files...", func(): pressed[0] += 10)   # same label: replaced, not duplicated
	flow._show_settings()
	await process_frame
	_check(_texts(flow, "Button") == ["Game files...", "Back"], "a game's entry sits above Back, once: %s" % [_texts(flow, "Button")])
	_check(not "Not built yet." in _texts(flow, "Label"), "and the placeholder message is gone")
	_button(flow, "Game files...").pressed.emit()
	_check(pressed[0] == 10, "pressing it runs the game's (latest) action")
	GameFlow.settings_entries.clear()

	print("game_flow_settings_check: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)
