class_name WinRibbon
extends Control
## The end-of-match victory ribbon (document 92): after the winning capture the original fades the game to black (FUN_004225d0 starts a 1000 ms fade, the handler
## 0x4222a0 waits for it), then shows the winner's ribbon bitmap over the cleared screen (FUN_00430b10 draws TITLE\Ban{B,G}{L,H}.bmp with FUN_004306b0: the winner
## picks tan or green, the display mode low or high resolution) while a victory jingle plays (TITLE\Win*.stm, not decoded: the port plays none), and fades it out
## when the jingle ends.
## Traced: the fade to black (1000 ms), the ribbon choice, its placement (centred, top edge at y 180 of a 240-high low-res screen, doubled in high-res).
## PORT CHOICES / UNTRACED: the ribbon is shown until Enter (the original holds it for the jingle's length, then leaves the level); the 500 ms fade-in of the ribbon
## is the port's; the black background behind it is inferred (the sequence has no scene draw between the fade and the bitmap); the high-resolution bitmap is drawn at
## 1.5x so it is 540 wide, the size the low-res one would have at the port's 3x scale.

const FADE_OUT_S := 1.0        ## FUN_0042fdd0(0, 1000)
const RIBBON_FADE_IN_S := 0.5  ## port choice
const TOP_FRACTION := 180.0 / 240.0
const SCALE_HIGH := 1.5

var _black: ColorRect
var _ribbon: TextureRect
var _t := -1.0
var _tex: Texture2D


func setup(pack: Pack) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 0)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ribbon = TextureRect.new()
	_ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ribbon.stretch_mode = TextureRect.STRETCH_SCALE
	_ribbon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ribbon.modulate.a = 0.0
	add_child(_ribbon)
	_pack = pack


var _pack: Pack


## The ribbon file of `winner_idx` (0 tan, 1 green), read from the pack's hud folder (tools/extract_win_banners.py); null when the pack has none.
func _load(winner_idx: int) -> Texture2D:
	var name := "win_banner_%s_high.png" % ("tan" if winner_idx == 0 else "green")
	for i in range(_pack.layers.size() - 1, -1, -1):
		var path := "%s/hud/%s" % [_pack.layers[i], name]
		if FileAccess.file_exists(path):
			var img := Image.load_from_file(path)
			if img != null:
				return ImageTexture.create_from_image(img)
	return null


## True when a ribbon will be shown (the caller keeps its own text otherwise).
func start(winner_idx: int) -> bool:
	_tex = _load(winner_idx)
	if _tex == null:
		return false
	_ribbon.texture = _tex
	_ribbon.size = Vector2(_tex.get_size()) * SCALE_HIGH
	_t = 0.0
	visible = true
	return true


func _process(delta: float) -> void:
	if _t < 0.0:
		return
	_t += delta
	_black.color.a = clampf(_t / FADE_OUT_S, 0.0, 1.0)
	_ribbon.modulate.a = clampf((_t - FADE_OUT_S) / RIBBON_FADE_IN_S, 0.0, 1.0)
	var vp := get_viewport_rect().size
	size = vp   # a Control under a CanvasLayer is not laid out by anchors (placeholder_hud.gd sizes its fade the same way)
	_black.size = vp
	_ribbon.position = Vector2((vp.x - _ribbon.size.x) * 0.5, vp.y * TOP_FRACTION)
