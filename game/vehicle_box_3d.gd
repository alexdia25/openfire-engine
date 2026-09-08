class_name VehicleBoxRender3D
extends Node3D
## Replaces game/vehicle_billboard_3d.gd's flat-card approximation with the vehicle's REAL
## geometry, traced directly out of RFIRE.BIN rather than approximated. Chasing the user's
## "why are there no visible treads" observation all the way through found that the Tank was
## never a flat sprite in the original at all -- it's a real multi-part 3D shape.
##
## The Tank's real descriptor has **14 parts, not 6 and not the 8 document 37's own addendum
## found** -- both earlier counts were undercounts from trusting the wrong signal (the
## descriptor's own count-like field turned out to be the CORNER array's length, not a part
## count; the angle-bucket draw-order lists only cover 6 of the 14 parts, not a manifest of all
## of them). Document 38 re-derived the real count the only reliable way: walking the parts
## array from index 0 and stopping at the first entry whose cel/corner indices are implausible
## -- applied generally (see tools/ghidra_scripts/DumpVehicleTypeParts.java), not just for the
## Tank. The first six (FACES below) are the ones this file already had rendering correctly:
##
##   bottom (167 tan / 168 green) -- flat, at the vehicle's base
##   top    (172 tan / 173 green) -- flat, at full height (the detailed "hull-top" cel,
##                                   with what read as headlight/hatch ports)
##   left, right tread (182 tan / 183 green) -- vertical side faces, the SAME tread cel
##                                   this project found completely unused until now
##   front, back detail (187 tan / 188 green) -- small vertical accent faces
##
## The remaining 8 real parts split into two groups (see EXTRA_PARTS and UNRESOLVED_PARTS below
## for the full story on each):
##   - 4 (177, 192 x2, 212) are instantiated and confirmed clean at every heading. Two are exact
##     positional duplicates of a FACES panel with a different cel (177 over the bottom, 192
##     over both the top and the left tread) -- read as trim/window/hatch decals layered on the
##     base panel (177's atlas note: "tan block, red-dot windows"; 192's: "tan cab, red
##     eyes+mouth trim"), not a second copy of the same face. 212 is this file's old, single
##     "WARPED_PARTS" entry, now confirmed to be a genuine flat (if tilted) rectangle.
##   - 4 more (197, 207, and BOTH of cel 202's real parts) are real but NOT instantiated -- this
##     session traced the actual cause precisely (a texture-UV mapping problem this function's
##     naive rectangle-onto-4-corners assumption gets wrong for a non-rectangular quad,
##     confirmed by a magenta-debug-colour render proving the triangle COVERAGE is already
##     complete and gap-free), a materially better diagnosis than the previous session's "every
##     triangulation looked glitched."
##
## Still open, and NOT settled by any of this: whether/how 177/192 take a team colour (their
## "+1" cels are already flagged in the registry as not a confirmed pair -- see EXTRA_PARTS' own
## comment), the UV fix above, and whether these 14 parts are really the *entire* Tank -- a
## raised turret box and gun barrel are visible in the user's reference screenshots and still
## don't match anything in this exhaustively-boundary-detected 14-part descriptor at all; a
## rendered screenshot of these 14 real parts (see document 38) is real evidence that gap is
## NOT hiding anywhere in this specific per-vehicle-type record, wherever it does live.
##
## Traced via the real per-object rendering pipeline document 35 already found for
## decorations (same FUN_0041afb0/FUN_0041b2b0 CCB-corner-projection call), starting from
## RFIRE.BIN's own vehicle-type table (`0x004452d8`, 4 entries -- type 0's name string reads
## literally "Tank") down to its real local-space corner array. Team colour is a flat +1 cel
## offset for the six FACES parts (167->168, 172->173, 182->183, 187->188), confirmed by direct
## visual comparison. Cel 202's own "+1" (203) measures genuinely greener (a real pair); 212's
## (213) measures byte-identical (not a real pair) -- both confirmed this session.
##
## `vehicle.hovercraft.rotation.tan.01-09` (game/vehicle_billboard_3d.gd's GROUND_DECAL
## texture, cels 218-226) turned out never to be referenced by this real descriptor at all --
## a reasonable guess made before any of this was traced, not the game's actual Tank art.
## GROUND_DECAL is kept as a fallback (`RF_DEBUG_VEHICLE_RENDER=ground_decal`) since it's
## still a real, working, previously-verified rendering path -- just not the accurate one.
##
## Coordinates below are converted once from RFIRE.BIN's raw 16.16 fixed-point corner values
## to pixels (the scale factor -- 8/3 -- was confirmed by checking it reproduces each face's
## own real sprite pixel dimensions exactly, not assumed). Local axes: X = vehicle width
## (left/right), Y = height (up), Z = length (front/back) -- a direct relabelling of the
## original's own (x=width, y=length, z=height) local space, not a guess. Which end (+Z or
## -Z) is the front, and the exact yaw needed to align it with Vehicle.heading_deg's own
## "0 = +X" convention, were matched empirically (screenshot against a real driven forward
## movement), the same way document 30 and the GROUND_DECAL facing fix both had to be.

const TEAM_COLOUR_CEL_OFFSET := {"tan": 0, "green": 1}

## Ground clearance so the bottom face doesn't clip into the terrain plane -- not a traced
## value (matches VehicleBillboard3D's own placeholder HEIGHT_PX reasoning).
const GROUND_CLEARANCE_PX := 2.0

## One entry per real face: base (tan) cel index, local center position (px), and local
## half-extents (px) matching that cel's own pixel dimensions exactly (64x64, 64x16, 16x16 --
## see the file header for how the fixed-point-to-pixel scale was confirmed against these).
## "axis" says which local plane the face lies in and which way it opens:
##   "top"    -- horizontal, texture faces +Y (up)
##   "side_x" -- vertical, texture faces +X or -X (left/right tread)
##   "side_z" -- vertical, texture faces +Z or -Z (front/back detail)
const FACES := [
	{"cel": 167, "center": Vector3(0, 0, 0), "half": Vector2(32, 32), "axis": "top", "sign": 1},
	{"cel": 172, "center": Vector3(0, 13.333, 0), "half": Vector2(32, 32), "axis": "top", "sign": 1},
	{"cel": 182, "center": Vector3(-18, 6.667, 0), "half": Vector2(32, 6.667), "axis": "side_x", "sign": -1},
	{"cel": 182, "center": Vector3(18, 6.667, 0), "half": Vector2(32, 6.667), "axis": "side_x", "sign": 1},
	{"cel": 187, "center": Vector3(0, 6.667, -22), "half": Vector2(8, 6.667), "axis": "side_z", "sign": -1},
	{"cel": 187, "center": Vector3(0, 6.667, 27), "half": Vector2(8, 6.667), "axis": "side_z", "sign": 1},
]

## The real descriptor's remaining 8 parts (indices 6-13 of the real 14 -- see document 38),
## found only after re-checking the boundary-detection this document 38 needed: the earlier
## "8 parts, not 6" addendum (document 37) was *itself* still an undercount, because it trusted
## the angle-bucket draw-order lists as a part manifest when they only ever cover the first six
## "primary" hull faces. These eight are drawn unconditionally, outside any angle bucket.
##
## Only 4 of the 8 are instantiated below -- confirmed rendering cleanly at every heading (this
## session swept all 8 compass directions, not just one screenshot). Two are exact positional
## duplicates of an existing FACES entry with a DIFFERENT cel (177 over the bottom's 167, 192
## over both the top's 172 and the left tread's 182) -- read as detail/trim decals layered on
## the base hull panel (177's atlas note is "tan block, red-dot windows", 192's is "tan cab, red
## eyes+mouth trim"), not a second copy of the same face. 212 (this file's old, single
## WARPED_PARTS entry) is a genuine flat, if tilted, rectangle -- confirmed clean on its own by
## the same sweep.
##
## The remaining 4 (197, 207, and BOTH of cel 202's real parts) are deliberately NOT
## instantiated -- see UNRESOLVED_PARTS below for why, and for this session's real, precise
## diagnosis (a texture-UV problem, not the triangulation/geometry problem the previous
## session's "every triangulation glitched" framing assumed).
##
## Team colour: only cel 202's pair (203) is a confirmed real tan->green shift (measured this
## session) -- moot for now since 202 isn't rendered. 177/192's own "+1" cels (178/193) are
## already flagged in the registry as NOT part of a confirmed team pair -- so, honestly, this
## file does not yet know whether/how these take a team colour, and deliberately does not guess:
## they draw their single known (tan) cel for both teams until that's traced. 212 has no team
## variant at all (213 measures byte-identical to it, confirmed this session).
const EXTRA_PARTS := [
	{"cel": 177, "team_pair": -1, "corners": [
		Vector3(-32, 0, -32), Vector3(32, 0, -32), Vector3(32, 0, 32), Vector3(-32, 0, 32),
	]},
	{"cel": 192, "team_pair": -1, "corners": [
		Vector3(-32, 13.333, -32), Vector3(32, 13.333, -32), Vector3(32, 13.333, 32), Vector3(-32, 13.333, 32),
	]},
	{"cel": 192, "team_pair": -1, "corners": [
		Vector3(-18, 13.333, 32), Vector3(-18, 13.333, -32), Vector3(-18, 0, -32), Vector3(-18, 0, 32),
	]},
	{"cel": 212, "team_pair": -1, "corners": [
		Vector3(8, 0, -22), Vector3(-8, 0, -22), Vector3(-8, 13.333, 30), Vector3(8, 13.333, 30),
	]},
]

## Real cel + corners for the 4 remaining parts of the real 14, NOT instantiated by setup().
## Both 202 parts were confirmed (this session, via a magenta-debug-colour material bypassing
## the real texture entirely) to have COMPLETE, gap-free triangle coverage -- the visible defect
## is a genuine texture-UV artifact, not a hole: this function's naive "map the atlas rectangle
## straight onto the 4 corners in order" UV assignment produces a warped/self-overlapping UV
## layout for a non-rectangular (here: concave) quad, which samples into the wrong part of the
## atlas (very likely the transparent/black padding around the real sprite) for some pixels.
## 197/207 are genuinely non-planar (not just non-rectangular), so likely need the same fix
## plus something else. Whoever picks this up next needs a real per-corner UV, not a rectangle
## stretched over 4 arbitrary points -- possibly stored in RFIRE.BIN's own corner/part data
## somewhere this session didn't look, since a 1996 renderer doing real quad texture-mapping
## must have had per-vertex UVs from *somewhere*.
const UNRESOLVED_PARTS := [
	{"cel": 197, "team_pair": -1, "corners": [
		Vector3(32, 13.333, -32), Vector3(-18, 13.333, -32), Vector3(-18, 0, -32), Vector3(32, 13.333, 32),
	]},
	{"cel": 207, "team_pair": -1, "corners": [
		Vector3(-32, 13.333, -32), Vector3(-18, 13.333, 32), Vector3(-18, 0, 32), Vector3(-32, 13.333, 32),
	]},
	{"cel": 202, "team_pair": 203, "corners": [
		Vector3(18, 13.333, 32), Vector3(8, 13.333, -22), Vector3(-8, 13.333, -22), Vector3(18, 13.333, -32),
	]},
	{"cel": 202, "team_pair": 203, "corners": [
		Vector3(18, 0, -32), Vector3(18, 0, 32), Vector3(-8, 13.333, -22), Vector3(18, 13.333, -32),
	]},
]

## Empirically matched (see file header) -- 0 until verified against a real driven-forward
## screenshot, the same process the GROUND_DECAL facing fix needed.
const FACING_OFFSET_DEG := 90.0

var vehicle: Vehicle
var pack: Pack
var _sprites: Array[Sprite3D] = []
var _extra_meshes: Array[MeshInstance3D] = []


func setup(shared_vehicle: Vehicle, shared_pack: Pack) -> void:
	vehicle = shared_vehicle
	pack = shared_pack
	vehicle.visible = false  # logic only -- same reasoning as VehicleBillboard3D

	for face in FACES:
		var sprite := Sprite3D.new()
		sprite.shaded = false
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sprite.pixel_size = 1.0
		sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		sprite.position = face["center"]
		match face["axis"]:
			"top":
				sprite.rotation_degrees.x = -90.0
			"side_x":
				sprite.rotation_degrees.y = 90.0 if face["sign"] > 0 else -90.0
			"side_z":
				sprite.rotation_degrees.y = 180.0 if face["sign"] > 0 else 0.0
		add_child(sprite)
		_sprites.append(sprite)

	for part in EXTRA_PARTS:
		var mesh_instance := MeshInstance3D.new()
		add_child(mesh_instance)
		_extra_meshes.append(mesh_instance)

	# Built once, not per-frame like the Sprite3D faces' _apply_cel: a vehicle's team never
	# changes after spawn, and rebuilding a SurfaceTool mesh every frame (unlike just swapping
	# a Sprite3D's texture/region) would be real, needless per-frame cost for no visual benefit.
	for i in EXTRA_PARTS.size():
		var part: Dictionary = EXTRA_PARTS[i]
		var cel: int = part["cel"]
		if part["team_pair"] != -1 and vehicle.team == "green":
			cel = part["team_pair"]
		_build_warped_mesh(_extra_meshes[i], part["corners"], cel)

	_refresh()


## Approximates the quad's own overall normal via Newell's method (sum of successive edge
## cross products) -- works even for a not-quite-planar quad, which is exactly why this is
## Newell's method rather than a single 3-point cross product: it doesn't depend on picking
## "the right" 3 corners out of 4 that might not agree.
func _quad_normal(corners: Array) -> Vector3:
	var n := Vector3.ZERO
	for i in corners.size():
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % corners.size()]
		n += Vector3(
			(a.y - b.y) * (a.z + b.z),
			(a.z - b.z) * (a.x + b.x),
			(a.x - b.x) * (a.y + b.y),
		)
	return n.normalized()


## Builds a two-triangle quad from four real corners (in loop order, taken directly from
## RFIRE.BIN's own corner data -- see EXTRA_PARTS) textured with one cel's atlas region.
## Sprite3D can't represent this (it's always an axis-aligned rectangle in its own local
## plane); a real ArrayMesh is the only way to place a non-rectangular quad exactly.
##
## The diagonal to split on (0-2 or 1-3) is NOT always 1-3: real corner data extracted this
## session (document 38 -- Tank part 11, cel 202) turned out to be a non-convex quad, where
## splitting on the wrong diagonal produces one inverted/overlapping triangle and a visible
## hole in the rendered hull (confirmed by disabling every other new part one at a time until
## this one was isolated as the cause). The fix that works for both convex and non-convex
## simple quads: pick whichever diagonal produces two triangles that both wind the same way as
## the quad's own overall normal (see _quad_normal above) -- the wrong diagonal always produces
## at least one triangle winding the opposite way.
func _build_warped_mesh(mesh_instance: MeshInstance3D, corners: Array, cel_index: int) -> void:
	var s := pack.get_sprite(_CEL_NAMES.get(cel_index, ""))
	if s.is_empty():
		return
	var tex := pack.get_texture(int(s.get("page", 0)))
	if tex == null:
		return
	var tex_w := float(tex.get_width())
	var tex_h := float(tex.get_height())
	var sx: float = s.get("x", 0)
	var sy: float = s.get("y", 0)
	var sw: float = s.get("w", 0)
	var sh: float = s.get("h", 0)
	# Atlas-region UVs, matching Sprite3D's region_rect elsewhere in this file -- same
	# source rect, just computed by hand since ArrayMesh has no region_rect equivalent.
	var uvs := [
		Vector2(sx / tex_w, sy / tex_h),
		Vector2((sx + sw) / tex_w, sy / tex_h),
		Vector2((sx + sw) / tex_w, (sy + sh) / tex_h),
		Vector2(sx / tex_w, (sy + sh) / tex_h),
	]

	var normal := _quad_normal(corners)
	var c0: Vector3 = corners[0]
	var c1: Vector3 = corners[1]
	var c2: Vector3 = corners[2]
	var c3: Vector3 = corners[3]
	# Score each candidate diagonal by how well its two triangles' own normals agree with the
	# quad's overall normal -- the correct diagonal scores positively on both; the wrong one
	# scores negatively on at least one (see this function's own comment above).
	var score_02 := (c1 - c0).cross(c2 - c0).dot(normal) + (c2 - c0).cross(c3 - c0).dot(normal)
	var score_13 := (c1 - c0).cross(c3 - c0).dot(normal) + (c2 - c1).cross(c3 - c1).dot(normal)
	var tri_indices: Array[int]
	if score_02 >= score_13:
		tri_indices = [0, 1, 2, 0, 2, 3]
	else:
		tri_indices = [0, 1, 3, 1, 2, 3]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for idx in tri_indices:
		st.set_uv(uvs[idx])
		st.add_vertex(corners[idx])
	st.generate_normals()

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# Debug-only: RF_DEBUG_WARPED_MESH_COLOR=1 swaps the real texture for a flat colour, so a
	# screenshot shows exactly what triangle area this function actually covers, independent of
	# the texture's own UV sampling. This is what distinguished "the mesh has a real hole" from
	# "the mesh is complete but its UVs sample the wrong part of the atlas" for UNRESOLVED_PARTS
	# (cel 202's magenta render this session had zero gaps, proving it's the latter).
	if OS.get_environment("RF_DEBUG_WARPED_MESH_COLOR") == "1":
		mat.albedo_color = Color.MAGENTA
	else:
		mat.albedo_texture = tex
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # real corner winding not verified -- see file header
	mesh_instance.mesh = st.commit()
	mesh_instance.material_override = mat


func _process(_delta: float) -> void:
	if vehicle == null:
		return
	global_position = Vector3(vehicle.position.x, GROUND_CLEARANCE_PX, vehicle.position.y)
	rotation_degrees.y = -vehicle.heading_deg + FACING_OFFSET_DEG
	_refresh()


func _refresh() -> void:
	if vehicle == null or vehicle.pack == null:
		return
	var offset: int = TEAM_COLOUR_CEL_OFFSET.get(vehicle.team, 0)
	for i in FACES.size():
		var cel: int = FACES[i]["cel"] + offset
		_apply_cel(_sprites[i], cel)


func _apply_cel(sprite: Sprite3D, cel_index: int) -> void:
	# Cel indices aren't sprite ids -- the pack only exposes sprite ids (section 2.4.2), so
	# this reverse-maps the handful of real cels this file cares about. See _CEL_NAMES below.
	var s := pack.get_sprite(_CEL_NAMES.get(cel_index, ""))
	if s.is_empty():
		return
	var tex := pack.get_texture(int(s.get("page", 0)))
	if tex == null:
		return
	sprite.texture = tex
	sprite.region_enabled = true
	sprite.region_rect = Rect2(s.get("x", 0), s.get("y", 0), s.get("w", 0), s.get("h", 0))


## The only real cels this file ever needs -- named directly rather than searching the whole
## registry by cel-index-as-string, since Pack only indexes sprites by their registry id, not
## by raw ART.CAR index.
const _CEL_NAMES := {
	167: "vehicle.hovercraft.hull.01",
	168: "vehicle.hovercraft.hull.02",
	172: "vehicle.hovercraft.hull.04",
	173: "vehicle.hovercraft.hull.05",
	177: "vehicle.hovercraft.hull.07",
	182: "vehicle.hovercraft.track.01",
	183: "vehicle.hovercraft.track.02",
	187: "vehicle.hovercraft.hull.10",
	188: "vehicle.hovercraft.hull.21",  # registry correction, document 37 -- see that cel's own note
	192: "vehicle.hovercraft.hull.12",
	197: "vehicle.hovercraft.hull.14",
	202: "vehicle.hovercraft.hull.16",
	203: "vehicle.hovercraft.turret_detail.01",
	207: "vehicle.hovercraft.hull.18",
	212: "vehicle.hovercraft.wheel_hub.01",
}
