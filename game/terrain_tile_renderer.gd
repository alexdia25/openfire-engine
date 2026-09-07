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
		# See this file's header -- real per-part positions aren't known, so multi-part
		# decorations are spread evenly around a small ring instead of stacked identically.
		var ring_radius: float = 0.0 if parts.size() <= 1 else tile * 0.22
		for i in parts.size():
			var sprite_id: String = parts[i].get("sprite_id", "")
			var sprite := pack.get_sprite(sprite_id)
			if sprite.is_empty():
				continue
			var tex := pack.get_texture(int(sprite.get("page", 0)))
			if tex == null:
				continue
			var w: float = sprite.get("w", 0)
			var h: float = sprite.get("h", 0)
			var angle := TAU * float(i) / float(parts.size())
			var pos := centre + Vector2(cos(angle), sin(angle)) * ring_radius
			var src := Rect2(sprite.get("x", 0), sprite.get("y", 0), w, h)
			var dst := Rect2(pos.x - w * 0.5, pos.y - h * 0.5, w, h)
			draw_texture_rect_region(tex, dst, src)
