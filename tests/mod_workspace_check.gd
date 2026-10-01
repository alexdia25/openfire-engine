# The mod tool's workspace (EDITOR_PLAN.md 3, E0) over the engine's synthetic fixture: a mod created in user:// over the
# game's base pack; importing a replacement and a new sprite, a pivot change, a colour and a team mask, each undone and
# redone against both the mod's own tables and the live Pack; saved, reopened from disk, and reverted back to the base
# art. Moved from openfire's tools/tests (issue alexdia25/openfire#65). Run (see tests/README.md):
#   godot --headless --path .harness --script res://addons/openfire_engine/tests/mod_workspace_check.gd
extends SceneTree

const Fixture := preload("fixtures/synthetic_pack.gd")

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _solid(w: int, h: int, c: Color) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return img


func _pixel(p: Pack, id: String) -> Color:
	return p.get_sprite_image(id).get_pixel(0, 0)


func _init() -> void:
	ProjectSettings.set_setting(EngineConfig.BASE_PACK, Fixture.build("user://packs"))
	var dir := ProjectSettings.globalize_path("user://mod_workspace_check/testmod")
	if DirAccess.dir_exists_absolute(dir):
		OS.move_to_trash(dir)
	var ws := ModWorkspace.create(dir, "Workspace test")
	_check(ws != null and ws.pack.layers.size() == 2, "new mod created over the base")
	_check(not ws.is_dirty(), "a fresh mod is clean")

	var hull := "fx.hull"
	var base_hull := ws.pack.get_sprite_image(hull)
	var base_pivot := Vector2(float(ws.pack.get_sprite(hull)["pivot_x"]), float(ws.pack.get_sprite(hull)["pivot_y"]))

	# replacement at the same size keeps the pivot; the live pack shows it at once
	ws.import_frame(hull, _solid(base_hull.get_width(), base_hull.get_height(), Color.MAGENTA))
	_check(_pixel(ws.pack, hull) == Color.MAGENTA, "replacement is live")
	_check(ws.sprite_origin(hull) == "mod" and ws.mod_sprites[hull]["file"] == "fx/hull.png", "mod entry filed like build_pack")
	_check(Vector2(float(ws.pack.get_sprite(hull)["pivot_x"]), float(ws.pack.get_sprite(hull)["pivot_y"])) == base_pivot, "same-size import keeps the pivot")
	_check(ws.is_dirty(), "edit makes it dirty")
	ws.undo.undo()
	_check(_pixel(ws.pack, hull) == base_hull.get_pixel(0, 0) and ws.sprite_origin(hull) == "base", "undo restores the base frame")
	ws.undo.redo()
	_check(_pixel(ws.pack, hull) == Color.MAGENTA and ws.sprite_origin(hull) == "mod", "redo re-applies")

	# a brand-new sprite, its pivot, a mask for it and a new colour
	ws.import_frame("testmod.hovertank.hull", _solid(8, 6, Color(0.5, 0.5, 0.5)))
	ws.import_frame("testmod.hovertank.hull_mask", _solid(8, 6, Color.WHITE))
	ws.set_pivot("testmod.hovertank.hull", Vector2(2, 3))
	_check(float(ws.pack.get_sprite("testmod.hovertank.hull")["pivot_x"]) == 2.0, "pivot set live")
	ws.undo.undo()
	_check(float(ws.pack.get_sprite("testmod.hovertank.hull")["pivot_x"]) == 4.0, "pivot undo back to centred")
	ws.undo.redo()
	ws.set_colour("purple", [0.8, 0.7, 0.5])
	_check(ws.pack.team_colours.has("purple") and ws.mod_colours["purple"]["source"] == "mod", "colour added")
	ws.set_mask("testmod.hovertank.hull", "testmod.hovertank.hull_mask")
	var purple := ws.pack.get_sprite_image(ws.pack.team_sprite("testmod.hovertank.hull", "purple")).get_pixel(0, 0)
	_check(purple.b > purple.g and purple.r > purple.g, "masked new sprite recolours in the new colour")
	ws.set_colour("purple", [0.33, 0.7, 0.5])
	var greenish := ws.pack.get_sprite_image(ws.pack.team_sprite("testmod.hovertank.hull", "purple")).get_pixel(0, 0)
	_check(greenish.g > greenish.r and greenish.g > greenish.b, "changing a colour regenerates its sprites")
	ws.undo.undo()
	var again := ws.pack.get_sprite_image(ws.pack.team_sprite("testmod.hovertank.hull", "purple")).get_pixel(0, 0)
	_check(again.is_equal_approx(purple), "undoing a colour change regenerates the old colour")

	_check(ws.save(), "save")
	_check(not ws.is_dirty(), "clean after save")
	_check(FileAccess.file_exists(dir.path_join("sprites/fx/hull.png")) and FileAccess.file_exists(dir.path_join("sprites/testmod/hovertank/hull.png")), "frames written")
	_check(FileAccess.file_exists(dir.path_join("teams/colours.json")) and FileAccess.file_exists(dir.path_join("sprites/team_sets.json")), "tables written")

	# reopen from disk: a new workspace and a fresh Pack see exactly what was saved
	var ws2 := ModWorkspace.new()
	_check(ws2.open(dir), "reopen")
	_check(_pixel(ws2.pack, hull) == Color.MAGENTA, "replacement persisted")
	_check(float(ws2.pack.get_sprite("testmod.hovertank.hull")["pivot_x"]) == 2.0, "pivot persisted")
	_check(ws2.pack.team_masks.has("testmod.hovertank.hull") and ws2.pack.team_colours.has("purple"), "mask and colour persisted")
	_check(ws2.pack.get_sprite_image(hull).get_size() == base_hull.get_size(), "sizes intact")

	# revert brings the base art back; removing the colour brings nothing back (the base has none)
	ws2.revert_sprite(hull)
	_check(_pixel(ws2.pack, hull) == base_hull.get_pixel(0, 0) and not ws2.mod_sprites.has(hull), "revert shows the base frame")
	ws2.remove_colour("purple")
	_check(not ws2.pack.team_colours.has("purple"), "removed colour gone at runtime")
	ws2.remove_colour("red")   # not the mod's: removing it from the mod leaves the base's red in place
	_check(ws2.pack.team_colours.has("red"), "a base colour survives a mod-level remove")
	_check(ws2.save(), "save again")
	var ws3 := ModWorkspace.new()
	ws3.open(dir)
	_check(_pixel(ws3.pack, hull) == base_hull.get_pixel(0, 0) and not ws3.pack.team_colours.has("purple"), "reverts persisted")
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("sprites/sprites.json")))
	_check(not doc["sprites"].has(hull) and doc["sprites"].has("testmod.hovertank.hull"), "only the mod's own sprites are written")

	# a pivot-only override of a base sprite needs no copy of its pixels (metadata-only entry)
	ws3.set_pivot("fx.wheel", Vector2(1, 1))
	ws3.save()
	var entry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("sprites/sprites.json")))["sprites"]["fx.wheel"]
	_check(not entry.has("file"), "pivot-only override carries no frame")
	var ws4 := ModWorkspace.new()
	ws4.open(dir)
	_check(float(ws4.pack.get_sprite("fx.wheel")["pivot_x"]) == 1.0 and ws4.pack.get_sprite_image("fx.wheel") != null,
			"metadata-only override loads over the base frame")

	for w in [ws, ws2, ws3, ws4]:
		w.close()
	print("mod_workspace_check: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)
