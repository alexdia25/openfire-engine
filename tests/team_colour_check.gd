# Team recolouring (PORTING_PLAN.md 2.7.7) on the engine's synthetic fixture: a pack's team sets resolve to the drawn
# art for the original colours and to generated sprites for any other; pixels the two teams share are never touched;
# art outside any set is unchanged; and masked art (a mod's new vehicle: one drawing plus a team-paint mask) is
# recoloured inside its mask only, with drawn_as for art drawn in one of the colours. How closely the rule rebuilds
# Return Fire's real green from its tan stays openfire's check. Moved from openfire's tools/tests (issue
# alexdia25/openfire#65). Run (see tests/README.md):
#   godot --headless --path .harness --script res://addons/openfire_engine/tests/team_colour_check.gd
extends SceneTree

const Fixture := preload("fixtures/synthetic_pack.gd")

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _init() -> void:
	var p := Pack.new()
	_check(p.load_from(Fixture.build("user://packs")), "the fixture loads")
	var tan: String = Fixture.TEAM_PAIR[0]
	var green: String = Fixture.TEAM_PAIR[1]
	_check(p.team_sets.get(tan) == green, "the team set loaded")
	_check(p.team_colours.has("tan") and p.team_colours.has("green") and p.team_colours.has("red"), "colours loaded")
	_check(p.team_sprite(tan, "tan") == tan and p.team_sprite(tan, "green") == green, "the original colours return the drawn art")
	_check(p.team_sprite(green, "tan") == tan, "the green member resolves to the same set")
	_check(p.team_sprite("fx.tile", "red") == "fx.tile", "art outside any set is unchanged")
	_check(p.team_sprite(tan, "no_such_colour") == tan, "an unknown colour is unchanged")

	var red_id := p.team_sprite(tan, "red")
	_check(red_id == tan + "@red" and not p.get_sprite(red_id).is_empty(), "the red body is generated")
	var a := p.get_sprite_image(tan)
	var red := p.get_sprite_image(red_id)
	var shared_same := true
	var team_red := true
	for y in 8:
		for x in 8:
			if x < 4:
				shared_same = shared_same and red.get_pixel(x, y) == a.get_pixel(x, y)
			else:
				var c := red.get_pixel(x, y)
				team_red = team_red and c.r > c.g and c.r > c.b
	_check(shared_same, "pixels shared by tan and green are untouched")
	_check(team_red, "the team pixels are red")

	p.prepare_team_colours(["red", "blue"])
	_check(p.sprites.has(tan + "@red") and p.sprites.has(tan + "@blue"), "prepare makes every set in every colour")

	_check_masked_art()
	print("team_colour_check: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)


## Masked art: the hull is drawn with grey team paint on its left half and dark metal on its right, the mask covering
## the left half; the fin is drawn in blue and declared so.
func _check_masked_art() -> void:
	var mod := ProjectSettings.globalize_path("user://team_colour_check/mask_mod")
	if DirAccess.dir_exists_absolute(mod):
		OS.move_to_trash(mod)
	DirAccess.make_dir_recursive_absolute(mod.path_join("sprites/mod"))
	PackWriter.write_json(mod.path_join("pack.json"), {"id": "mask_mod", "name": "masked art test", "base_pack": Fixture.ID})
	var hull := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	var hull_mask := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 8:
			if x < 4:
				hull.set_pixel(x, y, Color.from_hsv(0.0, 0.0, 0.3 + 0.08 * y))   # grey shades
				hull_mask.set_pixel(x, y, Color.WHITE)
			else:
				hull.set_pixel(x, y, Color(0.1, 0.1, 0.12))                       # metal, not team paint
	hull.save_png(mod.path_join("sprites/mod/hull.png"))
	hull_mask.save_png(mod.path_join("sprites/mod/hull_mask.png"))
	var fin := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	fin.fill(Color.from_hsv(0.61, 0.7, 0.55))
	fin.save_png(mod.path_join("sprites/mod/fin.png"))
	var fin_mask := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	fin_mask.fill(Color.WHITE)
	fin_mask.save_png(mod.path_join("sprites/mod/fin_mask.png"))
	var frame := func(f: String, w: int, h: int) -> Dictionary: return {"file": f, "w": w, "h": h, "pivot_x": w / 2.0, "pivot_y": h / 2.0}
	PackWriter.write_json(mod.path_join("sprites/sprites.json"), {"atlas_pages": [], "sprites": {
		"mod.hovertank.hull": frame.call("mod/hull.png", 8, 8), "mod.hovertank.hull.mask": frame.call("mod/hull_mask.png", 8, 8),
		"mod.hovertank.fin": frame.call("mod/fin.png", 4, 4), "mod.hovertank.fin.mask": frame.call("mod/fin_mask.png", 4, 4)}})
	PackWriter.write_json(mod.path_join("sprites/team_sets.json"), {"masks": {
		"mod.hovertank.hull": "mod.hovertank.hull.mask",
		"mod.hovertank.fin": {"mask": "mod.hovertank.fin.mask", "drawn_as": "blue"}}})

	var p := Pack.new()
	_check(p.load_from(mod), "masked mod loads")
	var red := p.team_sprite("mod.hovertank.hull", "red")
	_check(red == "mod.hovertank.hull@red" and not p.get_sprite(red).is_empty(), "masked hull generated in red")
	var src := p.get_sprite_image("mod.hovertank.hull")
	var out := p.get_sprite_image(red)
	var paint_red := true
	var metal_same := true
	for y in 8:
		for x in 8:
			var c := out.get_pixel(x, y)
			if x < 4:
				paint_red = paint_red and c.r > c.g * 1.5 and c.r > c.b * 1.5 and c.s > 0.5
			else:
				metal_same = metal_same and c == src.get_pixel(x, y)
	_check(paint_red, "grey-drawn team paint takes the colour's saturation (not left grey)")
	_check(metal_same, "unmasked pixels are untouched")
	_check(out.get_pixel(0, 7).v > out.get_pixel(0, 0).v, "the drawing's shading is kept")
	_check(p.team_sprite("mod.hovertank.hull", "tan").ends_with("@tan") and p.team_sprite("mod.hovertank.hull", "green").ends_with("@green"),
			"masked art is generated in the original colours too")
	_check(p.team_variant(["mod.hovertank.hull", "mod.hovertank.hull", "x.flash"], "green") == "mod.hovertank.hull@green",
			"team_variant goes through the mask, not the list index")
	_check(p.team_sprite("mod.hovertank.fin", "blue") == "mod.hovertank.fin", "drawn_as returns the drawing itself")
	var fin_red := p.get_sprite_image(p.team_sprite("mod.hovertank.fin", "red")).get_pixel(1, 1)
	_check(fin_red.r > fin_red.b, "a colour-drawn part is recoloured by hue (blue -> red)")
	p.prepare_team_colours(["tan", "green", "red"])
	_check(p.sprites.has("mod.hovertank.hull@red") and p.sprites.has("mod.hovertank.fin@tan"), "prepare includes masked art")
	_check(p.team_sprite(Fixture.TEAM_PAIR[0], "green") == Fixture.TEAM_PAIR[1], "the base's own pair is unaffected in the same stack")
