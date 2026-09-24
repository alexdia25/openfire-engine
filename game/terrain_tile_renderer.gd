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
## Decorations (document 35, docs/process/) used to be drawn here too, baked flush into this
## same ground texture -- document 40's follow-up found that flat, exactly as high as the dirt
## underneath, is never able to look like it stands up no matter how correctly the real
## Camera3D foreshortens it (no parallax, no occlusion -- a tree reads as a shadow). They're a
## real Node3D layer now, `game/decoration_field_3d.gd`, built alongside this node instead of
## inside it -- see that file for the current technique.

## The one tile art that is a real hole (document 89): the home pad's open state, art 92 = "structure.hangar_pit_surround" (a hazard border on three sides, transparent centre). Every other tile gets an
## opaque clear-colour underlay first, so the baked texture (whose viewport is now transparent) looks exactly as it did when the viewport cleared to that colour.
const HOLE_SPRITE_ID := "structure.hangar_pit_surround"

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
	var clear := RenderingServer.get_default_clear_color()
	for y in level.height:
		for x in level.width:
			var art_id := level.get_art_id(x, y)
			var sprite_id := pack.get_tile_sprite_id(art_id)
			var side := int(pack.tileset.get(str(art_id), {}).get("side", -1))
			if side >= 0:   # a team-owned tile (the home pads): drawn in its side's colour, PORTING_PLAN.md 2.7.7
				sprite_id = pack.team_sprite(sprite_id, level.side_colour(side))
			if sprite_id != HOLE_SPRITE_ID:
				draw_rect(Rect2(x * tile, y * tile, tile, tile), clear)
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
