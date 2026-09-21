class_name ProjectileBillboard3D
extends Node3D
## Pairs a real, unmodified, invisible Projectile (game/projectile.gd -- movement/lifetime logic
## only) with a 3D presentation. The art is the original's Tank shell (document 46/48): projectile
## type 0's draw descriptor is one flat 4x4-unit quad of cel 1075 plus a ground-shadow quad (cel
## 1076, effect page). The height above the ground is still a placeholder (the real object carries a
## z), and the sphere below is only a fallback if the pack lacks those sprites.

const SHELL_ID := "projectile.shell.01"
const SHADOW_ID := "effect.shadow.hard.projectile_shell"
const QUAD_SIZE := 4.0
const SHADOW_ALPHA := 5.0 / 32.0

const HEIGHT_PX := 10.0  ## fallback sphere only (placeholder)
## The Tank shell leaves the muzzle 7 units up and flies level (pitch 0: the velocity is (0, -speed, 0)
## turned by the heading only, FUN_004148f0/FUN_00414b10), so it keeps that height (document 52).
const SHELL_HEIGHT_PX := 7.0 + VehicleBoxRender3D.GROUND_CLEARANCE_PX  # 7 traced + the vehicle box's clearance
const RADIUS_PX := 3.0   ## matches Projectile.RADIUS_PX

const TEAM_COLOURS := {
	"tan": Color(0.82, 0.71, 0.55),
	"green": Color(0.30, 0.55, 0.30),
}

var projectile: Projectile
var _pack: Pack
var _body: MeshInstance3D
var _body_mat: StandardMaterial3D
var _shadow: MeshInstance3D
var _shown_frame := -1
var _mesh: MeshInstance3D
var _height := HEIGHT_PX


func setup(shared_projectile: Projectile, pack: Pack = null) -> void:
	projectile = shared_projectile
	projectile.visible = false  # logic only -- see file header

	if projectile.lob and pack != null:
		_pack = pack
		_setup_missile()
		projectile.tree_exited.connect(queue_free)
		return

	if pack != null and projectile.type_id != 0 and _add_descriptor_parts(pack):
		_height = projectile.z + VehicleBoxRender3D.GROUND_CLEARANCE_PX
		_follow()
		projectile.tree_exited.connect(queue_free)
		return

	if pack != null and not pack.get_sprite(SHELL_ID).is_empty():
		_add_quad(pack, SHADOW_ID, -SHELL_HEIGHT_PX + 0.5, true)
		_add_quad(pack, SHELL_ID, 0.0, false)
		_height = SHELL_HEIGHT_PX
		global_position = Vector3(projectile.position.x, _height, projectile.position.y)
		projectile.tree_exited.connect(queue_free)
		return

	_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS_PX
	sphere.height = RADIUS_PX * 2.0
	_mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = TEAM_COLOURS.get(projectile.team, Color.WHITE)
	_mesh.material_override = mat
	add_child(_mesh)

	global_position = Vector3(projectile.position.x, _height, projectile.position.y)
	# Projectile queue_free()s itself on expiry (its own LIFETIME_SEC) -- nothing else frees
	# this pairing node, so it has to notice and follow.
	projectile.tree_exited.connect(queue_free)


func _process(_delta: float) -> void:
	if not is_instance_valid(projectile):
		queue_free()
		return
	if projectile.lob:
		_update_missile()
		return
	_follow()


func _follow() -> void:
	global_position = Vector3(projectile.position.x, _height, projectile.position.y)
	if projectile.type_id != 0:
		rotation_degrees.y = -90.0 - projectile.heading_deg


## Types other than the shell draw straight from their body and shadow descriptors (documents 46, 58): parts of
## (cel, flags, four corners with x lateral, y = -forward, z up); flag 8 adds the team variant, flag 16 marks the
## flat shadow parts (drawn on the ground, translucent).
func _add_descriptor_parts(pack: Pack) -> bool:
	if projectile.type_id >= pack.projectile_types.size():
		return false
	var t: Dictionary = pack.projectile_types[projectile.type_id]
	var drew := false
	for key in ["shadow_descriptor", "body_descriptor"]:
		var shadow: bool = key == "shadow_descriptor"
		for part in pack.projectile_descriptors.get(String(t[key]), []):
			var ids: Array = part["sprite_ids"]
			var variant := 1 if projectile.team == "green" else 0
			var sp := pack.get_sprite(ids[clampi(variant, 0, ids.size() - 1)])
			if sp.is_empty():
				continue
			var tex := pack.get_texture(int(sp.get("page", 0)))
			var tw := float(tex.get_width())
			var th := float(tex.get_height())
			var c: Array[Vector3] = []
			for q in part["corners"]:
				var y: float = float(q[2])
				if shadow:
					y = -(projectile.z + VehicleBoxRender3D.GROUND_CLEARANCE_PX) + 0.5
				c.append(Vector3(q[0], y, q[1]))
			var sx := float(sp["x"])
			var sy := float(sp["y"])
			var sw := float(sp["w"])
			var sh := float(sp["h"])
			var uv := [Vector2(sx / tw, sy / th), Vector2((sx + sw) / tw, sy / th),
					Vector2((sx + sw) / tw, (sy + sh) / th), Vector2(sx / tw, (sy + sh) / th)]
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
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
			if shadow:
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.albedo_color = Color(0.0, 0.0, 0.0, SHADOW_ALPHA)
			else:
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			mi.material_override = mat
			add_child(mi)
			drew = true
	return drew


## The Jeep missile (document 61): descriptor 0x4548f0, one quad (x -2.7..0, y -2.7..2.8, drawn as read) of cel
## 1779 + spin frame (+ 12 for the green team; init callback 0x436be0), turning 3 degrees a tick, drawn at its height;
## its shadow (object class 4, cel 1076, flag 0x10) is on the ground offset by the height in x and y (FUN_00409b50).
const MISSILE_CORNERS := [Vector3(-2.7, 0.0, -2.7), Vector3(0.0, 0.0, -2.7), Vector3(0.0, 0.0, 2.8), Vector3(-2.7, 0.0, 2.8)]


func _setup_missile() -> void:
	_body = MeshInstance3D.new()
	_body_mat = StandardMaterial3D.new()
	_body_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_body_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_body_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_body_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_body.material_override = _body_mat
	add_child(_body)
	_shadow = MeshInstance3D.new()
	var sp := _pack.get_sprite(SHADOW_ID)
	if not sp.is_empty():
		var tex := _pack.get_texture(int(sp.get("page", 0)))
		_shadow.mesh = _quad_mesh(MISSILE_CORNERS, sp, tex)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_texture = tex
		m.albedo_color = Color(0.0, 0.0, 0.0, SHADOW_ALPHA)
		_shadow.material_override = m
	add_child(_shadow)
	_update_missile()


func _update_missile() -> void:
	var z := maxf(projectile.z, 0.0)
	var yaw := -projectile.spin_deg
	_body.position = Vector3(projectile.position.x, z + VehicleBoxRender3D.GROUND_CLEARANCE_PX, projectile.position.y)
	_body.rotation_degrees.y = yaw
	_shadow.position = Vector3(projectile.position.x + z, 0.5, projectile.position.y + z)
	_shadow.rotation_degrees.y = yaw
	var f := projectile.lob_frame() + (12 if projectile.team == "green" else 0)
	if f != _shown_frame:
		_shown_frame = f
		var sid := "projectile.jeep_missile.%s.%02d" % ["green" if f >= 12 else "tan", (f % 12) + 1]
		var s := _pack.get_sprite(sid)
		if not s.is_empty():
			var tex := _pack.get_texture(int(s.get("page", 0)))
			_body.mesh = _quad_mesh(MISSILE_CORNERS, s, tex)
			_body_mat.albedo_texture = tex


func _quad_mesh(c: Array, sp: Dictionary, tex: Texture2D) -> ArrayMesh:
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var u0: float = float(sp["x"]) / tw
	var v0: float = float(sp["y"]) / th
	var u1: float = (float(sp["x"]) + float(sp["w"])) / tw
	var v1: float = (float(sp["y"]) + float(sp["h"])) / th
	var uv := [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uv[i])
		st.add_vertex(c[i])
	return st.commit()


func _add_quad(pack: Pack, sprite_id: String, y: float, is_shadow: bool) -> void:
	var sp := pack.get_sprite(sprite_id)
	var tex := pack.get_texture(int(sp.get("page", 0)))
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var u0: float = float(sp["x"]) / tw
	var v0: float = float(sp["y"]) / th
	var u1: float = (float(sp["x"]) + float(sp["w"])) / tw
	var v1: float = (float(sp["y"]) + float(sp["h"])) / th
	var h := QUAD_SIZE * 0.5
	var c := [Vector3(-h, y, -h), Vector3(h, y, -h), Vector3(h, y, h), Vector3(-h, y, h)]
	var uv := [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
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
