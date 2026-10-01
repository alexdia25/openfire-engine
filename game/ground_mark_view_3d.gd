class_name GroundMarkView3D
extends Node3D
## Draws a GroundMark (game/ground_mark.gd): one flat quad on the ground. For the soldier's body the descriptor 0x44ea58 is a single part
## (cel 806 + variant, flags 0x108) on an 8 x 8 ground quad (-4..4, z 0), from the pack's world/infantry.json `corpse` table.

var mark: GroundMark


func setup(m: GroundMark, pack: Pack) -> void:
	mark = m
	position = Vector3(m.position.x, 0.5 + CoplanarParts.COPLANAR_STEP, m.position.y)
	var ids: Array = pack.infantry.get("corpse_sprites", [])
	if m.variant < 0 or m.variant >= ids.size():
		return
	var s := pack.get_sprite(String(ids[m.variant]))
	if s.is_empty():
		return
	var tex := pack.get_texture(int(s.get("page", 0)))
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var u0 := float(s["x"]) / tw
	var v0 := float(s["y"]) / th
	var u1 := (float(s["x"]) + float(s["w"])) / tw
	var v1 := (float(s["y"]) + float(s["h"])) / th
	var c: Array[Vector3] = []
	for q in pack.infantry.get("corpse", {}).get("quad", []):
		c.append(Vector3(q[0], q[2], q[1]))
	if c.size() != 4:
		return
	var uv := [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uv[i])
		st.add_vertex(c[i])
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.albedo_texture = tex
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)


func _process(_delta: float) -> void:
	if mark == null or mark.finished:
		queue_free()
