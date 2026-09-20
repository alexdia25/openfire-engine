class_name GateView3D
extends Node3D
## Draws a Gate (game/gate.gd) from the original's two draw descriptors (document 56). Each descriptor (a door
## wing) has a local offset and parts (cel, flags, 4 corner indices) like a decoration; the descriptor's draw
## hook (FUN_0042e240 and its three siblings) rewrites corners 9, 10, 13 and 14 along the gate's axis to
## +-(16 - floor(open)) every frame and swaps the part 6 / 7 cel from 0x359 (closed) to 0x35a (open) once
## floor(open) >= 1. A part with flag 8 takes the tile's team variant as a +cel offset. The parts' render-mode
## bits (0x100 / 0x200) select shading tables that are not reproduced.

var gate: Gate
var _pack: Pack
var _parts: Array = []  ## [{mi, desc_i, part_i, last_key}]


func setup(pack: Pack, g: Gate) -> void:
	_pack = pack
	gate = g
	for di in g.data["descs"].size():
		var d: Dictionary = g.data["descs"][di]
		for pi in d["parts"].size():
			var mi := MeshInstance3D.new()
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			mi.material_override = mat
			add_child(mi)
			_parts.append({"mi": mi, "mat": mat, "di": di, "pi": pi, "key": ""})
	_refresh(true)


func _process(_delta: float) -> void:
	_refresh(false)


func _refresh(force: bool) -> void:
	var opened := int(floor(gate.open))
	var dyn_value := 16.0 - float(opened) if opened >= 1 else 16.0
	for p in _parts:
		var d: Dictionary = gate.data["descs"][p["di"]]
		var part: Dictionary = d["parts"][p["pi"]]
		var is_dyn_part: bool = p["pi"] == int(d["dyn_part"])
		var key := "%d" % opened if (is_dyn_part or _touches_dynamic(d, part)) else "static"
		if not force and key == p["key"]:
			continue
		p["key"] = key
		var sid: String
		if is_dyn_part:
			sid = d["sprite_open"] if opened >= 1 else d["sprite_closed"]
		else:
			var ids: Array = part["sprite_ids"]
			sid = ids[clampi(gate.variant, 0, ids.size() - 1)]
		var s := _pack.get_sprite(sid)
		if s.is_empty():
			(p["mi"] as MeshInstance3D).mesh = null
			continue
		var tex := _pack.get_texture(int(s.get("page", 0)))
		(p["mat"] as StandardMaterial3D).albedo_texture = tex
		var corners := _corners(d, part, dyn_value)
		(p["mi"] as MeshInstance3D).mesh = _quad(corners, s, tex)


## JSON numbers are floats; compare as ints (Array.has would not match 9 with 9.0).
func _is_dyn(d: Dictionary, idx: int) -> bool:
	for k in d["dyn_corners"]:
		if int(k) == idx:
			return true
	return false


func _touches_dynamic(d: Dictionary, part: Dictionary) -> bool:
	for i in part["corner_idx"]:
		if _is_dyn(d, int(i)):
			return true
	return false


func _corners(d: Dictionary, part: Dictionary, dyn_value: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var axis: String = d["dyn_axis"]
	for i in part["corner_idx"]:
		var c: Array = (d["corners"][int(i)] as Array).duplicate()
		if _is_dyn(d, int(i)):
			var v: float = float(d["dyn_sign"]) * dyn_value
			if axis == "x":
				c[0] = v
			else:
				c[1] = v
		var wx := gate.centre.x + float(d["offset"][0]) + float(c[0])
		var wz := gate.centre.y + float(d["offset"][1]) + float(c[1])
		out.append(Vector3(wx, float(c[2]) + 0.5, wz))
	return out


func _quad(c: Array[Vector3], s: Dictionary, tex: Texture2D) -> ArrayMesh:
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var sx := float(s.get("x", 0))
	var sy := float(s.get("y", 0))
	var sw := float(s.get("w", 0))
	var sh := float(s.get("h", 0))
	var uv := [Vector2(sx / tw, sy / th), Vector2((sx + sw) / tw, sy / th),
			Vector2((sx + sw) / tw, (sy + sh) / th), Vector2(sx / tw, (sy + sh) / th)]
	# Same Newell-normal diagonal choice as DecorationField3D (the wall faces are non-convex when drawn flat).
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
