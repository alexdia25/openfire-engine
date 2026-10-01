class_name ModLoader
extends RefCounted
## Builds the pack the game runs on (PORTING_PLAN.md 2.7.4, 2.7.9): the original content, with the mods the player has
## enabled layered on top of it, in order. Mods never replace original files -- each one is its own folder whose entries
## override the original's per id, and anything a mod doesn't touch is the original. So with no mods enabled, or if any
## enabled mod fails to load, the game runs the original content unchanged.
##
## `RF_PACK=<dir>` still overrides everything for one run (testing, and the mod tool's "Play this map").
##
## Which pack is "the original content" is the game's to say, not the engine's: `base_pack_dir()`.

const MODS_DIR := "user://mods"   ## where the mod tool creates mods; a mod may live anywhere, it is listed by its path


## The game's base pack: the project's `EngineConfig.base_pack()` (`openfire/packs/base_pack`, which an export may vary
## by feature tag, e.g. to a `user://` pack generated on the player's machine). "" if the game names none.
static func base_pack_dir() -> String:
	return EngineConfig.base_pack()


## Whether `dir` holds a loadable pack manifest (a pack.json that parses to an object). Quiet: a missing pack is an
## expected state (a first run before the game's content exists), not an engine error.
static func has_pack(dir: String) -> bool:
	if dir == "" or not FileAccess.file_exists(dir.path_join("pack.json")):
		return false
	var json := JSON.new()
	return json.parse(FileAccess.get_file_as_string(dir.path_join("pack.json"))) == OK and json.data is Dictionary


## The game's pack: RF_PACK if set, else the base pack (`base_dir`, "" = `base_pack_dir()`) plus the enabled mods
## (GameSettings.enabled_mods unless `mods` is given). Never fails over a bad mod: it is skipped (a warning), and if the
## stack still won't load, the base alone is used.
static func load_game_pack(base_dir := "", mods: Variant = null) -> Pack:
	if base_dir == "":
		base_dir = base_pack_dir()
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


## Directories the editor must never open for editing: the base pack this build ships, and any others named here by
## the same convention (the pack's own directory, never a mod's). A pack with no `base_pack` of its own is NOT
## automatically one of these -- since PORTING_PLAN.md 2.7's sharpened end goal (2026-09-27), it is a normal,
## editable **standalone project** (a game with no Return Fire content under it at all), not "a base pack" in the
## sense this list means. Compared with `editor_open_problem()` by resolved path, so `dir` may be given as `res://`,
## `user://` or a plain filesystem path.
static func protected_base_dirs() -> Array[String]:
	var base := base_pack_dir()
	return [base] if base != "" else []


## Why a directory can't be used as a mod ("" if it can): it must exist, have a readable pack.json, and name a base
## pack (a pack without one is not layerable over another -- `load_game_pack()`'s stack only works when every entry
## in `GameSettings.enabled_mods` has a `base_pack`, even though `Pack.load_stack()` itself never reads that field;
## a standalone project belongs in `RF_PACK` or as its own `base_dir`, not the enabled-mods list). Used by
## `load_game_pack()` and `list_mods()`; the editor's own "can I open this" gate is `editor_open_problem()` below,
## which is a different, narrower question.
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


## Why a directory can't be opened in the editor ("" if it can): it must exist and have a readable pack.json, and it
## must not be one of `protected_base_dirs()` -- original content is never edited directly, whatever a mod or a
## standalone project changes is its own copy. Unlike `mod_problem()`, a missing `base_pack` is fine here: it means
## "a project with nothing under it," which New game... creates on purpose.
static func editor_open_problem(dir: String) -> String:
	var path := dir.path_join("pack.json")
	if not FileAccess.file_exists(path):
		return "no pack.json"
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not (json.data is Dictionary):
		return "pack.json is not valid JSON"
	var resolved := ProjectSettings.globalize_path(dir)
	for protected in protected_base_dirs():
		if resolved == ProjectSettings.globalize_path(protected):
			return "it is original content, never edited directly"
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
