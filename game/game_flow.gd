class_name GameFlow
extends Node
## The game's own front end and state machine (PORTING_PLAN.md 2.8), replacing "boot straight into a level" as the
## project's main scene: title screen -> main menu -> settings / multiplayer / campaign -> level select -> (intro
## scene if the level has one) -> level -> (outro scene, or mission failed if the player ran out of vehicles) ->
## level select. Exactly the diagram the user gave (2026-09-28); every state in it is a real, reachable node here,
## even where the screen itself is `PlaceholderScreen` (title, main menu, settings, multiplayer, mission failed) --
## so nothing about the flow's *shape* has to change when a real screen replaces one of those.
##
## "Death Screen" is NOT a separate node here, on purpose: it already lives entirely inside the Level state
## (`MatchController`'s death sequence -- the skull, then the vehicle-choice hangar reopening) and never leaves
## "Level" in the diagram either (confirmed by the user, 2026-09-28). The diagram's "objectives completed" win is
## exactly `match_over` below, into the outro (also confirmed): Return Fire's own win state IS the outro-scene path,
## not a separate thing.
##
## "Mid-level scene" (a level's own `flow.mid_level` triggers) IS wired, as `trigger_mid_level()` below, but nothing
## calls it yet -- no level, original or otherwise, names a trigger, so there is nothing to fire it. Per the user
## (2026-09-28), it returns to the SAME running level when it finishes, not to level select: it pauses the tree and
## overlays a `StoryScene` rather than tearing the level down and reloading it, the one state in the diagram that
## doesn't replace `_current`/`_level_view` the way every other transition does.
##
## `LevelData.flow` (EDITOR_PLAN.md's future level-flow panel writes it): `{"intro": "<scene id>", "outro": "<scene
## id>", "mid_level": [{"trigger": "<name>", "scene": "<scene id>"}]}`. A scene id names `scenes/<id>.json` in the
## pack (`StoryScene.load_doc`); a level naming none, or naming one that isn't there, skips straight past that state
## -- the normal case, since Return Fire's own levels define none of these. `StoryScene` is a placeholder for the
## eventual visual-novel presentation (user direction, 2026-09-27).

@export var pack_path: String = ""   ## "" = the game's own base pack (ModLoader.base_pack_dir())

var pack: Pack
var _current: Control = null   ## the front-end screen on screen now (title / menu / settings / multiplayer / level select / a story scene)
var _level_view: Node3D = null   ## the running TerrainView3D, while a level is in progress
var _overlay: StoryScene = null   ## a mid-level scene playing over the (paused) live level; see trigger_mid_level()


func _ready() -> void:
	pack = ModLoader.load_game_pack(pack_path)
	pack_path = pack.pack_dir
	_show_title()


## Escape leaves a running level for the level select ("level quit" in the diagram) -- a level's own keys (drive,
## fire, dock, the debug level-switch keys) are all handled inside TerrainView3D/MatchController, which never binds
## Escape, so this is free to claim here without conflict.
func _unhandled_input(event: InputEvent) -> void:
	if _level_view != null and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_clear_level()
		_show_level_select()


func _clear_current() -> void:
	if _current != null and is_instance_valid(_current):
		_current.queue_free()
	_current = null


func _clear_level() -> void:
	if _level_view != null and is_instance_valid(_level_view):
		_level_view.queue_free()
	_level_view = null


func _show_placeholder(title: String, message: String, buttons: Array) -> void:
	_clear_current()
	var s := PlaceholderScreen.new()
	add_child(s)
	_current = s
	s.setup(title, message, buttons)


func _show_title() -> void:
	var headline: String = pack.manifest.get("title", pack.manifest.get("name", ""))
	_show_placeholder(headline.to_upper(), "", [["Start", func(): _show_main_menu()]])


func _show_main_menu() -> void:
	_show_placeholder("Main menu", "", [
		["Campaign", func(): _show_level_select()],
		["Multiplayer", func(): _show_multiplayer()],
		["Settings", func(): _show_settings()]])


func _show_settings() -> void:
	_show_placeholder("Settings", "Not built yet.", [["Back", func(): _show_main_menu()]])


func _show_multiplayer() -> void:
	_show_placeholder("Multiplayer", "Not built yet -- PORTING_PLAN.md section 4 item 7.", [["Back", func(): _show_main_menu()]])


func _show_level_select() -> void:
	_clear_current()
	var s := LevelSelectScreen.new()
	add_child(s)
	_current = s
	s.setup(pack)
	s.level_chosen.connect(func(id): start_level(id))
	s.back_pressed.connect(func(): _show_main_menu())


func _show_mission_failed() -> void:
	_show_placeholder("Mission failed", "Out of vehicles.", [["Back to level select", func(): _show_level_select()]])


## Plays `scene_id` (a pack's `scenes/<id>.json`, `StoryScene`'s format) if it names one that exists, else calls
## `then` at once. Used for both the intro (before `_enter_level`) and the outro (after a win, before level select).
func _play_story(scene_id: String, then: Callable) -> void:
	if scene_id == "":
		then.call()
		return
	var doc := StoryScene.load_doc(pack, scene_id)
	if doc.is_empty():
		then.call()
		return
	_clear_current()
	var scene := StoryScene.new()
	add_child(scene)
	_current = scene
	scene.finished.connect(func():
		_clear_current()
		then.call(), CONNECT_ONE_SHOT)
	scene.setup(doc)


## Starts `level_id`: its intro scene first if `LevelData.flow` names one, then the level itself. The level select
## screen and the debug level-switch key (inside TerrainView3D) both end up here.
func start_level(level_id: String) -> void:
	var lv := LevelData.new()
	if not lv.load_from(pack.level_dir(level_id), pack.level_override_paths(level_id)):
		_enter_level(level_id)   # let the real load fail loudly inside the view too, with its own error
		return
	_play_story(String(lv.flow.get("intro", "")), func(): _enter_level(level_id))


func _enter_level(level_id: String) -> void:
	_clear_current()
	var view: Node3D = load("res://game/terrain_view_3d.tscn").instantiate()
	view.pack_path = pack_path
	view.level_id = level_id
	view.managed_by_flow = true   # this view's own win/loss screen (ribbon, jingle, banner) is the outro/mission-failed
	# lead-in, and the dev level-switch keys give way to Level Select (PORTING_PLAN.md 2.8)
	add_child(view)
	_level_view = view
	await get_tree().process_frame   # TerrainView3D builds `controller` in _ready(), which add_child() only schedules
	if not is_instance_valid(view) or view.controller == null:
		_clear_level()
		_show_level_select()
		return
	# The outcome is known as soon as match_over/out_of_vehicles fires, but the level itself is NOT torn down then:
	# its own win/loss presentation (PlaceholderHud.show_win/show_lost -- the ribbon, the victory jingle, the banner)
	# IS this diagram's outro lead-in (confirmed by the user, 2026-09-28: Return Fire's win state "should basically
	# be considered an outro scene"), and it needs to actually be seen before anything replaces it. `continue_pressed`
	# (the existing "press Enter to play again" prompt, now re-emitted here instead of reloading the scene) is the
	# real end of the Level state; only then does GameFlow act on the outcome it recorded.
	var outcome := [-1]   # -1 undecided, -2 lost (out_of_vehicles), >= 0 the winning side (match_over)
	view.controller.match_over.connect(func(w): outcome[0] = w, CONNECT_ONE_SHOT)
	view.controller.out_of_vehicles.connect(func(): outcome[0] = -2, CONNECT_ONE_SHOT)
	view.continue_pressed.connect(func():
		if outcome[0] == -2:
			_on_level_lost(level_id)
		elif outcome[0] >= 0:
			_on_level_won(outcome[0], level_id)
		, CONNECT_ONE_SHOT)


func _on_level_won(_winner_idx: int, level_id: String) -> void:
	_clear_level()
	var lv := LevelData.new()
	lv.load_from(pack.level_dir(level_id), pack.level_override_paths(level_id))
	_play_story(String(lv.flow.get("outro", "")), func(): _show_level_select())


func _on_level_lost(_level_id: String) -> void:
	_clear_level()
	_show_mission_failed()


## "Mid-level scene" (PORTING_PLAN.md 2.8): plays `scene_id` over the running level and returns to that SAME level,
## paused, when it finishes -- the one flow transition that doesn't tear down `_level_view`. Whatever eventually
## calls this (a level's `flow.mid_level` trigger firing inside `MatchController`) passes it the scene id named for
## that trigger; a level naming no scene there, or one this call can't find, is simply never called for it. No-op
## while no level is running, or while another mid-level scene is already up.
func trigger_mid_level(scene_id: String) -> void:
	if _level_view == null or _overlay != null:
		return
	var doc := StoryScene.load_doc(pack, scene_id)
	if doc.is_empty():
		return
	var scene := StoryScene.new()
	scene.process_mode = Node.PROCESS_MODE_ALWAYS   # keeps running while get_tree().paused hides everything else
	add_child(scene)
	_overlay = scene
	get_tree().paused = true
	scene.finished.connect(func():
		get_tree().paused = false
		scene.queue_free()
		_overlay = null, CONNECT_ONE_SHOT)
	scene.setup(doc)
