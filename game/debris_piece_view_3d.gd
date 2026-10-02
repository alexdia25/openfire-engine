class_name DebrisPieceView3D
extends Node3D
## Draws a DebrisPiece (game/debris_piece.gd; document 119): one flat quad of the part's sprite about the piece's centre, turned by its yaw (about the
## vertical) and roll (about the lateral axis, PORT CHOICE: FUN_0042a7b0 builds the matrix from `+0x68` and `+0x4c` with the table at 0x481710, whose
## axis was not decoded), shown as the burn-out frames while the record's frame op runs, shaded by the tint op and faded from `fade_start`.

const DARKEN := Color(0.25, 0.22, 0.2)   ## PORT CHOICE: the tint op shades toward palette entry 2 of the burn-out cels; the palette is not read

var piece: DebrisPiece
var _pack: Pack
var _mi: MeshInstance3D
var _mat: StandardMaterial3D
var _key := ""


func setup(p: DebrisPiece, pack: Pack) -> void:
	piece = p
	_pack = pack
	_mi = MeshInstance3D.new()
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mi.material_override = _mat
	add_child(_mi)
	_sync()


func _process(_delta: float) -> void:
	if piece == null or piece.finished:
		queue_free()
		return
	_sync()


func _sync() -> void:
	position = Vector3(piece.position.x, 0.5 + piece.z, piece.position.y)
	basis = Basis(Vector3.RIGHT, deg_to_rad(piece.roll)) * Basis(Vector3.UP, deg_to_rad(piece.yaw))
	var id := piece.frame_id if piece.frame_id != "" else piece.sprite_id
	if id != _key:
		_key = id
		_build(id)
	var shade := Color.WHITE.lerp(DARKEN, clampf(piece.tint, 0.0, 1.0))
	_mat.albedo_color = Color(shade.r, shade.g, shade.b, piece.fade_alpha())


func _build(id: String) -> void:
	var s := _pack.get_sprite(id)
	if s.is_empty() or piece.offsets.size() != 4:
		_mi.mesh = null
		return
	var tex := _pack.get_texture(int(s.get("page", 0)))
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var sx := float(s["x"])
	var sy := float(s["y"])
	var sw := float(s["w"])
	var sh := float(s["h"])
	var uv := [Vector2(sx / tw, sy / th), Vector2((sx + sw) / tw, sy / th), Vector2((sx + sw) / tw, (sy + sh) / th), Vector2(sx / tw, (sy + sh) / th)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uv[i])
		st.add_vertex(piece.offsets[i])
	_mi.mesh = st.commit()
	_mat.albedo_texture = tex
