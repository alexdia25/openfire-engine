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
## NONE of these 8 are instantiated -- see DETAIL_PARTS and WARPED_DETAIL_PARTS below for the
## full story. Two real bugs got found and fixed along the way (a triangulation-winding bug
## producing an inverted triangle/visible hole for a non-convex quad; a missing
## `.transparency` line rendering every transparent pixel as opaque black), and each looked
## like real progress in turn -- but a real, visible defect (most concretely: cel 212, a 16x16
## circular ring, stretched across a corner span ~3.25x longer in one axis than the other,
## spills visibly past the tread's own wheel graphics instead of sitting on one of them)
## survived both fixes. Non-uniform stretching distorts detailed/circular content even when the
## destination is a genuine rectangle, not just when it's skewed -- a materially different (and
## still unresolved) problem from either bug already fixed. All 8 are reverted; see DETAIL_PARTS'
## own comment for the honest, complete diagnosis.
##
## The colour-footprint map (`RF_DEBUG_PART_MAP=1`, with the real, already-verified camera
## settings -- an exaggerated tilt/zoom badly distorts this check) did settle the turret/gun
## barrel question conclusively rather than by absence, independent of whether any of these 8
## parts ever render correctly: none of their real 3D corners extend past the hull's own
## bounding box. The raised turret box and gun barrel visible in the user's reference
## screenshots are not anywhere in this exhaustively-walked 14-part descriptor -- not a search
## gap, a geometric impossibility for anything encoded in this specific record. Whatever draws
## them is a separate mechanism this file doesn't reach.
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
## NONE of these 8 are instantiated by setup() -- every one of them, including the 4 (177,
## 192 x2, 212) that are geometrically clean rectangles, was shipped and then pulled back out
## this same session after a real, visible defect survived two independent bug fixes:
##   - Fix 1 (real bug, confirmed correct): `_build_warped_mesh()`'s triangulation always split
##     a quad on the same diagonal, producing an inverted triangle and a visible hole for a
##     non-convex quad (cel 202's part 11). Fixed generally via a Newell-normal winding check.
##   - Fix 2 (real bug, confirmed correct): the hand-built `StandardMaterial3D` never set
##     `.transparency`, so every transparent source pixel rendered as opaque black -- the
##     "black gaps" both this file and its own earlier debug renders showed. Fixed with
##     `mat.transparency = TRANSPARENCY_ALPHA`.
##   - Neither fix addressed the actual remaining problem: **non-uniform stretching distorts
##     detailed/circular content even when the destination is a genuine rectangle.** 212 is a
##     16x16 circular ring stretched across a corner span roughly 16 wide x 52 long -- a true
##     rectangle, not skewed, but stretched ~3.25x more in one axis than the other, so the ring
##     spills visibly past the tread's own wheel graphics instead of sitting on one of them
##     (confirmed directly against a live render, user-reported). 177 (32x32) and 192 (32x16)
##     have the same non-uniform-scale problem at a smaller, less obvious magnitude. 197/207
##     (non-planar) and 202's two parts (one non-rectangular, one non-planar) have this same
##     problem *plus* an outright skew.
##
## The 6 primary FACES don't have this problem because they were already confirmed (document
## 37) to match their own corner span exactly at native size in BOTH dimensions -- a uniform
## 1:1 "scale," not a stretch. None of these 8 parts share that property in both dimensions
## (confirmed by comparing each cel's real atlas pixel size against its own corner span -- see
## the table in document 38's addendum). Two real, unresolved possibilities for what's actually
## missing: (a) the original engine has some correction this project hasn't found (a per-part
## scale field, a different placement rule for small decals vs. primary panels), confirmed NOT
## to be a separate CCB mode (`FUN_00419820` is identical for every part, decompiled and
## checked this session); or (b) this project's corner-to-part mapping for indices 6-13 is
## still subtly wrong despite passing every consistency check tried so far (shared corners with
## already-verified faces, boundary detection, real cel content matching plausible roles).
##
## Kept below as real, RE-verified data (cel, corners, and team-colour pairing where confirmed)
## for whoever resolves either possibility -- not deleted, not guessed at further.
const DETAIL_PARTS := [
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

## The other 4 real parts -- corners genuinely don't form a rectangle (202's two parts -- one's
## a trapezoid, one's non-planar) or aren't even planar (197, 207) -- same non-shipped status
## and same reasoning as DETAIL_PARTS above, with an outright skew on top. See that const's own
## comment for the full explanation.
const WARPED_DETAIL_PARTS := [
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

	# Debug-only: RF_DEBUG_PART_MAP=1 hides the 6 primary faces and colours all 8 real detail
	# parts (DETAIL_PARTS + WARPED_DETAIL_PARTS -- neither is instantiated normally, see both
	# consts' own comments) distinctly instead of texturing them, so a screenshot shows exactly
	# where each part's real 3D footprint sits relative to the hull -- this is what confirmed
	# (with the standard, already-verified camera settings -- an exaggerated tilt/zoom badly
	# distorts this) that none of the 8 extends past the hull's own bounding box, meaning the
	# turret/gun barrel visible in reference footage genuinely is not encoded anywhere in this
	# per-vehicle-type record, not just unaccounted-for by an incomplete search.
	if OS.get_environment("RF_DEBUG_PART_MAP") == "1":
		for s in _sprites:
			s.visible = false
		var debug_colors := [Color.RED, Color.ORANGE, Color.YELLOW, Color.GREEN, Color.CYAN, Color.BLUE, Color.PURPLE, Color.WHITE]
		var all_parts: Array = DETAIL_PARTS + WARPED_DETAIL_PARTS
		for i in all_parts.size():
			var part: Dictionary = all_parts[i]
			var mesh_instance := MeshInstance3D.new()
			add_child(mesh_instance)
			var cel: int = part["cel"]
			if part["team_pair"] != -1 and vehicle.team == "green":
				cel = part["team_pair"]
			_build_warped_mesh(mesh_instance, part["corners"], cel, debug_colors[i])
	# DETAIL_PARTS and WARPED_DETAIL_PARTS are NOT instantiated in a normal run -- see both
	# consts' own comments for why (every one of these 8 real parts produced a visible defect
	# once actually compared against the user's reference screenshots, surviving 2 real,
	# independently-confirmed bug fixes along the way). Only the 6 primary FACES render.

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
## RFIRE.BIN's own corner data -- see DETAIL_PARTS) textured with one cel's atlas region.
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
func _build_warped_mesh(mesh_instance: MeshInstance3D, corners: Array, cel_index: int, debug_color: Color = Color.TRANSPARENT) -> void:
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
	# StandardMaterial3D defaults transparency to DISABLED -- unlike Sprite3D (used for FACES
	# above), which configures its own material's alpha handling automatically. Without this,
	# every fully-transparent pixel in the source cel renders as opaque using whatever raw RGB
	# happens to sit there (often black), which is exactly the "black gaps" this file's own
	# earlier magenta-vs-textured debug comparison found and misdiagnosed as a scale/anchor
	# problem -- it's this missing line.
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Debug-only: RF_DEBUG_WARPED_MESH_COLOR=1 swaps the real texture for a flat colour, so a
	# screenshot shows exactly what triangle area this function actually covers, independent of
	# the texture's own UV sampling.
	if debug_color != Color.TRANSPARENT:
		mat.albedo_color = debug_color
	elif OS.get_environment("RF_DEBUG_WARPED_MESH_COLOR") == "1":
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
