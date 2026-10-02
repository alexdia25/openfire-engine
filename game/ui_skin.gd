class_name UiSkin
extends RefCounted
## The front end's skin (issue #51; configurable per pack by `ui/skin.json`, below). The engine's default is plain (dark screen, the engine's own controls); a game declares its
## own look. The original game's pack declares the look of its front end (wiki document 122): Return Fire for Windows 95 showed its menus as ordinary Win95 dialogs (Player Selector,
## Level Selector, Hall of Fame; dialog resources 2001, 2002, 104 in RFIRE.BIN) over the title picture -- a grey 3D-bevelled face, a navy title bar, white sunken
## list fields, push buttons that sink when pressed. This builds that look as a `Theme` and a window frame; the colours are the system defaults of the era
## (button face #c0c0c0, shadow #808080, light #dfdfdf, active caption #000080 fading to #1084d0). PORT CHOICE: drawn here, not extracted -- the original takes them from Windows.

##
## `ui/skin.json` (a pack layer may replace any key; the others keep the defaults here): "style" ("plain", the default, or "bevel": the 3D-bevelled dialog window below),
## {"face", "hilight", "light", "shadow", "dark", "caption_a", "caption_b", "desktop"} as "#rrggbb" colours (the bevel style's), and "font_size". A mod re-skins every
## front-end screen by shipping its own file; the colour defaults below are the Win95 system colours, used once a pack asks for "bevel".

var style := "plain"

var face := Color("c0c0c0")
var hilight := Color("ffffff")
var light := Color("dfdfdf")
var shadow := Color("808080")
var dark := Color("000000")
var caption_a := Color("000080")
var caption_b := Color("1084d0")
var desktop := Color("008080")   ## the screen behind the dialogs when the pack has no title picture (bevel style)
var font_size := 14

var _theme: Theme = null


static func from_dict(d: Dictionary) -> UiSkin:
	var s := UiSkin.new()
	for k in ["face", "hilight", "light", "shadow", "dark", "caption_a", "caption_b", "desktop"]:
		if d.has(k):
			s.set(k, Color(String(d[k])))
	s.font_size = int(d.get("font_size", s.font_size))
	s.style = String(d.get("style", s.style))
	return s


## A 6 x 6 bevel (2 px edges) as a nine-patch: `raised` = light top-left / dark bottom-right, else the reverse (sunken); `field` = a white face (list and text fields).
func bevel(raised: bool, field := false) -> StyleBoxTexture:
	var img := Image.create(6, 6, false, Image.FORMAT_RGBA8)
	img.fill(hilight if field else face)
	var tl_out := hilight if raised else shadow
	var tl_in := light if raised else dark
	var br_out := dark if raised else hilight
	var br_in := shadow if raised else light
	for i in 6:
		img.set_pixel(i, 0, tl_out)
		img.set_pixel(0, i, tl_out)
		img.set_pixel(i, 5, br_out)
		img.set_pixel(5, i, br_out)
	for i in range(1, 5):
		img.set_pixel(i, 1, tl_in)
		img.set_pixel(1, i, tl_in)
		img.set_pixel(i, 4, br_in)
		img.set_pixel(4, i, br_in)
	var sb := StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(img)
	sb.texture_margin_left = 2
	sb.texture_margin_right = 2
	sb.texture_margin_top = 2
	sb.texture_margin_bottom = 2
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


func theme() -> Theme:
	if style != "bevel":
		return null   # the engine's own theme
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = font_size
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = dark
	focus.set_border_width_all(1)
	focus.set_expand_margin_all(-4)
	for cls in ["Button"]:
		t.set_stylebox("normal", cls, bevel(true))
		t.set_stylebox("hover", cls, bevel(true))
		t.set_stylebox("pressed", cls, bevel(false))
		t.set_stylebox("disabled", cls, bevel(true))
		t.set_stylebox("focus", cls, focus)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			t.set_color(c, cls, dark)
		t.set_color("font_disabled_color", cls, shadow)
	t.set_color("font_color", "Label", dark)
	var field := bevel(false, true)
	t.set_stylebox("panel", "ItemList", field)
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_color("font_color", "ItemList", dark)
	t.set_color("font_selected_color", "ItemList", hilight)
	t.set_color("font_hovered_color", "ItemList", dark)
	var sel := StyleBoxFlat.new()
	sel.bg_color = caption_a
	t.set_stylebox("selected", "ItemList", sel)
	t.set_stylebox("selected_focus", "ItemList", sel)
	t.set_stylebox("hovered", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("panel", "PanelContainer", bevel(true))
	_theme = t
	return t


## A dialog window: a raised frame, a navy caption bar with `title`, and a face-coloured client area. Returns {root, body}: add `root` where the window goes (it sizes to its
## content and is centred by the caller), put the dialog's controls in `body`.
func window(title: String) -> Dictionary:
	if style != "bevel":
		var plain := VBoxContainer.new()
		plain.add_theme_constant_override("separation", 8)
		var head := Label.new()
		head.text = title
		head.add_theme_font_size_override("font_size", 28)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		plain.add_child(head)
		return {"root": plain, "body": plain}
	var frame := PanelContainer.new()
	frame.theme = theme()
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # the 6 x 6 bevels must not blur into their faces
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	frame.add_child(col)
	var bar := PanelContainer.new()
	var grad := Gradient.new()
	grad.set_color(0, caption_a)
	grad.set_color(1, caption_b)
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	gt.width = 256
	gt.height = 4
	var bar_box := StyleBoxTexture.new()
	bar_box.texture = gt
	bar_box.content_margin_left = 6
	bar_box.content_margin_top = 2
	bar_box.content_margin_bottom = 2
	bar.add_theme_stylebox_override("panel", bar_box)
	var cap := Label.new()
	cap.text = title
	cap.add_theme_color_override("font_color", hilight)
	cap.add_theme_font_size_override("font_size", font_size)
	bar.add_child(cap)
	col.add_child(bar)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	col.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	margin.add_child(body)
	return {"root": frame, "body": body}


## The screen behind a front-end dialog: the title picture scaled to the window (aspect kept, black bars), or the era's desktop teal when the pack has none.
func add_backdrop(parent: Control, picture: Texture2D) -> void:
	var bg := ColorRect.new()
	bg.color = Color.BLACK if picture != null else (desktop if style == "bevel" else Color(0.08, 0.08, 0.1))
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	if picture != null:
		var pic := TextureRect.new()
		pic.texture = picture
		pic.set_anchors_preset(Control.PRESET_FULL_RECT)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(pic)


## Puts a window (from `window()`) in the middle of `parent`.
func centre(parent: Control, root: Control) -> void:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(cc)
	cc.add_child(root)
