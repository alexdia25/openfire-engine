class_name DeathSkullView
extends Control
## The laughing skull of the loss sequence (document 88): FUN_00418510 draws one 64 x 64 cel (2125 + the mouth table's frame, +7 for player 0: a player sees the OTHER
## team's helmet -- player 0 the green skulls 2133-2139, player 1 the tan ones 2126-2132) as a quad turned by the angle (64 steps) and scaled (0.01 growing to 1.2), with the
## fade-out's transparency. State and timing live in MatchController; this only draws it. PORT CHOICE (the original's screen position is the player's `+0x10/+0x14`, not
## traced): the centre of the view, scaled with the window height against the original's 480 lines.

var mc: MatchController


func setup(controller: MatchController) -> void:
	mc = controller
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if mc == null or mc.vehicle == null or mc.death_phase < 2:
		return
	var f := mc.skull_frame()
	if f < 1:
		return
	var team := "green" if mc.vehicle.player_index() == 0 else "tan"
	var s := mc.pack.get_sprite("ui.death_skull.%s.f%d" % [team, f])
	if s.is_empty():
		return
	var tex := mc.pack.get_texture(int(s.get("page", 0)))
	var vp := get_viewport_rect().size   # (a Control under a CanvasLayer has no parent rect to anchor to)
	var px := vp.y / 480.0 * mc.skull_scale()
	draw_set_transform(vp * 0.5, deg_to_rad(mc.skull_angle_deg()), Vector2(px, px))
	draw_texture_rect_region(tex, Rect2(-32.0, -32.0, 64.0, 64.0), Rect2(float(s["x"]), float(s["y"]), float(s["w"]), float(s["h"])),
			Color(1, 1, 1, mc.skull_alpha))
