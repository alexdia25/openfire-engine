class_name LevelSelectScreen
extends Control
## PORT-ONLY PLACEHOLDER (PORTING_PLAN.md 2.8): the campaign's level list, "Level Select" in the game-flow diagram.
## Lists a pack's real levels (`Pack.list_levels()`), sorted; picking one asks `GameFlow` to start it. Not the
## original's own front end (Return Fire had one campaign in a fixed order; every level under the pack is offered
## here so any of the 204 converted maps, or a mod's own, can be played) -- a real, ordered campaign list is future
## work, not a blocker for the flow structure itself.

signal level_chosen(level_id: String)
signal back_pressed


func setup(pack: Pack) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_deferred("size", get_viewport_rect().size)   # anchors alone do not size a Control added ad hoc under a non-Control ancestor (deferred: Control warns/reverts an immediate size set while its own FULL_RECT anchors are active)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 40
	box.offset_top = 24
	box.offset_right = -40
	box.offset_bottom = -24
	add_child(box)
	var title := Label.new()
	title.text = "Level select"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func(): back_pressed.emit())
	box.add_child(back)
	var list := ItemList.new()   # scrolls its own rows internally, so no ScrollContainer wrapper is needed (or wanted:
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL   # one would give this a (0, 0) child unless sized explicitly)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(list)
	var ids := pack.list_levels()
	ids.sort()
	for id in ids:
		list.add_item(id)
	list.item_activated.connect(func(i): level_chosen.emit(ids[i]))
