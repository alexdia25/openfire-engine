class_name DecorationField3D
extends Node3D
## Every level decoration (bushes, palms, coral, dock posts, ...) as real 3D geometry, built from
## the ORIGINAL's own per-part quad corners (document 44, extracted from RFIRE.BIN: each coastal
## id's descriptor lists parts, and each part's 4 corners are local-space coordinates in world
## units, tile = 32 units, x=width, y=length (+y = screen down), z=height). Each part's cel is
## stretched over its quad exactly the way the original's CCB corner-mapping does (document 38),
## so sizes, tilt and height are traced, not estimated. This replaces the earlier hand-made
## composition (a ring of flat cards + an invented palm-trunk card + PALM_SCALE): no decoration
## in the original references the trunk cel that composition drew.
##
## All quads are batched into one ArrayMesh per atlas page (thousands of parts, one draw call
## each would be wasteful) and use alpha-scissor instead of blending, so no depth sorting is
## needed for the hard-edged pixel art.
##
## Still NOT modelled: the original's per-tile position jitter (descriptor callback +0x28,
## document 35 -- a deterministic hash that nudges each decoration off its tile centre) and the
## team-colour cel variant for flag bit 3.

const EFFECT_PAGE := 1
const SHADOW_ALPHA := 0.3

var pack: Pack
var level: LevelData


func setup(shared_pack: Pack, shared_level: LevelData) -> void:
	pack = shared_pack
	level = shared_level
	_build()


func _build() -> void:
	var tile := pack.tile_size_px
	var builders := {}  # page index -> SurfaceTool
	for entry in level.decorations:
		var parts: Array = pack.get_decoration_parts(int(entry.get("coastal_id", 0)))
		var cx := (float(entry.get("x", 0)) + 0.5) * tile
		var cz := (float(entry.get("y", 0)) + 0.5) * tile
		for part in parts:
			if not part.has("corners"):
				continue
			var s := pack.get_sprite(part.get("sprite_id", ""))
			if s.is_empty():
				continue
			var page := int(s.get("page", 0))
			if not builders.has(page):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				builders[page] = st
			var off: Array = part.get("offset", [0.0, 0.0])
			var corners: Array[Vector3] = []
			for c in part["corners"]:
				corners.append(Vector3(cx + off[0] + c[0], c[2] + 0.5, cz + off[1] + c[1]))
			_add_quad(builders[page], corners, s, pack.get_texture(page))

	for page in builders:
		var tex := pack.get_texture(page)
		var st: SurfaceTool = builders[page]
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_texture = tex
		if page == EFFECT_PAGE:
			# Effect-mask cels (document 9: a translucent darken blend through the game's shadow
			# tables, e.g. the palm/bush ground shadows). The exact darken strength isn't recorded
			# (rows 2/4 of a 32-row table) -- black at SHADOW_ALPHA is a placeholder, not traced.
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(0.0, 0.0, 0.0, SHADOW_ALPHA)
		else:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mi.material_override = mat
		add_child(mi)


## Same corner -> UV mapping and split-diagonal choice as VehicleBoxRender3D._build_warped_mesh:
## corners run in loop order, mapped to the cel's TL, TR, BR, BL; the diagonal whose two triangles
## both agree with the quad's overall normal (Newell's method) avoids a hole on non-convex quads.
func _add_quad(st: SurfaceTool, c: Array[Vector3], s: Dictionary, tex: Texture2D) -> void:
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var sx: float = s.get("x", 0)
	var sy: float = s.get("y", 0)
	var sw: float = s.get("w", 0)
	var sh: float = s.get("h", 0)
	var uvs := [
		Vector2(sx / tw, sy / th), Vector2((sx + sw) / tw, sy / th),
		Vector2((sx + sw) / tw, (sy + sh) / th), Vector2(sx / tw, (sy + sh) / th),
	]
	var n := Vector3.ZERO
	for i in 4:
		var a := c[i]
		var b := c[(i + 1) % 4]
		n += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
	n = n.normalized()
	var score_02 := (c[1] - c[0]).cross(c[2] - c[0]).dot(n) + (c[2] - c[0]).cross(c[3] - c[0]).dot(n)
	var score_13 := (c[1] - c[0]).cross(c[3] - c[0]).dot(n) + (c[2] - c[1]).cross(c[3] - c[1]).dot(n)
	var tri := [0, 1, 2, 0, 2, 3] if score_02 >= score_13 else [0, 1, 3, 1, 2, 3]
	for idx in tri:
		st.set_uv(uvs[idx])
		st.add_vertex(c[idx])
