class_name Wreck3D
extends Node3D
## What a destroyed vehicle leaves behind (documents 48, 87). TRACED: on death the vehicle class
## (0x445438) spawns a wreck object (class 0x4453e8) that eventually shows the type record's
## `+0x164` descriptor -- for the Tank/Jeep/MSV three flat ground quads (a shadow plus two debris
## decals, identical geometry for all three, only the textures differ), for the Heli a single large
## decal (document 48's table; the MSV's own quads turned out to be the exact same size as the
## Tank/Jeep's despite the "large" registry name).
##
## Document 87 found the object's `+0x148` descriptor (drawn before landing, per the wreck's update
## FUN_0040c8f0) is the SAME cel set as the type's own live body -- a dying vehicle tumbles down
## showing its intact model, not a separate "wreck" sprite -- and that the Heli alone has a
## per-type hook (`+0x230`, `FUN_0040eae0`, spawning a real shadow object) run somewhere in the same
## sequence (re-checking document 63's own claim that this lived at `+0x234`: that address is
## always 0 for all four types -- `+0x234` is a second, generic "dying handler" slot that is also
## unused everywhere, and `+0x238` is a Heli-only per-hit *reaction* callback that jitters its lean
## and always returns 0, not a death override).
##
## **Contradiction found, not resolved:** FUN_0040c8f0 only runs its gravity/landing logic when the
## object's own move-function slot is non-zero; tracing where that slot is populated led back to
## the wreck class's own `+0x1c`, which reads as 0 -- implying the branch is dead and a fresh wreck
## would instead hit the "no mover" path (`FUN_0042c0f0`, which looks like generic immediate
## object teardown) on its first tick. That can't be right for an object that is supposed to persist
## on the ground, so a step in this chain is almost certainly mis-identified, but time did not allow
## re-deriving it. **Given that, the fall below is a reasonable, GUESSED interpolation** ("the wreck
## ends up on the ground where the vehicle died", the one fact that IS solid) using the project's
## already-traced ballistic gravity (`LOB_GRAVITY`, documents 52/61) and zero initial vertical
## speed, not a confirmed reproduction of the original's own timing. Flagged in NEXT_STEPS. Also not
## reproduced: the tumbling-body render during the fall, and the Heli's trailing shadow object.

const SHADOW_SIZE := 27.0
const DECAL_SIZE := 24.0
const SHADOW_ALPHA := 5.0 / 32.0

const TICK_HZ := 62.5
const GRAVITY := 1638.0 / 65536.0  ## reusing LOB_GRAVITY (documents 52/61) -- see the "Contradiction found" note above
var _vz := 0.0
var _height := 0.0
var _falling := false

## Tank and Jeep share a descriptor (`0x43ece8`/`0x440218`); the MSV's (`0x43f628`) traces to the
## same corner sizes, just its own cels. Keyed by `Vehicle.vehicle_type`.
const SETS := {
	0: {"shadow": "effect.shadow.hard.wreck_small", "a": {"tan": "vehicle.wreck.small.a.tan", "green": "vehicle.wreck.small.a.green"}, "b": {"tan": "vehicle.wreck.small.b.tan", "green": "vehicle.wreck.small.b.green"}},
	1: {"shadow": "effect.shadow.hard.wreck_small", "a": {"tan": "vehicle.wreck.small.a.tan", "green": "vehicle.wreck.small.a.green"}, "b": {"tan": "vehicle.wreck.small.b.tan", "green": "vehicle.wreck.small.b.green"}},
	2: {"shadow": "effect.shadow.hard.wreck_large", "a": {"tan": "vehicle.wreck.large.a.tan", "green": "vehicle.wreck.large.a.green"}, "b": {"tan": "vehicle.wreck.large.b.tan", "green": "vehicle.wreck.large.b.green"}},
}
## The Heli's single-part descriptor (`0x440fa0`) is not centred: its traced corners span
## x [-13.6, 13.6], y [-13.6, 40.8] (fixed16.16 / 65536) -- a 27.2 x 54.4 rectangle offset 13.6
## units off-centre, not a symmetric square like the other three types'.
const HELI_DECAL := {"tan": "vehicle.wreck.heli.tan", "green": "vehicle.wreck.heli.green"}
const HELI_HALF := Vector2(13.6, 27.2)
const HELI_CENTER := Vector2(0.0, 13.6)


func setup(pack: Pack, team: String, at: Vector2, heading_deg: float, vehicle_type: int = 0, start_height: float = 0.0) -> void:
	position = Vector3(at.x, 0.0, at.y)  # local, not global (matches VehicleRender3D's own convention): stays correct when parented at the scene root, and testable outside a full 3D viewport
	rotation_degrees.y = -heading_deg
	_height = start_height
	_falling = start_height > 0.0
	if vehicle_type == 3:
		_add_quad(pack, HELI_DECAL.get(team, HELI_DECAL["tan"]), 0.4, false, HELI_HALF, HELI_CENTER)
	else:
		var s: Dictionary = SETS.get(vehicle_type, SETS[0])
		_add_quad(pack, s["shadow"], 0.4, true, Vector2(SHADOW_SIZE, SHADOW_SIZE) * 0.5)
		_add_quad(pack, s["a"].get(team, s["a"]["tan"]), 0.6, false, Vector2(DECAL_SIZE, DECAL_SIZE) * 0.5)
		_add_quad(pack, s["b"].get(team, s["b"]["tan"]), 2.6, false, Vector2(DECAL_SIZE, DECAL_SIZE) * 0.5)
	position.y = _height


func _process(delta: float) -> void:
	if not _falling:
		return
	var ticks := delta * TICK_HZ
	_vz -= GRAVITY * ticks
	_height += _vz * ticks
	if _height <= 0.0:
		_height = 0.0
		_falling = false
	position.y = _height


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
	add_child(mi)
