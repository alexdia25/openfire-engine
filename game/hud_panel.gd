class_name HudPanel
extends Control
## The player's panel as the original lays it out (documents 66, 68, 69, 70), for the current vehicle type: the base picture (cel 1943 + vehicle
## index, 144 x 56), the fuel bar (kind 5: an easing fill, a colour that steps down with the fill and flashes when nearly empty) at the rectangle of the
## vehicle's record, and the radar window (kind 6) at its record position and size. Ammunition bars (not modelled yet), the Jeep's compass (kind 8, its
## needle source unconfirmed), the radar's grid and brackets, and the panel's slide-in are NOT drawn. UNVERIFIED: the bar colours are read from
## the words at 0x446760 as 15-bit RGB (document 70). The scale (3 px per original pixel) and the screen position are the port's choice.

const SCALE := 3

var mc: MatchController
var _base: TextureRect
var _radar: RadarView
var _bar_bg: ColorRect
var _bar_fill: ColorRect
var _type := -1
var _fill := 0.0        ## the drawn fill in pixels (eases toward the fuel, 0.6 px per tick)
var _rect: Array = []
var _fuel_max := 1.0


func setup(controller: MatchController) -> void:
	mc = controller
	_base = TextureRect.new()
	_base.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_base)
	_bar_bg = ColorRect.new()
	add_child(_bar_bg)
	_bar_fill = ColorRect.new()
	add_child(_bar_fill)
	_radar = RadarView.new()
	add_child(_radar)
	_radar.setup(controller)
	size = Vector2(144, 56) * SCALE


static func _rgb555(w: int) -> Color:
	return Color(((w >> 10) & 31) / 31.0, ((w >> 5) & 31) / 31.0, (w & 31) / 31.0)


func _layout(t: int) -> void:
	_type = t
	var hp: Dictionary = mc.pack.hud_panels
	var pn: Dictionary = hp.get("panels", {}).get(str(t), {})
	if pn.is_empty():
		visible = false
		return
	visible = true
	var s := mc.pack.get_sprite(String(pn["sprite_id"]))
	var tex := mc.pack.get_texture(int(s.get("page", 0)))
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(float(s["x"]), float(s["y"]), float(s["w"]), float(s["h"]))
	_base.texture = at
	_base.size = Vector2(float(s["w"]), float(s["h"])) * SCALE
	_base.stretch_mode = TextureRect.STRETCH_SCALE
	_base.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect = pn["fuel"]["rect"]
	_fuel_max = float(pn["fuel"]["max"])
	_bar_bg.color = _rgb555(int(hp["fuel_colour_words"]["empty"]))
	_bar_bg.position = Vector2(float(_rect[0]), float(_rect[1])) * SCALE
	_bar_bg.size = Vector2(float(_rect[2] - _rect[0] + 1), float(_rect[3] - _rect[1] + 1)) * SCALE
	var s9: Dictionary = pn["slot9"]
	if int(s9["kind"]) == 6:
		_radar.visible = true
		_radar.configure(Vector2i(int(s9["size"][0]), int(s9["size"][1])), SCALE)
		_radar.position = Vector2(float(s9["pos"][0]), float(s9["pos"][1])) * SCALE
	else:
		_radar.visible = false   # the Jeep's compass (kind 8) is not drawn yet
	_fill = float(_rect[2] - _rect[0] + 1) * clampf(mc.vehicle.fuel / _fuel_max, 0.0, 1.0)


func _process(delta: float) -> void:
	var v := mc.vehicle
	if v == null or mc.pack.hud_panels.is_empty():
		return
	if v.vehicle_type != _type:
		_layout(v.vehicle_type)
	if not visible:
		return
	var width := float(_rect[2] - _rect[0] + 1)
	var target := width * clampf(v.fuel / _fuel_max, 0.0, 1.0)
	_fill = move_toward(_fill, target, 0.6 * delta * Vehicle.TICK_HZ)   # FUN_0042cdd0 at 0x9999 (0.6) pixels per tick
	var f := floorf(_fill + 0.9)   # FUN_00411f80 adds 0xe666 (0.9) before taking the whole part
	var words: Dictionary = mc.pack.hud_panels["fuel_colour_words"]
	var key := "6"
	if f < width / 4.0:
		key = "0" if f < width / 8.0 else "2"
		if f < width / 16.0 and int(Time.get_ticks_msec() / 1000.0 * Vehicle.TICK_HZ) & 0x20 == 0:
			key = "8"
	elif f < width * 3.0 / 8.0:
		key = "4"
	_bar_fill.color = _rgb555(int(words[key]))
	_bar_fill.position = _bar_bg.position
	_bar_fill.size = Vector2(minf(f, width) * SCALE, _bar_bg.size.y)
