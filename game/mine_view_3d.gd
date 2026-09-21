class_name MineView3D
extends Node3D
## Draws a Mine (game/mine.gd): descriptor 0x454200 is one flat quad, corners (+-6, +-6) at z 1, cel 1081 + the mine's
## variant (0 / 2 blinking while armed, 1 once expired; document 60). The three cels are 8 x 8 "ember" sprites.

const CELS := ["effect.ember_small.01", "effect.ember_small.02", "effect.ember_small.03"]
const HALF := 6.0
const HEIGHT := 1.0

var mine: Mine
var _pack: Pack
var _mi: MeshInstance3D
var _mat: StandardMaterial3D
var _shown := -1


func setup(m: Mine, pack: Pack) -> void:
	mine = m
	_pack = pack
	position = Vector3(m.position.x, HEIGHT, m.position.y)
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_mi = MeshInstance3D.new()
	_mi.material_override = _mat
	add_child(_mi)
	m.tree_exited.connect(queue_free)
	_refresh()


func _process(_delta: float) -> void:
	if not is_instance_valid(mine):
		queue_free()
		return
	_refresh()


func _refresh() -> void:
	if mine.variant == _shown:
		return
	_shown = mine.variant
	var s := _pack.get_sprite(CELS[clampi(_shown, 0, 2)])
	if s.is_empty():
		return
	var tex := _pack.get_texture(int(s.get("page", 0)))
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var u0 := float(s["x"]) / tw
	var v0 := float(s["y"]) / th
	var u1 := (float(s["x"]) + float(s["w"])) / tw
	var v1 := (float(s["y"]) + float(s["h"])) / th
	var c := [Vector3(-HALF, 0, -HALF), Vector3(HALF, 0, -HALF), Vector3(HALF, 0, HALF), Vector3(-HALF, 0, HALF)]
	var uv := [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uv[i])
		st.add_vertex(c[i])
	_mi.mesh = st.commit()
	_mat.albedo_texture = tex
