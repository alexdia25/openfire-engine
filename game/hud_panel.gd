class_name HudPanel
extends Control
## The player's panel as the original lays it out (documents 66, 68-72), for the current vehicle type: the base picture (cel 1943 + vehicle index,
## 144 x 56), the fuel bar (kind 5) and the ammunition bars (kind 4; the Jeep's 16 missile pips, kind 7) at the rectangles of the vehicle's record, the
## radar window (kind 6) or the Jeep's compass (kind 8). A bar's fill eases 0.6 px a tick toward the value; its colour steps down as it empties (fuel:
## flashing when nearly empty). NOT drawn: the compass's per-value palette, the radar's grid and brackets and ping, the panel's slide-in, and the
## vehicle-stock counts of template slot 2 (`FUN_004116a0`). The bar colours are the nearest palette colours to the 15-bit words at 0x446760 / 0x446778 (document 74).
## The scale (3 px per original pixel) and the screen position are the port's choice.

const SCALE := 3

var mc: MatchController
var _base: TextureRect
var _radar: RadarView
var _compass: TextureRect
var _compass_on := false
var _bars: Array = []      ## {kind, rect [l, t, r, b], slot (-1 = fuel), bg, fill, drawn}
var _pips: Array = []      ## 16 TextureRects (the Jeep's missiles)
var _pip_tex: AtlasTexture
var _type := -1


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
	_radar = RadarView.new()
	add_child(_radar)
	_radar.setup(controller)
	size = Vector2(144, 56) * SCALE


## A bar colour (document 74): the game turns the 15-bit word into the nearest colour of its palette; build_pack.py has done that (`*_rgb`).
static func _rgb(c: Array) -> Color:
	return Color8(int(c[0]), int(c[1]), int(c[2]))


func _atlas(sprite_id: String) -> AtlasTexture:
	var s := mc.pack.get_sprite(sprite_id)
	var at := AtlasTexture.new()
	at.atlas = mc.pack.get_texture(int(s.get("page", 0)))
	at.region = Rect2(float(s["x"]), float(s["y"]), float(s["w"]), float(s["h"]))
	return at


func _add_bar(kind: int, slot: int, rect: Array) -> void:
	var bg := ColorRect.new()
	bg.color = _rgb(mc.pack.hud_panels["fuel_rgb"]["empty"])
	bg.position = Vector2(float(rect[0]), float(rect[1])) * SCALE
	bg.size = Vector2(float(rect[2] - rect[0] + 1), float(rect[3] - rect[1] + 1)) * SCALE
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
	var hp: Dictionary = mc.pack.hud_panels
	var pn: Dictionary = hp.get("panels", {}).get(str(t), {})
	if pn.is_empty():
		visible = false
		return
	visible = true
	var at := _atlas(String(pn["sprite_id"]))
	_base.texture = at
	_base.size = at.region.size * SCALE
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
				r.size = _pip_tex.region.size * SCALE
				r.position = Vector2(float(hp["pips"]["x"][i]), float(hp["pips"]["y"][i])) * SCALE
				add_child(r)
				_pips.append(r)
	var s9: Dictionary = pn["slot9"]
	_compass_on = false
	_compass.visible = false
	if int(s9["kind"]) == 6:
		_radar.visible = true
		_radar.configure(Vector2i(int(s9["size"][0]), int(s9["size"][1])), SCALE)
		_radar.position = Vector2(float(s9["pos"][0]), float(s9["pos"][1])) * SCALE
	else:
		_radar.visible = false
		_compass_on = int(s9["kind"]) == 8
		_compass.position = Vector2(float(s9["pos"][0]), float(s9["pos"][1])) * SCALE
		_compass.size = Vector2(float(s9["size"][0]), float(s9["size"][1])) * SCALE


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
	else:   # ammunition: FUN_00411da0 (a different colour set, thresholds at 1/16, 1/4 and 3/16)
		var words2: Dictionary = hp["ammo_rgb"]
		if f < span / 4.0:
			key = "0" if f < span / 16.0 else "2"
		elif f < floorf(span / 16.0) * 3.0:
			key = "4"
		b["fill"].color = _rgb(words2[key])
	b["fill"].position = b["bg"].position
	b["fill"].size = Vector2(minf(f, full) * SCALE, b["bg"].size.y)


func _process(delta: float) -> void:
	var v := mc.vehicle
	if v == null or mc.pack.hud_panels.is_empty():
		return
	if v.vehicle_type != _type:
		_layout(v.vehicle_type)
	if not visible:
		return
	if _compass_on:
		# kind 8 (document 71): the reticle cel for the target (flag: negative value, home: positive); its per-value palette is NOT reproduced
		var cv := mc.compass_value(v)
		var cd: Dictionary = mc.pack.hud_panels["compass"]
		_compass.texture = _atlas(String(cd["flag_sprite_id"] if cv < 0 else cd["home_sprite_id"]))
		_compass.visible = true
	for b in _bars:
		_update_bar(b, v, delta)
	for i in _pips.size():
		_pips[i].visible = i < v.ammo[0]   # kind 7: pip i + 1 is lit while the stock reaches it (the easing of FUN_004127b0 is not reproduced)
