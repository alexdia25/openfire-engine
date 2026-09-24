extends Control
## The mod tool (EDITOR_PLAN.md; phase E0): open or create a mod pack layered over original_pc, edit its sprites and team
## colours, check it, save it. Desktop only (the web build has no writable filesystem, PORTING_PLAN.md 2.5.1).
## Run:  godot --path . res://editor/editor_main.tscn
##
## Debug / screenshot switches (like the game's RF_DEBUG_*): RF_EDITOR_MOD=<dir> opens that mod; RF_EDITOR_TAB=<index>
## picks a tab; RF_EDITOR_SELECT=<sprite id> selects a sprite; RF_EDITOR_COLOUR=<name> selects a colour;
## RF_EDITOR_SCREENSHOT=<png> (+ RF_EDITOR_DELAY_FRAMES) saves a screenshot and quits.

const SETTINGS := "user://editor.cfg"

var ws: ModWorkspace
var _path_label: Label
var _save_btn: Button
var _undo_btn: Button
var _redo_btn: Button
var _tabs: TabContainer
var _assets: AssetsPanel
var _colours: ColoursPanel
var _findings: ItemList
var _dir_dialog: FileDialog
var _dir_action := Callable()


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		get_window().size = Vector2i(1500, 900)   # the game's 1152 x 648 default is cramped for three panes
		get_window().move_to_center()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.11, 0.11, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 8
	root.offset_top = 8
	root.offset_right = -8
	root.offset_bottom = -8
	add_child(root)

	var bar := HBoxContainer.new()
	root.add_child(bar)
	var title := Label.new()
	title.text = "Return Fire mod tool"
	title.add_theme_font_size_override("font_size", 18)
	bar.add_child(title)
	_path_label = Label.new()
	_path_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_label.modulate = Color(1, 1, 1, 0.65)
	_path_label.clip_text = true
	bar.add_child(_path_label)
	_bar_button(bar, "New mod...", func(): _ask_dir(_new_mod))
	_bar_button(bar, "Open mod...", func(): _ask_dir(_open_mod))
	_bar_button(bar, "Open folder", func(): OS.shell_open(ws.mod_dir))
	_undo_btn = _bar_button(bar, "Undo", func(): ws.undo.undo(), KEY_Z)
	_redo_btn = _bar_button(bar, "Redo", func(): ws.undo.redo(), KEY_Y)
	_save_btn = _bar_button(bar, "Save", func(): ws.save(), KEY_S)
	_bar_button(bar, "Reload", func(): ws.reload())

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)
	_assets = AssetsPanel.new()
	_assets.name = "Assets"
	_tabs.add_child(_assets)
	_colours = ColoursPanel.new()
	_colours.name = "Team colours"
	_tabs.add_child(_colours)
	var validate := VBoxContainer.new()
	validate.name = "Validate"
	_tabs.add_child(validate)
	_findings = ItemList.new()
	_findings.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_findings.item_activated.connect(func(i):
		var id := String(_findings.get_item_metadata(i))
		if id != "":
			_tabs.current_tab = 0
			_assets.select(id))
	validate.add_child(_findings)
	for placeholder in [["Vehicles", "The vehicle editor: phase E1 (viewer) and E3-E4 (editing), after vehicle definitions land (PORTING_PLAN 2.7.6 steps 3-5)."],
			["Maps", "The map editor: phase E1 (viewer) and E2 (editing). See docs/EDITOR_PLAN.md section 5."]]:
		var l := Label.new()
		l.name = placeholder[0]
		l.text = placeholder[1]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.modulate = Color(1, 1, 1, 0.6)
		_tabs.add_child(l)

	_dir_dialog = FileDialog.new()
	_dir_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_dir_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dir_dialog.dir_selected.connect(func(d): if _dir_action.is_valid(): _dir_action.call(d))
	add_child(_dir_dialog)

	var poll := Timer.new()
	poll.wait_time = 1.0
	poll.autostart = true
	poll.timeout.connect(func(): if ws != null: ws.poll_external())
	add_child(poll)

	var start := OS.get_environment("RF_EDITOR_MOD")
	if start == "":
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS)
		start = String(cfg.get_value("editor", "last_mod", ""))
	if start == "" or not FileAccess.file_exists(start.path_join("pack.json")):
		start = ProjectSettings.globalize_path("user://mods/my_mod")
		if not FileAccess.file_exists(start.path_join("pack.json")):
			ModWorkspace.create(start, "My mod").close()
	_open_mod(start)
	_debug_hooks()


func _bar_button(bar: HBoxContainer, text: String, action: Callable, ctrl_key := KEY_NONE) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	if ctrl_key != KEY_NONE:
		var ev := InputEventKey.new()
		ev.keycode = ctrl_key
		ev.ctrl_pressed = true
		var sc := Shortcut.new()
		sc.events = [ev]
		b.shortcut = sc
		b.tooltip_text = "Ctrl+%s" % OS.get_keycode_string(ctrl_key)
	bar.add_child(b)
	return b


func _open_mod(dir: String) -> void:
	var next := ModWorkspace.new()
	if not next.open(dir):
		next.close()
		return
	if ws != null:
		ws.close()
	ws = next
	ws.changed.connect(_on_changed)
	_assets.setup(ws)
	_colours.setup(ws)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("editor", "last_mod", dir)
	cfg.save(SETTINGS)
	_on_changed()


func _new_mod(dir: String) -> void:
	if not FileAccess.file_exists(dir.path_join("pack.json")):
		ModWorkspace.create(dir, dir.get_file()).close()
	_open_mod(dir)


func _ask_dir(action: Callable) -> void:
	_dir_action = action
	_dir_dialog.popup_centered_ratio(0.6)


func _on_changed() -> void:
	_path_label.text = "   %s  %s%s" % [ws.manifest.get("name", ""), ws.mod_dir, "   (unsaved changes)" if ws.is_dirty() else ""]
	_save_btn.disabled = not ws.is_dirty()
	_undo_btn.disabled = not ws.undo.has_undo()
	_redo_btn.disabled = not ws.undo.has_redo()
	get_window().title = "%sReturn Fire mod tool -- %s" % ["* " if ws.is_dirty() else "", ws.manifest.get("name", "")]
	_findings.clear()
	var found := ModValidator.check(ws)
	if found.is_empty():
		_findings.add_item("No problems found.")
		_findings.set_item_metadata(0, "")
	for f in found:
		var i := _findings.add_item("%s   %s" % ["ERROR" if f["level"] == "error" else "warning", f["message"]])
		_findings.set_item_metadata(i, f["sprite_id"])
		_findings.set_item_custom_fg_color(i, Color(1.0, 0.45, 0.4) if f["level"] == "error" else Color(1.0, 0.85, 0.45))
	_tabs.set_tab_title(2, "Validate (%d)" % found.size() if not found.is_empty() else "Validate")


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and ws != null:
		ws.close()


func _debug_hooks() -> void:
	var tab := OS.get_environment("RF_EDITOR_TAB")
	if tab != "":
		_tabs.current_tab = int(tab)
	var sel := OS.get_environment("RF_EDITOR_SELECT")
	if sel != "":
		_assets._search.text = sel
		_assets._rebuild_tree()
		_assets.select(sel)
	var colour := OS.get_environment("RF_EDITOR_COLOUR")
	if colour != "":
		_colours._selected = colour
		_colours._refresh()
	var shot := OS.get_environment("RF_EDITOR_SCREENSHOT")
	if shot != "":
		var frames := int(OS.get_environment("RF_EDITOR_DELAY_FRAMES")) if OS.get_environment("RF_EDITOR_DELAY_FRAMES") != "" else 10
		for i in frames:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(shot)
		get_tree().quit()
