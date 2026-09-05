extends Node2D
## Phase 4 step 1 proof: load a pack, render one level's terrain + spawn/candidate
## markers. Everything is read through Pack/LevelData -- never build/ or *.RFM/*.CAR
## directly (PORTING_PLAN.md section 2.4). Replaces the placeholder boot scene until
## a real menu (section 2.6) picks a pack + level instead of these two exports.

## Team colours per PORTING_PLAN.md section 4 item 5 (user-confirmed 2026-09-06,
## cross-checked against art): team 0 is tan, team 1 is green. The actual colouring
## *mechanism* is still open -- these are just marker colours for this debug view.
const TEAM_COLOURS := {
	0: Color(0.82, 0.71, 0.55),
	1: Color(0.30, 0.55, 0.30),
}
const POOL_COLOURS := {
	"a": Color.CYAN,
	"b": Color.MAGENTA,
}

@export var pack_path: String = "res://packs/original_pc"
@export var level_id: String = "RFMAP001"

var pack: Pack
var level: LevelData


func _ready() -> void:
	pack = Pack.new()
	if not pack.load_from(pack_path):
		push_error("TerrainView: failed to load pack at %s" % pack_path)
		return

	level = LevelData.new()
	if not level.load_from(pack_path.path_join("levels").path_join(level_id)):
		push_error("TerrainView: failed to load level %s" % level_id)
		return

	get_window().title = "Return Fire -- %s (%s)" % [level.level_name, level_id]
	_fit_debug_camera()
	queue_redraw()

	var screenshot_path := OS.get_environment("RF_DEBUG_SCREENSHOT")
	if screenshot_path != "":
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(screenshot_path)
		get_tree().quit()


## Debug-only overview camera so the whole level is visible at once -- not the real
## scrolling/split-screen camera (that's Phase 4 step 3), just enough to eyeball this
## step's output.
func _fit_debug_camera() -> void:
	var map_px := Vector2(level.width, level.height) * pack.tile_size_px
	var viewport_size := get_viewport_rect().size
	var zoom_factor := minf(viewport_size.x / map_px.x, viewport_size.y / map_px.y)
	var cam := Camera2D.new()
	cam.zoom = Vector2.ONE * zoom_factor
	cam.position = map_px * 0.5
	add_child(cam)
	cam.make_current()


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

	for sp in level.spawn_points:
		var team := int(sp.get("team", 0))
		var colour: Color = TEAM_COLOURS.get(team, Color.WHITE)
		var centre := Vector2(float(sp.get("x", 0)) + 0.5, float(sp.get("y", 0)) + 0.5) * tile
		draw_circle(centre, tile * 0.6, colour)

	for pool_id in level.candidate_pools:
		var colour: Color = POOL_COLOURS.get(pool_id, Color.WHITE)
		for c in level.candidate_pools[pool_id]:
			var top_left := Vector2(float(c.get("x", 0)), float(c.get("y", 0))) * tile
			draw_rect(Rect2(top_left, Vector2(tile, tile)), colour, false, 2.0)
