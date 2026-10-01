# The engine knows no particular game (openfire-engine README, "What a game tells the engine"): which pack is the
# game's base comes from the project's own `openfire/packs/base_pack` setting (EngineConfig), with nothing assumed when
# it is unset; ModLoader.has_pack() is a quiet yes/no for a first run before any content exists; a mod names its base
# by id and finds it under EngineConfig.PACK_SEARCH_ROOTS; and the mod tool's "New mod" layers over whatever the game's
# base is (by its manifest id), or makes a standalone project when there is none. Run (see tests/README.md):
#   godot --headless --path .harness --script res://addons/openfire_engine/tests/engine_config_check.gd
extends SceneTree

const Fixture := preload("fixtures/synthetic_pack.gd")

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _init() -> void:
	var root := "user://engine_config_check"
	if DirAccess.dir_exists_absolute(root):
		OS.move_to_trash(ProjectSettings.globalize_path(root))

	# nothing set: a project with no content of its own yet
	ProjectSettings.set_setting(EngineConfig.BASE_PACK, "")
	_check(ModLoader.base_pack_dir() == "", "no base pack named: none assumed")
	_check(ModLoader.protected_base_dirs().is_empty(), "so nothing is protected from the editor")
	_check(ModWorkspace.default_base() == "", "and a new mod is a standalone project (no base_pack)")
	_check(EngineConfig.asset_registry() == "", "no asset registry unless the game names one")

	# has_pack(): quiet, for a first run before the content exists
	_check(not ModLoader.has_pack(""), "has_pack: an empty path is not a pack")
	_check(not ModLoader.has_pack(root.path_join("missing")), "has_pack: a missing directory is not a pack")
	PackWriter.write_json(root.path_join("broken/placeholder.json"), {})
	FileAccess.open(root.path_join("broken/pack.json"), FileAccess.WRITE).store_string("{ nope")
	_check(not ModLoader.has_pack(root.path_join("broken")), "has_pack: an unparseable pack.json is not a pack")

	# the game names its base pack: here, one generated into user:// (as a game whose content is made on the player's
	# machine would), so nothing about it is bundled under res://
	var base_dir := Fixture.build("user://packs")
	ProjectSettings.set_setting(EngineConfig.BASE_PACK, base_dir)
	_check(ModLoader.has_pack(base_dir), "has_pack: the fixture is a pack")
	_check(ModLoader.base_pack_dir() == base_dir, "the base pack is the project's setting")
	_check(ModLoader.protected_base_dirs().size() == 1 and ModLoader.protected_base_dirs()[0] == base_dir, "the base is protected from direct editing")
	_check(ModLoader.editor_open_problem(base_dir) != "", "the editor refuses to open it")
	_check(ModWorkspace.default_base() == Fixture.ID, "a new mod layers over the base, named by its manifest id")
	var pack := ModLoader.load_game_pack("", [])
	_check(pack.layers.size() == 1 and pack.manifest.get("title") == "Fixture", "load_game_pack() with no base_dir loads the project's base")

	# a mod far from its base finds it by id through the search roots
	var mod := ProjectSettings.globalize_path(root.path_join("elsewhere/a_mod"))
	var ws := ModWorkspace.create(mod, "A mod")
	_check(ws != null, "a mod is created over the base")
	ws.close()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(mod.path_join("pack.json")))
	_check(manifest.get("base_pack") == Fixture.ID, "its manifest names the base by id")
	var layered := Pack.new()
	_check(layered.load_from(mod) and layered.layers.size() == 2 and layered.layers[0] == base_dir,
			"and it loads over the base found under user://packs (EngineConfig.PACK_SEARCH_ROOTS)")

	ProjectSettings.set_setting(EngineConfig.BASE_PACK, "")
	print("engine_config_check: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)
