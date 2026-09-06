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
