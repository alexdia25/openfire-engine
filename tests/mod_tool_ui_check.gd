# Smoke test of the mod tool's UI (EDITOR_PLAN.md, E0) over the engine's synthetic fixture: the editor scene opens a
# fresh mod, the Assets panel selects and replaces a sprite, the Team colours panel adds a colour, undo / save /
# validation update the top bar and the Validate tab, the vehicle preview builds every vehicle with the game's renderer,
# and the map viewer lists, draws and describes the levels. The logic under it is mod_workspace_check's; this checks the
# panels are wired to it. Moved from openfire's tools/tests (issue alexdia25/openfire#65). Run (see tests/README.md):
#   godot --headless --path .harness --script res://addons/openfire_engine/tests/mod_tool_ui_check.gd
extends SceneTree

const Fixture := preload("fixtures/synthetic_pack.gd")

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _init() -> void:
	ProjectSettings.set_setting(EngineConfig.BASE_PACK, Fixture.build("user://packs"))
	var team_art: String = Fixture.TEAM_PAIR[0]
	var dir := ProjectSettings.globalize_path("user://mod_tool_ui_check/uimod")
	if DirAccess.dir_exists_absolute(dir):
		OS.move_to_trash(dir)
	ModWorkspace.create(dir, "UI test").close()
	OS.set_environment("RF_EDITOR_MOD", dir)
	var main: Control = load("res://addons/openfire_engine/editor/editor_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var ws: ModWorkspace = main.ws
	_check(ws != null and ws.mod_dir == dir, "editor opened the mod")
	_check(main._save_btn.disabled and main._undo_btn.disabled, "clean mod: save and undo disabled")

	var assets: AssetsPanel = main._assets
	assets.select(team_art)
	await process_frame
	_check(assets._canvas.sprite_id == team_art, "canvas shows the selected sprite")
	_check(assets._canvas.mask_texture != null, "a base team pair shows its team paint")
	var strip_found := false
	for c in assets._inspector.get_children():
		if c is GridContainer and c.get_child_count() == ws.pack.team_colours.size():
			strip_found = true
	_check(strip_found, "inspector shows a colour strip, one swatch per colour")

	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.CYAN)
	ws.import_frame(team_art, img, "Replace frame")
	await process_frame
	_check(not main._save_btn.disabled and not main._undo_btn.disabled, "an edit enables save and undo")
	_check(main._path_label.text.contains("unsaved"), "top bar says unsaved")
	var tree_has_mod_colour := false
	assets._mod_only.button_pressed = true
	assets._rebuild_tree()
	var groups := assets._tree.get_root().get_children()
	_check(groups.size() == 1 and groups[0].get_child_count() == 1, "'In this mod' filter lists just the replaced sprite")

	var colours: ColoursPanel = main._colours
	colours._name.text = "teal"
	colours._picker.color = Color.from_hsv(0.5, 0.7, 0.5)
	colours._apply()
	await process_frame
	var listed := false
	for i in colours._list.item_count:
		listed = listed or String(colours._list.get_item_metadata(i)) == "teal"
	_check(listed and ws.mod_colours.has("teal"), "a colour added in the panel is in the mod and listed")
	_check(colours._preview.get_child_count() == ColoursPanel.samples(ws.pack).size() and colours._preview.get_child_count() >= 1,
			"the preview shows the pack's own team art in it (%d)" % colours._preview.get_child_count())

	var findings: ItemList = main._findings
	var warned := false
	for i in findings.item_count:
		warned = warned or findings.get_item_text(i).contains("unsaved")
	_check(warned, "Validate lists the unsaved changes")
	ws.undo.undo()
	await process_frame
	_check(not ws.mod_colours.has("teal"), "undo from the top bar's stack removes the colour")
	ws.save()
	await process_frame
	_check(main._save_btn.disabled, "save disables save")

	# the vehicle preview assembles every vehicle type with the game's renderer, in any colour
	var vp: VehiclePreviewPanel = main._vehicles
	for t in Fixture.VEHICLES.size():
		vp.select_type(t)
		await process_frame
		var expected := "VehicleRender3D"
		_check(vp.vehicle != null and vp.vehicle.vehicle_type == t and vp._render != null and vp._render.get_script().get_global_name() == expected,
				"preview builds type %d with %s" % [t, expected])
		_check(vp._sliders_box.get_child_count() >= 4, "type %d has pose sliders" % t)
	vp.select_type(0)
	await process_frame
	(vp._sliders_box.get_child(3) as HSlider).value = 90.0   # [heading label, slider, turret label, turret slider, ...]
	await process_frame
	_check(is_equal_approx(vp._render._groups["turret"]["node"].rotation_degrees.y, -90.0), "the turret slider turns the game renderer's turret")
	vp.select_colour("red")
	await process_frame
	_check(vp.vehicle.art_colour() == "red", "preview colour is applied to the vehicle")
	vp._flash.button_pressed = true
	await process_frame
	_check(vp.vehicle.flashing(), "hit flash toggle")

	# the map viewer lists every level, draws one, recolours its sides and describes a tile
	var mp: MapViewPanel = main._maps
	_check(mp._names.size() == 2 and mp._names.get("LEVEL01", "") == "First Light" and mp._names.get("LEVEL02", "") == "Second Wind", "map viewer lists the levels with their names")
	mp.select_level("LEVEL02")
	await process_frame
	_check(mp.level != null and mp.level_id == "LEVEL02" and mp._tiles != null and mp._tiles.level == mp.level, "a level is drawn by the game's tile renderer")
	mp.show_sides_as(["red", "blue"])
	await process_frame
	_check(mp.level.side_colours == ["red", "blue"], "show sides as recolours the preview")
	var sp: Dictionary = mp.level.spawn_points[0]
	mp._describe((Vector2(float(sp["x"]), float(sp["y"])) + Vector2(0.5, 0.5)) * 32.0)
	_check(mp._hover.text.contains("spawn point") and mp._hover.text.contains("art "), "hover describes the tile under the cursor")
	mp.show_layers(["Water"])
	await process_frame
	_check(mp._overlay.show_water and not mp._overlay.show_roads, "overlay layers toggle")

	main.queue_free()
	await process_frame
	print("mod_tool_ui_check: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)
