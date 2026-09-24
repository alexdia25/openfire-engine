class_name SelectorScreen
extends Control
## The docked vehicle-choice screen ("the hangar"), drawn as FUN_00417d60 / FUN_00417500 / FUN_004116a0 do (document 78) on the original's 320 x 240 layout, doubled:
##  - a backdrop of sky strips (cels 2084-2086), clouds (2087-2089) and dirt (2080-2083), laid out by the game's own random numbers (the C runtime `rand`, seeded
##    0x1abfac + the player, and per column of dirt 0x1abfac + player + x * 65536), so it looks the same every time;
##  - the hangar (cel 2075, 132 x 123, centred, y = 22) with the four vehicle pictures at half size (cels 2094 + type * 2 + team) in their bays: Heli, Tank / MSV, Jeep; a type
##    with no stock left shows an empty bay; the cursor's bay has its dark box (2078), a spotlight (2077, tinted), and a blinking pointer (2091-2093);
##  - the lift in the middle shaft: a cap (2076) and a body (2079) stretched to the bottom of the screen, at the height `d0` of SelectorAnim, carrying the confirmed picture;
##  - the panel of the cursor's type (frame cel 1940, interior 1942, the vehicle icon, the count of vehicles left, the weapon icons and their capacities: FUN_004116a0);
##  - the map window (frame 2090 with the level's radar bitmap) while `M` is pressed; a black fade over everything but the panel (alpha 1 - fade).
## The 2x scale, the centring and the "M" key are the port's; the rest are the original's numbers. NOT drawn: the panel's slide-in and the sounds.
##
## Fixed (document 80): the pointer used to be mirrored for the right-hand bays (Tank, Jeep) with a negative-width destination Rect2, an invented
## touch never traced from the code -- Godot's AtlasTexture ignores the scale half of a negative-size draw_texture_rect and draws at native (1x)
## size instead, so the two right-hand pointers landed far outside their bays. The mirroring is dropped; the pointer is now drawn the same way for
## all four bays. Whether the original mirrors it at all is unknown (document 78 only read "two red ticks", no flip flag in the traced table).

const S := 2.0

var mc: MatchController
var _sel: Dictionary
var _tex_cache: Dictionary = {}
var _backdrop: Array = []      ## [sprite id, x, y]
var _backdrop_team := -1
var _map_image: ImageTexture = null


func setup(controller: MatchController) -> void:
	mc = controller
	_sel = mc.pack.selector_data
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if _sel.is_empty():
		return
	mc.selection_changed.connect(_refresh)
	# the spotlight (cel 2077) is drawn with a tint blend in the original (PIXC 0x1f801f80): approximated by an additive layer
	_glow = Control.new()
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = mat
	add_child(_glow)
	_glow.draw.connect(func():
		if mc.selecting:
			var at := _atlas(String(_sel["sprites"]["highlight"]))
			if at.atlas != null:
				_glow.draw_texture_rect(at, Rect2(_glow_at, at.region.size * S), false, Color(1, 1, 1, 0.6)))


func _refresh() -> void:
	visible = not _sel.is_empty() and (mc.selecting or mc.undocking)
	if visible and _map_image == null:
		var radar := RadarView.new()
		radar.setup(mc)
		_map_image = ImageTexture.create_from_image(radar.full_image())
		radar.free()
	queue_redraw()


func _process(_delta: float) -> void:
	size = get_viewport_rect().size
	if _glow != null:
		_glow.size = size
		_glow.queue_redraw()   # a Control under a CanvasLayer has no parent rectangle to anchor to
	if visible:
		queue_redraw()


## The pack's `sprites` block (tools/build_pack.py) names every picture this screen draws by sprite id, with the original's
## cel arithmetic already expanded into lists (PORTING_PLAN.md 2.7.5); the cel numbers in the comments are provenance.
func _atlas(id: String) -> AtlasTexture:
	if _tex_cache.has(id):
		return _tex_cache[id]
	var s := mc.pack.get_sprite(id)
	var at := AtlasTexture.new()
	if not s.is_empty():
		at.atlas = mc.pack.get_texture(int(s.get("page", 0)))
		at.region = Rect2(float(s["x"]), float(s["y"]), float(s["w"]), float(s["h"]))
	_tex_cache[id] = at
	return at


var _origin := Vector2.ZERO
var _glow_at := Vector2(-1000, -1000)
var _glow: Control


## Draws sprite `id` with its top-left at the logical position `p` (320 x 240 units), optionally scaled / tinted. (A mirror option used to live here
## for the pointer; dropped, see the header note -- AtlasTexture + a negative-size destination Rect2 doesn't scale correctly in this Godot version.)
func _blit(id: String, p: Vector2, scale := 1.0, tint := Color.WHITE) -> void:
	var at := _atlas(id)
	if at.atlas == null:
		return
	var sz := at.region.size * scale * S
	draw_texture_rect(at, Rect2(_origin + p * S, sz), false, tint)


func _draw() -> void:
	if _sel.is_empty() or mc == null:
		return
	var screen := Vector2(_sel["screen"][0], _sel["screen"][1])
	_origin = ((size - screen * S) / 2.0).floor()
	var team := mc.vehicle.player_index()
	var sp: Dictionary = _sel["sprites"]
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	_draw_backdrop(team, screen)
	var hx := (screen.x - float(_sel["hangar"]["size"][0])) / 2.0
	var hy := float(_sel["hangar"]["y"])
	_blit(String(sp["hangar"]), Vector2(hx, hy))
	var anim: SelectorAnim = mc.select_anim
	var stock: Array = mc.vehicle_stock
	for t in 4:
		var e: Dictionary = _sel["entries"][str(t)]
		var pic := Vector2(e["picture"][0], e["picture"][1])
		var pic_id := mc.pack.team_variant(sp["pictures"][t], mc.vehicle.art_colour())
		if mc.selecting and mc.selection == t or (mc.undocking and mc.selection == t):
			_blit(String(sp["box"]), Vector2(hx, hy) + Vector2(e["box"][0], e["box"][1]))
			var moved := Vector2(anim.d4, anim.d8) if anim != null else Vector2.ZERO
			_blit(pic_id, Vector2(hx, hy) + pic + moved, 0.5)
			if mc.selecting:
				var frame := int(Time.get_ticks_msec() / 1000.0 * Vehicle.TICK_HZ) >> 4
				var pp := Vector2(hx, hy) + Vector2(e["pointer"][0], e["pointer"][1])
				_blit(String(sp["pointer"][frame % 3]), pp)
				_glow_at = _origin + (Vector2(hx, hy) + Vector2(e["highlight"][0], e["highlight"][1])) * S   # drawn additively by the glow layer
		elif stock[t] != 0:
			_blit(pic_id, Vector2(hx, hy) + pic, 0.5)
	# the picture area is 320 x 240 units: what the backdrop's strips put outside it is cut off (the original clips to its screen)
	draw_rect(Rect2(0.0, 0.0, _origin.x, size.y), Color.BLACK)
	draw_rect(Rect2(_origin.x + screen.x * S, 0.0, size.x, size.y), Color.BLACK)
	draw_rect(Rect2(0.0, 0.0, size.x, _origin.y), Color.BLACK)
	draw_rect(Rect2(0.0, _origin.y + screen.y * S, size.x, size.y), Color.BLACK)
	# the lift (cap 2076 and body 2079 stretched down)
	var px := hx + float(_sel["platform"]["x"])
	var py := hy + (anim.d0 if anim != null else float(_sel["platform"]["start_y"]))
	var body := _atlas(String(sp["platform_body"]))
	if body.atlas != null:
		var bh := maxf(screen.y + 2.0 - py, 0.0)
		draw_texture_rect(body, Rect2(_origin + Vector2(px, py) * S, Vector2(body.region.size.x * S, bh * S)), false)
	_blit(String(sp["platform_cap"]), Vector2(px, py))
	if anim != null and anim.fade < 1.0:
		draw_rect(Rect2(_origin, screen * S), Color(0, 0, 0, 1.0 - anim.fade))
	if anim == null or anim.panel_visible:
		_draw_panel()
	if mc.map_open and mc.selecting:
		_draw_map(screen)


func _draw_backdrop(team: int, screen: Vector2) -> void:
	if _backdrop_team != team:
		_build_backdrop(team, screen)
	for b in _backdrop:
		_blit(String(b[0]), Vector2(b[1], b[2]))


## FUN_00417500: the picture list of the backdrop for `team`, using the C runtime's rand (state * 214013 + 2531011, bits 16-30) as the game does.
func _build_backdrop(team: int, screen: Vector2) -> void:
	_backdrop_team = team
	_backdrop.clear()
	var sp: Dictionary = _sel["sprites"]
	var base := int(_sel["backdrop"]["seed_base"])
	var rng := CrtRand.new()
	rng.seed_with(base + team)
	var cx := screen.x / 2.0
	var strip_w := 64.0
	var centre := String(sp["strip_centre"])
	_backdrop.append([centre, cx - 32.0, 0.0])
	_backdrop.append([centre, cx - 32.0, 16.0])
	var x := cx - 32.0
	while x >= 0.0:   # left of the centre strip: 64, 0, -64
		x -= strip_w
		_backdrop.append([sp["strip"][rng.below(2)], x, 0.0])
		_backdrop.append([sp["strip"][rng.below(2)], x, 16.0])
	x = cx - 32.0 + strip_w
	while x < screen.x:
		_backdrop.append([sp["strip"][rng.below(2)], x, 0.0])
		_backdrop.append([sp["strip"][rng.below(2)], x, 16.0])
		x += strip_w
	x = 0.0
	while x < screen.x:   # clouds along the horizon
		_backdrop.append([sp["cloud"][rng.below(3)], x, float(_sel["backdrop"]["cloud_y"])])
		x += 64.0
	x = 0.0
	while x < screen.x:   # dirt, each column reseeded with the player and its x in 16.16
		rng.seed_with(base + team + (int(x) << 16))
		var y := float(_sel["backdrop"]["dirt_y"])
		while y < screen.y:
			_backdrop.append([sp["dirt"][rng.below(4)], x, y])
			y += 32.0
		x += 32.0


## FUN_004116a0 for the cursor's type, on the frame of the HUD panel at (87, 168).
func _draw_panel() -> void:
	var sp: Dictionary = _sel["sprites"]
	var pp := Vector2(_sel["panel"]["pos"][0], _sel["panel"]["pos"][1])
	var off := Vector2(_sel["panel"]["offset"][0], _sel["panel"]["offset"][1])
	_blit(String(sp["panel_frame"]), pp + Vector2(-3, -2))
	_blit(String(sp["panel_interior"]), pp + Vector2(9, 2))
	var t := mc.selection
	_blit(String(sp["icon"][t]), pp + off + Vector2(6, 1))
	_draw_number(mc.vehicle_stock[t], pp + off, 0x1D, 3)
	_blit(String(sp["weapon_icon"][t]), pp + off + Vector2(6, 0x1A))
	_draw_number(int(_sel["ammo_capacity"][t]), pp + off, 0x11, 0x1C)
	var second := String(sp["second_icon"][t])
	if second != "":
		var count := int(_sel["second_capacity"][t])
		if count != 0:   # the MSV's mines (the reserve) appear only with two players: not shown
			_blit(second, pp + off + Vector2(0x26, 0x1B))
			_draw_number(count, pp + off, 0x32, 0x1C)


## FUN_004116a0's digit layout: a '1' for a hundred, then tens and ones, 8 units apart (6 after a '1'); values of 255 (unlimited) show as 99 (PLACEHOLDER).
func _draw_number(value: int, origin: Vector2, x: int, y: int) -> void:
	var v := mini(value, 199) if value != 255 else 99
	var digits: Array = _sel["sprites"]["digits"]
	var cx := x
	if v > 99:
		_blit(String(digits[1]), origin + Vector2(cx, y))
		cx += 6
	if v > 9:
		var tens := (v / 10) % 10
		_blit(String(digits[tens]), origin + Vector2(cx, y))
		cx += 8 - (2 if tens == 1 else 0)
	_blit(String(digits[v % 10]), origin + Vector2(cx, y))


func _draw_map(screen: Vector2) -> void:
	var fpos := Vector2((screen.x - 144.0) / 2.0, (screen.y - 144.0) / 2.0)
	_blit(String(_sel["sprites"]["map_frame"]), fpos)
	if _map_image != null:
		draw_texture_rect(_map_image, Rect2(_origin + (fpos + Vector2(8, 8)) * S, Vector2(128, 128) * S), false)
