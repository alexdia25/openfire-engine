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
var _parts: Array = []          ## per part: {mesh: MeshInstance3D, data: Dictionary, sprite_id: String}
var _type := 0                  ## the type this renderer was built for; the vehicle may be swapped under it
var _ring: MeshInstance3D            ## the Jeep's swim-mode wheels (part 11)
var _ring_mat: StandardMaterial3D
var _flash := false               ## drawn in variant 2 (the hit flash)
var _anim_key: Variant = null   ## last animation state drawn (rebuild the animated parts only when it changes)


func setup(v: Vehicle, pack: Pack) -> void:
	vehicle = v
	_pack = pack
	_type = v.vehicle_type
	v.visible = false  # logic only, like the box renderer
	var t: Dictionary = pack.vehicle_types.get(str(v.vehicle_type), {})
	var variant := v.player_index()
	for part in t.get("parts", []):
		var ids: Array = part["sprite_ids"]
		var s := pack.get_sprite(ids[clampi(variant, 0, ids.size() - 1)])
		if s.is_empty():
			_parts.append({})
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
		_parts.append({"mesh": mi, "mat": mat})
	if v.vehicle_type == 3:
		_build_heli_extras()
	_follow()


func _process(delta: float) -> void:
	_follow()
	_animate()
	if _type == 3 and _rotor != null:
		_animate_heli(delta)


## The Heli's rotor (documents 63, 79). A LIVE Heli has no shadow: the only code that creates a shadow object for it is its dying handler
## (document 63, "Shadows"), so none is drawn here; it belongs with the dying sequence. The rotor is the object the Heli descriptor's next-link points at
## (0x440708): two halves of a blade bar, cel 584 + team and cel 580 + team, each a quad over corners set 3 (0x4405a0:
## x +-13.6, y 0..-27.2 and 0..27.2, z 10), turning about the vertical axis by `vehicle.rotor_speed_steps` steps of 5.625 degrees a tick (state +0x80
## grows by state +0x84): 4.0 at full speed, ramped up from 0 during the start-up (document 79).
##
## **User-flagged (2026-09-22): "different textures used when the helicopter is in full flight, we
## aren't using those here."** Document 63's own init callback (`0x403350`) picks a MODE from the
## rotor speed before choosing which corner set (blade width) to draw: `whole(speed) - 1` clamped to
## 0-3, or **mode 4 while the start-up value (state+0x58, `Vehicle._heli_spinup_progress`) is below
## 1** -- exactly `Vehicle.heli_spinup_stage == 1`, document 79's ~56-tick silent phase, before the
## rotor visibly starts spinning at all. Modes 0-3 are the same two-half-bar quad at increasing half-
## widths (3.4/3.4/6.8/13.6 -- document 63's "6.8/13.6/27.2 wide" halved for a +-x extent); this file
## used to always draw at the mode-3 (full-flight) width, correct only once `rotor_speed_steps`
## reaches 4.0. Mode 4 is a wholly different, single, non-spinning blade (cel 588, "rotor.c",
## `0x4406c0`) -- a real, separate, previously-unrendered asset, not a width variant. So a freshly
## spawned or just-undocked Heli was showing the full spinning blur from tick 0, where the original
## shows this static blade for ~56 ticks, then widens the blur through the ~160-tick ramp
## (document 79) before finally matching what this file already drew.
const ROTOR_HALF_WIDTHS := [3.4, 3.4, 6.8, 13.6]  ## modes 0-3, document 63
const ROTOR_FOLDED_CORNERS := [[3.4, 1.7, 10.0], [3.4, -25.5, 10.0], [-3.4, -25.5, 10.0], [-3.4, 1.7, 10.0]]  ## mode 4, cel 588 (0x4406c0)
var _rotor: Node3D
var _rotor_deg := 0.0
var _rotor_mode := -1  ## -1 = not yet built; 4 = the folded, non-spinning single blade


func _build_heli_extras() -> void:
	_rotor = Node3D.new()
	add_child(_rotor)
	_update_heli_rotor_mode()


func _heli_rotor_mode() -> int:
	if vehicle.heli_spinup_stage == 1:
		return 4
	return clampi(int(floorf(vehicle.rotor_speed_steps)) - 1, 0, 3)


func _update_heli_rotor_mode() -> void:
	var mode := _heli_rotor_mode()
	if mode == _rotor_mode:
		return
	_rotor_mode = mode
	for c in _rotor.get_children():
		c.queue_free()
	var team := "green" if vehicle.player_index() == 1 else "tan"
	var quads: Array
	if mode == 4:
		quads = [["vehicle.heli.rotor.c", ROTOR_FOLDED_CORNERS]]
	else:
		var w: float = ROTOR_HALF_WIDTHS[mode]
		quads = [
			["vehicle.heli.rotor.b." + team, [[w, 0.0, 10.0], [w, -27.2, 10.0], [-w, -27.2, 10.0], [-w, 0.0, 10.0]]],
			["vehicle.heli.rotor.a." + team, [[w, 27.2, 10.0], [w, 0.0, 10.0], [-w, 0.0, 10.0], [-w, 27.2, 10.0]]],
		]
	for h in quads:
		var s := _pack.get_sprite(String(h[0]))
		if s.is_empty():
			continue
		var tex := _pack.get_texture(int(s.get("page", 0)))
		var mi := MeshInstance3D.new()
		mi.mesh = _quad(h[1], s, tex)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.albedo_texture = tex
		mi.material_override = mat
		_rotor.add_child(mi)


func _animate_heli(delta: float) -> void:
	_update_heli_rotor_mode()
	if _rotor_mode == 4:
		return  # mode 4 is the static, non-spinning blade -- document 63
	_rotor_deg = fposmod(_rotor_deg + vehicle.rotor_speed_steps * 5.625 * delta * Vehicle.TICK_HZ, 360.0)
	_rotor.rotation_degrees.y = -_rotor_deg


## Per-tick part animation, read from the type's draw callbacks (document 59). Only what the callbacks do to the
## part list is reproduced; parts not named here are static.
func _animate() -> void:
	if vehicle == null or not is_instance_valid(vehicle) or vehicle.vehicle_type != _type:
		return  # a type swap frees this renderer (terrain_view_3d._on_player_type_changed) a frame later
	if vehicle.flashing() != _flash:
		_flash = vehicle.flashing()
		_redraw_team_parts()
	if vehicle.vehicle_type == 1:
		# FUN_00402fc0: the wheel-strip parts 9 and 10 (cel 457) are drawn as cel 457 + ((obj+0x40 & 0x30000) >> 16),
		# obj+0x40 being the object's x position in 16.16: the frame is the integer x (world units) modulo 4, so
		# the strip steps once per unit driven along x and (as coded) does not move for travel along y alone.
		var frame := int(floorf(vehicle.position.x)) & 3
		# swim mode (document 62): the row of the table picked by whole(immersion * 8) reshapes the wheel strips, and
		# from row 4 on a square of four wheels (part 11) shows underneath, its size following the immersion
		var row := mini(int(floorf(vehicle.swim_amount * 8.0 + 0.0001)), 8)
		var ring := maxf(vehicle.swim_amount, 0.25) if row > 3 else 0.0
		var key := [frame, row, snappedf(ring, 0.01)]
		if key != _anim_key:
			_anim_key = key
			var swim: Dictionary = _pack.vehicle_types.get("1", {}).get("swim", {})
			var r: Array = swim.get("rows", [[4.5, 8.0, 4.5, 0.0]])[row]
			var a: float = r[0]
			var c: float = r[1]
			var d: float = r[2]
			var f: float = r[3]
			var sid := "vehicle.jeep.p457.frame_%02d" % (frame + 1)
			_set_part_sprite(9, sid, [[-a, -12.0, c], [-a, 12.0, c], [-d, 12.0, f], [-d, -12.0, f]])
			_set_part_sprite(10, sid, [[a, 12.0, c], [a, -12.0, c], [d, -12.0, f], [d, 12.0, f]])
			_update_ring(ring, swim)
	elif vehicle.vehicle_type == 2:
		# FUN_00402ec0: the canister part 13 is cel 326 minus the rockets fired in the current salvo (326, 325,
		# 324: three, two, one canisters), and while the launcher reloads (state+0x58 runs -6.0 -> 0 at 0.15 per
		# tick, FUN_0040d790) its two front corners (48, 49) slide: y = 11.25 - 6 + 6 * remaining / 40.
		var fired: int = vehicle.salvo_index()
		var slide: float = 6.0 * vehicle.salvo_reload_remaining() / 40.0
		var elev := snappedf(vehicle.gun_elev_deg, 0.1)
		var key := [fired, roundf(slide * 8.0), elev]
		if key != _anim_key:
			_anim_key = key
			var rack: Dictionary = _pack.vehicle_types.get("2", {}).get("rack", {})
			if rack.is_empty():
				return
			# corners 44-51 = R(elevation) * base + (0, 6, 12); base y of corners 4 and 5 is -6 - n while reloading
			var a := deg_to_rad(-elev)
			var pts: Array = []
			var off: Array = rack["offset"]
			for i in 8:
				var b: Array = (rack["base"] as Array)[i].duplicate()
				if i == 4 or i == 5:
					b[1] = -6.0 + slide
				var y: float = b[1] * cos(a) - b[2] * sin(a)
				var zz: float = b[1] * sin(a) + b[2] * cos(a)
				pts.append([b[0] + off[0], y + off[1], zz + off[2]])
			_set_part_sprite(2, _msv_plate_sprite(), [pts[0], pts[1], pts[2], pts[3]])
			_set_part_sprite(13, "vehicle.msv.p324.canisters_%d" % (3 - fired), [pts[5], pts[4], pts[7], pts[6]])


## Redraws every flag-8 part in the current variant: the team's, or variant 2 while the hit flash lasts
## (FUN_00402d20 sets the draw variant to 2 while the hit time is in the future).
func _redraw_team_parts() -> void:
	var t: Dictionary = _pack.vehicle_types.get(str(vehicle.vehicle_type), {})
	var parts: Array = t.get("parts", [])
	for i in parts.size():
		var part: Dictionary = parts[i]
		if _parts[i].is_empty() or not (int(part["flags"]) & 8):
			continue
		var ids: Array = part["sprite_ids"]
		var v := 2 if _flash else vehicle.player_index()
		_set_part_sprite(i, String(ids[clampi(v, 0, ids.size() - 1)]), null)


func _msv_plate_sprite() -> String:
	var t: Dictionary = _pack.vehicle_types.get("2", {})
	var ids: Array = t["parts"][2]["sprite_ids"]
	var v := 2 if _flash else vehicle.player_index()
	return String(ids[clampi(v, 0, ids.size() - 1)])


func _update_ring(scale: float, swim: Dictionary) -> void:
	if _ring == null:
		_ring = MeshInstance3D.new()
		_ring_mat = StandardMaterial3D.new()
		_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ring_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		_ring.material_override = _ring_mat
		add_child(_ring)
	_ring.visible = scale > 0.0
	if scale <= 0.0:
		return
	var s := _pack.get_sprite(String(swim.get("ring_sprite", "")))
	if s.is_empty():
		return
	var tex := _pack.get_texture(int(s.get("page", 0)))
	var h: float = float(swim.get("ring_half", 12.0)) * scale
	_ring.mesh = _quad([[h, -h, 0.0], [h, h, 0.0], [-h, h, 0.0], [-h, -h, 0.0]], s, tex)
	_ring_mat.albedo_texture = tex


func _set_part_sprite(index: int, sprite_id: String, corners: Variant) -> void:
	if index >= _parts.size() or _parts[index].is_empty():
		return
	var s := _pack.get_sprite(sprite_id)
	if s.is_empty():
		return
	var tex := _pack.get_texture(int(s.get("page", 0)))
	var t: Dictionary = _pack.vehicle_types.get(str(vehicle.vehicle_type), {})
	var c: Array = corners if corners != null else t["parts"][index]["corners"]
	_parts[index]["mesh"].mesh = _quad(c, s, tex)
	_parts[index]["mat"].albedo_texture = tex


func _follow() -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	visible = vehicle.alive and not vehicle.docked
	position = Vector3(vehicle.position.x, GROUND_CLEARANCE_PX + vehicle.z, vehicle.position.y)
	rotation_degrees.y = -90.0 - vehicle.heading_deg
	if vehicle.vehicle_type == 3:
		# the whole Heli tilts with its pitch and bank (FUN_0041b590; document 63)
		rotation_degrees.x = -vehicle.pitch_deg()
		rotation_degrees.z = vehicle.bank_deg()
	else:
		rotation_degrees.x = 0.0
		rotation_degrees.z = 0.0


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
