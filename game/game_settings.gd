class_name GameSettings
extends RefCounted
## User-facing switches. There is no settings menu yet, so `user://settings.cfg` (written with the defaults on first run) is the interface: edit it, or bind a future
## menu to these variables and call save_settings(). `RF_NO_SWOOP=1` in the environment forces the camera swoop off for one run.

const PATH := "user://settings.cfg"

## The camera swoops in from a high, zoomed-out view when a vehicle comes out of the base (document 90). Off = the camera is simply at its normal place.
static var camera_swoop_in := true

## Mods layered over the original content, in load order (later wins), as folder paths (PORTING_PLAN.md 2.7.9; ModLoader).
## Empty = the original game exactly as it is.
static var enabled_mods: Array = []


static func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		camera_swoop_in = bool(cfg.get_value("camera", "swoop_in", camera_swoop_in))
		enabled_mods = Array(cfg.get_value("mods", "enabled", []))
	else:
		save_settings()
	if OS.get_environment("RF_NO_SWOOP") == "1":
		camera_swoop_in = false


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("camera", "swoop_in", camera_swoop_in)
	cfg.set_value("mods", "enabled", enabled_mods)
	cfg.save(PATH)
