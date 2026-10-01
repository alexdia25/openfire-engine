# Coplanar parts (document 102): a descriptor part lying in the plane of an earlier part that covers it would z-fight
# with it, so the renderer draws it over by a small outward shift instead of a depth tie. CoplanarParts finds such
# pairs; VehicleRender3D shifts exactly the covered part, outward. On a synthetic vehicle (a strip on a side panel, a
# tilted strip, a part elsewhere). Whether Return Fire's own vehicles need it stays openfire's check
# (tank_coplanar_check, vehicle_coplanar_check). Moved from openfire's tools/tests (issue alexdia25/openfire#65). Run:
#   godot --headless --path .harness --script res://addons/openfire_engine/tests/coplanar_parts_check.gd
extends SceneTree

const Fixture := preload("fixtures/synthetic_pack.gd")

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _init() -> void:
	# the helper on its own: a strip inside a panel in one plane is found, a tilted one is not
	var panel := [Vector3(0, 13, -12), Vector3(0, 13, 12), Vector3(0, 0, 12), Vector3(0, 0, -12)]
	var strip := [Vector3(0, 8, -12), Vector3(0, 8, 12), Vector3(0, 0, 12), Vector3(0, 0, -12)]
	var tilted := [Vector3(0.5, 8, -12), Vector3(0.5, 8, 12), Vector3(0, 0, 12), Vector3(0, 0, -12)]
	_check(CoplanarParts.covered_pairs([panel, strip]) == [[0, 1]], "a strip inside a panel, in one plane, is a covered pair")
	_check(CoplanarParts.covered_pairs([panel, tilted]).is_empty(), "a tilted strip is not")

	# the renderer: a vehicle whose left side panel carries a strip in its own plane (x = -4), like a wheel strip
	Fixture.build("user://packs")
	var mod := ProjectSettings.globalize_path("user://coplanar_parts_check/mod")
	if DirAccess.dir_exists_absolute(mod):
		OS.move_to_trash(mod)
	PackWriter.write_json(mod.path_join("pack.json"), {"id": "copmod", "name": "coplanar test", "base_pack": Fixture.ID})
	var def := Fixture.vehicle_def("copmod.box", "Box", 9)
	def["render"] = {"parts": [
		{"sprite_ids": ["fx.hull"], "flags": 0, "corners": [[-4.0, -6.0, 6.0], [-4.0, 6.0, 6.0], [-4.0, 6.0, 0.0], [-4.0, -6.0, 0.0]]},
		{"sprite_ids": ["fx.wheel"], "flags": 0, "corners": [[-4.0, -5.0, 3.0], [-4.0, 5.0, 3.0], [-4.0, 5.0, 0.0], [-4.0, -5.0, 0.0]]},
		{"sprite_ids": ["fx.turret"], "flags": 0, "corners": [[-2.0, -2.0, 7.0], [2.0, -2.0, 7.0], [2.0, 2.0, 7.0], [-2.0, 2.0, 7.0]]}]}
	PackWriter.write_json(mod.path_join("vehicles/copmod.box/vehicle.json"), def)
	var pack := Pack.new()
	_check(pack.load_from(mod), "the mod loads")
	var v := Vehicle.new()
	v.team = "tan"
	v.setup(pack)
	v.set_vehicle_type(pack.vehicle_index("copmod.box"))
	var r := VehicleRender3D.new()
	get_root().add_child(r)
	r.setup(v, pack)
	var s: Array = r._coplanar_shifts()
	_check(s[1].x < -0.01 and absf(s[1].y) < 1e-6 and absf(s[1].z) < 1e-6, "the strip is shifted outward (-x) off its panel: %s" % s[1])
	_check(s[0] == Vector3.ZERO and s[2] == Vector3.ZERO, "the panel and the unrelated part stay put")
	_check(absf(s[1].x) < 0.1 and absf(s[1].x) > 0.005, "the shift is far under a pixel but above the depth resolution")
	r.free()
	v.free()

	print("coplanar_parts_check: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)
