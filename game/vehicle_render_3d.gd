class_name VehicleRender3D
extends Node3D
## Draws any vehicle type from its draw descriptor (document 57): the parts of tools/data/vehicle_types.json
## (cel, flags, four corners in world units), as quads exactly the way decorations are (document 44). A part
## with flag 8 takes the team variant as a +1 cel (tan, green). Used for the Jeep; the Tank keeps its own box
## renderer (game/vehicle_box_3d.gd), which predates this and adds the separately drawn turret. The Jeep's
## rotating wheel strip (cels 457-461) shows its first frame and its passenger/turret is not separate: only the
## hull descriptor is drawn. Corner axes as elsewhere: x lateral, y = -forward, z up.

const GROUND_CLEARANCE_PX := 2.0  ## same as VehicleBoxRender3D

var vehicle: Vehicle
var _pack: Pack


func setup(v: Vehicle, pack: Pack) -> void:
	vehicle = v
	_pack = pack
	v.visible = false  # logic only, like the box renderer
	var t: Dictionary = pack.vehicle_types.get(str(v.vehicle_type), {})
	var variant := v.player_index()
	for part in t.get("parts", []):
		var ids: Array = part["sprite_ids"]
		var s := pack.get_sprite(ids[clampi(variant, 0, ids.size() - 1)])
		if s.is_empty():
			continue
		var tex := pack.get_texture(int(s.get("page", 0)))
		var mi := MeshInstance3D.new()
		mi.mesh = _quad(part["corners"], s, tex)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.albedo_texture = tex
		mi.material_override = mat
		add_child(mi)
	_follow()


func _process(_delta: float) -> void:
	_follow()


func _follow() -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	visible = vehicle.alive
	position = Vector3(vehicle.position.x, GROUND_CLEARANCE_PX, vehicle.position.y)
	rotation_degrees.y = -90.0 - vehicle.heading_deg


func _quad(corners: Array, s: Dictionary, tex: Texture2D) -> ArrayMesh:
	var c: Array[Vector3] = []
	for q in corners:
		c.append(Vector3(q[0], q[2], q[1]))
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var sx := float(s.get("x", 0))
	var sy := float(s.get("y", 0))
	var sw := float(s.get("w", 0))
	var sh := float(s.get("h", 0))
	var uv := [Vector2(sx / tw, sy / th), Vector2((sx + sw) / tw, sy / th),
			Vector2((sx + sw) / tw, (sy + sh) / th), Vector2(sx / tw, (sy + sh) / th)]
	var n := Vector3.ZERO
	for i in 4:
		var a := c[i]
		var b := c[(i + 1) % 4]
		n += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
	n = n.normalized()
	var score_02 := (c[1] - c[0]).cross(c[2] - c[0]).dot(n) + (c[2] - c[0]).cross(c[3] - c[0]).dot(n)
	var score_13 := (c[1] - c[0]).cross(c[3] - c[0]).dot(n) + (c[2] - c[1]).cross(c[3] - c[1]).dot(n)
	var tri := [0, 1, 2, 0, 2, 3] if score_02 >= score_13 else [0, 1, 3, 1, 2, 3]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for idx in tri:
		st.set_uv(uv[idx])
		st.add_vertex(c[idx])
	return st.commit()
