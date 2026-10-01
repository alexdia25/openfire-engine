# Layered packs (PORTING_PLAN.md section 2.7.4) against the engine's synthetic fixture pack: a small mod pack in user://
# whose pack.json names the fixture as its base_pack, checking the per-id override rules -- replace, add, null-remove,
# atlas page offsets, loose frames packed at load time (2.7.5), sound files and levels resolving to the layer that
# supplied them, and a base_pack found through EngineConfig.PACK_SEARCH_ROOTS. Run (see tests/README.md):
#   godot --headless --path .harness --script res://addons/openfire_engine/tests/pack_layering_check.gd
extends SceneTree

const Fixture := preload("fixtures/synthetic_pack.gd")

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


## The top-left pixel of a sprite, read back from the page it was packed or placed on.
func _pixel(pk: Pack, id: String) -> Color:
	var s := pk.get_sprite(id)
	var img := pk.get_texture(int(s["page"])).get_image()
	return img.get_pixel(int(s["x"]), int(s["y"]))


func _init() -> void:
	var base_dir := Fixture.build("user://packs")   # a search root, so a mod anywhere can name it by id
	var base := Pack.new()
	_check(base.load_from(base_dir), "base pack loads")
	_check(base.layers.size() == 1, "base pack is one layer")
	var base_sprites := base.sprites.size()
	var base_pages := base.atlas_textures.size()
	var replaced_id := "fx.hull"
	var removed_id := "fx.turret"
	var frame_id := "fx.wheel"   # replaced by a loose frame of a different size

	var mod := ProjectSettings.globalize_path("user://pack_layering_check/test_mod")
	if DirAccess.dir_exists_absolute(mod):
		OS.move_to_trash(mod)
	PackWriter.write_json(mod.path_join("pack.json"), {"id": "test_mod", "name": "layering test", "base_pack": Fixture.ID})
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.MAGENTA)
	DirAccess.make_dir_recursive_absolute(mod.path_join("sprites/mod"))
	img.save_png(mod.path_join("sprites/mod_page.png"))
	var frame := Image.create(3, 5, false, Image.FORMAT_RGBA8)
	frame.fill(Color.CYAN)
	frame.save_png(mod.path_join("sprites/mod/frame.png"))
	PackWriter.write_json(mod.path_join("sprites/sprites.json"), {"atlas_pages": ["mod_page.png"], "sprites": {
		replaced_id: {"page": 0, "x": 0, "y": 0, "w": 4, "h": 4, "pivot_x": 2, "pivot_y": 2},
		"mod.new_sprite": {"page": 0, "x": 0, "y": 0, "w": 2, "h": 2, "pivot_x": 1, "pivot_y": 1},
		removed_id: null,
		frame_id: {"file": "mod/frame.png", "pivot_x": 1, "pivot_y": 2}}})
	var tank: Dictionary = base.vehicle_types["0"].duplicate(true)
	tank["hit_points"] = 99.0
	PackWriter.write_json(mod.path_join("vehicles/vehicle_types.json"), {"types": {"0": tank, "4": {"name": "Hovertank"}}})
	PackWriter.write_json(mod.path_join("audio/audio.json"), {"Ding": {"file": "MODDING.wav", "category": "sfx", "priority": 0}})
	PackWriter.write_json(mod.path_join("effects/explosions.json"), {"records": {"rec.small": {"modded": true}}})
	PackWriter.write_json(mod.path_join("levels/MODMAP01/level.json"), {"name": "MODMAP01", "width": 1, "height": 1})

	var p := Pack.new()
	_check(p.load_from(mod), "mod pack loads through its base_pack chain (found under a search root, not beside it)")
	_check(p.layers.size() == 2 and p.layers[0] == base_dir and p.layers[1] == mod, "two layers, mod on top")
	_check(p.manifest.get("id") == "test_mod", "manifest is the top layer's")
	_check(p.atlas_textures.size() == base_pages + 1, "mod atlas page appended")
	_check(_pixel(p, replaced_id) == Color.MAGENTA, "replaced sprite reads the mod's own atlas page")
	_check(_pixel(p, frame_id) == Color.CYAN and int(p.get_sprite(frame_id)["w"]) == 3 and int(p.get_sprite(frame_id)["h"]) == 5,
			"loose-frame override packed at its own size")
	_check(_pixel(base, frame_id) == Fixture.SPRITE_COLOURS[frame_id], "base pack's frame untouched")
	_check(p.get_sprite("mod.new_sprite").get("w") == 2, "new sprite added")
	_check(p.get_sprite(removed_id).is_empty(), "null entry removes a sprite")
	_check(p.sprites.size() == base_sprites, "sprite count: +1 added, -1 removed")
	_check(float(p.vehicle_types["0"]["hit_points"]) == 99.0, "vehicle type 0 overridden per id")
	_check(p.vehicle_types.has("1") and p.vehicle_types.has("4"), "other types kept, new type added")
	_check(p.get_sound_path("Ding") == mod.path_join("audio/MODDING.wav"), "overridden cue resolves to the mod's audio dir")
	_check(p.get_sound_path("Boom") == base_dir.path_join("audio/boom.wav"), "untouched cue resolves to the base's audio dir")
	_check(p.get_explosion("rec.small").get("modded", false), "explosion record overridden per id")
	_check(p.explosions.get("records", {}).size() == 2, "other explosion records kept")
	_check(not p.explosions.get("coastal_destroy_effect", {}).is_empty(), "other explosion tables kept")
	_check("MODMAP01" in p.list_levels() and "LEVEL01" in p.list_levels(), "levels listed from both layers")
	_check(p.level_dir("LEVEL01") == base_dir.path_join("levels/LEVEL01"), "base level resolves to the base")
	_check(p.level_dir("MODMAP01") == mod.path_join("levels/MODMAP01"), "mod level resolves to the mod")
	_check(p.level_dir("NOPE") == "", "unknown level resolves to nothing")

	# An explicit stack ignores base_pack and takes the order given.
	var s := Pack.new()
	_check(s.load_stack([base_dir, mod]), "explicit load_stack")
	_check(float(s.vehicle_types["0"]["hit_points"]) == 99.0, "explicit stack applies the mod")

	print("pack_layering_check: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)
