class_name RadarView
extends TextureRect
## The radar of the original (documents 68, 69): a 32 x 32 window of a one-pixel-per-tile map, centred on the player's tile, coloured by
## FUN_00412dc0's rules (land 0x87, water 0x91, per-coastal-id colours for the team buildings and structures, split by the tile's pool
## bits) through the game's palette (hud/radar.json, built by tools/build_pack.py), with the flag's blinking pole-and-pennant blip
## (descriptor 0x4404b0 / 0x4404c0, 15 ticks on, 15 off), the ping (documents 68, 71, 103): a 16-frame growing ring, centred on the
## window (it always tracks the panel's own vehicle), shown while MatchController.radar_ping_frame() is >= 0 -- the tracked vehicle
## was hit within the last 74 ticks -- and the grid overlay (cel 1963, document 107): drawn unconditionally, on top of everything
## else including the ping, whenever the config's own cel field is nonzero (always, for an ordinary vehicle). Cel 1963 is really a
## background-recolour blend mask (document 9's PRE0=3 family) this pack can't reproduce; approximated as a plain additive white
## overlay, the same stand-in the hangar spotlight uses (document 103), at its own alpha (no rescale needed here, unlike there).
## NOT reproduced (untraced): the corner-bracket cursor (cel 1964: it animates via an 8-rectangle table keyed by a "child" object's
## own state, object+0x5c, that this pass never traced), the bitmap background outside the map, and the panel frame around it.
## The window size and position come from the vehicle's panel record (document 70); the on-screen scale is the port's choice.

var scale_px := 4.0

var mc: MatchController
var _img: Image
var _rd: Dictionary
var _win := Vector2i(32, 32)
var _ping: TextureRect
var _ping_tex_cache: Array[AtlasTexture] = []
var _grid: TextureRect


func setup(controller: MatchController) -> void:
	mc = controller
	_rd = mc.pack.radar_data
	if _rd.is_empty():
		visible = false
		return
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	stretch_mode = TextureRect.STRETCH_SCALE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	if _rd.has("ping"):   # built before configure() so its first call can size it
		_ping = TextureRect.new()
		_ping.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_ping.stretch_mode = TextureRect.STRETCH_SCALE
		_ping.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_ping.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_ping)
	if _rd.has("grid"):   # added AFTER _ping: FUN_004122d0 draws the grid last, over the ping too
		_grid = TextureRect.new()
		_grid.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_grid.stretch_mode = TextureRect.STRETCH_SCALE
		_grid.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_grid.material = mat
		var s := mc.pack.get_sprite(String(_rd["grid"]["sprite_id"]))
		if not s.is_empty():
			var at := AtlasTexture.new()
			at.atlas = mc.pack.get_texture(int(s.get("page", 0)))
			at.region = Rect2(float(s["x"]), float(s["y"]), float(s["w"]), float(s["h"]))
			_grid.texture = at
		add_child(_grid)
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
	if _ping != null:
		# FUN_004122d0 places the ring at (width - cel_width, height - cel_height) * 0x8000 from the panel corner: since the
		# ping cels are the same 32 x 32 as the traced window, that offset is always 0 -- the ring exactly fills the window.
		_ping.size = size
		_ping.position = Vector2.ZERO
	if _grid != null:   # cel 1963 is also 32 x 32, the same as the traced window: same reasoning, no offset
		_grid.size = size
		_grid.position = Vector2.ZERO


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
	if _ping != null:
		var frame := mc.radar_ping_frame()
		_ping.visible = frame >= 0
		if frame >= 0:
			_ping.texture = _ping_texture(frame)


func _ping_texture(frame: int) -> AtlasTexture:
	while _ping_tex_cache.size() <= frame:
		var id := String(_rd["ping"]["sprite_ids"][_ping_tex_cache.size()])
		var s := mc.pack.get_sprite(id)
		var at := AtlasTexture.new()
		if not s.is_empty():
			at.atlas = mc.pack.get_texture(int(s.get("page", 0)))
			at.region = Rect2(float(s["x"]), float(s["y"]), float(s["w"]), float(s["h"]))
		_ping_tex_cache.append(at)
	return _ping_tex_cache[frame]


## The whole level as the radar bitmap (one pixel per tile): what the map window of the choice screen shows (document 78).
func full_image() -> Image:
	var lv := mc.level
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLACK)
	for y in mini(lv.height, 128):
		for x in mini(lv.width, 128):
			img.set_pixel(x, y, _tile_colour(x, y))
	return img
