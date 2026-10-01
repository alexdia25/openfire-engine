extends RefCounted
## A tiny pack generated fresh for the engine's own tests: original, throwaway content (flat-colour frames, a few
## vehicles, two small levels), so the engine is tested with no game's content present at all -- the same position a
## new game built on it starts from. `build(root)` writes `<root>/fixture_base` and returns that directory.
##
## Its ids are deliberately generic ("fx.*", "LEVEL01") so a test never passes because it happens to know some
## particular game's names.

const ID := "fixture_base"
const SPRITE_COLOURS := {"fx.hull": Color.RED, "fx.turret": Color.GREEN, "fx.wheel": Color.BLUE, "fx.tile": Color.SADDLE_BROWN}
const VEHICLES := ["fx.tank", "fx.buggy", "fx.copter"]
const LEVELS := {"LEVEL01": "First Light", "LEVEL02": "Second Wind"}
const LEVEL_SIZE := 4


## A complete, minimal vehicle definition (the shape `Pack._flat_view()` and the editor read).
static func vehicle_def(id: String, name: String, index: int) -> Dictionary:
	return {
		"id": id, "name": name, "original_index": index,
		"stats": {"hit_points": 10.0 + index, "armor": 0.0, "fuel": 100.0, "sink_depth": 10.0, "dock_tolerance": 4.0, "death_wait_ticks": 60.0},
		"shape": {"layer": 2, "mask": 39, "z": [0.0, 8.0], "poly": [[-4.0, -6.0], [4.0, -6.0], [4.0, 6.0], [-4.0, 6.0]]},
		"drive": {"model": "ground", "max_forward_per_tick": 1.0, "max_reverse_per_tick": -0.5, "accel_per_tick2": 0.05,
				"friction_per_tick2": 0.02, "turn_steps_per_tick": 0.3},
		"aim": {"model": "none"}, "water": {"model": "none"}, "weapons": {"ammo": [0, 0], "cooldown_ticks": [20, 0], "slots": []},
		"render": {"parts": []}}


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
		DirAccess.make_dir_recursive_absolute(dir.path_join("sprites/fx"))
		img.save_png(dir.path_join("sprites").path_join(rel))
		entries[id] = {"file": rel, "pivot_x": 4, "pivot_y": 4}
	PackWriter.write_json(dir.path_join("sprites/sprites.json"), {"sprites": entries})

	var roster := []
	for i in VEHICLES.size():
		var id: String = VEHICLES[i]
		PackWriter.write_json(dir.path_join("vehicles").path_join(id).path_join("vehicle.json"), vehicle_def(id, id.trim_prefix("fx.").capitalize(), i))
		roster.append({"id": id, "stock_key": "", "default_stock": 3})
	PackWriter.write_json(dir.path_join("vehicles/roster.json"), {"vehicles": roster})

	PackWriter.write_json(dir.path_join("audio/audio.json"), {
		"Ding": {"file": "ding.wav", "category": "sfx", "priority": 0},
		"Boom": {"file": "boom.wav", "category": "sfx", "priority": 1}})
	PackWriter.write_json(dir.path_join("effects/explosions.json"), {
		"records": {"rec.small": {"size": 1}, "rec.large": {"size": 2}},
		"coastal_destroy_effect": {"1": "rec.large"}})

	for level_id in LEVELS:
		var ldir := dir.path_join("levels").path_join(level_id)
		PackWriter.write_json(ldir.path_join("level.json"), {
			"name": LEVELS[level_id], "width": LEVEL_SIZE, "height": LEVEL_SIZE, "side_colours": ["tan", "green"],
			"spawn_points": [], "decorations": []})
		var art := FileAccess.open(ldir.path_join("art.bin"), FileAccess.WRITE)
		var grid := PackedByteArray()
		grid.resize(LEVEL_SIZE * LEVEL_SIZE)
		art.store_buffer(grid)
	return dir
