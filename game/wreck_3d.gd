class_name Wreck3D
extends Node3D
## Draws a Wreck (game/wreck.gd; documents 48, 87, 118): the dying vehicle's own body while the wreck object is in its first phase, then the flat
## decal the type record's `+0x164` names.
##  - TRACED: the wreck object is created with the descriptor `+0x148` of the vehicle type record (FUN_0040c7e0), and that is the SAME cel set as the
##    live body (the Tank's 14 parts, cels 167-212, turret and barrel included, in their rest pose; the Heli's 12 parts, cels 524-574, without the rotor).
##    So a vehicle that dies falls and slides as its intact self. NOT tilted: the body's init callback (the Heli's FUN_004034c0, the Tank's FUN_00402d20)
##    reads the nose pitch (obj +0x70) and the bank (state +0x88) only for a live vehicle (class 1); for a wreck (class 6) both are 0, so the dying Heli is flat.
##  - After 8 ticks FUN_0040cca0 swaps the descriptor to `+0x160`: for the Tank, Jeep and MSV the decal itself (three flat ground quads: a shadow plus
##    two debris decals, identical geometry, only the textures differ), for the Heli (0x440bd0, not decoded) something else, so the Heli keeps its
##    body until it lands. A vehicle that ran out of fuel keeps its body (`+0x148`) there.
##  - Landing (FUN_0040c8f0) swaps to `+0x164`: the same decal for the ground types, for the Heli a single large decal (cel 606, a 27.2 x 54.4 unit
##    rectangle 13.6 units off-centre, not a symmetric square).
## The decal stays: a settled decal wreck becomes a `Stay` mark (FUN_0040ad10) that the original removes only after it has been out of sight for 720 ticks.

const SHADOW_ALPHA := 5.0 / 32.0

var wreck: Wreck
var _decal: Node3D
var _ghost: Vehicle
var _body: VehicleRender3D

## The quads drawn are the vehicle definition's `wreck.quads` (sprites [tan, green], height, half-size, centre, shadow):
## Tank and Jeep share a descriptor (`0x43ece8`/`0x440218`); the MSV's (`0x43f628`) traces to the same corner sizes, just
## its own cels; the Heli's single-part descriptor (`0x440fa0`) is not centred -- its traced corners span x [-13.6, 13.6],
## y [-13.6, 40.8], a 27.2 x 54.4 rectangle 13.6 units off-centre. Built by tools/build_pack.py (WRECKS).


func setup(pack: Pack, w: Wreck) -> void:
	wreck = w
	var colour := w.colour if w.colour != "" else w.team
	_decal = Node3D.new()
	add_child(_decal)
	for q in pack.vehicle_value(w.vehicle_type, "wreck.quads", []):
		var half: Array = q.get("half", [12, 12])
		var centre: Array = q.get("center", [0, 0])
		_add_quad(pack, pack.team_variant(q["sprites"], colour), float(q.get("height", 0.6)), bool(q.get("shadow", false)),
				Vector2(float(half[0]), float(half[1])), Vector2(float(centre[0]), float(centre[1])))
	if pack.vehicle_def(w.vehicle_type).get("render", {}).has("parts"):
		_ghost = Vehicle.new()
		_ghost.vehicle_type = w.vehicle_type
		_ghost.team = w.team
		_ghost.colour = colour
		_ghost.announce_created = false
		_ghost.setup(pack)
		# no nose pitch and no bank: the body's init callback reads them for a live vehicle only (FUN_004034c0), so the ghost's speed stays 0
		_body = VehicleRender3D.new()
		_body.hidden_groups = pack.vehicle_value(w.vehicle_type, "wreck.body_hidden_groups", [])
		add_child(_body)
		_body.setup(_ghost, pack)
	_sync()


func _sync() -> void:
	if _ghost != null:
		_ghost.position = wreck.position
		_ghost.heading_deg = wreck.heading_deg
		_ghost.z = wreck.height()
	var decal := wreck.phase == Wreck.Phase.DECAL or _ghost == null
	_decal.visible = decal
	if _ghost != null:
		_ghost.alive = not decal   # VehicleRender3D shows itself while its vehicle is alive
	_decal.position = Vector3(wreck.position.x, wreck.height(), wreck.position.y)
	_decal.rotation_degrees.y = -wreck.heading_deg


func _process(_delta: float) -> void:
	if wreck == null:
		return
	if wreck.finished and not wreck.mark:
		queue_free()
		return
	_sync()


func _exit_tree() -> void:
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.free()


func _add_quad(pack: Pack, sprite_id: String, y: float, is_shadow: bool, half: Vector2, center: Vector2 = Vector2.ZERO) -> void:
	var s := pack.get_sprite(sprite_id)
	if s.is_empty():
		return
	var tex := pack.get_texture(int(s.get("page", 0)))
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var u0: float = float(s["x"]) / tw
	var v0: float = float(s["y"]) / th
	var u1: float = (float(s["x"]) + float(s["w"])) / tw
	var v1: float = (float(s["y"]) + float(s["h"])) / th
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Corner order matches the descriptor: (-x,-z), (+x,-z), (+x,+z), (-x,+z) -> cel TL, TR, BR, BL.
	var c := [Vector3(center.x - half.x, y, center.y - half.y), Vector3(center.x + half.x, y, center.y - half.y),
			Vector3(center.x + half.x, y, center.y + half.y), Vector3(center.x - half.x, y, center.y + half.y)]
	var uv := [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]
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
	_decal.add_child(mi)
