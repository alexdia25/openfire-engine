class_name SpriteCanvas
extends Control
## The sprite detail view (EDITOR_PLAN.md 3.1): one sprite drawn zoomed with nearest filtering on a checkerboard, a pixel
## grid from 6x zoom, the pivot as a crosshair, and optionally a team-paint mask over it. Built as a canvas with a current
## *tool* so pixel tools can be added later without changing it: today the tools are "pan/zoom" (always) and "pivot"
## (click sets the pivot).

signal pivot_picked(pivot: Vector2)

enum Tool { VIEW, PIVOT }

var pack: Pack
var sprite_id := ""
var mask_id := ""           ## drawn tinted over the sprite when set (a team-paint mask)
var mask_texture: Texture2D  ## or a ready-made mask image the sprite's size (a tan/green pair's differing pixels)
var tool := Tool.VIEW
var zoom := 8.0
var _offset := Vector2.ZERO  ## pan, in screen pixels
var _dragging := false
var _auto_fit := true        ## refit on resize until the user zooms or pans this sprite


func _ready() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # pixel art: never smooth it when zoomed
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(func():
		if _auto_fit:
			_fit()
		queue_redraw())


func show_sprite(shared_pack: Pack, id: String, mask := "", mask_tex: Texture2D = null) -> void:
	pack = shared_pack
	var changed_sprite := id != sprite_id
	sprite_id = id
	mask_id = mask
	mask_texture = mask_tex
	if changed_sprite:
		_auto_fit = true
		_fit()
	queue_redraw()


func _fit() -> void:
	_offset = Vector2.ZERO
	var s := pack.get_sprite(sprite_id) if pack != null else {}
	if s.is_empty() or size.x <= 0.0:
		zoom = 8.0
		return
	var fit := minf(size.x / float(s["w"]), size.y / float(s["h"])) * 0.8
	zoom = clampf(floorf(fit), 1.0, 32.0)


func _origin(s: Dictionary) -> Vector2:
	return (size - Vector2(float(s["w"]), float(s["h"])) * zoom) / 2.0 + _offset


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.16, 0.16, 0.18))
	if pack == null or sprite_id == "":
		return
	var s := pack.get_sprite(sprite_id)
	if s.is_empty():
		return
	var o := _origin(s)
	var w := float(s["w"])
	var h := float(s["h"])
	var cell := maxf(zoom, 4.0) * 2.0
	for y in int(ceil(h * zoom / cell)):
		for x in int(ceil(w * zoom / cell)):
			var r := Rect2(o + Vector2(x, y) * cell, Vector2(cell, cell)).intersection(Rect2(o, Vector2(w, h) * zoom))
			draw_rect(r, Color(0.32, 0.32, 0.34) if (x + y) % 2 == 0 else Color(0.26, 0.26, 0.28))
	var tex := pack.get_texture(int(s["page"]))
	draw_texture_rect_region(tex, Rect2(o, Vector2(w, h) * zoom), Rect2(float(s["x"]), float(s["y"]), w, h))
	if mask_id != "":
		var m := pack.get_sprite(mask_id)
		if not m.is_empty():
			draw_texture_rect_region(pack.get_texture(int(m["page"])), Rect2(o, Vector2(w, h) * zoom),
					Rect2(float(m["x"]), float(m["y"]), float(m["w"]), float(m["h"])), Color(1.0, 0.1, 0.9, 0.55))
	if mask_texture != null:
		draw_texture_rect(mask_texture, Rect2(o, Vector2(w, h) * zoom), false, Color(1.0, 0.1, 0.9, 0.55))
	if zoom >= 6.0:
		var grid := Color(0, 0, 0, 0.25)
		for x in int(w) + 1:
			draw_line(o + Vector2(x * zoom, 0), o + Vector2(x * zoom, h * zoom), grid)
		for y in int(h) + 1:
			draw_line(o + Vector2(0, y * zoom), o + Vector2(w * zoom, y * zoom), grid)
	draw_rect(Rect2(o, Vector2(w, h) * zoom), Color(1, 1, 1, 0.35), false)
	var p := o + Vector2(float(s.get("pivot_x", w / 2.0)), float(s.get("pivot_y", h / 2.0))) * zoom
	for c in [[Color.BLACK, 3.0], [Color(1.0, 0.85, 0.1), 1.0]]:
		draw_line(p - Vector2(10, 0), p + Vector2(10, 0), c[0], c[1])
		draw_line(p - Vector2(0, 10), p + Vector2(0, 10), c[0], c[1])
	draw_string(get_theme_default_font(), Vector2(8, size.y - 8), "%dx  %d x %d px%s" % [int(zoom), int(w), int(h),
			"   click to set the pivot" if tool == Tool.PIVOT else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.7))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			_auto_fit = false
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = minf(zoom * 1.25, 64.0)
			queue_redraw()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = maxf(zoom / 1.25, 1.0)
			queue_redraw()
		elif event.button_index == MOUSE_BUTTON_LEFT and tool == Tool.PIVOT and pack != null:
			var s := pack.get_sprite(sprite_id)
			if not s.is_empty():
				pivot_picked.emit(((event.position - _origin(s)) / zoom).clamp(Vector2.ZERO, Vector2(float(s["w"]), float(s["h"]))))
		elif event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			_dragging = true
	elif event is InputEventMouseButton and not event.pressed and event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
		_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		_offset += event.relative
		queue_redraw()
