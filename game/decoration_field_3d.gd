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
## All quads are batched into one ArrayMesh per atlas page, per chunk (thousands of parts, one draw
## call each would be wasteful) and use alpha-scissor instead of blending, so no depth sorting is
## needed for the hard-edged pixel art.
##
## Per-tile position jitter (document 44, FUN_004365c0 / FUN_00436540): a descriptor whose
## callback at +0x28 is 0x4365c0 (28 parts) is nudged off its tile centre by a 16x16 table indexed
## by (tile_y & 15, tile_x & 15), each entry (dx, dy) = rand(25) - 12 world units. The table is
## built at level load from the MSVC LCG (seed*214013 + 2531011, >>16 & 0x7fff, scaled as
## (r * 2 * n) >> 16) seeded with the sum of every raw tile byte (LevelData.tile_seed).
## Flag-8 parts (building walls etc.) shift their cel by the tile's variant (0 = tan, 1 = green),
## carried per decoration from the level's tile table (see tools/convert_rfm.py).

## Effect-mask sprites (document 9) are the ones whose pack entry says `"kind": "effect"` (they used to be recognised by
## living on atlas page 1; pages are now packed at load time, PORTING_PLAN.md 2.7.5).
const SHADOW_ALPHA := 5.0 / 32.0

## A structure's own ground shadow (an "effect" part, e.g. cel 1026, `effect.shadow.hard.030` on the red-cross building) is a flat quad
## at z=0 that genuinely overlaps the same structure's wall-base corners, also at z=0 (tools/data/coastal_decoration_corners.json,
## coastal id 36/37: the shadow's footprint runs well past the walls' own -16..16/-9..9 span) -- a real coplanar tie, along the wall's
## ground-contact edge, between two separate MeshInstance3Ds (the shadow's transparent material, the wall's alpha-scissor one), which
## flickered with the camera angle exactly like the Jeep's wheel strips against its side panels (document 102).
##
## CORRECTION: the first attempt shifted the shadow *below* the wall by one CoplanarParts.COPLANAR_STEP, on the assumption that (as with
## the Jeep's wheels) the later-drawn part should win. Checked against the real building with the shadow's alpha raised to make it
## unmissable (a diagnostic, not shipped): that shift lost the tie almost everywhere along the wall's edge instead of only exactly on
## it, hiding most of the shadow (reported: "the top of the shadow ... now it's underground"). At the untouched, exactly-tied height the
## shadow already wins the tie in this scene; shifting it *up* reinforces that instead of reversing it, and was confirmed, screenshot in
## hand, to match the reference look at three different camera tilts. Kept as a small constant step (not per-pair CoplanarParts) since
## only one kind (the shadow) ever needs this specific shift, and it always shifts the same way.
##
## SECOND CORRECTION: a HALF step, not a whole one. _build_chunk() now also runs CoplanarParts.shifts() across a whole chunk, for a
## different tie (two neighbouring decorations' own parts, not a decoration and its own shadow -- see that function). Those shifts are
## always a whole multiple of COPLANAR_STEP; at exactly one whole step above the ordinary 0.5 ground height, a covered ground-level part
## shifted by that same one step would land EXACTLY on the shadow baseline -- a brand new accidental tie this fix would otherwise
## introduce between a shadow and an unrelated shifted part that happens to share its footprint. A half step can never equal any whole
## multiple of COPLANAR_STEP, so this can't happen; it stays strictly above 0.5, so the shadow still always wins as before.
const SHADOW_Z_BIAS := 0.5 + CoplanarParts.COPLANAR_STEP * 0.5

## Decorations are batched per CHUNK_TILES x CHUNK_TILES tile block, not one mesh set for the whole
## level: a single tile's state change (a crushed bush, a gate opening) used to rebuild EVERY
## decoration on the map -- up to ~11000 quads for one tile, a stutter on every hit that got worse
## the bigger the level (reported: level 95's frame-rate issues on any destruction, and sometimes
## just from driving over a crushable bush). Rebuilding only the tile's own chunk bounds the cost to
## that chunk's own decoration count regardless of level size. Decoration entries are mutated in
## place (LevelData.set_coastal_id et al. never add or remove entries), so the chunk index built once
## at setup() stays valid for the level's whole lifetime.
const CHUNK_TILES := 8

var pack: Pack
var level: LevelData
var _chunks: Dictionary = {}          ## Vector2i(chunk) -> Node3D
var _indices_by_chunk: Dictionary = {}  ## Vector2i(chunk) -> Array[int] (indices into level.decorations)


func setup(shared_pack: Pack, shared_level: LevelData) -> void:
	pack = shared_pack
	level = shared_level
	_indices_by_chunk.clear()
	for i in level.decorations.size():
		var entry: Dictionary = level.decorations[i]
		var key := _chunk_key(int(entry.get("x", 0)), int(entry.get("y", 0)))
		if not _indices_by_chunk.has(key):
			_indices_by_chunk[key] = []
		(_indices_by_chunk[key] as Array).append(i)
	for key in _indices_by_chunk:
		_build_chunk(key)


func _chunk_key(tx: int, ty: int) -> Vector2i:
	return Vector2i(floori(float(tx) / CHUNK_TILES), floori(float(ty) / CHUNK_TILES))


## Rebuilds only the chunk this tile's decoration lives in, after that tile changed state.
func refresh_tile(tile: Vector2i) -> void:
	var key := _chunk_key(tile.x, tile.y)
	if _indices_by_chunk.has(key):
		_build_chunk(key)


func _build_chunk(chunk_key: Vector2i) -> void:
	var old: Node = _chunks.get(chunk_key)
	if old != null:
		old.queue_free()
		_chunks.erase(chunk_key)
	var tile := pack.tile_size_px

	# Pass 1: every part's own quad and sprite, across every decoration in the chunk together -- not
	# just one decoration's own parts. Buildings are commonly several adjacent tiles of the SAME
	# structure (a wall run, a facade), and their walls/shadows/marker signs routinely reach across the
	# tile boundary into a neighbour's own footprint: a real coplanar tie between TWO SEPARATE
	# decoration instances, the same painter's-order-vs-depth-test class as the vehicles (document 102)
	# and the single-decoration shadow tie already fixed above -- just one level up, between neighbours
	# instead of within one decoration's own parts. Reported: two close buildings flickering, alternating
	# which small pieces show, as the camera moves (level 32, "The OK Corral" -- confirmed against its
	# own real placements: every one of 45 close building pairs checked had a real tie). CoplanarParts
	# needs every quad in one list to find ties across decoration boundaries, so the shift is computed
	# once per chunk, not per decoration.
	var quads: Array = []
	var metas: Array = []  # parallel to quads: {sprite: Dictionary, page: int, kind: String}
	for i in _indices_by_chunk[chunk_key]:
		var entry: Dictionary = level.decorations[i]
		var parts: Array = pack.get_decoration_parts(int(entry.get("coastal_id", 0)))
		var cx := (float(entry.get("x", 0)) + 0.5) * tile
		var cz := (float(entry.get("y", 0)) + 0.5) * tile
		var jit: Vector2 = level.jitter_at(int(entry.get("x", 0)), int(entry.get("y", 0)))
		for part in parts:
			if not part.has("corners"):
				continue
			var sprite_id: String = part.get("sprite_id", "")
			if part.has("variant_sprite_ids"):
				var variant := clampi(int(entry.get("variant", 0)), 0, 3)
				var v: Variant = part["variant_sprite_ids"][variant]
				if variant <= 1 and v != null:
					# team-owned (document 44: variant 0 / 1 is the side): drawn in that side's colour (PORTING_PLAN.md 2.7.7)
					v = pack.team_variant(part["variant_sprite_ids"], level.side_colour(variant))
				if v != null:
					sprite_id = v
			var s := pack.get_sprite(sprite_id)
			if s.is_empty():
				continue
			var page := int(s.get("page", 0))
			var kind := String(s.get("kind", "sprite"))
			var off: Array = part.get("offset", [0.0, 0.0])
			var j := jit if part.get("jitter", false) else Vector2.ZERO
			var zoff: float = part.get("zoff", 0.0)
			var ground_y: float = SHADOW_Z_BIAS if kind == "effect" else 0.5
			var corners: Array[Vector3] = []
			for c in part["corners"]:
				corners.append(Vector3(cx + j.x + off[0] + c[0], c[2] + zoff + ground_y, cz + j.y + off[1] + c[1]))
			quads.append(corners)
			metas.append({"sprite": s, "page": page, "kind": kind})

	if quads.is_empty():
		return
	var shifts := CoplanarParts.shifts(quads)

	# Pass 2: batch the (now correctly ordered) quads into one mesh per atlas page/kind, as before.
	var builders := {}  # [page index, kind] -> SurfaceTool
	for i in quads.size():
		var meta: Dictionary = metas[i]
		var bkey := [meta["page"], meta["kind"]]
		if not builders.has(bkey):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			builders[bkey] = st
		var corners: Array[Vector3] = quads[i]
		var shift: Vector3 = shifts[i]
		if shift != Vector3.ZERO:
			for k in corners.size():
				corners[k] += shift
		_add_quad(builders[bkey], corners, meta["sprite"], pack.get_texture(meta["page"]))

	if builders.is_empty():
		return
	var root := Node3D.new()
	add_child(root)
	_chunks[chunk_key] = root
	for key in builders:
		var tex := pack.get_texture(int(key[0]))
		var st: SurfaceTool = builders[key]
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_texture = tex
		if key[1] == "effect":
			# Effect-mask cels (document 9): PRE0 13 = darken row 4 of the game's 32-row table, where
			# row k scales each colour channel by (31 - k) / 32 (FUN_00424420) -- 27/32 for row 4,
			# i.e. black at 5/32. (The original then snaps to the nearest palette index; ignored.)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(0.0, 0.0, 0.0, SHADOW_ALPHA)
		else:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mi.material_override = mat
		root.add_child(mi)


## Same corner -> UV mapping and split-diagonal choice as VehicleRender3D._quad:
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
