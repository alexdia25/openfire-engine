class_name DebugMarkerOverlay3D
extends Node3D
## Phase 4 of the rendering-migration plan (PORTING_PLAN.md section 2.2, section 4 item 13):
## bakes game/debug_marker_renderer.gd's 2D overlay (spawn-point markers, candidate-pool
## target markers -- see that file's own header for why these are honest placeholders, not
## real art) onto a transparent plane sitting just above the real terrain ground plane
## (game/terrain_view_3d.gd's Phase 2 addition), the same SubViewport-to-3D-texture technique
## Phase 2 used for the terrain art itself. Unlike that bake, this content changes at runtime
## (targets get destroyed, pools go silent) -- render_target_update_mode is UPDATE_ALWAYS, not
## Phase 2's UPDATE_ONCE. DebugMarkerRenderer2D only actually queue_redraw()s on a real
## target-hit signal, but re-rendering a handful of flat-colour primitives every frame
## regardless is cheap enough not to bother tracking that dirty state a second time here.

var _sub_vp: SubViewport
var _plane: MeshInstance3D


func setup(pack: Pack, level: LevelData, controller: MatchController) -> void:
	var map_size_px := Vector2(level.width, level.height) * pack.tile_size_px

	_sub_vp = SubViewport.new()
	_sub_vp.size = Vector2i(int(map_size_px.x), int(map_size_px.y))
	_sub_vp.transparent_bg = true
	_sub_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sub_vp)

	var renderer := DebugMarkerRenderer2D.new()
	_sub_vp.add_child(renderer)
	renderer.setup(pack, level, controller)

	_plane = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = map_size_px
	_plane.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _sub_vp.get_texture()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_plane.material_override = mat
	# Same axis remap as the terrain ground plane (terrain_view_3d.gd's _build_terrain_ground):
	# world X -> node X, world Y ("down" in the 2D scenes) -> node Z ("forward"). The small Y
	# offset lifts this plane just above the terrain mesh so the two don't z-fight.
	_plane.position = Vector3(map_size_px.x * 0.5, 0.5, map_size_px.y * 0.5)
	add_child(_plane)
