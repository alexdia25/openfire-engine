extends VehicleModule
## The MSV's launcher: FUN_0040d520 (documents 58, 64). Rockets leave the salvo positions in turn, `interval_ticks` apart;
## after the last of a salvo (or the last of the stock) the launcher reloads for `reload_ticks` (6.0 / 0.15, FUN_0040d790).
## The two points `rocket_point` (the rocket) and `blast_point` (the back-blast) are turned by the shot's pitch (level:
## `level_pitch_deg` down; raised: the mount's raised pitch up), then the salvo's offset (x, offset_y, offset_z) is added.
## The rocket type is `projectile_level`, or `projectile_raised` when raised; FUN_00415480 then turns the raised rocket's
## (x, y, 0) by the pitch's table row (a step of 5.625 degrees: `raised_row_deg`) and adds the height again.

const SCHEMA := {
	"slot": "weapon", "doc": "A launcher firing a salvo from several tubes, then reloading (FUN_0040d520 / FUN_0040d790)",
	"params": {
		"projectile_level": {"type": "int", "default": 8, "provenance": "traced:58"},
		"projectile_raised": {"type": "int", "default": 9, "provenance": "traced:64"},
		"interval_ticks": {"type": "float", "unit": "ticks", "default": 30.0, "provenance": "traced:58"},
		"reload_ticks": {"type": "float", "unit": "ticks", "default": 40.0, "provenance": "traced:58"},
		"salvo_x": {"type": "float[]", "unit": "units", "default": [-1.5, 0.0, 1.5], "provenance": "traced:64 (0x43ed90)"},
		"offset_y": {"type": "float", "unit": "units", "default": 6.0, "provenance": "traced:64"},
		"offset_z": {"type": "float", "unit": "units", "default": 12.0, "provenance": "traced:64"},
		"rocket_point": {"type": "vec3", "unit": "units", "default": [0.0, -15.0, -1.0], "provenance": "traced:64 (0x43edb8)"},
		"blast_point": {"type": "vec3", "unit": "units", "default": [0.0, 1.5, -1.0], "provenance": "traced:64 (0x43edb8)"},
		"level_pitch_deg": {"type": "float", "unit": "degrees", "default": 1.744, "provenance": "traced:64"},
		"raised_row_deg": {"type": "float", "unit": "degrees", "default": -45.0, "provenance": "traced:64 (table row 56)"},
		"flash": {"type": "explosion", "default": "0x4450d8", "provenance": "traced:58", "doc": "Back-blast record"},
	},
	"channels": ["_salvo_index", "_salvo_reload"],
}

const TICK_HZ := 62.5
const SELF_DRIVEN := false


func can_fire(v: Vehicle) -> bool:
	return v._salvo_reload <= 0.0


## A point (x, y, z), y = minus forward, turned by `a` radians about the lateral axis with the matrix of FUN_0041ae10
## ([1 0 0; 0 c s; 0 -s c] on a row vector): positive is downward.
static func _pitch_point(p: Vector3, a: float) -> Vector3:
	return Vector3(p.x, p.y * cos(a) - p.z * sin(a), p.y * sin(a) + p.z * cos(a))


static func _vec3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func fill_shot(v: Vehicle, spec: Dictionary) -> void:
	var rad := deg_to_rad(v.heading_deg)
	var fwd := Vector2(cos(rad), sin(rad))
	var right := Vector2(-fwd.y, fwd.x)
	var salvo: Array = params["salvo_x"]
	var x := float(salvo[v._salvo_index])
	v._fire_cooldown_remaining = f("interval_ticks") / TICK_HZ
	var raised := v.gun_elev_deg > 0.0
	var a := deg_to_rad(-v.raised_pitch_deg() if raised else f("level_pitch_deg"))
	var off := Vector3(x, f("offset_y"), f("offset_z"))
	var p0 := _pitch_point(_vec3(params["rocket_point"]), a) + off
	var p1 := _pitch_point(_vec3(params["blast_point"]), a) + off
	var launch_y := p0.y
	var launch_z := p0.z
	if raised:
		var row := deg_to_rad(f("raised_row_deg"))
		launch_z = p0.y * sin(row) + p0.z
		launch_y = p0.y * cos(row)
		spec["pitch_deg"] = -v.raised_pitch_deg()
	spec["type"] = int(params["projectile_raised"]) if raised else int(params["projectile_level"])
	spec["position"] = v.position + fwd * -launch_y + right * x
	spec["z"] = launch_z + v.z
	spec["flash"] = {"record": String(params["flash"]), "offset": Vector3(x, -p1.y, p1.z + v.z)}
	v._salvo_index += 1
	if v._salvo_index >= salvo.size() or v.ammo[0] < 1:   # the last rocket of the stock also starts the reload (FUN_0040d520)
		v._salvo_index = 0
		v._salvo_reload = f("reload_ticks")
