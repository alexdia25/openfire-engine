# The two panel layouts (document 96): HudLayout's arithmetic. Run:
#   godot --headless --path .harness --script res://addons/openfire_engine/tests/hud_layout_check.gd
extends SceneTree

var fails := 0


func check(name: String, ok: bool, detail: String = "") -> void:
	print(("ok   " if ok else "FAIL ") + name + ("  " + detail if detail != "" else ""))
	if not ok:
		fails += 1


func _init() -> void:
	var vp := Vector2(1152, 648)
	GameSettings.hud_layout = HudLayout.CLASSIC
	check("classic scale of 1152 x 648 is 2.7", is_equal_approx(HudLayout.classic_scale(vp), 2.7))
	var pic := HudLayout.picture_rect(vp)
	check("the picture is 864 x 648, centred", pic.size == Vector2(864, 648) and pic.position == Vector2(144, 0), str(pic))
	var view := HudLayout.view_rect(vp)
	check("the view is the top 152 of 240 rows: 864 x 410.4", view.position == Vector2(144, 0) and is_equal_approx(view.size.y, 410.4) and view.size.x == 864.0, str(view))
	check("the panel is at (87, 168) of the picture", HudLayout.panel_position(vp).is_equal_approx(Vector2(144 + 87 * 2.7, 168 * 2.7)), str(HudLayout.panel_position(vp)))
	check("the panel's scale is the picture's", is_equal_approx(HudLayout.panel_scale(vp), 2.7))
	var p43 := Vector2(1024, 768)
	check("a 4:3 window is filled exactly", HudLayout.picture_rect(p43) == Rect2(Vector2.ZERO, p43))
	GameSettings.hud_layout = HudLayout.MODERN
	check("modern: the view is the whole window", HudLayout.view_rect(vp) == Rect2(Vector2.ZERO, vp))
	check("modern: 3 pixels per original pixel, 12 px from the left, 198 above the bottom", HudLayout.panel_scale(vp) == 3.0 and HudLayout.panel_position(vp) == Vector2(12, 648 - 198))
	print("failures: ", fails)
	quit(1 if fails > 0 else 0)
