class_name TitleScreen
extends Control
## The front end's picture (issue #51): the original's shell between games (FUN_00422160 / FUN_00421fe0, wiki document 122) draws one full-screen bitmap, ART\NEWREQLG.RFA
## (640 x 480; NEWREQSM.RFA at 320 x 240), whose bottom bar reads "PRESS 'F2' TO BEGIN" -- F2 is the Game menu's "New Game" (menu command 0x401) -- and plays the Drums line
## under it. The pack's picture has that bar cut off (the importers write 640 x 453); this shows it scaled to the window with its aspect kept, with the port's own prompt
## underneath, and emits `begin` on F2 (the original's key), Enter, Space or a click.

const PROMPT := "Press Enter to begin"

signal begin

var _texture: Texture2D


func setup(texture: Texture2D) -> void:
	_texture = texture
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_deferred("size", get_viewport_rect().size)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var pic := TextureRect.new()
	pic.texture = texture
	pic.set_anchors_preset(Control.PRESET_FULL_RECT)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pic)
	var prompt := Label.new()
	prompt.text = PROMPT
	prompt.add_theme_font_size_override("font_size", 22)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	prompt.offset_top = -48
	prompt.offset_bottom = -12
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(prompt)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		begin.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_F2, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		get_viewport().set_input_as_handled()
		begin.emit()
