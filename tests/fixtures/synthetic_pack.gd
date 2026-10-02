extends RefCounted
## A small pack generated fresh for the engine's own tests: original, throwaway content, so the engine is tested with no
## game's content present at all -- the same position a new game built on it starts from. `build(root)` writes
## `<root>/fixture_base` and returns that directory. What it holds:
##
##   sprites      flat-colour frames (SPRITE_COLOURS), and one team pair (TEAM_PAIR): an 8 x 8 body whose left half is
##                shared grey metal and whose right half is tan in one frame and green in the other
##   teams        tan and green (the pair's two colours), plus red and blue presets to recolour to
##   vehicles     three (VEHICLES), each drawn as the team-coloured body with a turret that turns with turret_deg
##   levels       two 16 x 16 playable levels with a spawn point per side; LEVEL02 also has a field of decorations
##                (DECORATION_ID on every other tile) spanning all four of DecorationField3D's 8 x 8 chunks
##   home pad     its mechanism art (terrain/home_pad.json) and the projectile art, all fixture frames
##   terrain, audio, effects   just enough tables for the rest of the engine to load
##
## Its ids are deliberately generic ("fx.*", "LEVEL01") so a test never passes because it happens to know some
## particular game's names.

const ID := "fixture_base"
const SPRITE_COLOURS := {"fx.hull": Color.RED, "fx.turret": Color.GREEN, "fx.wheel": Color.BLUE, "fx.tile": Color.SADDLE_BROWN}
const TEAM_PAIR := ["fx.body.tan", "fx.body.green"]
const SHARED_GREY := Color(0.4, 0.4, 0.42)
const TAN := Color(0.8, 0.65, 0.45)
const GREEN := Color(0.35, 0.5, 0.25)
const VEHICLES := ["fx.tank", "fx.buggy", "fx.copter"]
const LEVELS := {"LEVEL01": "First Light", "LEVEL02": "Second Wind"}
const LEVEL_SIZE := 16
const SPAWNS := [{"team": 0, "x": 3, "y": 3}, {"team": 1, "x": 12, "y": 12}]   ## tile coordinates, far enough apart to move
const DECORATION_ID := 7


## A complete, minimal vehicle definition (the shape `Pack._flat_view()`, the renderer and the editor read): the team
## body with a turret group on top.
static func vehicle_def(id: String, name: String, index: int) -> Dictionary:
	return {
		"id": id, "name": name, "original_index": index,
		"stats": {"hit_points": 10.0 + index, "armor": 0.0, "fuel": 100.0, "sink_depth": 10.0, "dock_tolerance": 4.0, "death_wait_ticks": 60.0},
		"shape": {"layer": 2, "mask": 39, "z": [0.0, 8.0], "poly": [[-4.0, -6.0], [4.0, -6.0], [4.0, 6.0], [-4.0, 6.0]]},
		"drive": {"model": "ground", "max_forward_per_tick": 1.0, "max_reverse_per_tick": -0.5, "accel_per_tick2": 0.05,
				"friction_per_tick2": 0.02, "turn_steps_per_tick": 0.3},
		"aim": {"model": "none"}, "water": {"model": "none"}, "weapons": {"ammo": [0, 0], "cooldown_ticks": [20, 0], "slots": []},
		"wreck": {"quads": [{"sprites": ["fx.hull"], "height": 0.5, "half": [6, 6], "center": [0, 0]}], "friction": 0.1, "explosion": "fx.boom"},
		"render": {
			"parts": [
				{"sprite_ids": [TEAM_PAIR[0], TEAM_PAIR[1], "fx.hull"], "flags": 8,
					"corners": [[-4.0, -6.0, 1.0], [4.0, -6.0, 1.0], [4.0, 6.0, 1.0], [-4.0, 6.0, 1.0]]},
				{"group": "turret", "sprite_ids": ["fx.turret"], "flags": 0,
					"corners": [[-2.0, -2.0, 4.0], [2.0, -2.0, 4.0], [2.0, 2.0, 4.0], [-2.0, 2.0, 4.0]]}],
			"groups": {"turret": {"rotate": [{"axis": "y", "channel": "turret_deg", "scale": -1.0}]}}}}


static func _save(img: Image, dir: String, rel: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir.path_join("sprites").path_join(rel).get_base_dir())
	img.save_png(dir.path_join("sprites").path_join(rel))


static func build(root: String) -> String:
	var dir := root.path_join(ID)
	if DirAccess.dir_exists_absolute(dir):
		OS.move_to_trash(ProjectSettings.globalize_path(dir))
	PackWriter.write_json(dir.path_join("pack.json"), {
		"id": ID, "name": "Engine test fixture", "title": "Fixture", "version": "0.1.0", "engine_api_version": "0.1.0",
		"author": "openfire-engine tests", "license": "CC0", "base_pack": null, "overrides": [], "pixels_per_world_unit": 32})

	var entries := {}
	for id in SPRITE_COLOURS:
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(SPRITE_COLOURS[id])
		var rel := "fx/%s.png" % String(id).trim_prefix("fx.")
		_save(img, dir, rel)
		entries[id] = {"file": rel, "pivot_x": 4, "pivot_y": 4}
	for k in TEAM_PAIR.size():
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		for y in 8:
			for x in 8:
				img.set_pixel(x, y, SHARED_GREY if x < 4 else [TAN, GREEN][k])
		var rel := "fx/body.%s.png" % ["tan", "green"][k]
		_save(img, dir, rel)
		entries[TEAM_PAIR[k]] = {"file": rel, "pivot_x": 4, "pivot_y": 4}
	PackWriter.write_json(dir.path_join("sprites/sprites.json"), {"sprites": entries})
	PackWriter.write_json(dir.path_join("sprites/team_sets.json"), {"pairs": {TEAM_PAIR[0]: TEAM_PAIR[1]}, "masks": {}})
	PackWriter.write_json(dir.path_join("teams/colours.json"), {"reference": "tan", "colours": {
		"tan": {"source": "original", "variant": 0, "hsv": [TAN.h, TAN.s, TAN.v]},
		"green": {"source": "original", "variant": 1, "hsv": [GREEN.h, GREEN.s, GREEN.v]},
		"red": {"source": "port_preset", "hsv": [0.0, 0.75, 0.55]},
		"blue": {"source": "port_preset", "hsv": [0.61, 0.7, 0.55]}}})

	var roster := []
	for i in VEHICLES.size():
		var id: String = VEHICLES[i]
		PackWriter.write_json(dir.path_join("vehicles").path_join(id).path_join("vehicle.json"), vehicle_def(id, id.trim_prefix("fx.").capitalize(), i))
		roster.append({"id": id, "stock_key": "", "default_stock": 3})
	PackWriter.write_json(dir.path_join("vehicles/roster.json"), {"vehicles": roster})

	# every tile is art id 0, plain ground drawn with fx.tile
	PackWriter.write_json(dir.path_join("terrain/tileset.json"), {"tile_size_px": 32,
		"tiles": {"0": {"sprite_id": "fx.tile", "terrain_class": "ground"}}})
	PackWriter.write_json(dir.path_join("terrain/decorations.json"), {"decoration_types": {str(DECORATION_ID): [
		{"sprite_id": "fx.turret", "flags": 0, "corners": [[-8.0, -8.0, 6.0], [8.0, -8.0, 6.0], [8.0, 8.0, 0.0], [-8.0, 8.0, 0.0]],
			"offset": [0.0, 0.0], "zoff": 0.0, "jitter": false}]}})

	# the home pad's mechanism art (Pack.home_pad), drawn with fixture frames; the lift plate is the team pair
	PackWriter.write_json(dir.path_join("terrain/home_pad.json"), {
		"pit_walls": {"north": "fx.wheel", "west": "fx.wheel", "east": "fx.hull", "south": "fx.hull"},
		"hazard_strip": "fx.turret", "lift_plate": TEAM_PAIR, "leaves": {"left": TEAM_PAIR, "right": TEAM_PAIR},
		"dock_ready_glow": "fx.turret"})
	PackWriter.write_json(dir.path_join("vehicles/projectile_types.json"), {"types": [], "descriptors": {},
		"art": {"shell": "fx.turret", "shadow": "fx.tile"}})

	PackWriter.write_json(dir.path_join("audio/audio.json"), {
		"Ding": {"file": "ding.wav", "category": "sfx", "priority": 0},
		"Boom": {"file": "boom.wav", "category": "sfx", "priority": 1}})
	PackWriter.write_json(dir.path_join("effects/explosions.json"), {
		"records": {"rec.small": {"size": 1}, "rec.large": {"size": 2}},
		"coastal_destroy_effect": {"1": "rec.large"}})

	for level_id in LEVELS:
		var ldir := dir.path_join("levels").path_join(level_id)
		var decorations := []
		if level_id == "LEVEL02":
			for y in range(0, LEVEL_SIZE, 2):
				for x in range(1, LEVEL_SIZE, 2):
					decorations.append({"x": x, "y": y, "coastal_id": DECORATION_ID, "variant": 0})
		# PackWriter sorts keys, so "decorations" lands before "name" -- as in any level the mod tool saves
		PackWriter.write_json(ldir.path_join("level.json"), {
			"name": LEVELS[level_id], "width": LEVEL_SIZE, "height": LEVEL_SIZE, "side_colours": ["tan", "green"],
			"spawn_points": SPAWNS, "decorations": decorations})
		var art := FileAccess.open(ldir.path_join("art.bin"), FileAccess.WRITE)
		var grid := PackedByteArray()
		grid.resize(LEVEL_SIZE * LEVEL_SIZE)
		art.store_buffer(grid)
	return dir
