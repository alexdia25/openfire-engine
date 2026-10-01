class_name SoldierView3D
extends Node3D
## Draws a Soldier (game/soldier.gd; Return Fire's class 14 "MAN", issue #74, document 116): a body quad whose sprite is the soldier's
## team, facing and animation frame, and a ground shadow quad. The draw descriptor 0x44e928 has two parts per facing (FUN_00433950
## picks the block from the team and the heading's octant): the shadow (cel 755, flag 0x10) and the body (cel base + frame, flag 8),
## corners (x, y, z) = (-4,-1.5,4.5) (4,-1.5,4.5) (4,1.5,0) (-4,1.5,0) for the body, mirrored by swapping the corner order for the
## three facings that reuse another's frames. Both come from world/infantry.json (Pack.infantry); nothing here names the game.

var soldier: Soldier
var _pack: Pack
var _body: MeshInstance3D
var _shadow: MeshInstance3D
var _body_mat: StandardMaterial3D
var _shadow_mat: StandardMaterial3D
## The shadow part's flag 0x10 means a ground shadow: the cel is a white mask drawn as translucent black (the shell's shadow, projectile_billboard_3d.gd).
const SHADOW_ALPHA := 5.0 / 32.0
const SHADOW_LIFT := 0.5
var _shown := ""


func setup(s: Soldier, pack: Pack) -> void:
	soldier = s
	_pack = pack
	_body_mat = _material()
	_shadow_mat = _material()
	_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_mat.albedo_color = Color(0.0, 0.0, 0.0, SHADOW_ALPHA)
	_shadow = MeshInstance3D.new()
	_shadow.material_override = _shadow_mat
	_shadow.position.y = SHADOW_LIFT
	add_child(_shadow)
	_body = MeshInstance3D.new()
	_body.material_override = _body_mat
	add_child(_body)
	_refresh()


func _material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	return m


func _process(_delta: float) -> void:
	if soldier == null or soldier.finished:
		queue_free()
		return
	_refresh()


func _sprite_id() -> String:
	var sets: Array = _pack.infantry.get("sprites", {}).get("tan" if soldier.team == 0 else "green", [])
	var f := soldier.draw_frame()
	if int(f["dir"]) >= sets.size():
		return ""
	var frames: Array = sets[int(f["dir"])]
	if int(f["frame"]) >= frames.size():
		return ""
	return String(frames[int(f["frame"])])


func _wade_sprite_id(f: Dictionary) -> String:
	var ids: Array = _pack.infantry.get("wade_sprites", {}).get("tan" if soldier.team == 0 else "green", [])
	var i: int = int(f["frame"]) - int(_pack.infantry.get("wade", {}).get("frame_first", 10))
	return String(ids[i]) if i >= 0 and i < ids.size() else ""


func _refresh() -> void:
	position = Vector3(soldier.position.x, 0.0, soldier.position.y)
	var f := soldier.draw_frame()
	var wade: bool = f["wade"]
	_shadow.visible = not wade
	rotation_degrees.y = -float(soldier.heading) * Soldier.STEP_DEG if wade else 0.0   # the ripple quad turns with the heading, the body does not
	var id := _wade_sprite_id(f) if wade else _sprite_id()
	var key := "%s|%s|%s" % [id, f["mirror"], wade]
	if key == _shown:
		return
	_shown = key
	var quad: Array = _pack.infantry.get("wade", {}).get("quad", []) if wade else _pack.infantry.get("quad", [])
	_build(_body, _body_mat, id, quad, bool(f["mirror"]) and not wade)
	if _shadow.mesh == null:
		_build(_shadow, _shadow_mat, String(_pack.infantry.get("shadow_sprite", "")), _pack.infantry.get("shadow_quad", []), false)


func _build(mi: MeshInstance3D, mat: StandardMaterial3D, sprite_id: String, quad: Array, mirror: bool) -> void:
	var s := _pack.get_sprite(sprite_id) if sprite_id != "" else {}
	if s.is_empty() or quad.size() != 4:
		mi.mesh = null
		return
	var tex := _pack.get_texture(int(s.get("page", 0)))
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var u0 := float(s["x"]) / tw
	var v0 := float(s["y"]) / th
	var u1 := (float(s["x"]) + float(s["w"])) / tw
	var v1 := (float(s["y"]) + float(s["h"])) / th
	var c: Array[Vector3] = []
	for q in quad:
		c.append(Vector3(q[0], q[2], q[1]))   # the descriptors' (x, y, z): x lateral, y = -forward (3D z), z up
	var uv := [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]
	if mirror:
		uv = [Vector2(u1, v0), Vector2(u0, v0), Vector2(u0, v1), Vector2(u1, v1)]   # corner order 1, 0, 3, 2
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uv[i])
		st.add_vertex(c[i])
	mi.mesh = st.commit()
	mat.albedo_texture = tex
