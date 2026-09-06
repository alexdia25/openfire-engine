class_name ProjectileBillboard3D
extends Node3D
## Phase 4 of the rendering-migration plan (PORTING_PLAN.md section 2.2, section 4 item 13):
## pairs a real, unmodified, invisible Projectile (game/projectile.gd -- movement/lifetime
## logic only) with a 3D presentation, the same "extract, don't duplicate" pairing Phase 3's
## VehicleBillboard3D established for the vehicle (game/vehicle_billboard_3d.gd). Projectile's
## own _draw() is already an honest placeholder -- a flat-coloured circle, since no confirmed
## in-flight-projectile art has turned up in the asset registry (see that file's header) -- so
## this mirrors the same placeholder with a small flat-coloured sphere instead of a textured
## billboard; there's no real per-heading art here the way VehicleBillboard3D reuses
## Vehicle._frame_for_heading().

const HEIGHT_PX := 10.0  ## matches VehicleBillboard3D's own placeholder height off the ground
const RADIUS_PX := 3.0   ## matches Projectile.RADIUS_PX

const TEAM_COLOURS := {
	"tan": Color(0.82, 0.71, 0.55),
	"green": Color(0.30, 0.55, 0.30),
}

var projectile: Projectile
var _mesh: MeshInstance3D


func setup(shared_projectile: Projectile) -> void:
	projectile = shared_projectile
	projectile.visible = false  # logic only -- see file header

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
