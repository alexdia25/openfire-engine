class_name ColoursPanel
extends HSplitContainer
## The mod tool's Team colours tab (EDITOR_PLAN.md 3.2): the colour library (original, port preset, this mod), a picker
## that adds or changes a colour in the mod, and a live preview of sample team art in the selected colour.

## Sample team sets shown in the preview (whichever of these exist in the stack).
const SAMPLES := ["vehicle.tank.hull.04", "vehicle.tank.turret.top.01", "vehicle.jeep", "vehicle.msv", "vehicle.heli",
	"structure.building_wall", "marker.flag.cloth.tan.01", "structure.hangar_hatch.tan", "vehicle.wreck"]

var ws: ModWorkspace
var _list: ItemList
var _name: LineEdit
var _picker: ColorPicker
var _info: Label
var _preview: GridContainer
var _selected := ""


func setup(workspace: ModWorkspace) -> void:
	ws = workspace
	ws.changed.connect(_refresh)
	_refresh()


func _ready() -> void:
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 260
	add_child(left)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(i):
		_selected = String(_list.get_item_metadata(i))
		_load_selected())
	left.add_child(_list)
	var note := Label.new()
	note.text = "Tan and green are the original drawings; every other colour is generated from them (PORTING_PLAN 2.7.7)."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(1, 1, 1, 0.6)
	left.add_child(note)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right)
	var row := HBoxContainer.new()
	right.add_child(row)
	var l := Label.new()
	l.text = "Colour name"
	row.add_child(l)
	_name = LineEdit.new()
	_name.custom_minimum_size.x = 200
	row.add_child(_name)
	var apply := Button.new()
	apply.text = "Save colour to mod"
	apply.pressed.connect(_apply)
	row.add_child(apply)
	var remove := Button.new()
	remove.text = "Remove from mod"
	remove.pressed.connect(func(): if ws.mod_colours.has(_name.text): ws.remove_colour(_name.text))
	row.add_child(remove)
	_info = Label.new()
	_info.modulate = Color(1, 1, 1, 0.7)
	right.add_child(_info)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(body)
	_picker = ColorPicker.new()
	_picker.color_mode = ColorPicker.MODE_HSV
	_picker.edit_alpha = false
	_picker.presets_visible = false
	body.add_child(_picker)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	_preview = GridContainer.new()
	_preview.columns = 3
	scroll.add_child(_preview)


func _apply() -> void:
	var n := _name.text.strip_edges().to_lower()
	if n == "":
		return
	var c := _picker.color
	ws.set_colour(n, [c.h, c.s, c.v])
	_selected = n


func _refresh() -> void:
	if ws == null or _list == null:
		return
	_list.clear()
	var names: Array = ws.pack.team_colours.keys()
	names.sort_custom(func(a, b):
		var oa := ws.pack.is_original_colour(a)
		var ob := ws.pack.is_original_colour(b)
		return oa and not ob or (oa == ob and String(a) < String(b)))
	for n in names:
		var def: Dictionary = ws.pack.team_colours[n]
		var sw := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		sw.fill(ws.pack.team_rgb(String(n)))
		var src := "this mod" if ws.mod_colours.has(n) else ("original" if def.get("source") == "original" else "port preset")
		var i := _list.add_item("%s   (%s)" % [n, src], ImageTexture.create_from_image(sw))
		_list.set_item_metadata(i, String(n))
		if String(n) == _selected:
			_list.select(i)
	if _selected == "" and names.size() > 0:
		_selected = String(names[0])
	_load_selected()


func _load_selected() -> void:
	var def: Dictionary = ws.pack.team_colours.get(_selected, {})
	if def.is_empty():
		return
	_name.text = _selected
	var hsv: Array = def.get("hsv", [0, 0, 0.5])
	_picker.color = Color.from_hsv(float(hsv[0]), float(hsv[1]), float(hsv[2]))
	_info.text = "%s: the drawings as made, cannot be changed here" % _selected if ws.pack.is_original_colour(_selected) \
			else "Team paint is aimed at this hue, saturation and brightness (the mean of the paint pixels)."
	for c in _preview.get_children():
		c.queue_free()
	for prefix in SAMPLES:
		var id := _first_team_art(prefix)
		if id == "":
			continue
		var s := ws.pack.get_sprite(ws.pack.team_sprite(id, _selected))
		if s.is_empty():
			continue
		var box := VBoxContainer.new()
		_preview.add_child(box)
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(150, 150)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var at := AtlasTexture.new()
		at.atlas = ws.pack.get_texture(int(s["page"]))
		at.region = Rect2(float(s["x"]), float(s["y"]), float(s["w"]), float(s["h"]))
		tr.texture = at
		box.add_child(tr)
		var l := Label.new()
		l.text = id
		l.add_theme_font_size_override("font_size", 11)
		box.add_child(l)


func _first_team_art(prefix: String) -> String:
	if ws.pack.team_sets.has(prefix) or ws.pack.team_masks.has(prefix):
		return prefix
	var best := ""
	for id in ws.pack.team_sets:
		if String(id).begins_with(prefix) and (best == "" or ws.pack.get_sprite(String(id))["w"] * ws.pack.get_sprite(String(id))["h"] > ws.pack.get_sprite(best)["w"] * ws.pack.get_sprite(best)["h"]):
			best = String(id)
	return best
