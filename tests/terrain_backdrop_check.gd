# The finite ground mesh's own gap (terrain_view_3d.gd's _build_terrain_ground comment): near a map's edge the tilted
# camera's rays can overshoot it, which showed Godot's default background instead of terrain. A WorldEnvironment now
# fills that gap with a sand-toned backdrop, without adding ambient light that would change the ground plane's own
# directional-light shading. On the engine's synthetic fixture. Moved from openfire's tools/tests (issue
# alexdia25/openfire#65). Run (see tests/README.md):
#   godot --headless --path .harness --script res://addons/openfire_engine/tests/terrain_backdrop_check.gd
extends SceneTree

const Fixture := preload("fixtures/synthetic_pack.gd")

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _done(name: String) -> void:
	print("%s: %s" % [name, "PASS" if _failures == 0 else "%d FAILED" % _failures])
	quit(0 if _failures == 0 else 1)


func _view() -> Node:
	var view: Node = load("res://addons/openfire_engine/game/terrain_view_3d.tscn").instantiate()
	get_root().add_child(view)
	current_scene = view
	for i in 3:
		await process_frame
	return view


func _init() -> void:
	ProjectSettings.set_setting(EngineConfig.BASE_PACK, Fixture.build("user://packs"))
	var view: Node = await _view()
	var we: WorldEnvironment = null
	for c in view.get_children():
		if c is WorldEnvironment:
			we = c
	_check(we != null, "a WorldEnvironment was built")
	var env := we.environment
	_check(env.background_mode == Environment.BG_COLOR, "its background is a flat colour, not Godot's default clear colour")
	_check(env.background_color.r > 0.5 and env.background_color.g > 0.4 and env.background_color.b > 0.2,
			"the colour is a plausible sand tone, not black: %s" % env.background_color)
	_check(env.ambient_light_source == Environment.AMBIENT_SOURCE_DISABLED, "no ambient light: the ground plane's own shading is unchanged")
	_done("terrain_backdrop_check")
