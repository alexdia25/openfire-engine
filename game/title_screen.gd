class_name TitleScreen
extends Control
## The front end's picture (issue #51): the original's shell between games (FUN_00422160 / FUN_00421fe0, wiki document 122) draws one full-screen bitmap, ART\NEWREQLG.RFA
## (640 x 480; NEWREQSM.RFA at 320 x 240), whose bottom bar reads "PRESS 'F2' TO BEGIN" -- F2 is the Game menu's "New Game" (menu command 0x401) -- and plays the Drums line
## under it. The pack's picture keeps the grey bar with its text painted out (the importers do that); this shows it scaled to the window with its aspect kept, with the port's own
## prompt written on the bar, and emits `begin` on F2 (the original's key), Enter, Space or a click.

const PROMPT := "Press Enter to begin"
const BAR_CENTRE := 466.0 / 480.0   ## the bar's middle, as a fraction of the picture's height (rows 453-479 of 480)

var _pic: TextureRect
var _prompt: Label

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
	_pic = pic
	pic.texture = texture
	pic.set_anchors_preset(Control.PRESET_FULL_RECT)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pic)
	var prompt := Label.new()
	_prompt = prompt
	prompt.text = PROMPT
	prompt.add_theme_font_size_override("font_size", 20)
	prompt.add_theme_color_override("font_color", Color.WHITE)
	prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	prompt.add_theme_constant_override("outline_size", 4)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(prompt)
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_place_prompt)
	_place_prompt.call_deferred()


## The prompt goes on the picture's bar, wherever the window's scaling put the picture.
func _place_prompt() -> void:
	if _pic == null or _prompt == null or _texture == null:
		return
	var tex := Vector2(_texture.get_width(), _texture.get_height())
	var k := minf(size.x / tex.x, size.y / tex.y)
	var shown := tex * k
	var origin := (size - shown) * 0.5
	_prompt.size = Vector2(shown.x, 32.0)
	_prompt.position = Vector2(origin.x, origin.y + shown.y * BAR_CENTRE - 16.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		begin.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_F2, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		get_viewport().set_input_as_handled()
		begin.emit()
