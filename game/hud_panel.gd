class_name HudPanel
extends Control
## The player's panel as the original lays it out (documents 66, 68-72), for the current vehicle type: the base picture (cel 1943 + vehicle index,
## 144 x 56), the fuel bar (kind 5) and the ammunition bars (kind 4; the Jeep's 16 missile pips, kind 7) at the rectangles of the vehicle's record, the
## radar window (kind 6) or the Jeep's compass (kind 8). A bar's fill eases 0.6 px a tick toward the value; its colour steps down as it empties (fuel:
## flashing when nearly empty). NOT drawn: the compass's per-value palette, the radar's grid and brackets and ping, the panel's slide-in, and the
## vehicle-stock counts of template slot 2 (`FUN_004116a0`). The bar colours are the nearest palette colours to the 15-bit words at 0x446760 / 0x446778 (document 74).
## The scale (3 px per original pixel) and the screen position are the port's choice.

var _s := 3.0   ## window pixels per original pixel (HudLayout.panel_scale)
var _frame: TextureRect   ## the blank frame cel 1940 under the base (classic layout only)
var _layout_key := ""

var mc: MatchController
var _base: TextureRect
var _radar: RadarView
var _compass: TextureRect
var _compass_on := false
var _bars: Array = []      ## {kind, rect [l, t, r, b], slot (-1 = fuel), bg, fill, drawn}
var _pips: Array = []      ## 16 TextureRects (the Jeep's missiles)
var _pip_tex: AtlasTexture
var _type := -1
var _weapon_select_bomb: TextureRect   ## Heli only, kind 9 (document 83): lit/dim by Vehicle.heli_weapon_slot()
var _weapon_select_gun: TextureRect
var _lamps: Texture2D   ## the compass lamp in its 17 brightness steps (tools/extract_compass_lamps.py, document 103); null when the pack has none


func setup(controller: MatchController) -> void:
	mc = controller
	_base = TextureRect.new()
	_base.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_base)
	_compass = TextureRect.new()
	_compass.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_compass.stretch_mode = TextureRect.STRETCH_SCALE
	_compass.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(_compass)
	_lamps = HudLayout.load_pack_image(mc.pack, "compass_lamps.png")
	_radar = RadarView.new()
	add_child(_radar)
	_radar.setup(controller)
	size = Vector2(144, 56) * _s
	_frame = TextureRect.new()
	_frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_frame.stretch_mode = TextureRect.STRETCH_SCALE
	_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame.visible = false
	add_child(_frame)
	move_child(_frame, 0)


## A bar colour (document 74): the game turns the 15-bit word into the nearest colour of its palette; build_pack.py has done that (`*_rgb`).
static func _rgb(c: Array) -> Color:
	return Color8(int(c[0]), int(c[1]), int(c[2]))


func _atlas(sprite_id: String) -> AtlasTexture:
	var s := mc.pack.get_sprite(sprite_id)
	var at := AtlasTexture.new()
	at.atlas = mc.pack.get_texture(int(s.get("page", 0)))
	at.region = Rect2(float(s["x"]), float(s["y"]), float(s["w"]), float(s["h"]))
	return at


func _new_icon(pos: Array) -> TextureRect:
	var r := TextureRect.new()
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.position = Vector2(float(pos[0]), float(pos[1])) * _s
	add_child(r)
	return r


func _add_bar(kind: int, slot: int, rect: Array) -> void:
	var bg := ColorRect.new()
	bg.color = _rgb(mc.pack.hud_panels["fuel_rgb"]["empty"])
	bg.position = Vector2(float(rect[0]), float(rect[1])) * _s
	bg.size = Vector2(float(rect[2] - rect[0] + 1), float(rect[3] - rect[1] + 1)) * _s
	add_child(bg)
	var fill := ColorRect.new()
	add_child(fill)
	_bars.append({"kind": kind, "slot": slot, "rect": rect, "bg": bg, "fill": fill, "drawn": -1.0})


func _layout(t: int) -> void:
	_type = t
	for b in _bars:
		b["bg"].queue_free()
		b["fill"].queue_free()
	_bars.clear()
	for p in _pips:
		p.queue_free()
	_pips.clear()
	if _weapon_select_bomb != null:
		_weapon_select_bomb.queue_free()
		_weapon_select_gun.queue_free()
		_weapon_select_bomb = null
		_weapon_select_gun = null
	var hp: Dictionary = mc.pack.hud_panels
	var pn: Dictionary = hp.get("panels", {}).get(str(t), {})
	if pn.is_empty():
		visible = false
		return
	visible = true
	_frame.visible = false
	if HudLayout.is_classic() and mc.pack.get_sprite("ui.hud.panel_blank") != {}:   # the frame around the base: template slot 2, cel 1940 at (-3, -2)
		var fa := _atlas("ui.hud.panel_blank")
		_frame.texture = fa
		_frame.position = HudLayout.FRAME_OFFSET * _s
		_frame.size = fa.region.size * _s
		_frame.visible = true
	var at := _atlas(String(pn["sprite_id"]))
	_base.texture = at
	_base.size = at.region.size * _s
	_base.stretch_mode = TextureRect.STRETCH_SCALE
	_base.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_add_bar(5, -1, pn["fuel"]["rect"])
	for w in pn.get("weapons", []):
		if int(w["kind"]) == 4:
			_add_bar(4, int(w["slot"]), w["rect"])
		elif int(w["kind"]) == 7:
			_pip_tex = _atlas(String(hp["pips"]["sprite_id"]))
			for i in 16:
				var r := TextureRect.new()
				r.texture = _pip_tex
				r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				r.stretch_mode = TextureRect.STRETCH_SCALE
				r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				r.size = _pip_tex.region.size * _s
				r.position = Vector2(float(hp["pips"]["x"][i]), float(hp["pips"]["y"][i])) * _s
				add_child(r)
				_pips.append(r)
	if t == 3:   # Heli only: kind 9's weapon-select icons (document 83)
		var ws: Dictionary = hp["weapon_select"]
		_weapon_select_bomb = _new_icon(ws["bomb_pos"])
		_weapon_select_gun = _new_icon(ws["gun_pos"])
	var s9: Dictionary = pn["slot9"]
	_compass_on = false
	_compass.visible = false
	if int(s9["kind"]) == 6:
		_radar.visible = true
		_radar.configure(Vector2i(int(s9["size"][0]), int(s9["size"][1])), _s)
		_radar.position = Vector2(float(s9["pos"][0]), float(s9["pos"][1])) * _s
		_radar.set_grid(s9.get("grid_sprite_id"), bool(s9.get("grid_is_negative", false)))
	else:
		_radar.visible = false
		_compass_on = int(s9["kind"]) == 8
		_compass.position = Vector2(float(s9["pos"][0]), float(s9["pos"][1])) * _s
		_compass.size = Vector2(float(s9["size"][0]), float(s9["size"][1])) * _s


## Which colour table a weapon bar (kind 4, FUN_00411da0) draws with (document 103). The bar does `CMP [slot + 0x14], 0` and takes the ammunition table
## (0x446778, the dark olive) when the flag is set, else the fuel table (0x446760, amber). The element factory (FUN_00412cd0) zeroes the flag, and only the
## Heli sets it: at creation (0x40baee: panel + 0xd0 = slot 7's flag = 1) and in its weapon switch (FUN_0040e7a0, 0x40e7d9..0x40e800: slot 6's flag = the
## selected-weapon bit 0x10000000, slot 7's = its opposite). So every weapon bar is amber, except the Heli's bar for the weapon that is not selected.
static func uses_ammo_colours(vehicle_type: int, slot: int, selected_slot: int) -> bool:
	return vehicle_type == 3 and slot != selected_slot


## The lamp's cel in compass_lamps.png for a compass value (FUN_00412960): the row is the cel (0 = cel 1969 for a negative value, 1 = cel 1971), the column is the
## palette `|value|` clamped to 16 (`if (0x10 < v) v = 0x10`; the palettes fade from cel 1970's / 1972's PLUT at 0 to the lamp's own PLUT at 16).
static func lamp_region(value: int) -> Rect2i:
	return Rect2i(mini(absi(value), 16) * 16, 0 if value < 0 else 16, 16, 16)


## A bar's value as the fraction of its maximum: fuel, or the ammunition of its weapon slot.
func _fraction(b: Dictionary, v: Vehicle) -> float:
	if int(b["slot"]) < 0:
		return clampf(v.fuel / v.fuel_max, 0.0, 1.0)
	var mx := float(v.ammo_max[int(b["slot"])])
	return clampf(float(v.ammo[int(b["slot"])]) / mx, 0.0, 1.0) if mx > 0.0 else 0.0


func _update_bar(b: Dictionary, v: Vehicle, delta: float) -> void:
	var rect: Array = b["rect"]
	var full := float(rect[2] - rect[0] + 1)   # pixels of the whole bar (the "pixels per unit" of the init is width / max)
	var span := float(rect[2] - rect[0])       # the thresholds compare against right - left
	var target := full * _fraction(b, v)
	if float(b["drawn"]) < 0.0:
		b["drawn"] = target
	b["drawn"] = move_toward(float(b["drawn"]), target, 0.6 * delta * Vehicle.TICK_HZ)   # FUN_0042cdd0 at 0x9999 (0.6) px per tick
	var f := floorf(float(b["drawn"]) + 0.9)   # FUN_00411f80 / 00411da0 add 0xe666 (0.9) before taking the whole part
	var hp: Dictionary = mc.pack.hud_panels
	var key := "6"
	if int(b["kind"]) == 5:   # fuel: FUN_00411f80
		var words: Dictionary = hp["fuel_rgb"]
		if f < span / 4.0:
			key = "0" if f < span / 8.0 else "2"
			if f < span / 16.0 and int(Time.get_ticks_msec() / 1000.0 * Vehicle.TICK_HZ) & 0x20 == 0:
				key = "8"
		elif f < span * 3.0 / 8.0:
			key = "4"
		b["fill"].color = _rgb(words[key])
	else:   # ammunition: FUN_00411da0 (thresholds at 1/16, 1/4 and 3/16; the colour table is chosen by the slot's flag, see uses_ammo_colours)
		var words2: Dictionary = hp["ammo_rgb"] if uses_ammo_colours(v.vehicle_type, int(b["slot"]), v.heli_weapon_slot()) else hp["fuel_rgb"]
		if f < span / 4.0:
			key = "0" if f < span / 16.0 else "2"
		elif f < floorf(span / 16.0) * 3.0:
			key = "4"
		b["fill"].color = _rgb(words2[key])
	b["fill"].position = b["bg"].position
	b["fill"].size = Vector2(minf(f, full) * _s, b["bg"].size.y)


## The panel's place and scale follow HudLayout (document 96): rebuilt when the layout or the window size changes.
func _apply_layout() -> void:
	var vp := get_viewport_rect().size
	var key := "%s %s" % [GameSettings.hud_layout, vp]
	if key == _layout_key:
		return
	_layout_key = key
	_s = HudLayout.panel_scale(vp)
	size = Vector2(144, 56) * _s
	position = HudLayout.panel_position(vp)
	_type = -1   # rebuild the bars, pips, radar and compass at the new scale


func _process(delta: float) -> void:
	var v := mc.vehicle
	if v == null or mc.pack.hud_panels.is_empty():
		return
	_apply_layout()
	if v.vehicle_type != _type:
		_layout(v.vehicle_type)
	if not visible:
		return
	if _compass_on:
		# kind 8 (documents 71, 103): a lamp, green for a flag target (negative value), red for home (positive), brighter the better the nose points at it
		var cv := mc.compass_value(v)
		if _lamps != null:
			var at := AtlasTexture.new()
			at.atlas = _lamps
			at.region = Rect2(lamp_region(cv))
			_compass.texture = at
		else:   # no lamp sheet in the pack: the cel as stored (its own, unfaded palette)
			var cd: Dictionary = mc.pack.hud_panels["compass"]
			_compass.texture = _atlas(String(cd["flag_sprite_id"] if cv < 0 else cd["home_sprite_id"]))
		_compass.visible = true
	for b in _bars:
		_update_bar(b, v, delta)
	for i in _pips.size():
		_pips[i].visible = i < v.ammo[0]   # kind 7: pip i + 1 is lit while the stock reaches it (the easing of FUN_004127b0 is not reproduced)
	if _weapon_select_bomb != null:
		var ws: Dictionary = mc.pack.hud_panels["weapon_select"]
		var ids: Dictionary = ws["sprite_ids"]
		var bomb_selected := v.heli_weapon_slot() == 1
		_weapon_select_bomb.texture = _atlas(String(ids["bomb_lit" if bomb_selected else "bomb_dim"]))
		_weapon_select_gun.texture = _atlas(String(ids["gun_dim" if bomb_selected else "gun_lit"]))
		_weapon_select_bomb.size = _weapon_select_bomb.texture.get_size() * _s
		_weapon_select_gun.size = _weapon_select_gun.texture.get_size() * _s
