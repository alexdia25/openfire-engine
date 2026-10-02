# The game's front end / state machine (PORTING_PLAN.md 2.8) with the engine's synthetic fixture as the game: title ->
# main menu -> settings / multiplayer / campaign -> level select -> (intro if the level's flow names one) -> level ->
# quit back to level select, or a win (an outro if named) / a loss (mission failed) back to level select. A level with
# no intro/outro skips that state entirely. Moved from openfire's tools/tests (issue alexdia25/openfire#65). Run:
#   godot --headless --path .harness --script res://addons/openfire_engine/tests/game_flow_check.gd
extends SceneTree

const Fixture := preload("fixtures/synthetic_pack.gd")

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _init() -> void:
	ProjectSettings.set_setting(EngineConfig.BASE_PACK, Fixture.build("user://packs"))
	# a mod naming LEVEL01's intro/outro, so the flow's "skip if absent" and "play if present" paths both get exercised
	var mod := ProjectSettings.globalize_path("user://game_flow_check/mod")
	if DirAccess.dir_exists_absolute(mod):
		OS.move_to_trash(mod)
	PackWriter.write_json(mod.path_join("pack.json"), {"id": "flowmod", "name": "game flow test", "base_pack": Fixture.ID})
	PackWriter.write_json(mod.path_join("levels/LEVEL01/level.override.json"), {"flow": {"intro": "flow_intro", "outro": "flow_outro"}})
	PackWriter.write_json(mod.path_join("scenes/flow_intro.json"), {"title": "Briefing", "lines": ["Go."]})
	PackWriter.write_json(mod.path_join("scenes/flow_outro.json"), {"title": "Debrief", "lines": ["Done."]})

	var flow := GameFlow.new()
	flow.pack_path = mod
	get_root().add_child(flow)
	await process_frame
	_check(flow.pack != null and flow.pack.layers.size() == 2, "the mod's pack loads (base + the mod)")
	_check(flow._current is PlaceholderScreen, "boots to the title screen")

	flow._show_main_menu()
	_check(flow._current is PlaceholderScreen, "main menu is a placeholder screen too")
	flow._show_settings()
	_check(flow._current is PlaceholderScreen, "settings doesn't crash (placeholder)")
	_check(LevelData.peek_players(flow.pack.level_dir("LEVEL01")) == 2, "a level with two spawn points is a two-player level")
	flow._show_multiplayer()
	_check(flow._current is LevelSelectScreen, "multiplayer opens the level select of the two-player levels")
	var ml: ItemList = flow._current.find_children("*", "ItemList", true, false)[0]
	_check(ml.item_count == 2, "it lists both fixture levels (two spawn points each)")

	flow._show_level_select()
	_check(flow._current is LevelSelectScreen, "campaign opens the level select")
	var sel: LevelSelectScreen = flow._current
	_check(sel.get_children().size() > 0, "it lists something")
	_check((sel.find_children("*", "ItemList", true, false)[0] as ItemList).item_count == 0, "of the one-player levels only: the fixture has none")

	# starting a level whose flow names an intro plays it first, not the level
	flow.start_level("LEVEL01")
	await process_frame
	_check(flow._current is StoryScene and flow._level_view == null, "an intro plays before the level, which hasn't started yet")
	flow._current.finished.emit()
	await process_frame
	await process_frame
	_check(flow._current == null and flow._level_view != null, "the intro finishing enters the level")
	_check(flow._level_view.controller != null, "the level really loaded (a real MatchController)")

	# quitting (Escape) leaves the level for the level select without playing an outro
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	flow._unhandled_input(esc)
	_check(flow._level_view == null and flow._current is LevelSelectScreen, "Escape quits the level back to level select")

	# a level with no intro (a plain pack, no override) goes straight to the level
	var plain := GameFlow.new()
	get_root().add_child(plain)
	await process_frame
	plain.start_level("LEVEL01")
	await process_frame
	_check(plain._level_view != null and plain._current == null, "no intro named: the level starts immediately, nothing skipped-but-shown")
	plain.queue_free()

	# a win: the level's OWN win screen (ribbon/jingle/banner) is the outro lead-in and must actually be seen -- the
	# level is not torn down the instant match_over fires, only once the player presses Enter on that screen
	flow.start_level("LEVEL01")
	await process_frame
	flow._current.finished.emit()   # past the intro again
	await process_frame
	await process_frame
	var won_view := flow._level_view
	_check(won_view.managed_by_flow, "GameFlow marks the view as its own, not a standalone run")
	won_view.controller.match_over.emit(0)
	_check(flow._level_view == won_view, "match_over alone does not tear the level down: its own win screen must be seen first")
	won_view.continue_pressed.emit()   # the player pressed Enter on the level's own win screen
	_check(flow._level_view == null, "continuing past the win screen frees the level view")
	_check(flow._current is StoryScene, "then plays the named outro")
	flow._current.finished.emit()
	await process_frame
	_check(flow._current is LevelSelectScreen, "the outro finishing returns to level select")

	# a mid-level scene (still unfired by anything real -- see game_flow.gd) plays over the SAME level and returns to
	# it, paused, rather than tearing the level down like every other transition
	flow.start_level("LEVEL01")
	await process_frame
	flow._current.finished.emit()
	await process_frame
	await process_frame
	var mid_level_view := flow._level_view
	flow.trigger_mid_level("flow_intro")   # reusing the intro scene's data; any scene id would do
	_check(flow._overlay is StoryScene and flow._level_view == mid_level_view, "a mid-level scene overlays the same level, not a new one")
	_check(paused, "the tree pauses while it plays")
	flow._overlay.finished.emit()
	_check(not paused and flow._overlay == null and flow._level_view == mid_level_view,
			"finishing it unpauses and returns to the very same level, not level select")
	var esc2 := InputEventKey.new()
	esc2.pressed = true
	esc2.keycode = KEY_ESCAPE
	flow._unhandled_input(esc2)

	# running out of vehicles: the same "own screen first" rule, then mission failed instead of the outro
	flow.start_level("LEVEL01")
	await process_frame
	flow._current.finished.emit()
	await process_frame
	await process_frame
	var lost_view := flow._level_view
	lost_view.controller.out_of_vehicles.emit()
	_check(flow._level_view == lost_view, "out_of_vehicles alone does not tear the level down either")
	lost_view.continue_pressed.emit()
	_check(flow._current is PlaceholderScreen and flow._level_view == null, "continuing shows mission failed, not the outro")

	# the dev level-switch keys ([ ] / PageUp / PageDown) are disabled once GameFlow is managing the view
	flow.start_level("LEVEL01")
	await process_frame
	flow._current.finished.emit()
	await process_frame
	await process_frame
	var switch_view: Node3D = flow._level_view
	var before: String = switch_view.level_id
	var bracket := InputEventKey.new()
	bracket.pressed = true
	bracket.keycode = KEY_BRACKETRIGHT
	switch_view._unhandled_input(bracket)
	_check(switch_view.level_id == before, "the next-level shortcut does nothing under GameFlow")

	print("game_flow_check: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)
