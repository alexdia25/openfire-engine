class_name ClassicFrame
extends Control
## The classic layout's surround (document 96): black outside the 4:3 picture, and the backdrop strip (ART\1PBSCRL.RFA, tools/extract_hud_strip.py) below the game view,
## where the vehicle's panel sits. Draws nothing in the modern layout. Sized to the window every frame (a Control under a CanvasLayer is not laid out by anchors).

var _strip: Texture2D
var _last_key := ""


func setup(pack: Pack) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip = HudLayout.load_pack_image(pack, "strip_1p_low.png")


func _process(_delta: float) -> void:
	var vp := get_viewport_rect().size
	size = vp
	var key := "%s %s" % [GameSettings.hud_layout, vp]
	if key != _last_key:
		_last_key = key
		queue_redraw()


func _draw() -> void:
	if not HudLayout.is_classic():
		return
	var vp := get_viewport_rect().size
	var pic := HudLayout.picture_rect(vp)
	draw_rect(Rect2(0, 0, pic.position.x, vp.y), Color.BLACK)
	draw_rect(Rect2(pic.end.x, 0, vp.x - pic.end.x, vp.y), Color.BLACK)
	draw_rect(Rect2(0, 0, vp.x, pic.position.y), Color.BLACK)
	draw_rect(Rect2(0, pic.end.y, vp.x, vp.y - pic.end.y), Color.BLACK)
	var k := HudLayout.classic_scale(vp)
	if _strip == null:
		draw_rect(Rect2(pic.position + Vector2(0, HudLayout.STRIP_TOP * k), Vector2(HudLayout.SCREEN.x, HudLayout.SCREEN.y - HudLayout.STRIP_TOP) * k), Color(0.15, 0.15, 0.17))
		return
	draw_texture_rect(_strip, Rect2(pic.position + Vector2(0, HudLayout.STRIP_TOP * k), _strip.get_size() * k), false)
