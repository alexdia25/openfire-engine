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
	# a second, smaller window beside the list: the selected level's map and difficulty (the original shows both as a level is picked)
	var info := skin.window("Level")
	var ibody: VBoxContainer = info["body"]
	var map_rect := TextureRect.new()
	map_rect.custom_minimum_size = Vector2(256, 256)
	map_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	map_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ibody.add_child(map_rect)
	var facts := Label.new()
	ibody.add_child(facts)
	var show := func(i: int) -> void:
		var lv := LevelData.new()
		if i < 0 or not lv.load_from(pack.level_dir(ids[i]), pack.level_override_paths(ids[i])):
			map_rect.texture = null
			facts.text = ""
			return
		var img := LevelPreview.image(pack, lv)
		map_rect.texture = ImageTexture.create_from_image(img) if img != null else null
		facts.text = "Difficulty: %d\nPlayers: %d\nSize: %d x %d" % [lv.levl_value, LevelData.peek_players(pack.level_dir(ids[i])), lv.width, lv.height]
	list.item_selected.connect(show)
	if not ids.is_empty():
		list.select(0)
		show.call(0)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	w["root"].size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row2.add_child(w["root"])
	var side := VBoxContainer.new()
	info["root"].size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	side.add_child(info["root"])
	row2.add_child(side)
	skin.centre(self, row2)
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
