# The render descriptor's water views (issue alexdia25/openfire#25, openfire document 123), with no game's vehicles: a synthetic vehicle whose descriptor has a
# hull, a spray part drawn only while wading, and two sinking parts (with the sprite picked by the depth, the player's colour and a depth limit) that replace the
# hull while it sinks -- plus the vehicle's own water state: the view channel, the splash counter's frame, the Jeep-style swim spray remap and the poses the mod
# tool uses. Run (see tests/README.md):
#   godot --headless --path .harness --script res://addons/openfire_engine/tests/water_modes_check.gd
extends SceneTree

const Fixture := preload("fixtures/synthetic_pack.gd")

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


static func _quad(z: float, h := 2.0) -> Array:
	return [[-h, -h, z], [h, -h, z], [h, h, z], [-h, h, z]]


func _shown(r: VehicleRender3D) -> Array:
	var out: Array = []
	r._update_parts()
	for p in r._parts:
		if p["mesh"].visible and p["mesh"].mesh != null:
			out.append(String(p["data"]["name"]))
	return out


func _init() -> void:
	var base_dir := Fixture.build("user://packs")
	var mod := ProjectSettings.globalize_path("user://water_modes_check/mod")
	if DirAccess.dir_exists_absolute(mod):
		OS.move_to_trash(mod)
	PackWriter.write_json(mod.path_join("pack.json"), {"id": "watermod", "name": "water modes test", "base_pack": Fixture.ID})
	var def := Fixture.vehicle_def("watermod.boat", "Boat", 9)
	var ids := ["fx.hull", "fx.turret", "fx.wheel", "fx.tile", "fx.hull", "fx.turret"]
	def["render"] = {
		"parts": [
			{"name": "hull", "sprite_ids": ["fx.hull"], "flags": 0, "corners": _quad(1.0, 4.0)},
			{"name": "spray", "modes": [1], "sprite_ids": ["fx.wheel"], "flags": 0, "corners": _quad(0.0, 3.0),
				"sprites_by": {"channel": "wade_frame", "max": 2, "sprites": ["fx.wheel", "fx.tile", "fx.hull"]}},
			{"name": "swim spray", "modes": [3], "sprite_ids": ["fx.wheel"], "flags": 0, "corners": _quad(0.0, 3.0),
				"sprites_by": {"channel": "wade_swim_frame", "max": 2, "sprites": ["fx.wheel", "fx.tile", "fx.hull"]}},
			{"name": "sunk", "modes": [2], "sprite_ids": ["fx.hull"], "flags": 0, "corners": _quad(2.0, 4.0),
				"sprites_by": {"channel": "sink_frame", "sprites": ids, "team_stride": 3, "hide_outside": 3}},
			{"name": "ripple", "modes": [2], "sprite_ids": ["fx.tile"], "flags": 0, "corners": _quad(0.0, 6.0),
				"sprites_by": {"channel": "ripple_frame", "max": 1, "sprites": ["fx.tile", "fx.wheel"]}}],
		"mode_channel": "water_view", "replaced_in": [2], "ripple": {"frames": [0, 0, 1, 1], "clock_mask": 6}}
	PackWriter.write_json(mod.path_join("vehicles/watermod.boat/vehicle.json"), def)

	var pack := Pack.new()
	_check(pack.load_from(mod), "the mod loads over the fixture")
	var t := pack.vehicle_index("watermod.boat")
	var used := VehicleRender3D.channels_used(pack.vehicle_def(t)["render"])
	_check(used.has("wade_counter") and used.has("z") and used.has("water_pose"), "channels_used lists the poseable drivers of the water channels: %s" % [used])

	var v := Vehicle.new()
	v.team = "tan"
	v.setup(pack)
	v.set_vehicle_type(t)
	var r := VehicleRender3D.new()
	get_root().add_child(r)
	r.setup(v, pack)
	_check(v.ripple_table.size() == 4 and int(v.ripple_table[2]) == 1 and v.ripple_mask == 6, "the renderer hands the vehicle the descriptor's ripple table")

	_check(v.water_view() == 0 and _shown(r) == ["hull"], "dry: the hull alone")
	v.wading = true
	v.wade_counter = 4.0
	_check(v.water_view() == 1 and _shown(r) == ["hull", "spray"], "wading: the hull and the spray")
	_check(r._sprite_id(r._parts[1]["data"]) == "fx.hull", "the spray's frame is the counter's integer part, clamped to the table (4 -> the last)")
	v.wade_counter = 1.7
	_check(r._sprite_id(r._parts[1]["data"]) == "fx.tile", "...1.7 -> frame 1")

	v.wade_counter = 6.0
	_check(v.wade_swim_frame() == 7, "the swim spray frame above 4: 4 + 1.5 * (6 - 4)")
	v.wade_counter = 10.0
	_check(v.wade_swim_frame() == 13, "...and from 8: 10 + 1.6 * (10 - 8)")
	v.wade_counter = 13.0
	_check(v.wade_swim_frame() == 17, "...capped at 17")

	v.wading = false
	v._sinking = true
	v.z = -1.4
	_check(v.water_view() == 2 and v.channel("sink_frame") == 2.0, "sinking: the depth is -floor(z): z = -1.4 -> 2")
	_check(_shown(r) == ["sunk", "ripple"], "sinking: the hull is replaced by the sinking part and the ripple")
	_check(r._sprite_id(r._parts[3]["data"]) == "fx.wheel", "the sinking picture is the one for that depth (index 2 of the tan set)")
	v.team = "green"
	_check(r._sprite_id(r._parts[3]["data"]) == "fx.turret", "...and for the other player the second set (index 2 + the stride 3 = 5)")
	v.z = -3.2
	_check(r._sprite_id(r._parts[3]["data"]) == "" and _shown(r) == ["ripple"], "past the depth limit nothing is drawn but the ripple")
	v.z = 0.0
	_check(_shown(r) == ["sunk", "ripple"], "depth 0 draws the first picture")

	# the poses the mod tool uses
	v._sinking = false
	v.set_channel("water_pose", 1.0)
	_check(v.wading and not v._sinking and v.wade_counter >= 4.0 and v.channel("water_pose") == 1.0, "pose 1: wading with a counter")
	v.set_channel("water_pose", 2.0)
	_check(v._sinking and not v.wading and v.water_view() == 2, "pose 2: sinking")
	v.set_channel("water_pose", 0.0)
	_check(v.water_view() == 0 and _shown(r) == ["hull"], "pose 0: dry again")

	r.free()
	v.free()
	print("water_modes_check: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)
