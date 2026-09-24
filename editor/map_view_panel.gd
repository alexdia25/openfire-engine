class_name MapViewPanel
extends HSplitContainer
## The mod tool's map viewer (EDITOR_PLAN.md 5.2-5.4, phase E1, read-only): every level in the stack, drawn top-down
## by the game's own TerrainTileRenderer with the decorations and buildings over it (the same part data the game's 3D
## DecorationField3D uses, projected flat), the spawn and target-pool markers, and optional overlays for water, roads
## and destructible tiles; a hover inspector for the tile under the cursor; the level's rules; "show sides as" colours;
## and "Play this map", which runs the real game on the level with the open mod.

const ROAD_ART := [0x49, 0x5a]   ## FUN_0040c390's pavement range (exclusive), as Vehicle._terrain_speed_scale reads it

var ws: ModWorkspace
var level: LevelData
var level_id := ""
var _levels: ItemList
var _search: LineEdit
var _names: Dictionary = {}          ## level id -> display name (read from the head of level.json)
var _rules: Label
var _hover: Label
var _side_picks: Array[OptionButton] = []
var _layer_checks: Dictionary = {}   ## layer name -> CheckBox
var _container: SubViewportContainer
var _vp: SubViewport
var _camera: Camera2D
var _world: Node2D
var _tiles: TerrainTileRenderer
var _decor: DecorLayer
var _markers: MarkerLayer
var _overlay: OverlayLayer
var _dragging := false


func setup(workspace: ModWorkspace) -> void:
	ws = workspace
	ws.changed.connect(func(): if level != null: _show_level(level_id))
	_list_levels()


func _ready() -> void:
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 300
	add_child(left)
	_search = LineEdit.new()
	_search.placeholder_text = "Search levels (name or id)"
	_search.text_changed.connect(func(_t): _fill_list())
	left.add_child(_search)
	_levels = ItemList.new()
	_levels.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_levels.item_selected.connect(func(i): _show_level(String(_levels.get_item_metadata(i))))
	left.add_child(_levels)
	_rules = Label.new()
	_rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rules.add_theme_font_size_override("font_size", 13)
	left.add_child(_rules)
	var play := Button.new()
	play.text = "Play this map (with this mod)"
	play.tooltip_text = "Runs the real game on this level with the open mod layered over the original (saves first)"
	play.pressed.connect(_play)
	left.add_child(play)

	var centre := VBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(centre)
	var bar := HBoxContainer.new()
	centre.add_child(bar)
	for layer in ["Decorations", "Markers", "Water", "Roads", "Destructible", "Grid"]:
		var c := CheckBox.new()
		c.text = layer
		c.button_pressed = layer in ["Decorations", "Markers"]
		c.toggled.connect(func(_b): _apply_layers())
		bar.add_child(c)
		_layer_checks[layer] = c
	var sides := Label.new()
	sides.text = "   Show sides as"
	bar.add_child(sides)
	for side in 2:
		var o := OptionButton.new()
		o.item_selected.connect(func(_i): _recolour_sides())
		bar.add_child(o)
		_side_picks.append(o)

	_container = SubViewportContainer.new()
	_container.stretch = true
	_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_container.gui_input.connect(_view_input)
	centre.add_child(_container)
	_vp = SubViewport.new()
	_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_container.add_child(_vp)
	_world = Node2D.new()
	_vp.add_child(_world)
	_overlay = OverlayLayer.new()
	_world.add_child(_overlay)
	_decor = DecorLayer.new()
	_world.add_child(_decor)
	_markers = MarkerLayer.new()
	_world.add_child(_markers)
	_camera = Camera2D.new()
	_world.add_child(_camera)
	_hover = Label.new()
	_hover.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hover.add_theme_font_size_override("font_size", 13)
	_hover.custom_minimum_size.y = 60
	centre.add_child(_hover)


# --- levels -----------------------------------------------------------------------------------------------------------

func _list_levels() -> void:
	_names.clear()
	for id in ws.pack.list_levels():
		_names[id] = _peek_name(ws.pack.level_dir(id))
	_fill_list()
	if level_id == "" and _names.has("RFMAP001"):
		_show_level("RFMAP001")


## The level's display name without parsing the whole file: "name" sits near the top of level.json.
static func _peek_name(dir: String) -> String:
	var f := FileAccess.open(dir.path_join("level.json"), FileAccess.READ)
	if f == null:
		return ""
	var head := f.get_buffer(600).get_string_from_utf8()
	var re := RegEx.create_from_string("\"name\"\\s*:\\s*\"([^\"]*)\"")
	var m := re.search(head)
	return m.get_string(1) if m != null else ""


func _fill_list() -> void:
	_levels.clear()
	var q := _search.text.strip_edges().to_lower()
	for id in _names:
		var label := "%s   %s" % [id, _names[id]]
		if q != "" and not label.to_lower().contains(q):
			continue
		var i := _levels.add_item(label)
		_levels.set_item_metadata(i, id)
		if id == level_id:
			_levels.select(i)


func select_level(id: String) -> void:
	_show_level(id)
	_fill_list()


func _show_level(id: String) -> void:
	var lv := LevelData.new()
	if not lv.load_from(ws.pack.level_dir(id)):
		return
	var first := level == null or level_id != id
	level = lv
	level_id = id
	# a fresh TerrainTileRenderer per level: it is made for one setup() (it adds its layers and a frame hook there)
	if _tiles != null:
		_tiles.queue_free()
	_tiles = TerrainTileRenderer.new()
	_world.add_child(_tiles)
	_world.move_child(_tiles, 0)
	_fill_side_picks()
	_tiles.setup(ws.pack, level)
	_decor.setup(ws.pack, level)
	_markers.setup(ws.pack, level)
	_overlay.setup(ws.pack, level)
	_apply_layers()
	if first:
		var map_px := Vector2(level.width, level.height) * ws.pack.tile_size_px
		_camera.position = _start_view(map_px)
		_camera.zoom = Vector2.ONE * 0.5
	var vp := level.vehicle_params
	var players := 2 if level.spawn_points.size() > 1 else 1
	_rules.text = "%s  \"%s\"\n%dx%d tiles, %d player%s, difficulty %d (LEVL)\nby %s, %s\nvehicles: Tank %s, Jeep %s, MSV %s, Heli %s   mines M %s\ntarget pools: A %d, B %d   decorations %d\ntile seed %d" % [
		id, level.level_name, level.width, level.height, players, "" if players == 1 else "s", level.levl_value,
		_meta("author"), _meta("created"), int(vp.get("T", 0)), int(vp.get("J", 0)), int(vp.get("A", 0)), int(vp.get("H", 0)),
		"from the difficulty" if int(vp.get("M", 255)) == 255 else str(int(vp.get("M", 0))),
		level.candidate_pools.get("a", []).size(), level.candidate_pools.get("b", []).size(), level.decorations.size(),
		level.tile_seed]


func _meta(key: String) -> String:
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(ws.pack.level_dir(level_id).path_join("level.json")))
	return String(v.get(key, "")) if v is Dictionary else ""


## Centre on the first spawn point, where the player starts.
func _start_view(map_px: Vector2) -> Vector2:
	if level.spawn_points.is_empty():
		return map_px / 2.0
	var sp: Dictionary = level.spawn_points[0]
	return (Vector2(float(sp["x"]), float(sp["y"])) + Vector2(0.5, 0.5)) * ws.pack.tile_size_px


## Sets the "show sides as" colours and redraws (the mod tool's RF_EDITOR_SIDES switch uses this).
func show_sides_as(colours: Array) -> void:
	for side in mini(colours.size(), _side_picks.size()):
		var o := _side_picks[side]
		for i in o.item_count:
			if o.get_item_text(i) == String(colours[side]):
				o.select(i)
	_recolour_sides()


## Turns layers on by name ("Water", "Roads", ...), the others off except Decorations and Markers.
func show_layers(names: Array) -> void:
	for layer in _layer_checks:
		_layer_checks[layer].set_pressed_no_signal(layer in names or layer in ["Decorations", "Markers"])
	_apply_layers()


func _fill_side_picks() -> void:
	var names: Array = ws.pack.team_colours.keys()
	names.sort()
	for side in 2:
		var o := _side_picks[side]
		var want := String(level.side_colour(side)) if o.item_count == 0 or o.selected < 0 else o.get_item_text(o.selected)
		o.clear()
		for n in names:
			o.add_item(String(n))
			if String(n) == want:
				o.select(o.item_count - 1)
	_recolour_sides(false)


## Preview only: the chosen colours are what the level would look like; saving them per map comes with the map override
## file (PORTING_PLAN.md 2.7.3, step 6).
func _recolour_sides(redraw := true) -> void:
	if level == null:
		return
	var colours: Array = []
	for o in _side_picks:
		colours.append(o.get_item_text(o.selected) if o.selected >= 0 else "")
	level.side_colours = colours
	ws.pack.prepare_team_colours(colours)
	if redraw:
		_show_level(level_id)   # rebuilds every layer (the tile renderer too) in the new colours; the pickers keep them


func _apply_layers() -> void:
	_decor.visible = _layer_checks["Decorations"].button_pressed
	_markers.visible = _layer_checks["Markers"].button_pressed
	_overlay.show_water = _layer_checks["Water"].button_pressed
	_overlay.show_roads = _layer_checks["Roads"].button_pressed
	_overlay.show_damage = _layer_checks["Destructible"].button_pressed
	_overlay.show_grid = _layer_checks["Grid"].button_pressed
	_overlay.queue_redraw()


# --- view and hover ---------------------------------------------------------------------------------------------------

func _view_input(event: InputEvent) -> void:
	if level == null:
		return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera.zoom = (_camera.zoom * 1.2).clamp(Vector2.ONE * 0.05, Vector2.ONE * 8.0)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera.zoom = (_camera.zoom / 1.2).clamp(Vector2.ONE * 0.05, Vector2.ONE * 8.0)
	elif event is InputEventMouseMotion:
		if _dragging:
			_camera.position -= event.relative / _camera.zoom
		_describe(_camera.position + (event.position - _container.size / 2.0) / _camera.zoom)


func _describe(world: Vector2) -> void:
	var tsz := float(ws.pack.tile_size_px)
	var t := Vector2i((world / tsz).floor())
	if t.x < 0 or t.y < 0 or t.x >= level.width or t.y >= level.height:
		_hover.text = ""
		return
	var art := level.get_art_id(t.x, t.y)
	var tile: Dictionary = ws.pack.tileset.get(str(art), {})
	var text := "tile (%d, %d)   art %d = %s (%s)" % [t.x, t.y, art, tile.get("sprite_id", "?"), tile.get("terrain_class", "?")]
	var coastal := level.get_coastal_id(t.x, t.y)
	if coastal != 0:
		var parts := ws.pack.get_decoration_parts(coastal)
		var dmg := ws.pack.get_coastal_damage(coastal)
		text += "\ncoastal id %d, side %d: %s%s" % [coastal, level.get_variant(t.x, t.y),
				parts[0].get("sprite_id", "?") if not parts.is_empty() else "(no decoration)",
				("   destructible, %s hit points" % dmg["hp"]) if dmg.has("hp") and int(dmg["hp"]) > 0 else ""]
	var water := Water.class_at(level, ws.pack, (Vector2(t) + Vector2(0.5, 0.5)) * tsz)
	text += "\nwater: %s   %s" % [["land", "shallow", "deep"][water], "road (1.2x speed)" if art > ROAD_ART[0] - 1 and art < ROAD_ART[1] else ""]
	for sp in level.spawn_points:
		if int(sp["x"]) == t.x and int(sp["y"]) == t.y:
			text += "\nplayer %d spawn point" % (int(sp["team"]) + 1)
	for pool in level.candidate_pools:
		for c in level.candidate_pools[pool]:
			if int(c["x"]) == t.x and int(c["y"]) == t.y:
				text += "\ntarget candidate, pool %s" % String(pool).to_upper()
	_hover.text = text


# --- play test --------------------------------------------------------------------------------------------------------

## Runs the game on this level with the mod layered over the original: RF_PACK and RF_DEBUG_LEVEL, the same switches
## terrain_view_3d.gd reads. Unsaved edits are saved first, since the game reads the mod from disk.
func _play() -> void:
	if level_id == "":
		return
	if ws.is_dirty():
		ws.save()
	OS.set_environment("RF_PACK", ws.mod_dir)
	OS.set_environment("RF_DEBUG_LEVEL", level_id)
	OS.create_process(OS.get_executable_path(), ["--path", ProjectSettings.globalize_path("res://"), "res://game/terrain_view_3d.tscn"])
	OS.unset_environment("RF_PACK")
	OS.unset_environment("RF_DEBUG_LEVEL")


# --- layers -----------------------------------------------------------------------------------------------------------

## Decorations and buildings seen from straight above: every part's quad projected onto the ground, lowest first so roofs
## end up on top -- the same parts, offsets, jitter and team colours as DecorationField3D, only flattened.
class DecorLayer extends Node2D:
	var pack: Pack
	var level: LevelData

	func setup(p: Pack, lv: LevelData) -> void:
		pack = p
		level = lv
		queue_redraw()

	func _draw() -> void:
		if level == null:
			return
		var tile := float(pack.tile_size_px)
		var quads: Array = []
		for entry in level.decorations:
			var cx := (float(entry.get("x", 0)) + 0.5) * tile
			var cy := (float(entry.get("y", 0)) + 0.5) * tile
			var jit: Vector2 = level.jitter_at(int(entry.get("x", 0)), int(entry.get("y", 0)))
			for part in pack.get_decoration_parts(int(entry.get("coastal_id", 0))):
				if not part.has("corners"):
					continue
				var sprite_id: String = part.get("sprite_id", "")
				if part.has("variant_sprite_ids"):
					var variant := clampi(int(entry.get("variant", 0)), 0, 3)
					var v: Variant = part["variant_sprite_ids"][variant]
					if variant <= 1 and v != null:
						v = pack.team_variant(part["variant_sprite_ids"], level.side_colour(variant))
					if v != null:
						sprite_id = v
				var s := pack.get_sprite(sprite_id)
				if s.is_empty():
					continue
				var off: Array = part.get("offset", [0.0, 0.0])
				var j := jit if part.get("jitter", false) else Vector2.ZERO
				var pts := PackedVector2Array()
				var top := -INF
				for c in part["corners"]:
					pts.append(Vector2(cx + j.x + off[0] + c[0], cy + j.y + off[1] + c[1]))
					top = maxf(top, float(c[2]))
				if absf(_area(pts)) < 1.0:
					continue   # a wall seen edge-on
				quads.append([top + float(part.get("zoff", 0.0)), pts, s])
		quads.sort_custom(func(a, b): return a[0] < b[0])
		for q in quads:
			var s: Dictionary = q[2]
			var tex := pack.get_texture(int(s["page"]))
			var tw := float(tex.get_width())
			var th := float(tex.get_height())
			var x0 := float(s["x"]) / tw
			var y0 := float(s["y"]) / th
			var x1 := (float(s["x"]) + float(s["w"])) / tw
			var y1 := (float(s["y"]) + float(s["h"])) / th
			var uvs := PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])
			var col := Color(0, 0, 0, 5.0 / 32.0) if String(s.get("kind", "sprite")) == "effect" else Color.WHITE
			draw_polygon(q[1], PackedColorArray([col, col, col, col]), uvs, tex)

	static func _area(p: PackedVector2Array) -> float:
		var a := 0.0
		for i in p.size():
			a += p[i].cross(p[(i + 1) % p.size()])
		return a / 2.0


## Spawn points (a ring in the side's colour, P1 / P2) and the target candidate pools (A cyan, B magenta squares).
class MarkerLayer extends Node2D:
	var pack: Pack
	var level: LevelData

	func setup(p: Pack, lv: LevelData) -> void:
		pack = p
		level = lv
		queue_redraw()

	func _draw() -> void:
		if level == null:
			return
		var tile := float(pack.tile_size_px)
		var font := ThemeDB.fallback_font
		for pool in level.candidate_pools:
			var col := Color.CYAN if pool == "a" else Color.MAGENTA
			for c in level.candidate_pools[pool]:
				draw_rect(Rect2(Vector2(float(c["x"]), float(c["y"])) * tile + Vector2(4, 4), Vector2(tile - 8, tile - 8)), col, false, 3.0)
		for sp in level.spawn_points:
			var centre := (Vector2(float(sp["x"]), float(sp["y"])) + Vector2(0.5, 0.5)) * tile
			var col := pack.team_rgb(level.side_colour(int(sp["team"])))
			draw_arc(centre, tile * 0.7, 0, TAU, 32, Color.BLACK, 7.0)
			draw_arc(centre, tile * 0.7, 0, TAU, 32, col.lightened(0.2), 4.0)
			draw_string(font, centre + Vector2(-14, -tile * 0.8), "P%d" % (int(sp["team"]) + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)


## Per-tile overlays: water class (FUN_0042f280 via Water.class_at), road tiles, destructible tiles, a tile grid.
class OverlayLayer extends Node2D:
	var pack: Pack
	var level: LevelData
	var show_water := false
	var show_roads := false
	var show_damage := false
	var show_grid := false
	var _water: PackedByteArray

	func setup(p: Pack, lv: LevelData) -> void:
		pack = p
		level = lv
		_water = PackedByteArray()
		queue_redraw()

	func _draw() -> void:
		if level == null:
			return
		var tile := float(pack.tile_size_px)
		if show_water and _water.is_empty():
			_water.resize(level.width * level.height)
			for y in level.height:
				for x in level.width:
					_water[y * level.width + x] = Water.class_at(level, pack, (Vector2(x, y) + Vector2(0.5, 0.5)) * tile)
		for y in level.height:
			for x in level.width:
				var r := Rect2(Vector2(x, y) * tile, Vector2(tile, tile))
				if show_water and _water[y * level.width + x] > 0:
					draw_rect(r, Color(0.1, 0.4, 1.0, 0.25) if _water[y * level.width + x] == 1 else Color(0.0, 0.1, 0.7, 0.45))
				if show_roads:
					var art := level.get_art_id(x, y)
					if art > 0x48 and art < 0x5a:
						draw_rect(r, Color(1.0, 0.9, 0.2, 0.3))
				if show_damage:
					var dmg := pack.get_coastal_damage(level.get_coastal_id(x, y))
					if int(dmg.get("hp", 0)) > 0:
						draw_rect(r.grow(-2), Color(1.0, 0.2, 0.2, 0.9), false, 2.0)
		if show_grid:
			for x in level.width + 1:
				draw_line(Vector2(x * tile, 0), Vector2(x * tile, level.height * tile), Color(0, 0, 0, 0.25))
			for y in level.height + 1:
				draw_line(Vector2(0, y * tile), Vector2(level.width * tile, y * tile), Color(0, 0, 0, 0.25))
