class_name StoryScene
extends Control
## PORT-ONLY PLACEHOLDER for the level flow's intro/outro/mid-level scenes (PORTING_PLAN.md 2.8; EDITOR_PLAN.md's
## level-flow panel authors `LevelData.flow`'s scene ids). The user's own direction (2026-09-27): these will
## eventually be visual-novel style scripted scenes (portraits, backgrounds, branching text); this plays only the
## minimal shape of one -- a title and a sequence of lines, one per key/click -- so `GameFlow` and the data format
## (a pack's `scenes/<id>.json`) exist and are exercised now, without building the real presentation early.
##
## `scenes/<id>.json`: `{"title": "...", "lines": ["...", "...", ...]}`. Missing entirely is not an error at this
## layer -- `GameFlow` skips the intro/outro state altogether when a level's `flow` names no scene, or a named
## scene's file doesn't exist (a level author removed it, or a mod hasn't written it yet).

signal finished

var _lines: PackedStringArray = PackedStringArray()
var _index := -1
var _title_label: Label
var _text_label: Label
var _hint_label: Label


static func load_doc(pack: Pack, scene_id: String) -> Dictionary:
	for i in range(pack.layers.size() - 1, -1, -1):
		var path: String = pack.layers[i].path_join("scenes").path_join(scene_id + ".json")
		if FileAccess.file_exists(path):
			var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if doc is Dictionary:
				return doc
	return {}


func setup(doc: Dictionary) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_deferred("size", get_viewport_rect().size)   # anchors alone do not size a Control added ad hoc under a non-Control ancestor (deferred: Control warns/reverts an immediate size set while its own FULL_RECT anchors are active)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(560, 0)
	box.position -= box.custom_minimum_size * 0.5
	add_child(box)
	_title_label = Label.new()
	_title_label.text = String(doc.get("title", ""))
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title_label)
	_text_label = Label.new()
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.custom_minimum_size = Vector2(560, 120)
	box.add_child(_text_label)
	_hint_label = Label.new()
	_hint_label.text = "press enter / click to continue"
	_hint_label.modulate = Color(1, 1, 1, 0.5)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_hint_label)
	var raw: Array = doc.get("lines", [])
	_lines = PackedStringArray()
	for line in raw:
		_lines.append(String(line))
	_advance()


func _advance() -> void:
	_index += 1
	if _index >= _lines.size():
		finished.emit()
		return
	_text_label.text = _lines[_index]


func _unhandled_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo and
			(event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE)) or \
			(event is InputEventMouseButton and event.pressed)
	if pressed:
		_advance()
