class_name TerrainTileRenderer
extends Node2D
## The level's tile-grid draw loop, drawn into game/terrain_view_3d.gd's SubViewport and baked into the ground plane's texture. Deliberately excludes spawn markers,
## candidate-pool markers, the vehicle and projectiles: those are gameplay/debug overlays or live objects that a baked texture can't represent. Decorations are a real
## Node3D layer (game/decoration_field_3d.gd), not part of this texture.
##
## Incremental (a crushed or destroyed tile used to re-render the whole 4096-pixel map: ~70 ms, a visible hitch): the first render draws every tile, after that only
## the tiles named in mark_tile() are redrawn over the previous contents, so the viewport must not clear between renders (terrain_view_3d.gd sets CLEAR_MODE_NEVER).
## Two layers draw in order: the underlay replaces the tile's pixels (an opaque clear colour, or transparent for the pad's hole, blend_disabled so it overwrites
## instead of blending), then the art is drawn over it.

## The one tile art that is a real hole (document 89): the home pad's open state, art 92 = "structure.hangar_pit_surround" (a hazard border on three sides, transparent
## centre). Every other tile gets an opaque clear-colour underlay first, so the baked texture (whose viewport is transparent) looks exactly as it did when the
## viewport cleared to that colour.
const HOLE_SPRITE_ID := "structure.hangar_pit_surround"

var pack: Pack
var level: LevelData
var _under: Node2D
var _art: Node2D
var _full := true
var _dirty: Array[Vector2i] = []
var _drawn := false   ## a draw pass has issued the current commands; they count as rendered only after the frame's post-draw


class Layer extends Node2D:
	var owner_renderer: TerrainTileRenderer
	var is_underlay := false

	func _draw() -> void:
		owner_renderer._draw_layer(self, is_underlay)


func setup(shared_pack: Pack, shared_level: LevelData) -> void:
	pack = shared_pack
	level = shared_level
	_under = _make_layer(true)
	_art = _make_layer(false)
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; render_mode blend_disabled; void fragment() {}"   # writes the colour (alpha included) instead of blending it
	var m := ShaderMaterial.new()
	m.shader = shader
	_under.material = m
	_full = true
	_dirty.clear()
	RenderingServer.frame_post_draw.connect(_on_frame_post_draw)
	_under.queue_redraw()
	_art.queue_redraw()


## A tile's art (or its team colour) changed: redraw just that tile on the next render.
func mark_tile(tile: Vector2i) -> void:
	if not _full and not _dirty.has(tile):
		_dirty.append(tile)
	_under.queue_redraw()
	_art.queue_redraw()


## A redraw REPLACES the layer's draw commands, so the "everything" / dirty lists may only be cleared once a frame has actually rendered them: otherwise a tile changing
## before the first render would leave a commands list with just that tile, and the map would never be drawn.
func _on_frame_post_draw() -> void:
	if _drawn:
		_drawn = false
		_full = false
		_dirty = []


func _make_layer(underlay: bool) -> Node2D:
	var l := Layer.new()
	l.owner_renderer = self
	l.is_underlay = underlay
	add_child(l)
	return l


func _tile_sprite_id(x: int, y: int) -> String:
	var art_id := level.get_art_id(x, y)
	var sprite_id := pack.get_tile_sprite_id(art_id)
	var side := int(pack.tileset.get(str(art_id), {}).get("side", -1))
	if side >= 0:   # a team-owned tile (the home pads): drawn in its side's colour, PORTING_PLAN.md 2.7.7
		sprite_id = pack.team_sprite(sprite_id, level.side_colour(side))
	return sprite_id


func _draw_layer(layer: Node2D, underlay: bool) -> void:
	if pack == null or level == null:
		return
	var tile := pack.tile_size_px
	var clear := RenderingServer.get_default_clear_color()
	var tiles: Array[Vector2i] = []
	if _full:
		for y in level.height:
			for x in level.width:
				tiles.append(Vector2i(x, y))
	else:
		tiles = _dirty
	for t in tiles:
		var sprite_id := _tile_sprite_id(t.x, t.y)
		var dst := Rect2(t.x * tile, t.y * tile, tile, tile)
		if underlay:
			layer.draw_rect(dst, Color(0, 0, 0, 0) if sprite_id == HOLE_SPRITE_ID else clear)
			continue
		if sprite_id == "":
			continue
		var sprite := pack.get_sprite(sprite_id)
		if sprite.is_empty():
			continue
		var tex := pack.get_texture(int(sprite.get("page", 0)))
		if tex == null:
			continue
		var src := Rect2(sprite.get("x", 0), sprite.get("y", 0), sprite.get("w", 0), sprite.get("h", 0))
		layer.draw_texture_rect_region(tex, dst, src)
	if not underlay:   # the art layer draws last
		_drawn = true
