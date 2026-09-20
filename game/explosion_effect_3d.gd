class_name ExplosionEffect3D
extends Node3D
## One explosion object ("Expl", class 0x44bb70), played exactly as the original draws it -- TRACED,
## documents 50-51 (FUN_0042dbe0 update, FUN_0042dd90 draw). A record carries a duration, a per-tick
## progress rate, a scale and a list of parts; each part is a quad (corners in world units, x = width,
## y = length toward the screen, z = up, all multiplied by the record's scale) that shows frame
## `cel + (n - start)` while `start <= n <= end`, n = floor(progress). From n >= fade a part fades:
## alpha = 1 - (n - fade + 1) / (end - fade + 2), then quantised to the 3DO's 16 translucency levels
## (FUN_00423060). A part with variant_mode 1-4 stands for a group of 2/4/8 following parts of which
## exactly one is drawn, chosen per object.
##
## The record's script is run the way FUN_0042dbe0 runs it (WAIT until progress reaches n, STOP yields
## for a tick, END stops), but only the TILE_STATE op has an effect here: it fires `tile_state`, the
## moment the original re-textures the destroyed tile (FUN_0042e600) -- for a collapsing tile that is
## AFTER the first frames of the explosion, not at the hit. Op 21 (FUN_0042d9f0) does the same later: it
## clears the tile's decoration at once and schedules the state change `n` ticks on (FUN_004146d0 ->
## FUN_0042da50 -> FUN_0042e600) -- the bush and palm records use it. Sounds, the ground glow, neighbour tiles
## (TILE_SET / TILE_DMG) and damage boxes are not played.
##
## Approximations (marked, not traced): the mapping from a translucency level to an opacity (the
## original's blend-table words are hardware register values; here opacity = (level + 1) / 16), blending
## as ordinary alpha, and the effect's z (drawn at the ground). The time unit is the 16 ms tick.

const TICK_HZ := 62.5

signal tile_state  ## the script reached its TILE_STATE op (or the timer op 21 scheduled ran out)
signal tile_cleared  ## op 21 ran: the tile loses its decoration NOW; its result state follows after the delay

## A muzzle flash is attached to its vehicle (FUN_0042e0b0 / FUN_0042daf0): every tick it is placed at
## the vehicle's position plus `follow_offset` (x sideways, y forward, z up, in world units) turned by
## the vehicle's heading, and drawn turned with it.
var follow: Vehicle = null
var follow_offset := Vector3.ZERO

var _record: Dictionary
var _pc := 0
var _script_done := false
var _timers: Array[float] = []  ## op 21's delayed FUN_0042e600 call (FUN_004146d0), in ticks
var _pack: Pack
var _progress := 0.0
var _parts: Array = []  ## [{data, mesh_instance, material, last_frame}]


static func spawn(parent: Node, pack: Pack, record: Dictionary, at: Vector2) -> ExplosionEffect3D:
	if record.is_empty():
		return null
	var fx := ExplosionEffect3D.new()
	parent.add_child(fx)
	fx.setup(pack, record, at)
	return fx


func setup(pack: Pack, record: Dictionary, at: Vector2) -> void:
	_pack = pack
	_record = record
	position = Vector3(at.x, 0.0, at.y)  # local to the spawning parent, which sits at the world origin
	var parts: Array = record.get("parts", [])
	var i := 0
	while i < parts.size():
		var mode := int(parts[i].get("variant_mode", 0))
		var group := 1
		match mode:
			1, 4:
				group = 2
			2:
				group = 4
			3:
				group = 8
		var pick := i + (randi() % mini(group, parts.size() - i))
		_add_part(parts[pick])
		i += group


func _add_part(data: Dictionary) -> void:
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	mi.visible = false
	add_child(mi)
	_parts.append({"data": data, "mi": mi, "mat": mat, "last": -1})


static func spawn_attached(parent: Node, pack: Pack, record: Dictionary, vehicle: Vehicle,
		offset: Vector3) -> ExplosionEffect3D:
	var fx := spawn(parent, pack, record, vehicle.position)
	if fx != null:
		fx.follow = vehicle
		fx.follow_offset = offset
		fx._follow()
	return fx


func _follow() -> void:
	if follow == null or not is_instance_valid(follow):
		return
	var rad := deg_to_rad(follow.heading_deg)
	var fwd := Vector2(cos(rad), sin(rad))
	var right := Vector2(-fwd.y, fwd.x)
	var p := follow.position + fwd * follow_offset.y + right * follow_offset.x
	position = Vector3(p.x, follow_offset.z, p.y)
	# corners are (x right, y = -forward, z up): the same yaw the vehicle box uses
	rotation_degrees.y = -90.0 - follow.heading_deg


func _process(delta: float) -> void:
	_follow()
	for i in range(_timers.size() - 1, -1, -1):
		_timers[i] -= delta * TICK_HZ
		if _timers[i] <= 0.0:
			_timers.remove_at(i)
			tile_state.emit()
	_progress += float(_record.get("rate_per_tick", 0.25)) * delta * TICK_HZ
	if _progress >= float(_record.get("duration", 1.0)):
		queue_free()
		return
	_run_script()
	var n := int(floor(_progress))
	for p in _parts:
		_update_part(p, n)


## FUN_0042dbe0's loop, reduced to control flow plus TILE_STATE.
func _run_script() -> void:
	var script: Array = _record.get("script", [])
	while not _script_done and _pc < script.size():
		var op: Array = script[_pc]
		match op[0]:
			"END":
				_script_done = true
			"STOP":
				_pc += 1
				return
			"WAIT":
				if _progress < float(op[1]):
					return
				_pc += 1
			"TILE_STATE":
				tile_state.emit()
				_pc += 1
			"OP21":
				tile_cleared.emit()
				_timers.append(float(op[1]))
				_pc += 1
			_:
				_pc += 1


func _update_part(p: Dictionary, n: int) -> void:
	var d: Dictionary = p["data"]
	var mi: MeshInstance3D = p["mi"]
	var start := int(d["start"])
	var end := int(d["end"])
	if n < start or n > end:
		mi.visible = false
		return
	var opacity := 1.0
	var fade := int(d["fade"])
	if fade <= end and n >= fade:
		var alpha := 1.0 - float(n - fade + 1) / float(end - fade + 2)
		var level := int(floor(alpha * 16.0)) - 1
		if level < 1:
			mi.visible = false
			return
		opacity = minf(1.0, float(level + 1) / 16.0)
	var frame := n - start
	if frame != p["last"]:
		p["last"] = frame
		var sid: String = d["frames"][frame]
		var s := _pack.get_sprite(sid)
		if s.is_empty():
			mi.visible = false
			return
		mi.mesh = _quad(d["corners"], s, _pack.get_texture(int(s.get("page", 0))))
		(p["mat"] as StandardMaterial3D).albedo_texture = _pack.get_texture(int(s.get("page", 0)))
	(p["mat"] as StandardMaterial3D).albedo_color = Color(1, 1, 1, opacity)
	mi.visible = true


func _quad(corners: Array, s: Dictionary, tex: Texture2D) -> ArrayMesh:
	var sc := float(_record.get("scale", 1.0))
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var sx := float(s.get("x", 0))
	var sy := float(s.get("y", 0))
	var sw := float(s.get("w", 0))
	var sh := float(s.get("h", 0))
	var uv := [Vector2(sx / tw, sy / th), Vector2((sx + sw) / tw, sy / th),
			Vector2((sx + sw) / tw, (sy + sh) / th), Vector2(sx / tw, (sy + sh) / th)]
	var c: Array[Vector3] = []
	for q in corners:
		c.append(Vector3(q[0] * sc, q[2] * sc + 0.5, q[1] * sc))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Same corner -> cel mapping and split as DecorationField3D / VehicleBoxRender3D (corners are the
	# cel's TL, TR, BR, BL); the muzzle-flash trapezoid (record 0x445138) is convex, so 0-1-2 / 0-2-3 holds.
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uv[i])
		st.add_vertex(c[i])
	return st.commit()
