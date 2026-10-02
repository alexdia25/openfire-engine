# Issue alexdia25/openfire#69: the original's renderer draws every cell past the map's edge with one default tile, and its camera
# follows a vehicle out there without a clamp (FUN_00408d60, FUN_00416300). The port bakes `tileset.json`'s `off_map` tile
# `margin_tiles` deep around the ground and lets the camera go that far out. Run:
#   godot --headless --path .harness --script res://addons/openfire_engine/tests/off_map_check.gd
extends SceneTree

const Fixture := preload("fixtures/synthetic_pack.gd")

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _view() -> Node:
	var view: Node = load("res://addons/openfire_engine/game/terrain_view_3d.tscn").instantiate()
	get_root().add_child(view)
	current_scene = view
	for i in 3:
		await process_frame
	return view


func _plane(view: Node) -> PlaneMesh:
	for c in view.get_children():
		if c is MeshInstance3D and c.mesh is PlaneMesh:
			return c.mesh
	return null


func _init() -> void:
	var base := Fixture.build("user://packs")
	ProjectSettings.set_setting(EngineConfig.BASE_PACK, base)
	var plain: Node = await _view()
	var map_px := float(Fixture.LEVEL_SIZE * 32)
	_check(plain._ground_margin_px == 0.0 and _plane(plain).size == Vector2(map_px, map_px), "without an off_map table the ground is exactly the map")
	var pull: float = plain.camera_height_px / tan(deg_to_rad(plain.camera_tilt_deg))
	var near_edge: Vector3 = plain._camera_target_position(Vector2(-50.0, 100.0))
	_check(is_equal_approx(near_edge.x, minf(pull, maxf(map_px - pull, pull))), "and the camera stops at the edge as before (x %.1f)" % near_edge.x)
	plain.queue_free()
	await process_frame

	PackWriter.write_json(base.path_join("terrain/tileset.json"), {"tile_size_px": 32,
		"tiles": {"0": {"sprite_id": "fx.tile", "terrain_class": "ground"}}, "off_map": {"art": 0, "margin_tiles": 3}})
	var view: Node = await _view()
	_check(view._ground_margin_px == 96.0, "an off_map table of 3 tiles bakes a 96 unit border")
	_check(_plane(view).size == Vector2(map_px + 192.0, map_px + 192.0), "the ground plane grows by it on every side")
	var tr: TerrainTileRenderer = view._tile_renderer
	_check(tr.margin_tiles == 3 and tr.position == Vector2(96.0, 96.0), "the tile renderer is shifted by it so map tiles keep their coordinates")
	var out: Vector3 = view._camera_target_position(Vector2(-50.0, 100.0))
	_check(out.x < near_edge.x - 90.0, "and the camera may go that much further out (x %.1f against %.1f)" % [out.x, near_edge.x])
	# past the baked border the same tile repeats out to OPEN_WATER_EXTENT, in four strips around it
	var strips := 0
	var area := 0.0
	for c in view.get_children():
		if c is MeshInstance3D and c.mesh is PlaneMesh and c.mesh != _plane(view):
			strips += 1
			area += c.mesh.size.x * c.mesh.size.y
	var inner := map_px + 192.0
	var full: float = inner + 2.0 * view.OPEN_WATER_EXTENT
	_check(strips == 4 and is_equal_approx(area, full * full - inner * inner), "four open-water strips tile the ring around the border without overlap")
	var far: Vector3 = view._camera_target_position(Vector2(-5000.0, 100.0))
	_check(far.x < -4000.0, "and the camera follows far out over them (x %.1f)" % far.x)
	if _failures == 0:
		print("off map: all ok")
	quit(_failures)
