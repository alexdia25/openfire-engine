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
	_follow()


func _process(_delta: float) -> void:
	_follow()
	_animate()


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
		if frame != _anim_key:
			_anim_key = frame
			for i in [9, 10]:
				_set_part_sprite(i, "vehicle.jeep.p457.frame_%02d" % (frame + 1), null)
	elif vehicle.vehicle_type == 2:
		# FUN_00402ec0: the canister part 13 is cel 326 minus the rockets fired in the current salvo (326, 325,
		# 324: three, two, one canisters), and while the launcher reloads (state+0x58 runs -6.0 -> 0 at 0.15 per
		# tick, FUN_0040d790) its two front corners (48, 49) slide: y = 11.25 - 6 + 6 * remaining / 40.
		var fired: int = vehicle.salvo_index()
		var slide: float = 6.0 * vehicle.salvo_reload_remaining() / 40.0
		var key := [fired, roundf(slide * 8.0)]
		if key != _anim_key:
			_anim_key = key
			var y := 5.25 + slide
			var t: Dictionary = _pack.vehicle_types.get("2", {})
			var corners: Array = (t["parts"][13]["corners"] as Array).duplicate(true)
			corners[0][1] = y   # corner 49
			corners[1][1] = y   # corner 48
			_set_part_sprite(13, "vehicle.msv.p324.canisters_%d" % (3 - fired), corners)


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
