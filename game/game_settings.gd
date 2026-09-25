class_name GameSettings
extends RefCounted
## User-facing switches. There is no settings menu yet, so `user://settings.cfg` (written with the defaults on first run) is the interface: edit it, or bind a future
## menu to these variables and call save_settings(). `RF_NO_SWOOP=1` in the environment forces the camera swoop off for one run.

const PATH := "user://settings.cfg"

## The camera swoops in from a high, zoomed-out view when a vehicle comes out of the base (document 90). Off = the camera is simply at its normal place.
static var camera_swoop_in := true

## The player's panel layout (document 96): "classic" = the original's one-player screen (320 x 152 game view above the backdrop strip, the panel at (87, 168), all scaled to the
## window), "modern" = the port's own (the view fills the window, the panel at its bottom left). `RF_HUD=classic|modern` in the environment overrides it for one run.
## The temporary placeholder HUD (labels) is not affected.
static var hud_layout := "modern"

## The music (document 98): played from the pack's music/ folder (tools/extract_music.py). `RF_NO_MUSIC=1` mutes it for one run.
static var music_enabled := true

## Mods layered over the original content, in load order (later wins), as folder paths (PORTING_PLAN.md 2.7.9; ModLoader).
## Empty = the original game exactly as it is.
static var enabled_mods: Array = []


static func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		camera_swoop_in = bool(cfg.get_value("camera", "swoop_in", camera_swoop_in))
		enabled_mods = Array(cfg.get_value("mods", "enabled", []))
		hud_layout = String(cfg.get_value("hud", "layout", hud_layout))
		music_enabled = bool(cfg.get_value("audio", "music", music_enabled))
	else:
		save_settings()
	if OS.get_environment("RF_NO_SWOOP") == "1":
		camera_swoop_in = false
	if OS.get_environment("RF_NO_MUSIC") == "1":
		music_enabled = false
	if OS.get_environment("RF_HUD") in ["classic", "modern"]:
		hud_layout = OS.get_environment("RF_HUD")


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("camera", "swoop_in", camera_swoop_in)
	cfg.set_value("mods", "enabled", enabled_mods)
	cfg.set_value("hud", "layout", hud_layout)
	cfg.set_value("audio", "music", music_enabled)
	cfg.save(PATH)
