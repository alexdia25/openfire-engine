class_name AssetsPanel
extends HSplitContainer
## The mod tool's Assets tab (EDITOR_PLAN.md 3, 3.1, 3.2): every sprite in the stack grouped by object, the canvas, and an
## inspector with where the sprite comes from, the registry's confidence and note, import / replace / external edit /
## revert, and its team art (pair or mask) with a strip of every team colour.

const REGISTRY_PATH := "res://packs/registry/asset_ids.json"

var ws: ModWorkspace
var selected_id := ""
var _registry: Dictionary = {}          ## sprite id -> {confidence, note}
var _search: LineEdit
var _mod_only: CheckBox
var _team_only: CheckBox
var _tree: Tree
var _canvas: SpriteCanvas
var _pivot_tool: Button
var _show_mask: CheckBox
var _inspector: VBoxContainer
var _file_dialog: FileDialog
var _file_action := Callable()
var _id_dialog: ConfirmationDialog
var _id_edit: LineEdit
var _id_action := Callable()
var _tree_ids := 0


func setup(workspace: ModWorkspace) -> void:
	ws = workspace
	ws.changed.connect(_on_changed)
	_rebuild_tree()
	_refresh()


func _ready() -> void:
	var reg: Variant = JSON.parse_string(FileAccess.get_file_as_string(REGISTRY_PATH)) if FileAccess.file_exists(REGISTRY_PATH) else null
	if reg is Dictionary:
		for c in reg.get("cels", {}).values():
			_registry[String(c["id"])] = c

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 300
	add_child(left)
	var new_btn := Button.new()
	new_btn.text = "New sprite from PNG..."
	new_btn.pressed.connect(_ask_png.bind(_new_sprite_from_png))
	left.add_child(new_btn)
	_search = LineEdit.new()
	_search.placeholder_text = "Search sprite ids"
	_search.text_changed.connect(func(_t): _rebuild_tree())
	left.add_child(_search)
	var filters := HBoxContainer.new()
	left.add_child(filters)
	_mod_only = CheckBox.new()
	_mod_only.text = "In this mod"
	_mod_only.toggled.connect(func(_b): _rebuild_tree())
	filters.add_child(_mod_only)
	_team_only = CheckBox.new()
	_team_only.text = "Team art"
	_team_only.toggled.connect(func(_b): _rebuild_tree())
	filters.add_child(_team_only)
	_tree = Tree.new()
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.item_selected.connect(func():
		var it := _tree.get_selected()
		if it != null and it.get_metadata(0) != null:
			select(String(it.get_metadata(0))))
	left.add_child(_tree)

	var middle := HSplitContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(middle)
	var centre := VBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(centre)
	var tools := HBoxContainer.new()
	centre.add_child(tools)
	var fit := Button.new()
	fit.text = "Fit"
	fit.pressed.connect(func(): _canvas._fit(); _canvas.queue_redraw())
	tools.add_child(fit)
	_pivot_tool = Button.new()
	_pivot_tool.text = "Set pivot"
	_pivot_tool.toggle_mode = true
	_pivot_tool.toggled.connect(func(on): _canvas.tool = SpriteCanvas.Tool.PIVOT if on else SpriteCanvas.Tool.VIEW; _canvas.queue_redraw())
	tools.add_child(_pivot_tool)
	_show_mask = CheckBox.new()
	_show_mask.text = "Show team paint"
	_show_mask.button_pressed = true
	_show_mask.toggled.connect(func(_b): _refresh_canvas())
	tools.add_child(_show_mask)
	var hint := Label.new()
	hint.text = "  wheel: zoom   right-drag: pan"
	hint.modulate = Color(1, 1, 1, 0.6)
	tools.add_child(hint)
	_canvas = SpriteCanvas.new()
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.pivot_picked.connect(func(p): if selected_id != "": ws.set_pivot(selected_id, p))
	centre.add_child(_canvas)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 340
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	middle.add_child(scroll)
	_inspector = VBoxContainer.new()
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_inspector)

	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.filters = PackedStringArray(["*.png ; PNG images"])
	_file_dialog.file_selected.connect(func(path):
		var img := Image.new()
		if img.load(path) == OK and _file_action.is_valid():
			_file_action.call(img, path))
	add_child(_file_dialog)
	_id_dialog = ConfirmationDialog.new()
	_id_edit = LineEdit.new()
	_id_edit.custom_minimum_size.x = 420
	_id_dialog.add_child(_id_edit)
	_id_dialog.confirmed.connect(func(): if _id_action.is_valid(): _id_action.call(_id_edit.text.strip_edges().to_lower()))
	add_child(_id_dialog)


# --- tree -------------------------------------------------------------------------------------------------------------

func _group_of(id: String) -> String:
	var parts := id.split(".")
	return ".".join(parts.slice(0, 2)) if parts.size() > 2 else parts[0]


func _is_team_art(id: String) -> bool:
	var p := ws.pack
	return p.team_sets.has(id) or p._team_set_of.has(id) or p.team_masks.has(id)


func _rebuild_tree() -> void:
	if ws == null or _tree == null:
		return
	_tree.clear()
	var root := _tree.create_item()
	var q := _search.text.strip_edges().to_lower()
	var groups := {}
	var ids: Array = ws.pack.sprites.keys()
	ids.sort()
	var shown := 0
	for id in ids:
		var sid := String(id)
		if sid.contains("@"):
			continue   # generated team colours are shown in the inspector, not listed
		if q != "" and not sid.contains(q):
			continue
		if _mod_only.button_pressed and not ws.mod_sprites.has(sid):
			continue
		if _team_only.button_pressed and not _is_team_art(sid):
			continue
		var g := _group_of(sid)
		if not groups.has(g):
			var gi := _tree.create_item(root)
			gi.set_text(0, g)
			gi.set_selectable(0, false)
			gi.collapsed = q == "" and not _mod_only.button_pressed
			groups[g] = gi
		var it := _tree.create_item(groups[g])
		it.set_text(0, sid.substr(g.length() + 1) if sid.length() > g.length() else sid)
		it.set_metadata(0, sid)
		if ws.mod_sprites.has(sid):
			it.set_custom_color(0, Color(0.55, 0.85, 1.0))
			it.set_tooltip_text(0, "%s (in this mod)" % sid)
		else:
			it.set_tooltip_text(0, sid)
		if sid == selected_id:
			groups[g].collapsed = false
			it.select(0)
		shown += 1
	_tree_ids = ws.pack.sprites.size()


func select(id: String) -> void:
	if id == selected_id:
		return
	selected_id = id
	_refresh()


# --- inspector ----------------------------------------------------------------------------------------------------------

func _on_changed() -> void:
	if ws.pack.sprites.size() != _tree_ids:
		_rebuild_tree()
	_refresh()


func _refresh() -> void:
	_refresh_canvas()
	for c in _inspector.get_children():
		c.queue_free()
	if ws == null or selected_id == "" or not ws.pack.sprites.has(selected_id):
		_label("Select a sprite on the left.")
		return
	var s := ws.pack.get_sprite(selected_id)
	_label(selected_id, 18)
	var origin := ws.sprite_origin(selected_id)
	_label("From this mod" if origin == "mod" else "Original art (base pack)", 14, Color(0.55, 0.85, 1.0) if origin == "mod" else Color(0.8, 0.8, 0.8))
	_label("%d x %d px   pivot (%s, %s) %s   kind %s" % [s["w"], s["h"], s.get("pivot_x"), s.get("pivot_y"),
			"set by the mod" if s.get("pivot_source") == "mod" else "(default centre)", s.get("kind", "sprite")], 13)
	var reg: Dictionary = _registry.get(selected_id, {})
	if not reg.is_empty():
		_label("Registry: %s" % reg.get("confidence", ""), 13, Color(1.0, 0.85, 0.45) if reg.get("confidence") in ["visual", "visual_group"] else Color(0.6, 1.0, 0.6))
		if String(reg.get("note", "")) != "":
			_label(String(reg["note"]), 12, Color(0.75, 0.75, 0.75))
	_inspector.add_child(HSeparator.new())
	_button("Replace with PNG...", _ask_png.bind(func(img, _p): ws.import_frame(selected_id, img, "Replace frame")))
	_button("Open in image editor", func():
		var path := ws.export_for_external_edit(selected_id)
		if path != "":
			OS.shell_open(path))
	var revert := _button("Revert to original", func(): ws.revert_sprite(selected_id))
	revert.disabled = origin != "mod"
	_inspector.add_child(HSeparator.new())
	_team_section()


func _team_section() -> void:
	var p := ws.pack
	var id := selected_id
	_label("Team colour", 16)
	var tan: String = p._team_set_of.get(id, id)
	if p.team_masks.has(id):
		var def: Dictionary = p.team_masks[id]
		_label("One drawing with a team-paint mask: %s%s" % [def.get("mask", ""),
				(", drawn as %s" % def["drawn_as"]) if def.has("drawn_as") else ""], 13)
		_button("Remove the team mask", func(): ws.clear_mask(id)).disabled = not ws.mod_masks.has(id)
	elif p.team_sets.has(tan):
		_label("Original pair: tan %s / green %s" % [tan, p.team_sets[tan]], 13)
		_label("Other colours are made from the tan drawing where the two differ.", 12, Color(0.75, 0.75, 0.75))
	else:
		_label("Not team art. Give it a team-paint mask to make it recolourable:", 13)
	if not p.team_sets.has(tan):
		var row := HBoxContainer.new()
		_inspector.add_child(row)
		var mask_edit := LineEdit.new()
		mask_edit.placeholder_text = "mask sprite id"
		mask_edit.text = String(p.team_masks.get(id, {}).get("mask", ""))
		mask_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(mask_edit)
		var drawn := OptionButton.new()
		drawn.add_item("(any colour)")
		var names: Array = p.team_colours.keys()
		for n in names:
			drawn.add_item(String(n))
			if String(n) == String(p.team_masks.get(id, {}).get("drawn_as", "")):
				drawn.select(drawn.item_count - 1)
		drawn.tooltip_text = "The colour the drawing is already in, if any: that colour then shows the drawing unchanged"
		row.add_child(drawn)
		var drawn_as := func() -> String: return "" if drawn.selected <= 0 else drawn.get_item_text(drawn.selected)
		_button("Use this mask", func():
			if p.sprites.has(mask_edit.text.strip_edges()):
				ws.set_mask(id, mask_edit.text.strip_edges(), drawn_as.call()))
		_button("Import a mask PNG...", _ask_png.bind(func(img, _p):
			var mask_id := id + "_mask"
			ws.import_frame(mask_id, img, "Import team mask")
			ws.set_mask(id, mask_id, drawn_as.call())))
	if _is_team_art(id):
		_colour_strip(id)


## Every colour in the stack, drawn as this sprite would be in it.
func _colour_strip(id: String) -> void:
	var grid := GridContainer.new()
	grid.columns = 4
	_inspector.add_child(grid)
	var names: Array = ws.pack.team_colours.keys()
	names.sort_custom(func(a, b):
		var oa := ws.pack.is_original_colour(a)
		var ob := ws.pack.is_original_colour(b)
		return oa and not ob or (oa == ob and String(a) < String(b)))
	for n in names:
		var sid := ws.pack.team_sprite(id, String(n))
		var s := ws.pack.get_sprite(sid)
		var box := VBoxContainer.new()
		grid.add_child(box)
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(72, 72)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if not s.is_empty():
			var at := AtlasTexture.new()
			at.atlas = ws.pack.get_texture(int(s["page"]))
			at.region = Rect2(float(s["x"]), float(s["y"]), float(s["w"]), float(s["h"]))
			tr.texture = at
		box.add_child(tr)
		var l := Label.new()
		l.text = String(n)
		l.add_theme_font_size_override("font_size", 11)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)


func _refresh_canvas() -> void:
	if _canvas == null or ws == null:
		return
	var mask := ""
	var mask_tex: Texture2D = null
	if _show_mask.button_pressed and ws.pack.team_masks.has(selected_id):
		mask = String(ws.pack.team_masks[selected_id].get("mask", ""))
	elif _show_mask.button_pressed and selected_id != "":
		mask_tex = _pair_paint(selected_id)
	_canvas.show_sprite(ws.pack, selected_id, mask, mask_tex)


## For a sprite in an original tan/green pair: its team paint, the pixels where the two drawings differ (the same rule
## Pack._make_recolour uses), as a white-on-transparent texture. null for anything else.
func _pair_paint(id: String) -> Texture2D:
	var p := ws.pack
	var tan: String = p._team_set_of.get(id, id)
	if not p.team_sets.has(tan):
		return null
	var a := p.get_sprite_image(tan)
	var b := p.get_sprite_image(String(p.team_sets[tan]))
	if a == null or b == null or a.get_size() != b.get_size():
		return null
	var m := Image.create_empty(a.get_width(), a.get_height(), false, Image.FORMAT_RGBA8)
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x, y).a > 0.0 and a.get_pixel(x, y) != b.get_pixel(x, y):
				m.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(m)


func _label(text: String, font_size := 14, colour := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.modulate = colour
	_inspector.add_child(l)
	return l


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	_inspector.add_child(b)
	return b


# --- dialogs --------------------------------------------------------------------------------------------------------------

func _ask_png(action: Callable) -> void:
	_file_action = action
	_file_dialog.popup_centered_ratio(0.6)


func _new_sprite_from_png(img: Image, path: String) -> void:
	var suggestion := "%s.%s" % [ws.manifest.get("id", "mymod"), path.get_file().get_basename().to_lower().replace(" ", "_")]
	_ask_id("New sprite id (lower case, dot-separated, e.g. %s.hovertank.hull)" % ws.manifest.get("id", "mymod"), suggestion, func(id):
		if id == "" or not id.is_valid_filename():
			return
		ws.import_frame(id, img, "New sprite")
		_rebuild_tree()
		select(id))


func _ask_id(title: String, suggestion: String, action: Callable) -> void:
	_id_action = action
	_id_dialog.title = title
	_id_edit.text = suggestion
	_id_dialog.popup_centered()
	_id_edit.grab_focus()
