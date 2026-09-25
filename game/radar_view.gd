class_name RadarView
extends TextureRect
## The radar of the original (documents 68, 69): a 32 x 32 window of a one-pixel-per-tile map, centred on the player's tile, coloured by
## FUN_00412dc0's rules (land 0x87, water 0x91, per-coastal-id colours for the team buildings and structures, split by the tile's pool
## bits) through the game's palette (hud/radar.json, built by tools/build_pack.py), with the flag's blinking pole-and-pennant blip
## (descriptor 0x4404b0 / 0x4404c0, 15 ticks on, 15 off). NOT reproduced (untraced): the grid overlay (cel 1963), the corner-bracket
## cursor (cel 1964), the Jeep's direction arrow, the bitmap background outside the map, and the
## panel frame around it. The window size and position come from the vehicle's panel record (document 70); the on-screen scale is the port's choice.

var scale_px := 4.0

var mc: MatchController
var _img: Image
var _rd: Dictionary
var _win := Vector2i(32, 32)


func setup(controller: MatchController) -> void:
	mc = controller
	_rd = mc.pack.radar_data
	if _rd.is_empty():
		visible = false
		return
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	stretch_mode = TextureRect.STRETCH_SCALE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var w: Array = _rd.get("window", [32, 32])
	configure(Vector2i(int(w[0]), int(w[1])), scale_px)


## The window size in tiles (from the vehicle's panel record) and the screen pixels per tile.
func configure(window: Vector2i, scale: float) -> void:
	_win = window
	scale_px = scale
	_img = Image.create(_win.x, _win.y, false, Image.FORMAT_RGBA8)
	texture = ImageTexture.create_from_image(_img)
	custom_minimum_size = Vector2(_win) * scale_px
	size = custom_minimum_size


func _col(idx: int) -> Color:
	var c: Array = _rd["rgb"].get(str(idx), [0, 0, 0])
	return Color8(int(c[0]), int(c[1]), int(c[2]))


## FUN_00412dc0 for one tile.
func _tile_colour(x: int, y: int) -> Color:
	var lv := mc.level
	var id := lv.get_coastal_id(x, y)
	if id != 0:
		var pair: Array = _rd["coastal_colours"].get(str(id), [])
		if pair.is_empty():
			return _col(int(_rd["land"]))
		var variant := lv.get_variant(x, y)
		if variant <= 1 and not mc.pack.is_original_colour(lv.side_colour(variant)):
			return mc.pack.team_rgb(lv.side_colour(variant))   # a generated colour has no palette entry (PORTING_PLAN.md 2.7.7)
		return _col(int(pair[1] if variant != 0 else pair[0]))
	var art := lv.get_art_id(x, y) & 0x7F
	if art == 1 or art == 2 or (art >= 4 and art <= 0x33):
		return _col(int(_rd["water"]))
	if mc.mine_tiles.has(Vector2i(x, y)):   # tile word bit 31 (a mine lies here, document 75)
		return _col(int(_rd["flagged_tile"]))
	return _col(int(_rd["land"]))


func _process(_delta: float) -> void:
	if _img == null or mc.vehicle == null:
		return
	var tsz := float(mc.pack.tile_size_px)
	var cx := int(floor(mc.vehicle.position.x / tsz))
	var cy := int(floor(mc.vehicle.position.y / tsz))
	var ox := cx - _win.x / 2
	var oy := cy - _win.y / 2
	for py in _win.y:
		for px in _win.x:
			var tx := ox + px
			var ty := oy + py
			if tx < 0 or ty < 0 or tx >= mc.level.width or ty >= mc.level.height:
				_img.set_pixel(px, py, Color.BLACK)
			else:
				_img.set_pixel(px, py, _tile_colour(tx, ty))
	# the flag's blip: on for 15 ticks, off for 15 (the second descriptor has no points)
	var blip: Dictionary = _rd["flag_blip"]
	var period := int(blip["period_ticks"])
	if int(floor(Time.get_ticks_msec() / 1000.0 * Vehicle.TICK_HZ)) / period % 2 == 0:
		for f in mc.flags.values():
			var pos: Vector2 = f.carrier.position if f.carrier != null and is_instance_valid(f.carrier) else f.position
			var fx := int(floor(pos.x / tsz))
			var fy := int(floor(pos.y / tsz))
			var col := _col(int(blip["colours"][1 if f.owner_idx != 0 else 0]))
			for p in blip["points"]:
				var qx: int = fx + int(p[0]) - ox
				var qy: int = fy + int(p[1]) - oy
				if qx >= 0 and qy >= 0 and qx < _win.x and qy < _win.y:
					_img.set_pixel(qx, qy, col)
	(texture as ImageTexture).update(_img)


## The whole level as the radar bitmap (one pixel per tile): what the map window of the choice screen shows (document 78).
func full_image() -> Image:
	var lv := mc.level
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLACK)
	for y in mini(lv.height, 128):
		for x in mini(lv.width, 128):
			img.set_pixel(x, y, _tile_colour(x, y))
	return img
