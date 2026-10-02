class_name VehicleShadow3D
extends Node3D
## The ground shadow a vehicle casts, from its definition's `shadow` table (tools/data/vehicle_shadow.json; issue #26, wiki document 120): the Heli's.
## TRACED: the record's `+0x230` hook (FUN_0040eae0) makes a Shadow object (class 4, table 0x443078) for the vehicle when it is created (FUN_0040b700), and
## that object, each tick (FUN_00409bd0), sits on the ground at the owner's x + 0.332 * z and y - 0.5 * z, turned to the owner's heading. It is drawn
## translucent (part flags 0x10: alpha 5/32) as:
##  - the body, the quad of cel 579 (descriptor 0x440ed8 has the part twice, so it is darker; once the rotor's whole speed is 4 or more it is the one-part
##    descriptor 0x440e90: FUN_00403760);
##  - while the start-up / landing value (state +0x58) is below 1, the two tail corners are pulled in by 18 x (1 - value) (the shadow grows toward the tail as
##    the Heli spools up, shrinks as it lands);
##  - the rotor's shadow (the chained descriptor 0x440da8, init FUN_00403610, draw FUN_004036d0): two cels (589 and 605) on one bar, turned by the rotor
##    angle, narrow for rotor modes 0 and 1 and wide for 2 and 3.
## Not built: the rotor shadow's folded pair during the start-up (mode 4). PORT CHOICE: the rotor angle is accumulated here from the rotor speed, not
## shared with VehicleRender3D, so the blade shadow's phase is not the blade's.

const TICK_HZ := 62.5
const STEP_DEG := 5.625

var vehicle: Vehicle
var _pack: Pack
var _type := -1
var _cfg: Dictionary = {}
var _mat_cache: Dictionary = {}
var _rotor_angle := 0.0
var _meshes: Array[MeshInstance3D] = []


func setup(v: Vehicle, pack: Pack) -> void:
	vehicle = v
	_pack = pack


func _process(delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		queue_free()
		return
	if vehicle.vehicle_type != _type:
		_type = vehicle.vehicle_type
		_cfg = _pack.vehicle_def(_type).get("shadow", {})
	if _cfg.is_empty() or not vehicle.alive or vehicle.docked:
		visible = false
		return
	visible = true
	_rotor_angle = fposmod(_rotor_angle + vehicle.rotor_speed_steps * STEP_DEG * delta * TICK_HZ, 360.0)
	var off: Array = _cfg["offset_per_height"]
	position = Vector3(vehicle.position.x + float(off[0]) * vehicle.z, 0.3, vehicle.position.y + float(off[1]) * vehicle.z)
	rotation_degrees.y = -90.0 - vehicle.heading_deg
	_draw()


func _draw() -> void:
	for m in _meshes:
		m.queue_free()
	_meshes.clear()
	var alpha := float(_cfg.get("alpha", 5.0 / 32.0))
	var mode := int(vehicle.channel("rotor_mode"))
	# the start-up / landing value (state +0x58)
	var p := vehicle.channel("heli_spinup_progress") if vehicle.heli_spinup_stage == 1 else vehicle.heli_landing_gear_progress
	var shear := 0.0
	if p < 1.0:
		shear = float(_cfg.get("startup_shear", 18.0)) * (1.0 - clampf(p, 0.0, 1.0))
	var body: Dictionary = _cfg["body"]
	var corners: Array = []
	for c in body["corners"]:
		corners.append(Vector3(float(c[0]), float(c[1]), float(c[2])))
	for i in _cfg.get("tail_points", []):
		corners[int(i)].y -= shear
	var layers := 1 if shear == 0.0 and mode >= int(_cfg.get("single_layer_from_rotor_mode", 3)) and vehicle.heli_spinup_stage != 1 else 2
	for l in layers:
		_quad(String(body["sprite"]), corners, alpha, 0.0)
	var rotor: Dictionary = _cfg.get("rotor", {})
	if not rotor.is_empty() and mode != 4:
		var set: Array = rotor["wide"] if mode >= 2 else rotor["narrow"]
		var rc: Array = []
		for c in set:
			var v := Vector3(float(c[0]), float(c[1]), float(c[2]))
			var a := deg_to_rad(_rotor_angle)
			rc.append(Vector3(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a), 0.0))
		for s in rotor["sprites"]:
			_quad(String(s), rc, alpha, 0.05)


## One translucent quad on the ground: corners (x, y) in the vehicle's frame, y = minus forward.
func _quad(sprite_id: String, corners: Array, alpha: float, lift: float) -> void:
	var s := _pack.get_sprite(sprite_id)
	if s.is_empty():
		return
	var tex := _pack.get_texture(int(s.get("page", 0)))
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var uv := [Vector2(float(s["x"]) / tw, float(s["y"]) / th), Vector2((float(s["x"]) + float(s["w"])) / tw, float(s["y"]) / th),
			Vector2((float(s["x"]) + float(s["w"])) / tw, (float(s["y"]) + float(s["h"])) / th), Vector2(float(s["x"]) / tw, (float(s["y"]) + float(s["h"])) / th)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uv[i])
		st.add_vertex(Vector3(corners[i].x, lift, corners[i].y))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = tex
	mat.albedo_color = Color(0.0, 0.0, 0.0, alpha)
	mi.material_override = mat
	add_child(mi)
	_meshes.append(mi)
