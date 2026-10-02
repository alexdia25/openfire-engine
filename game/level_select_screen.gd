class_name LevelSelectScreen
extends Control
## "Level Select" in the game-flow diagram (PORTING_PLAN.md 2.8), drawn as the original's Level Selector dialog (resource 2002 in RFIRE.BIN: a list of levels, OK, Cancel; issue #51,
## wiki document 122) over the title picture. Lists a pack's real levels (`Pack.list_levels()`), sorted; OK or a double click asks `GameFlow` to start the chosen one. Not the
## original's own list (nine campaign radio buttons and an Add-Ons list); every level under the pack is offered here so any of the 204 converted maps, or a mod's own, can be played
## -- a real, ordered campaign list is future work, not a blocker for the flow structure itself.

signal level_chosen(level_id: String)
signal back_pressed

var backdrop: Texture2D   ## the title picture behind the dialog, set before `setup`
var skin := UiSkin.new()   ## the pack's skin, set before `setup`


## `players`: only the levels made for that many players are listed (0 = all): Campaign lists the one-player levels, Multiplayer the two-player ones.
func setup(pack: Pack, players := 0) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_deferred("size", get_viewport_rect().size)   # anchors alone do not size a Control added ad hoc under a non-Control ancestor (deferred: Control warns/reverts an immediate size set while its own FULL_RECT anchors are active)
	skin.add_backdrop(self, backdrop)
	var w := skin.window("Level Selector")
	var body: VBoxContainer = w["body"]
	var list := ItemList.new()   # scrolls its own rows internally, so no ScrollContainer wrapper is needed
	list.custom_minimum_size = Vector2(420, 300)
	body.add_child(list)
	var ids: Array[String] = []
	for id in pack.list_levels():
		if players == 0 or LevelData.peek_players(pack.level_dir(id)) == players:
			ids.append(id)
	ids.sort()
	for id in ids:
		var name := _peek_name(pack.level_dir(id))
		list.add_item("%s - %s" % [_level_number(id), name] if name != "" else id)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	var ok := Button.new()
	ok.text = "OK"
	ok.custom_minimum_size = Vector2(90, 0)
	ok.disabled = ids.is_empty()
	ok.pressed.connect(func():
		var sel := list.get_selected_items()
		if not sel.is_empty():
			level_chosen.emit(ids[sel[0]]))
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(90, 0)
	cancel.pressed.connect(func(): back_pressed.emit())
	row.add_child(ok)
	row.add_child(cancel)
	body.add_child(row)
	list.item_activated.connect(func(i): level_chosen.emit(ids[i]))
	if not ids.is_empty():
		list.select(0)
	skin.centre(self, w["root"])
	list.grab_focus()


## The level's display name (LevelData.peek_name, shared with the editor's map list).
static func _peek_name(dir: String) -> String:
	return LevelData.peek_name(dir)


## The number in a level id ("117" from "RFMAP117"), or the id itself if it has none (a mod's own id, not the
## original's RFMAPnnn convention).
static func _level_number(id: String) -> String:
	var re := RegEx.create_from_string("(\\d+)$")
	var m := re.search(id)
	return m.get_string(1) if m != null else id
