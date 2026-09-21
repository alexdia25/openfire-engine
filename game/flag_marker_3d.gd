class_name FlagMarker3D
extends Node3D
## Draws a FlagMarker (game/flag_marker.gd) the way the original does (document 65): on the ground, a small base plate (cel 1881)
## and the cloth with its pole (cel 1829 + frame, a 20 x 16 quad leaning 4 units, descriptor 0x440448); carried, two quads
## (descriptor 0x440318): the cloth seen from above (cel 1855 + frame) at height 10.5 and from the side (cel 1803 + frame) at 4.5-12.5,
## trailing behind the pole. Both turn with the flag's own heading (clockwise from north, node yaw = -heading). The original also
## tilts the ground cloth toward the camera by a value read from its camera record (`(cam+0x24 + 0xffe70000) >> 3`); that
## camera-specific tilt is NOT reproduced (untraced against this project's 3D camera).

var flag: FlagMarker
var pack: Pack
var _parts: Dictionary = {}   ## "plate" / "cloth" / "top" / "side" -> {mesh, mat, shown}


func setup(shared_flag: FlagMarker, shared_pack: Pack) -> void:
	flag = shared_flag
	pack = shared_pack
	flag.visible = false  # logic only
	for key in ["plate", "cloth", "top", "side"]:
		var mi := MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mi.material_override = mat
		add_child(mi)
		_parts[key] = {"mesh": mi, "mat": mat, "shown": -1}
	flag.tree_exited.connect(queue_free)
	_refresh()


func _process(_delta: float) -> void:
	if not is_instance_valid(flag):
		queue_free()
		return
	_refresh()


func _refresh() -> void:
	var carried := flag.carrier != null and is_instance_valid(flag.carrier)
	# the flag's origin is the carrier's origin turned by its heading plus (3.75, 6.75, -2): its height is the vehicle's minus 2
	# (vehicles are drawn 2 above the ground plane, so a carried flag's origin is on the plane)
	var y := 0.0
	if carried:
		y = flag.carrier.z
	position = Vector3(flag.position.x, y + 0.05, flag.position.y)
	rotation_degrees.y = -flag.heading_deg
	var f := flag.cloth_frame()
	var g: Dictionary = pack.flag_data.get("ground", {})
	var c: Dictionary = pack.flag_data.get("carried", {})
	_show("plate", not carried, g.get("plate", {}), 0)
	_show("cloth", not carried, g.get("cloth", {}), f)
	_show("top", carried, c.get("top", {}), f)
	_show("side", carried, c.get("side", {}), f)


func _show(key: String, visible_now: bool, part: Dictionary, frame: int) -> void:
	var p: Dictionary = _parts[key]
	var mi: MeshInstance3D = p["mesh"]
	mi.visible = visible_now
	if not visible_now or part.is_empty() or p["shown"] == frame:
		return
	p["shown"] = frame
	var ids: Array = part["sprite_ids"]
	var s := pack.get_sprite(String(ids[clampi(frame, 0, ids.size() - 1)]))
	if s.is_empty():
		return
	var tex := pack.get_texture(int(s.get("page", 0)))
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var corners: Array = part["corners"]
	var c: Array[Vector3] = []
	for q in corners:
		c.append(Vector3(q[0], q[2], q[1]))
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
		st.add_vertex(c[i])
	mi.mesh = st.commit()
	p["mat"].albedo_texture = tex
