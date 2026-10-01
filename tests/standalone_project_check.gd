# Standalone projects (PORTING_PLAN.md 2.7's sharpened end goal, 2026-09-27; EDITOR_PLAN.md "New game..."): a pack
# with no base_pack at all -- a game built entirely in the editor, with nothing under it -- is a normal, editable
# project, while the game's own base pack (here the engine's synthetic fixture) is still refused. Run (tests/README.md):
#   godot --headless --path .harness --script res://addons/openfire_engine/tests/standalone_project_check.gd
extends SceneTree

const Fixture := preload("fixtures/synthetic_pack.gd")

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _init() -> void:
	var base_dir := Fixture.build("user://packs")
	ProjectSettings.set_setting(EngineConfig.BASE_PACK, base_dir)
	var game := ProjectSettings.globalize_path("user://standalone_project_check/game")
	if DirAccess.dir_exists_absolute(game):
		OS.move_to_trash(game)

	# what "New game..." does
	var made := ModWorkspace.create(game, "My game", "")
	_check(made != null, "a standalone project is created")
	made.close()

	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(game.path_join("pack.json")))
	_check(manifest.get("base_pack", "not empty") == "", "its manifest has no base_pack at all")

	_check(ModLoader.editor_open_problem(game) == "", "the editor can open it")
	_check(ModLoader.mod_problem(game) != "", "but it is not a layerable mod (no base_pack): %s" % ModLoader.mod_problem(game))

	var ws := ModWorkspace.new()
	_check(ws.open(game), "ModWorkspace opens it")
	_check(ws.pack != null and ws.pack.layers.size() == 1 and ws.pack.layers[0] == game, "one layer: itself, nothing under it")
	_check(ws.pack.vehicle_order.is_empty() and ws.pack.list_levels().is_empty(), "no vehicles or levels until the editor adds some")

	# every panel a fresh project opens into stays usable with nothing in it (no crash, no error)
	var vp := VehiclePreviewPanel.new()
	get_root().add_child(vp)
	await process_frame   # panels build their controls in _ready(), which a bare add_child() does not run synchronously
	vp.setup(ws)
	_check(vp.vehicle == null, "the vehicle preview shows nothing selected, not an error")
	vp.queue_free()

	var mv := MapViewPanel.new()
	get_root().add_child(mv)
	await process_frame
	mv.setup(ws)
	mv.queue_free()

	# adding the project's own first vehicle works the same as in a mod
	PackWriter.write_json(game.path_join("vehicles/mygame.buggy/vehicle.json"), Fixture.vehicle_def("mygame.buggy", "Buggy", 0))
	ws.reload()
	_check(ws.pack.vehicle_order == ["mygame.buggy"], "a vehicle added to the project shows up, with no roster or base content assumed")

	ws.close()

	# the game's own base content is still refused
	_check(ModLoader.editor_open_problem(ModLoader.base_pack_dir()) != "", "the game's base pack still refuses to open")
	var refused := ModWorkspace.new()
	_check(not refused.open(ModLoader.base_pack_dir()), "and ModWorkspace agrees")

	print("standalone_project_check: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)
