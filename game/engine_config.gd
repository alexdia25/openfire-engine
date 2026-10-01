class_name EngineConfig
extends RefCounted
## What a game built on this engine tells the engine about itself. The engine knows no particular game: everything a
## consumer project (Return Fire's `openfire`, a new game) would otherwise have to edit engine code for is one of these
## ProjectSettings keys, set in that project's own `project.godot`. Every key is optional; the defaults are a project
## with no content of its own yet.
##
##   openfire/packs/base_pack       the pack the game runs on (a directory with a pack.json): `res://packs/<id>` for a
##                                  game that bundles its content, a `user://` path for one whose content is generated
##                                  on the player's machine. "" = none (the game shows an empty project).
##   openfire/editor/asset_registry an optional JSON file of notes about sprite ids ({"cels": {...: {id, confidence,
##                                  note}}}) that the mod tool's Assets panel shows beside each sprite. "" = none.
##
## A setting may be varied per export with a feature tag in the usual Godot way, e.g.
## `openfire/packs/base_pack.some_feature="user://packs/x"`.

const BASE_PACK := "openfire/packs/base_pack"
const ASSET_REGISTRY := "openfire/editor/asset_registry"

## Where packs named by id (a mod's `base_pack`) are looked for after the mod's own sibling directories: the game's
## bundled packs first, then packs generated on this machine.
const PACK_SEARCH_ROOTS: Array[String] = ["res://packs", "user://packs"]


static func base_pack() -> String:
	return String(ProjectSettings.get_setting(BASE_PACK, ""))


static func asset_registry() -> String:
	return String(ProjectSettings.get_setting(ASSET_REGISTRY, ""))
