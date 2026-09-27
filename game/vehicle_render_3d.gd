class_name VehicleRender3D
extends Node3D
## Draws any vehicle from the `render` descriptor of its definition (PORTING_PLAN.md 2.7.2, step 5; documents 57, 59, 63, 64):
## the parts of the original's draw descriptor -- a sprite (tan, green, hit-flash variants) over four corners -- as quads, exactly
## the way decorations are drawn (document 44), plus the bindings that make the moving parts move. The Tank's turret and barrel,
## the Jeep's wheel strips and swim ring, the MSV's rack and canisters and the Heli's rotor and tilt are all data in this
## vocabulary; there is no `vehicle_type` here, and a new vehicle gets moving parts by writing the same descriptor.
##
## Corner axes as in the original: x lateral, y = minus forward, z up, in world units. `Vehicle.channel(name)` is the number a
## binding reads (mostly the fields the behaviour modules drive: `turret_deg`, `gun_elev_deg`, `swim_amount`, `rotor_speed_steps` ...).
##
##   render.parts[i]  {sprite_ids: [tan, green, flash], flags (8 = takes the team variant), corners: [4 x corner]}
##       corner            [x, y, z]  or  {rig, point}: point `point` of the named rig
##       group             the group node the part hangs under (default: the vehicle itself)
##       sprites_by        {channel, sprites: [ids], scale, eps, wrap | max}   pick the sprite by a channel-derived index
##       corners_by        {channel, sets: [[4 corners]...], scale, eps, max}   pick the whole corner set by an index
##       scale_by          {channel, min}                                       scale x and y by max(channel, min)
##       visible           {channel, min, max, scale, eps}                      draw only while the (scaled) channel is in range
##   render.rigs.<name>  {channel, rotate: {axis: "x", scale}, base: [points], offset, adjust: [...]}
##       corners recomputed every frame as R(channel * scale, about the lateral axis) * base + offset, the way the original's
##       draw callbacks rebuild the Tank's barrel tip and the MSV's rack (an `adjust` sets one axis of some base points from a channel)
##   render.groups.<name>  {parent, rotate: [{axis: "x" | "y" | "z", channel, scale, rate}]}
##       a node the parts turn with (axes are the mesh's: y is up). `rate` accumulates degrees per tick x channel (the rotor);
##       without it the angle is channel * scale (the turret)
##   render.body  {rotate: [...]}   the same, applied to the whole vehicle (the Heli's pitch and bank)
##
## A part with `flags & 8` takes the vehicle's colour (`pack.team_variant`) or variant 2 during the hit flash (FUN_00402d20).
## Shared by the game scene and the mod tool's vehicle preview, so both draw a vehicle the same way (EDITOR_PLAN.md principle 3).

const GROUND_CLEARANCE_PX := 2.0  ## not a traced value: keeps the bottom faces off the terrain plane

var vehicle: Vehicle
var _pack: Pack
var _render: Dictionary = {}
var _type := 0                     ## the type this renderer was built for; the vehicle may be swapped under it
var _parts: Array = []             ## per part: {data, mesh, mat, group, shift, key}
var _groups: Dictionary = {}       ## name -> {node, spec}
var _group_order: Array = []       ## parents before children
var _rates: Dictionary = {}        ## "<owner>/<n>" -> the accumulated angle of a `rate` rotation, degrees
var _flash := false                ## drawn in variant 2 (the hit flash)


## The game's presentation of a vehicle, added under `parent`.
static func create_for(v: Vehicle, pack: Pack, parent: Node) -> Node3D:
	var r := VehicleRender3D.new()
	parent.add_child(r)
	r.setup(v, pack)
	return r


func setup(v: Vehicle, pack: Pack) -> void:
	vehicle = v
	_pack = pack
	_type = v.vehicle_type
	v.visible = false  # logic only
	_render = pack.vehicle_def(v.vehicle_type).get("render", {})
	_build_groups()
	var parts: Array = _render.get("parts", [])
	var shifts := _coplanar_shifts()
	for i in parts.size():
		var mi := MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mi.material_override = mat
		var group := String(parts[i].get("group", ""))
		(_groups[group]["node"] if group != "" and _groups.has(group) else self).add_child(mi)
		_parts.append({"data": parts[i], "mesh": mi, "mat": mat, "shift": shifts[i], "key": null})
	_turn_groups(0.0)
	_update_parts()
	_follow()


func _process(delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle) or vehicle.vehicle_type != _type:
		return  # a type swap frees this renderer (terrain_view_3d._on_player_type_changed) a frame later
	_flash = vehicle.flashing()
	_turn_groups(delta)
	_update_parts()
	_follow()


func _build_groups() -> void:
	var specs: Dictionary = _render.get("groups", {})
	var pending: Array = specs.keys()
	while not pending.is_empty():
		var progressed := false
		for name in pending.duplicate():
			var parent := String(specs[name].get("parent", ""))
			if parent != "" and not _groups.has(parent):
				continue
			var node := Node3D.new()
			(_groups[parent]["node"] if parent != "" else self).add_child(node)
			_groups[name] = {"node": node, "spec": specs[name]}
			_group_order.append(name)
			pending.erase(name)
			progressed = true
		if not progressed:
			push_warning("VehicleRender3D: group parents of %s form a loop" % [pending])
			break


## The channels a render descriptor reads, in the order the mod tool's preview lists them (the body, the groups, the rigs, then
## the parts' bindings), each once. A derived channel (`Vehicle.CHANNEL_DRIVERS`) is replaced by the channels that drive it.
static func channels_used(render: Dictionary) -> Array:
	var out: Array = []
	var add := func(name: String) -> void:
		for n in Vehicle.CHANNEL_DRIVERS.get(name, [name]):
			if not out.has(n):
				out.append(n)
	for e in render.get("body", {}).get("rotate", []):
		add.call(String(e["channel"]))
	for g in render.get("groups", {}).values():
		for e in g.get("rotate", []):
			add.call(String(e["channel"]))
	for r in render.get("rigs", {}).values():
		add.call(String(r["channel"]))
		for a in r.get("adjust", []):
			add.call(String(a["add_channel"]))
	for p in render.get("parts", []):
		for k in ["sprites_by", "corners_by", "scale_by", "visible"]:
			if p.has(k):
				add.call(String(p[k]["channel"]))
	return out


## One number from a binding: the channel read from the vehicle, then `index` for the ones that pick from a list.
func _value(spec: Dictionary) -> float:
	return vehicle.channel(String(spec["channel"]))


## The list index a channel-derived binding picks: floor(value * scale + eps), wrapped (`wrap`) or clamped to 0..(`max` | last).
static func index_of(spec: Dictionary, value: float, count: int) -> int:
	var i := floori(value * float(spec.get("scale", 1.0)) + float(spec.get("eps", 0.0)))
	if spec.has("wrap"):
		return posmod(i, int(spec["wrap"]))
	return clampi(i, 0, mini(int(spec.get("max", count - 1)), count - 1))


func _is_visible(spec: Dictionary) -> bool:
	var v := _value(spec)
	if spec.has("scale") or spec.has("eps"):
		v = floorf(v * float(spec.get("scale", 1.0)) + float(spec.get("eps", 0.0)))
	return v >= float(spec.get("min", -INF)) and v <= float(spec.get("max", INF))


## Turns the group nodes by their bindings (a `rate` binding accumulates, the rest read the channel directly) and lets the
## body's own bindings set the vehicle's tilt (`_follow`).
func _turn_groups(delta: float) -> void:
	for name in _group_order:
		var g: Dictionary = _groups[name]
		g["node"].rotation_degrees = _rotation(g["spec"].get("rotate", []), String(name), delta)


func _rotation(entries: Array, owner: String, delta: float) -> Vector3:
	var out := Vector3.ZERO
	for n in entries.size():
		var e: Dictionary = entries[n]
		var v := _value(e)
		var deg: float
		if e.has("rate"):
			var key := "%s/%d" % [owner, n]
			# the rotor: steps of `rate` degrees a tick, x the channel (FUN_00403420, document 63), kept in 0..360
			_rates[key] = fposmod(float(_rates.get(key, 0.0)) + v * float(e["rate"]) * delta * Vehicle.TICK_HZ, 360.0)
			deg = float(_rates[key]) * float(e.get("scale", 1.0))
		else:
			deg = v * float(e.get("scale", 1.0))
		match String(e.get("axis", "y")):
			"x":
				out.x += deg
			"z":
				out.z += deg
			_:
				out.y += deg
	return out


## The named rig's points now: R(channel * scale) * base + offset, the rotation about the lateral axis turning (y, z) as the
## original's FUN_0041ae10 does (a nose point (0, -1, 0) goes to height -sin), then the constant offset.
func _rig_points(name: String) -> Array:
	var rig: Dictionary = _render.get("rigs", {}).get(name, {})
	if rig.is_empty():
		return []
	var base: Array = []
	for b in rig["base"]:
		base.append(Vector3(b[0], b[1], b[2]))
	for a in rig.get("adjust", []):
		var value := float(a.get("set", 0.0)) + vehicle.channel(String(a["add_channel"])) * float(a.get("add_scale", 1.0))
		for p in a["points"]:
			var b: Vector3 = base[p]
			b[int(a.get("axis", 1))] = value
			base[p] = b
	var rot: Dictionary = rig.get("rotate", {})
	var ang := deg_to_rad(vehicle.channel(String(rig["channel"])) * float(rot.get("scale", 1.0)))
	var c := cos(ang)
	var s := sin(ang)
	var off: Array = rig.get("offset", [0.0, 0.0, 0.0])
	var out: Array = []
	for b in base:
		out.append(Vector3(b.x + off[0], b.y * c - b.z * s + off[1], b.y * s + b.z * c + off[2]))
	return out


## A part's four corners now, as Vector3 (x, y, z world units): its static corners, or the set its `corners_by` picks, with rig
## references resolved and `scale_by` applied. `rest` gives the descriptor's own corners without the channel-driven picks.
func _corners(part: Dictionary, rigs: Dictionary, rest := false) -> Array:
	var raw: Array = part["corners"]
	if part.has("corners_by") and not rest:
		var cb: Dictionary = part["corners_by"]
		raw = cb["sets"][index_of(cb, _value(cb), (cb["sets"] as Array).size())]
	var k := 1.0
	if part.has("scale_by") and not rest:
		var sb: Dictionary = part["scale_by"]
		k = maxf(_value(sb), float(sb.get("min", 0.0)))
	var out: Array = []
	for c in raw:
		if c is Dictionary:
			var name := String(c["rig"])
			if not rigs.has(name):
				rigs[name] = _rig_points(name)
			out.append(rigs[name][int(c["point"])])
		else:
			out.append(Vector3(c[0] * k, c[1] * k, c[2]))
	return out


## The sprite a part is drawn with: the one its `sprites_by` picks; otherwise a team-coloured part takes variant 2 (the hit flash,
## document 59) while flashing and the vehicle's colour the rest of the time.
func _sprite_id(part: Dictionary) -> String:
	if part.has("sprites_by"):
		var sb: Dictionary = part["sprites_by"]
		return String(sb["sprites"][index_of(sb, _value(sb), (sb["sprites"] as Array).size())])
	var ids: Array = part["sprite_ids"]
	if _flash and (int(part["flags"]) & 8) and ids.size() > 2:
		return String(ids[2])
	return _pack.team_variant(ids, vehicle.art_colour())


## Rebuilds the mesh of every part whose sprite or corners changed, and shows or hides the conditional ones.
func _update_parts() -> void:
	var rigs := {}   # each rig is evaluated once a frame
	for p in _parts:
		var d: Dictionary = p["data"]
		var mi: MeshInstance3D = p["mesh"]
		if d.has("visible"):
			var show := _is_visible(d["visible"])
			mi.visible = show
			if not show:
				continue
		var id := _sprite_id(d)
		var corners := _corners(d, rigs)
		var key := [id, corners]
		if key == p["key"]:
			continue
		p["key"] = key
		var s := _pack.get_sprite(id)
		if s.is_empty():
			mi.mesh = null
			continue
		var tex := _pack.get_texture(int(s.get("page", 0)))
		mi.mesh = _quad(corners, s, tex, p["shift"])
		p["mat"].albedo_texture = tex


func _follow() -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	visible = vehicle.alive and not vehicle.docked
	position = Vector3(vehicle.position.x, GROUND_CLEARANCE_PX + vehicle.z, vehicle.position.y)
	var tilt := _rotation(_render.get("body", {}).get("rotate", []), "body", 0.0)
	rotation_degrees = Vector3(tilt.x, -90.0 - vehicle.heading_deg + tilt.y, tilt.z)


## The outward shift (mesh space) each part needs so it draws over the earlier parts of its group that it overlaps in the same
## plane (CoplanarParts, document 102). Conditional parts (`visible`) take no part: they come and go over the rest.
func _coplanar_shifts() -> Array:
	var parts: Array = _render.get("parts", [])
	var out: Array = []
	out.resize(parts.size())
	out.fill(Vector3.ZERO)
	var by_group := {}
	var rigs := {}
	for i in parts.size():
		if not parts[i].has("visible"):
			by_group.get_or_add(String(parts[i].get("group", "")), []).append(i)
	for g in by_group:
		var idx: Array = by_group[g]
		var quads: Array = []
		for i in idx:
			var c: Array[Vector3] = []
			for q in _corners(parts[i], rigs, true):
				c.append(Vector3(q.x, q.z, q.y))
			quads.append(c)
		var shifts := CoplanarParts.shifts(quads)
		for n in idx.size():
			out[idx[n]] = shifts[n]
	return out


func _quad(corners: Array, s: Dictionary, tex: Texture2D, shift := Vector3.ZERO) -> ArrayMesh:
	var c: Array[Vector3] = []
	for q in corners:
		c.append(Vector3(q.x, q.z, q.y) + shift)
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
