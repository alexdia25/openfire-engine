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

const HEIGHT_PX := 10.0  ## matches VehicleBillboard3D's own placeholder height off the ground
const RADIUS_PX := 3.0   ## matches Projectile.RADIUS_PX

const TEAM_COLOURS := {
	"tan": Color(0.82, 0.71, 0.55),
	"green": Color(0.30, 0.55, 0.30),
}

var projectile: Projectile
var _mesh: MeshInstance3D


func setup(shared_projectile: Projectile, pack: Pack = null) -> void:
	projectile = shared_projectile
	projectile.visible = false  # logic only -- see file header

	if pack != null and not pack.get_sprite(SHELL_ID).is_empty():
		_add_quad(pack, SHADOW_ID, -HEIGHT_PX + 0.5, true)
		_add_quad(pack, SHELL_ID, 0.0, false)
		global_position = Vector3(projectile.position.x, HEIGHT_PX, projectile.position.y)
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

	global_position = Vector3(projectile.position.x, HEIGHT_PX, projectile.position.y)
	# Projectile queue_free()s itself on expiry (its own LIFETIME_SEC) -- nothing else frees
	# this pairing node, so it has to notice and follow.
	projectile.tree_exited.connect(queue_free)


func _process(_delta: float) -> void:
	if not is_instance_valid(projectile):
		queue_free()
		return
	global_position = Vector3(projectile.position.x, HEIGHT_PX, projectile.position.y)


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
