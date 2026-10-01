# The render-descriptor vocabulary (PORTING_PLAN.md 2.7.2 step 5; game/vehicle_render_3d.gd's header) with no game's
# vehicles at all: one synthetic vehicle whose descriptor uses every binding -- a group turned by a channel, a group
# turned at a rate, a rig (R(channel) * base + offset), sprites_by with wrap, corners_by, visible, scale_by and a body
# rotation -- each checked to move the way the vocabulary says. How Return Fire's four traced vehicles are expressed
# in this vocabulary stays openfire's own check (its tools/tests/render_descriptor_check.gd). Moved from openfire
# (issue alexdia25/openfire#65). Run (see tests/README.md):
#   godot --headless --path .harness --script res://addons/openfire_engine/tests/render_descriptor_check.gd
extends SceneTree

const Fixture := preload("fixtures/synthetic_pack.gd")

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _near(a: Vector3, b: Vector3) -> bool:
	return a.distance_to(b) < 0.001


func _part(r: VehicleRender3D, name: String) -> Dictionary:
	for p in r._parts:
		if String(p["data"].get("name", "")) == name:
			return p
	return {}


static func _quad(z: float, h := 2.0) -> Array:
	return [[-h, -h, z], [h, -h, z], [h, h, z], [-h, h, z]]


func _init() -> void:
	var base_dir := Fixture.build("user://packs")
	var mod := ProjectSettings.globalize_path("user://render_descriptor_check/mod")
	if DirAccess.dir_exists_absolute(mod):
		OS.move_to_trash(mod)
	PackWriter.write_json(mod.path_join("pack.json"), {"id": "rendmod", "name": "render descriptor test", "base_pack": Fixture.ID})
	var def := Fixture.vehicle_def("rendmod.gizmo", "Gizmo", 9)
	def["render"] = {
		"parts": [
			{"name": "hull", "sprite_ids": ["fx.hull"], "flags": 0, "corners": _quad(1.0, 4.0)},
			{"name": "turret", "group": "turret", "sprite_ids": ["fx.turret"], "flags": 0, "corners": _quad(5.0)},
			{"name": "barrel", "group": "turret", "sprite_ids": ["fx.turret"], "flags": 0,
				"corners": [{"rig": "tip", "point": 0}, {"rig": "tip", "point": 1}, [0.5, 0.0, 6.0], [-0.5, 0.0, 6.0]]},
			{"name": "wheel", "sprite_ids": ["fx.wheel"], "flags": 0, "corners": _quad(0.5),
				"sprites_by": {"channel": "position_x", "wrap": 3, "sprites": ["fx.wheel", "fx.hull", "fx.turret"]},
				"corners_by": {"channel": "swim_amount", "scale": 2.0, "max": 1, "sets": [_quad(0.5), _quad(0.25, 3.0)]}},
			{"name": "ring", "sprite_ids": ["fx.tile"], "flags": 0, "corners": _quad(0.0, 6.0),
				"visible": {"channel": "swim_amount", "scale": 2.0, "min": 1}, "scale_by": {"channel": "swim_amount", "min": 0.25}},
			{"name": "rotor", "group": "rotor", "sprite_ids": ["fx.hull"], "flags": 0, "corners": _quad(8.0, 6.0)}],
		"rigs": {"tip": {"channel": "gun_elev_deg", "rotate": {"axis": "x", "scale": -1.0},
			"base": [[0.0, -4.0, 0.0], [0.0, -6.0, 0.0]], "offset": [0.0, -1.0, 6.0]}},
		"groups": {"turret": {"rotate": [{"axis": "y", "channel": "turret_deg", "scale": -1.0}]},
			"rotor": {"rotate": [{"axis": "y", "channel": "rotor_speed_steps", "rate": 22.5, "scale": -1.0}]}},
		"body": {"rotate": [{"axis": "z", "channel": "bank_deg", "scale": 1.0}]}}
	PackWriter.write_json(mod.path_join("vehicles/rendmod.gizmo/vehicle.json"), def)

	var pack := Pack.new()
	_check(pack.load_from(mod), "the mod loads over the fixture")
	var t := pack.vehicle_index("rendmod.gizmo")
	_check(VehicleRender3D.channels_used(pack.vehicle_def(t)["render"]).size() >= 6, "channels_used lists what the descriptor binds: %s" % [VehicleRender3D.channels_used(pack.vehicle_def(t)["render"])])

	var v := Vehicle.new()
	v.team = "tan"
	v.setup(pack)
	v.set_vehicle_type(t)
	var r := VehicleRender3D.new()
	get_root().add_child(r)
	r.setup(v, pack)
	_check(r._parts.size() == 6 and r._groups.size() == 2, "six parts, two groups")

	v.turret_deg = 90.0
	r._process(0.0)
	_check(is_equal_approx(r._groups["turret"]["node"].rotation_degrees.y, -90.0), "a group turns by channel * scale")

	var barrel := _part(r, "barrel")
	_check(_near(r._corners(barrel["data"], {})[0], Vector3(0.0, -5.0, 6.0)), "a rig point at channel 0 is base + offset")
	v.gun_elev_deg = 30.0
	var raised: Vector3 = r._corners(barrel["data"], {})[0]
	_check(raised.z > 6.0 and is_equal_approx(raised.x, 0.0), "raising the channel turns the rig's points about the lateral axis (%s)" % raised)

	var wheel := _part(r, "wheel")
	for x in [0.2, 1.5, 2.9, 3.1, -0.5]:
		v.position.x = x
		var want: String = ["fx.wheel", "fx.hull", "fx.turret"][posmod(floori(x), 3)]
		_check(r._sprite_id(wheel["data"]) == want, "sprites_by wraps: x = %s picks %s" % [x, want])
	v.swim_amount = 0.0
	_check(_near(r._corners(wheel["data"], {})[0], Vector3(-2.0, -2.0, 0.5)), "corners_by: index 0 below the scaled threshold")
	v.swim_amount = 0.5
	_check(_near(r._corners(wheel["data"], {})[0], Vector3(-3.0, -3.0, 0.25)), "corners_by: index 1 once channel * scale reaches 1")

	var ring := _part(r, "ring")
	v.swim_amount = 0.4
	r._process(0.0)
	_check(not ring["mesh"].visible, "visible: hidden below its min")
	v.swim_amount = 0.5
	r._process(0.0)
	_check(ring["mesh"].visible and _near(r._corners(ring["data"], {})[0], Vector3(-3.0, -3.0, 0.0)), "shown from its min, scale_by halving x and y")

	v.rotor_speed_steps = 4.0
	r._process(1.0 / Vehicle.TICK_HZ)
	r._process(1.0 / Vehicle.TICK_HZ)
	_check(is_equal_approx(r._groups["rotor"]["node"].rotation_degrees.y, -180.0), "a rate group accumulates rate * channel a tick (2 ticks at 4: 180)")

	v.bank_steps = 2.0
	r._process(0.0)
	_check(is_equal_approx(r.rotation_degrees.z, v.channel("bank_deg")) and r.rotation_degrees.z != 0.0, "the body turns with its channel")

	r.free()
	v.free()
	print("render_descriptor_check: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)
