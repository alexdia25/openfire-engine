class_name DockReadyIndicator3D
extends Node3D
## The original's own "you're in position to dock" signal (document 80): `FUN_0040b400`, called once a tick only while a vehicle sits still on its
## own pad within the docking tolerance and is NOT pressing a fire button, rotates seven colour words of the shared palette (entries 12-14, plus two
## bytes of entry 15) at a fixed rate (0x2666/65536 a tick, ~6.83 ticks a step, about 9.1 steps a second) -- traced down to the exact instructions
## and independently reproduced in Python (a genuine, deterministic 7-step colour cycle). BUT: pixel-by-pixel inspection of cel 90/91's own raw
## indexed art (document 80) found it uses NONE of those palette entries anywhere in its 32 x 32 bitmap -- so this animation does NOT touch the
## hatch's own colours, and what it actually changes on screen (some other, unidentified sprite that happens to share those low palette entries) is
## NOT KNOWN. This node is therefore a full INVENTION standing in for an effect whose trigger and cadence are real but whose visible target is not:
## a border around the home pad, shown only while `MatchController.can_dock` is true, cycling a made-up hazard-light palette at the traced cadence.
## Neither the ring shape nor its colours are the original's.

const STEP_TICKS := 65536.0 / 0x2666   ## ~6.83 ticks a step, from FUN_0040b400's accumulator rate
const COLOURS := [
	Color(1.0, 0.85, 0.0), Color(1.0, 0.6, 0.0), Color(1.0, 0.3, 0.0),
	Color(1.0, 0.85, 0.0), Color(1.0, 1.0, 1.0), Color(0.1, 0.1, 0.1), Color(1.0, 0.85, 0.0),
]

var mc: MatchController
var _ring: MeshInstance3D
var _mat: StandardMaterial3D
var _acc := 0.0
var _step := 0


func setup(controller: MatchController, pack: Pack) -> void:
	mc = controller
	var tsz := float(pack.tile_size_px)
	var half := tsz * 0.5
	var thick := 4.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outer := half + 2.0
	var inner := outer - thick
	var corners_outer := [Vector3(-outer, 0, -outer), Vector3(outer, 0, -outer), Vector3(outer, 0, outer), Vector3(-outer, 0, outer)]
	var corners_inner := [Vector3(-inner, 0, -inner), Vector3(inner, 0, -inner), Vector3(inner, 0, inner), Vector3(-inner, 0, inner)]
	for i in 4:
		var j := (i + 1) % 4
		var quad := [corners_outer[i], corners_outer[j], corners_inner[j], corners_inner[i]]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(quad[idx])
	_ring = MeshInstance3D.new()
	_ring.mesh = st.commit()
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_ring.material_override = _mat
	add_child(_ring)
	position = Vector3(mc.home_position().x, 1.2, mc.home_position().y)
	_ring.visible = false


func _process(delta: float) -> void:
	var ready := mc.vehicle != null and mc.can_dock(mc.vehicle)
	_ring.visible = ready
	if not ready:
		_acc = 0.0
		_step = 0
		return
	_acc += delta * Vehicle.TICK_HZ
	while _acc >= STEP_TICKS:
		_acc -= STEP_TICKS
		_step = (_step + 1) % COLOURS.size()
	_mat.albedo_color = COLOURS[_step]
