class_name HangarPit3D
extends Node3D
## The home pad's pit and two-leaf lid (document 89), drawn while MatchController.pad_open (the pad tile is then the transparent art 92, a real hole in the ground).
## Every number below is read from the lift object's drawing descriptors, class `0x44db40` / `0x44db90` slot `+0x14` = `0x44dab0`, whose `+4` chain is the pit
## (`0x44dab0`, callback `0x42ebb0`), the vehicle (`0x44d8f8`, `0x42eae0`) and the leaves (`0x44d890`, `0x42ea10`):
##  - four pit walls, a 28 x 28 shaft from z 0 down to -31 (corners `0x44d940`, parts `0x44d9d0`: north `pit_wall.02`, west `.03`, east and south `.01`), and the 32 x 4
##    hazard strip along the front edge (part 4, corners 8-11);
##  - the plate under the vehicle, 32 x 30 (`0x44d8d8`, cel `0x33d`, flag 8 = team variant), which is at the OBJECT's height, so it rises and sinks with the vehicle;
##  - the two leaves, 16 x 31 each (corners `0x44d7d0`, cels `0x336` / `0x338`, flag 8), at z 0, `0.3 * age + 5` units either side of the centre
##    (MatchController.pad_leaf_offset), not drawn once `0.3 * age >= 18`.
## UNTRACED, port choices: object space is taken as the world's axes (the undock object's heading is 180 degrees and the original's rotation of the pit walls was not
## read), and whether the walls move with the object's height (here they are fixed at the ground: the physical reading). The hazard border and rim seen around the
## open pit in the footage are not identified (the strip above is only the front edge), and nothing is drawn between the walls and the tile's edge (a 2-unit ring).

const WALL_DEPTH := 31.0
const HALF := 14.0
const PAD_HALF := 16.0        ## the pad tile's half width: the leaves are cut off here (the mechanism is underground, nothing shows outside the original texture)
const LEAF_HALF_W := 8.0
## The leaves and the plate sit just BELOW the ground plane (y 0) so the tile's opaque hazard border (art 92, part of the ground texture) covers them where they reach the
## tile's edge, and only the hole in its centre shows them: they slide under the border. The plate stays under the leaves. Port choice (user direction), not traced.
const LEAF_Y := -0.1
const PLATE_MAX_Y := -0.15

var mc: MatchController
var pack: Pack
var _team := -1
var _plate: MeshInstance3D
var _leaf_left: MeshInstance3D
var _leaf_right: MeshInstance3D
var _leaf_ids: Array[String] = ["", ""]
var _leaf_off := -2.0
var _static: Array[MeshInstance3D] = []


func setup(controller: MatchController, shared_pack: Pack) -> void:
	mc = controller
	pack = shared_pack
	visible = false


func _process(_delta: float) -> void:
	if mc == null or not mc.pad_open or mc.vehicle == null:
		visible = false
		return
	var team := mc.vehicle.player_index()
	if team != _team:
		_build(team)
	var c := mc.pad_position()
	position = Vector3(c.x, 0.0, c.y)
	_plate.position.y = minf(mc.vehicle.z + 0.05, PLATE_MAX_Y)
	var off := mc.pad_leaf_offset()
	_leaf_left.visible = off >= 0.0
	_leaf_right.visible = off >= 0.0
	if off >= 0.0 and off != _leaf_off:
		_leaf_off = off
		_leaf_left.mesh = _leaf_mesh(_leaf_ids[0], -off)
		_leaf_right.mesh = _leaf_mesh(_leaf_ids[1], off)
	visible = true


func _build(team: int) -> void:
	_team = team
	for n in get_children():
		n.queue_free()
	var colour := mc.level.side_colour(team)   # PORTING_PLAN.md 2.7.7
	var c := [Vector3(-HALF, 0, -HALF), Vector3(HALF, 0, -HALF), Vector3(HALF, 0, HALF), Vector3(-HALF, 0, HALF),
			Vector3(-HALF, -WALL_DEPTH, -HALF), Vector3(HALF, -WALL_DEPTH, -HALF), Vector3(HALF, -WALL_DEPTH, HALF), Vector3(-HALF, -WALL_DEPTH, HALF)]
	for w in [["structure.hangar_pit_wall.02", [0, 1, 5, 4]], ["structure.hangar_pit_wall.03", [0, 3, 7, 4]],
			["structure.hangar_pit_wall.01", [2, 1, 5, 6]], ["structure.hangar_pit_wall.01", [2, 3, 7, 6]]]:
		var quad: Array[Vector3] = []
		for i in w[1]:
			quad.append(c[i])
		add_child(_quad(String(w[0]), quad))
	add_child(_quad("structure.hangar_hazard_strip.01", _rect(-16, -16, 16, -12, 0.08)))
	_plate = _quad(pack.team_variant(["structure.hangar_lift_plate.tan", "structure.hangar_lift_plate.green"], colour), _rect(-16, -15, 16, 15, 0.0))
	add_child(_plate)
	_leaf_ids = [pack.team_variant(["structure.hangar_leaf.left.tan", "structure.hangar_leaf.left.green"], colour),
			pack.team_variant(["structure.hangar_leaf.right.tan", "structure.hangar_leaf.right.green"], colour)]
	_leaf_off = -2.0
	_leaf_left = _quad(_leaf_ids[0], _rect(-8, -15, 8, 16, LEAF_Y))
	_leaf_right = _quad(_leaf_ids[1], _rect(-8, -15, 8, 16, LEAF_Y))
	add_child(_leaf_left)
	add_child(_leaf_right)


## Corners (top-left, top-right, bottom-right, bottom-left) of a flat rectangle in the original's (x, y) with y down the screen, at height h.
func _rect(x0: float, y0: float, x1: float, y1: float, h: float) -> Array[Vector3]:
	return [Vector3(x0, h, y0), Vector3(x1, h, y0), Vector3(x1, h, y1), Vector3(x0, h, y1)]


## A leaf 16 wide centred on `centre`, cut off at the pad's own footprint (x = +-PAD_HALF) with its texture cut the same way, or null once it is entirely outside.
func _leaf_mesh(sprite_id: String, centre: float) -> Mesh:
	var s := pack.get_sprite(sprite_id)
	if s.is_empty():
		return null
	var x0 := centre - LEAF_HALF_W
	var x1 := centre + LEAF_HALF_W
	var cx0 := maxf(x0, -PAD_HALF)
	var cx1 := minf(x1, PAD_HALF)
	if cx0 >= cx1:
		return null
	var tex := pack.get_texture(int(s.get("page", 0)))
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var sx := float(s["x"])
	var sy := float(s["y"])
	var sw := float(s["w"])
	var sh := float(s["h"])
	var u0 := (sx + sw * (cx0 - x0) / (x1 - x0)) / tw
	var u1 := (sx + sw * (cx1 - x0) / (x1 - x0)) / tw
	var v0 := sy / th
	var v1 := (sy + sh) / th
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [Vector3(cx0, LEAF_Y, -15.0), Vector3(cx1, LEAF_Y, -15.0), Vector3(cx1, LEAF_Y, 16.0), Vector3(cx0, LEAF_Y, 16.0)]
	var uvs := [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])
	return st.commit()


func _quad(sprite_id: String, corners: Array[Vector3]) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := pack.get_sprite(sprite_id)
	if s.is_empty():
		return mi
	var tex := pack.get_texture(int(s.get("page", 0)))
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var sx := float(s["x"])
	var sy := float(s["y"])
	var sw := float(s["w"])
	var sh := float(s["h"])
	var uv := [Vector2(sx / tw, sy / th), Vector2((sx + sw) / tw, sy / th),
			Vector2((sx + sw) / tw, (sy + sh) / th), Vector2(sx / tw, (sy + sh) / th)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uv[i])
		st.add_vertex(corners[i])
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.albedo_texture = tex
	mi.material_override = mat
	return mi
