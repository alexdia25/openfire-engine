# The hangar screen must be drawn above the view-fade layer: docking fades the view to black (view_fade 0) and the
# hangar then opens on top of it, below the death skull. (Regression: with the fade above the hangar, docking showed a
# fully black screen.) On the engine's synthetic fixture. Moved from openfire's tools/tests (issue alexdia25/openfire#65).
# Run (see tests/README.md):
#   godot --headless --path .harness --script res://addons/openfire_engine/tests/hud_layer_order_check.gd
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
	var hud: Node = null
	for c in view.get_children():
		if c is PlaceholderHud:
			hud = c
	_check(hud != null, "the level has its HUD")
	var fade_i := -1
	var select_i := -1
	var skull_i := -1
	for i in hud.get_child_count():
		var c := hud.get_child(i)
		if c is SelectorScreen:
			select_i = i
		elif c is DeathSkullView:
			skull_i = i
		elif c is ColorRect:
			fade_i = i
	_check(fade_i >= 0 and select_i > fade_i and skull_i > select_i,
			"fade < hangar screen < skull (children %d, %d, %d)" % [fade_i, select_i, skull_i])
	_done("hud_layer_order_check")
