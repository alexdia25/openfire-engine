class_name Wreck3D
extends Node3D
## What a destroyed Tank/Jeep leaves behind. TRACED (document 48): on death the vehicle class
## (0x445438) spawns a wreck object (class 0x4453e8, FUN_0040c8f0) that ends up drawing the type
## record's +0x164 descriptor -- for the Tank and Jeep `0x43ece8`: three flat 24-unit quads, a ground
## shadow (cel 274, 27 units, the effect page), a decal at ground level (cel 275, +1 green) and a second
## debris decal 2 units above it (cel 277, +1 green). The real object also falls and settles first
## (gravity in FUN_0040c8f0); that is not modelled -- the wreck simply appears.
##
## The MSV (cels 412-416) and Heli (606/607) have their own wreck descriptors; only the Tank's is used
## so far since it is the only playable type.

const SHADOW_SIZE := 27.0
const DECAL_SIZE := 24.0
const SHADOW_ALPHA := 5.0 / 32.0  ## same darken-row-4 approximation as DecorationField3D

const SHADOW_ID := "effect.shadow.hard.wreck_small"
const DECAL_A := {"tan": "vehicle.wreck.small.a.tan", "green": "vehicle.wreck.small.a.green"}
const DECAL_B := {"tan": "vehicle.wreck.small.b.tan", "green": "vehicle.wreck.small.b.green"}


func setup(pack: Pack, team: String, at: Vector2, heading_deg: float) -> void:
	global_position = Vector3(at.x, 0.0, at.y)
	rotation_degrees.y = -heading_deg
	_add_quad(pack, SHADOW_ID, SHADOW_SIZE, 0.4, true)
	_add_quad(pack, DECAL_A.get(team, DECAL_A["tan"]), DECAL_SIZE, 0.6, false)
	_add_quad(pack, DECAL_B.get(team, DECAL_B["tan"]), DECAL_SIZE, 2.6, false)


func _add_quad(pack: Pack, sprite_id: String, size: float, y: float, is_shadow: bool) -> void:
	var s := pack.get_sprite(sprite_id)
	if s.is_empty():
		return
	var tex := pack.get_texture(int(s.get("page", 0)))
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var u0: float = float(s["x"]) / tw
	var v0: float = float(s["y"]) / th
	var u1: float = (float(s["x"]) + float(s["w"])) / tw
	var v1: float = (float(s["y"]) + float(s["h"])) / th
	var h := size * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Corner order matches the descriptor: (-x,-y), (+x,-y), (+x,+y), (-x,+y) -> cel TL, TR, BR, BL.
	var c := [Vector3(-h, y, -h), Vector3(h, y, -h), Vector3(h, y, h), Vector3(-h, y, h)]
	var uv := [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uv[i])
		st.add_vertex(c[i])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = tex
	if is_shadow:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.0, 0.0, 0.0, SHADOW_ALPHA)
	else:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mi.material_override = mat
	add_child(mi)
