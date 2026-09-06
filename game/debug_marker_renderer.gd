class_name DebugMarkerRenderer2D
extends Node2D
## Phase 4 of the rendering-migration plan (PORTING_PLAN.md section 2.2, section 4 item 13):
## extracts terrain_view.gd's own debug-overlay drawing (spawn-point markers, candidate-pool
## target markers) into a reusable node, the same "extract, don't duplicate" move
## game/terrain_tile_renderer.gd made for the tile grid in Phase 2 and game/match_controller.gd
## just made for the gameplay logic behind these markers -- so the flat 2D scene and the new 3D
## scene's baked overlay plane (game/terrain_view_3d.gd's Phase 4 addition) share one drawing
## implementation instead of risking the two silently drifting apart.
##
## None of this is real game art. Section 4 item 1's real objects (spawn points, candidate-pool
## targets) have no confirmed visual presentation traced from RFIRE.BIN at all -- these are
## flat colour primitives, a debug view, same honesty flag as every other placeholder visual in
## this project (game/projectile.gd's circle, the old placeholder box Phase 1 replaced, etc).

## Team colours per PORTING_PLAN.md section 4 item 5 (user-confirmed 2026-09-06): team 0 is
## tan, team 1 is green. Just marker colours for this debug view.
const TEAM_COLOURS := {
	0: Color(0.82, 0.71, 0.55),
	1: Color(0.30, 0.55, 0.30),
}
const POOL_COLOURS := {
	"a": Color.CYAN,
	"b": Color.MAGENTA,
}

var pack: Pack
var level: LevelData
var controller: MatchController


func setup(shared_pack: Pack, shared_level: LevelData, shared_controller: MatchController) -> void:
	pack = shared_pack
	level = shared_level
	controller = shared_controller
	# Redraw whenever a target dies or a pool goes silent -- the only two ways this overlay's
	# content changes after setup (spawn markers never move).
	controller.target_hit.connect(func(_pool_id, _tile): queue_redraw())


func _draw() -> void:
	if pack == null or level == null or controller == null:
		return
	var tile := pack.tile_size_px

	for sp in level.spawn_points:
		var team := int(sp.get("team", 0))
		var colour: Color = TEAM_COLOURS.get(team, Color.WHITE)
		var centre := Vector2(float(sp.get("x", 0)) + 0.5, float(sp.get("y", 0)) + 0.5) * tile
		draw_circle(centre, tile * 0.6, colour)

	# Intact-but-not-active candidates as a thin hollow outline, a destroyed-and-not-replaced
	# candidate as a dim X (the pool spent that slot and, once its budget/candidates run out,
	# will never revisit it), and the pool's one currently-live target as a bright filled
	# square -- the thing a projectile can actually destroy right now.
	for pool_id in controller.pools:
		var colour: Color = POOL_COLOURS.get(pool_id, Color.WHITE)
		var pool: TargetPool = controller.pools[pool_id]
		for i in pool.candidates.size():
			var top_left := Vector2(pool.candidates[i]) * tile
			var rect := Rect2(top_left, Vector2(tile, tile))
			if i == pool.active_index:
				draw_rect(rect, colour, true)
			elif pool.intact[i]:
				draw_rect(rect, colour, false, 2.0)
			else:
				var dim := Color(colour, 0.35)
				draw_line(rect.position, rect.position + rect.size, dim, 2.0)
				draw_line(rect.position + Vector2(rect.size.x, 0), rect.position + Vector2(0, rect.size.y), dim, 2.0)
