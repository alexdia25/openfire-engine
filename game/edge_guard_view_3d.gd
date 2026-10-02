class_name EdgeGuardView3D
extends Node3D
## Draws an EdgeGuard (game/edge_guard.gd; Return Fire's submarine, issue #68, document 112): one quad whose sprite is the
## guard's current frame. The draw descriptor 0x44ebd8 is a single part (cel 630 + the frame index, flag 8) on a 128 x 64
## quad with corners (x, y, z) = (-64,-32,16) (64,-32,16) (64,32,-16) (-64,32,-16), in the pack's `quad`; the frame sprites
## are the pack's `frames`. Both come from world/edge_guard.json (Pack.edge_guard), nothing here names the game.

var guard: EdgeGuard
var _pack: Pack
var _mi: MeshInstance3D
var _mat: StandardMaterial3D
var _shown := -2


func setup(g: EdgeGuard, pack: Pack) -> void:
	guard = g
	_pack = pack
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_mi = MeshInstance3D.new()
	_mi.material_override = _mat
	add_child(_mi)
	_refresh()


func _process(_delta: float) -> void:
	if guard == null or guard.finished:
		queue_free()
		return
	_refresh()


func _refresh() -> void:
	position = Vector3(guard.position.x, 0.0, guard.position.y)
	var f := guard.shown_frame()
	if f == _shown:
		return
	_shown = f
	var frames: Array = _pack.edge_guard.get("frames", [])
	if f < 0 or f >= frames.size():
		_mi.mesh = null
		return
	var s := _pack.get_sprite(String(frames[f]))
	if s.is_empty():
		_mi.mesh = null
		return
	var tex := _pack.get_texture(int(s.get("page", 0)))
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var u0 := float(s["x"]) / tw
	var v0 := float(s["y"]) / th
	var u1 := (float(s["x"]) + float(s["w"])) / tw
	var v1 := (float(s["y"]) + float(s["h"])) / th
	var c: Array[Vector3] = []
	var qs := float(_pack.edge_guard.get("quad_scale", 1.0))   # a pack may draw the quad smaller or larger than its descriptor says
	for q in _pack.edge_guard.get("quad", []):
		c.append(Vector3(q[0], q[2], q[1]) * qs)   # the descriptors' (x, y, z): x lateral, y = -forward (3D z), z up
	if c.size() != 4:
		_mi.mesh = null
		return
	var uv := [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uv[i])
		st.add_vertex(c[i])
	_mi.mesh = st.commit()
	_mat.albedo_texture = tex
