class_name ModLoader
extends RefCounted
## Builds the pack the game runs on (PORTING_PLAN.md 2.7.4, 2.7.9): the original content, with the mods the player has
## enabled layered on top of it, in order. Mods never replace original files -- each one is its own folder whose entries
## override the original's per id, and anything a mod doesn't touch is the original. So with no mods enabled, or if any
## enabled mod fails to load, the game runs the original content unchanged.
##
## `RF_PACK=<dir>` still overrides everything for one run (testing, and the mod tool's "Play this map").

const BASE_PACK := "res://packs/original_pc"
const MODS_DIR := "user://mods"   ## where the mod tool creates mods; a mod may live anywhere, it is listed by its path


## The game's pack: RF_PACK if set, else the base pack plus the enabled mods (GameSettings.enabled_mods unless `mods` is
## given). Never fails over a bad mod: it is skipped (a warning), and if the stack still won't load, the base alone is used.
static func load_game_pack(base_dir := BASE_PACK, mods: Variant = null) -> Pack:
	var pack := Pack.new()
	var env := OS.get_environment("RF_PACK")
	if env != "":
		if pack.load_from(env):
			return pack
		push_warning("ModLoader: RF_PACK=%s did not load; running the original content" % env)
		pack = Pack.new()
		pack.load_from(base_dir)
		return pack
	if mods == null:
		GameSettings.load_settings()
		mods = GameSettings.enabled_mods
	var stack: Array[String] = [base_dir]
	for dir in mods:
		var why := mod_problem(String(dir))
		if why != "":
			push_warning("ModLoader: skipping mod %s: %s" % [dir, why])
			continue
		stack.append(String(dir))
	if stack.size() > 1 and pack.load_stack(stack):
		return pack
	if stack.size() > 1:
		push_warning("ModLoader: the enabled mods did not load together; running the original content")
	pack = Pack.new()
	pack.load_from(base_dir)
	return pack


## Why a directory can't be used as a mod ("" if it can): it must exist, have a readable pack.json, and name a base pack
## (a pack without one IS a base, e.g. original_pc -- never edited or loaded as a mod).
static func mod_problem(dir: String) -> String:
	var path := dir.path_join("pack.json")
	if not FileAccess.file_exists(path):
		return "no pack.json"
	var json := JSON.new()   # an instance parse returns the error quietly; a broken mod is expected, not an engine error
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not (json.data is Dictionary):
		return "pack.json is not valid JSON"
	var m: Dictionary = json.data
	if m.get("base_pack") == null or String(m.get("base_pack")) == "":
		return "it is a base pack, not a mod"
	return ""


## Every mod under MODS_DIR plus any enabled one elsewhere: [{dir, id, name, enabled}], enabled ones first in load order.
static func list_mods() -> Array[Dictionary]:
	GameSettings.load_settings()
	var out: Array[Dictionary] = []
	var seen := {}
	var dirs: Array = GameSettings.enabled_mods.duplicate()
	var root := ProjectSettings.globalize_path(MODS_DIR)
	var d := DirAccess.open(root)
	if d != null:
		for name in d.get_directories():
			dirs.append(root.path_join(name))
	for dir in dirs:
		if seen.has(dir) or mod_problem(String(dir)) != "":
			continue
		seen[dir] = true
		var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(String(dir).path_join("pack.json")))
		out.append({"dir": dir, "id": m.get("id", ""), "name": m.get("name", ""), "enabled": dir in GameSettings.enabled_mods})
	return out


static func set_enabled(dir: String, enabled: bool) -> void:
	GameSettings.load_settings()
	GameSettings.enabled_mods.erase(dir)
	if enabled:
		GameSettings.enabled_mods.append(dir)
	GameSettings.save_settings()
