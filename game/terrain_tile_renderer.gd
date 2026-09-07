class_name TerrainTileRenderer
extends Node2D
## Phase 2 of the rendering-migration plan (PORTING_PLAN.md section 2.2, section 4 item 13):
## the level's tile-grid draw loop, pulled out of game/terrain_view.gd's _draw() into its own
## node so it can be reused *unchanged* by two different consumers -- the still-fully-working
## flat 2D scene (as a plain child, drawn straight to screen) and the new 3D scaffold's
## SubViewport (game/terrain_view_3d.gd, baking this same output into a texture for a
## MeshInstance3D ground plane). This is a pure extraction: the loop body below is identical
## to what terrain_view.gd used to run inline, not a rewrite. Deliberately excludes spawn
## markers, candidate-pool markers, the vehicle, and projectiles -- those are gameplay/debug
## overlays, not terrain, and (from Phase 3 on) live objects that a one-shot baked texture
## can't represent anyway.
##
## Decorations (document 35, docs/process/) are drawn here too, not as a separate node --
## unlike the vehicle, a decoration never moves or turns after level load, so baking it into
## this same one-shot texture is exactly as visually correct as giving it its own live Node3D
## (both go through the same real Camera3D projection in the 3D scene either way) while being
## far cheaper than one node per placed bush/rock/post. Per-part positions within a multi-part
## decoration are an honest placeholder -- the real per-part corner offsets document 35 found
## in RFIRE.BIN weren't decoded, so parts are spread in a small fixed ring around the tile
## centre instead, rather than stacked exactly on top of each other.
##
## Palm-frond cels have no trunk pixels of their own (confirmed by direct atlas inspection,
## document 36 addendum) -- the coastal ids that use them (3, 4, 5, at least) draw only the
## fanned canopy shape, floating with nothing visibly holding it up. A real, unused, matching
## trunk cel exists (`decoration.tree.palm`, cel 138 -- two crossed palm trunks, never
## referenced by any of the 82 coastal ids document 35 extracted) -- CANOPY_SPRITE_IDS below is
## a compositional choice, not an RE finding: draw that trunk once, centred under any
## decoration whose parts are drawn entirely from this specific, visually-confirmed set of
## frond/canopy cels, rather than leave them looking unsupported. Not applied to the round
## bush-blob cels from the same 112-152 family (e.g. cels 112/113) -- those already read as
## low ground shrubs, not tree canopies, and shouldn't sprout a trunk.
const CANOPY_SPRITE_IDS := {
	"decoration.foliage.frond_blue": true,
	"decoration.foliage.bush_green.07": true,
	"decoration.foliage.bush_green.08": true,
	"decoration.foliage.bush_green.09": true,
	"decoration.foliage.bush_green.10": true,
	"decoration.foliage.bush_green.11": true,
}
const TRUNK_SPRITE_ID := "decoration.tree.palm"

var pack: Pack
var level: LevelData


func setup(shared_pack: Pack, shared_level: LevelData) -> void:
	pack = shared_pack
	level = shared_level
	queue_redraw()


func _draw() -> void:
	if pack == null or level == null:
		return

	var tile := pack.tile_size_px
	for y in level.height:
		for x in level.width:
			var art_id := level.get_art_id(x, y)
			var sprite_id := pack.get_tile_sprite_id(art_id)
			if sprite_id == "":
				continue
			var sprite := pack.get_sprite(sprite_id)
			if sprite.is_empty():
				continue
			var tex := pack.get_texture(int(sprite.get("page", 0)))
			if tex == null:
				continue
			var src := Rect2(sprite.get("x", 0), sprite.get("y", 0), sprite.get("w", 0), sprite.get("h", 0))
			var dst := Rect2(x * tile, y * tile, tile, tile)
			draw_texture_rect_region(tex, dst, src)

	_draw_decorations()


## Document 35: a tile's coastal-blend id can also spawn one or more real decoration parts
## (bushes, coral, dock posts, ...) on top of the plain ground tile drawn above. One id, two
## jobs -- see Pack.get_decoration_parts()'s own docstring for what's known/unknown about it.
func _draw_decorations() -> void:
	var tile := pack.tile_size_px
	for entry in level.decorations:
		var parts: Array = pack.get_decoration_parts(int(entry.get("coastal_id", 0)))
		if parts.is_empty():
			continue
		var centre := (Vector2(float(entry.get("x", 0)), float(entry.get("y", 0))) + Vector2(0.5, 0.5)) * tile

		# See this file's header (CANOPY_SPRITE_IDS) -- give a floating frond cluster a trunk
		# to stand on, drawn first so the canopy parts layer on top of it.
		var is_canopy_only := true
		for part in parts:
			if not CANOPY_SPRITE_IDS.has(part.get("sprite_id", "")):
				is_canopy_only = false
				break
		if is_canopy_only:
			_draw_sprite_centered(TRUNK_SPRITE_ID, centre)

		# See this file's header -- real per-part positions aren't known, so multi-part
		# decorations are spread evenly around a small ring instead of stacked identically.
		var ring_radius: float = 0.0 if parts.size() <= 1 else tile * 0.22
		for i in parts.size():
			var sprite_id: String = parts[i].get("sprite_id", "")
			var angle := TAU * float(i) / float(parts.size())
			_draw_sprite_centered(sprite_id, centre + Vector2(cos(angle), sin(angle)) * ring_radius)


## Draws one sprite centred at `pos`, in world pixels. Shared by the tile-decoration parts
## loop above and the CANOPY_SPRITE_IDS trunk-completion draw.
func _draw_sprite_centered(sprite_id: String, pos: Vector2) -> void:
	var sprite := pack.get_sprite(sprite_id)
	if sprite.is_empty():
		return
	var tex := pack.get_texture(int(sprite.get("page", 0)))
	if tex == null:
		return
	var w: float = sprite.get("w", 0)
	var h: float = sprite.get("h", 0)
	var src := Rect2(sprite.get("x", 0), sprite.get("y", 0), w, h)
	var dst := Rect2(pos.x - w * 0.5, pos.y - h * 0.5, w, h)
	draw_texture_rect_region(tex, dst, src)
