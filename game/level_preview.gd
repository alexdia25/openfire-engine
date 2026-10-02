class_name LevelPreview
extends RefCounted
## The level as the radar bitmap, one pixel per tile (documents 68, 69, 78): FUN_00412dc0's colour rules through the game's palette (pack `hud/radar.json`). The radar's
## live window (RadarView), the hangar's map window and the level selector's preview (issue #83) all draw from here.


## FUN_00412dc0 for one tile. `mines`: tiles with a mine on them (tile word bit 31, document 75), or {}.
static func tile_colour(pack: Pack, lv: LevelData, x: int, y: int, mines: Dictionary = {}) -> Color:
	var rd := pack.radar_data
	var id := lv.get_coastal_id(x, y)
	if id != 0:
		var pair: Array = rd["coastal_colours"].get(str(id), [])
		if pair.is_empty():
			return _col(rd, int(rd["land"]))
		var variant := lv.get_variant(x, y)
		if variant <= 1 and not pack.is_original_colour(lv.side_colour(variant)):
			return pack.team_rgb(lv.side_colour(variant))   # a generated colour has no palette entry (PORTING_PLAN.md 2.7.7)
		return _col(rd, int(pair[1] if variant != 0 else pair[0]))
	var art := lv.get_art_id(x, y) & 0x7F
	if art == 1 or art == 2 or (art >= 4 and art <= 0x33):
		return _col(rd, int(rd["water"]))
	if mines.has(Vector2i(x, y)):
		return _col(rd, int(rd["flagged_tile"]))
	return _col(rd, int(rd["land"]))


static func _col(rd: Dictionary, idx: int) -> Color:
	var c: Array = rd["rgb"].get(str(idx), [0, 0, 0])
	return Color8(int(c[0]), int(c[1]), int(c[2]))


## The whole level (up to 128 x 128 tiles), black outside it; null when the pack has no radar data.
static func image(pack: Pack, lv: LevelData, mines: Dictionary = {}) -> Image:
	if pack.radar_data.is_empty():
		return null
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLACK)
	for y in mini(lv.height, 128):
		for x in mini(lv.width, 128):
			img.set_pixel(x, y, tile_colour(pack, lv, x, y, mines))
	return img
