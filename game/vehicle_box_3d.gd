class_name VehicleBoxRender3D
extends Node3D
## Replaces game/vehicle_billboard_3d.gd's flat-card approximation with the vehicle's REAL
## geometry, traced directly out of RFIRE.BIN rather than approximated. Chasing the user's
## "why are there no visible treads" observation all the way through found that the Tank was
## never a flat sprite in the original at all -- it's a real multi-part 3D shape, and (document
## 39) a genuinely separate turret+barrel object drawn on top of it.
##
## **The Tank's hull has 6 real parts.** Document 38's "14 parts, not 6, not 8" finding was
## itself wrong, and document 39 found exactly why: the hull descriptor's own parts array
## (0x0043e700) sits in memory immediately before a DIFFERENT, real descriptor's parts array --
## the turret's (0x0043e7c0, exactly 6 part-records later) -- and boundary-detection walking
## forward from the hull's own array, with no way to know where one descriptor's data ends and
## an unrelated one begins, walked straight into the turret's real data and misread it as 8
## more hull parts. Those 8 "extra hull parts" were real records the whole time, just read
## against the WRONG corner array (the hull's 24-corner array instead of the turret's own
## 22-corner one, which happens to start exactly where the hull's ends) -- which is the real
## reason every one of them looked distorted, oversized, or "outside the bounds of the wheels"
## no matter which of 3 unrelated bugs got fixed along the way (a triangulation winding bug, a
## missing `.transparency` line, neither of which was ever the actual problem). See document
## 39 for the full trace and the reasoning that finally isolated it. The 6 real hull parts
## (FACES below) are exactly document 37's original, correct finding:
##
##   bottom (167 tan / 168 green) -- flat, at the vehicle's base
##   top    (172 tan / 173 green) -- flat, at full height (the detailed "hull-top" cel,
##                                   with what read as headlight/hatch ports)
##   left, right tread (182 tan / 183 green) -- vertical side faces, the SAME tread cel
##                                   this project found completely unused until now
##   front, back detail (187 tan / 188 green) -- small vertical accent faces
##
## **The turret and gun barrel are a real, separate object, now found and rendered
## (TURRET_PARTS below).** Decompiling the real vehicle draw dispatcher (`FUN_00402dc0`, not
## `FUN_0041b430` -- that's one level down, the generic per-descriptor renderer both the hull
## and the turret call) found it draws the hull once with the vehicle's own descriptor, then --
## when a linked turret sub-object exists -- swaps in a wholly different, dedicated descriptor
## (`0x0043e9b8`) and draws again with an independently composed rotation (hull heading plus a
## separate turret-aim angle). That second descriptor has its own real corner array
## (`0x0043e538`, 22 corners, contiguous with but distinct from the hull's) and its own 8 real
## parts -- the exact same 8 cels (177, 192 x2, 197, 207, 202 x2, 212) this project spent a
## whole session trying and failing to place correctly as hull decals, because they were never
## hull decals. Read against the CORRECT (turret's own) corner array, they form a coherent,
## correctly-scaled raised box (177/192x2/197/207, sitting right on the hull's own roof) with a
## barrel extending forward from it (202 x2) capped with a ring (212) -- matching the user's
## reference screenshots directly. This project does not yet model independent turret aim (no
## AI/player aim-angle state exists to drive it) -- the turret renders at the same heading as
## the hull, a known, documented simplification, not the real mechanism.
##
## Still open: cel 212 (the muzzle ring, part 7) renders visibly larger/lower than the barrel
## tip it caps -- confirmed real, unmodified data (triple-checked directly against the raw
## corner table, not a transcription error), and confirmed NOT explained by anything in
## `FUN_0041b2b0`'s own code this session re-checked for exactly this: the backface-culling
## flag bits it reads (piVar7[2]/[3], gated by flags bits 0x1/0x2) are unset here so inert; the
## rotation matrix `FUN_0041ae10` builds is a pure rotation (no embedded scale); the turret's
## angle-bucket lists all include index 7 at every viewing angle (a depth-sort order, not a
## per-angle subset -- it's never hidden). One hand-adjustment attempt (constraining the ring's
## height to the barrel's own tip band) was tried and reverted -- it fixed the size but broke
## the aspect ratio into a visibly squashed oval, confirming the raw data's own proportions
## (not the position) are more likely correct and this needs a real answer, not another guess.
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

## The Tank's real, SEPARATE turret+barrel descriptor (`0x0043e9b8`, document 39) -- a
## dedicated 8-part, 22-corner record, structurally identical in format to the hull's own but
## entirely distinct data. Corners already converted (same 8/3 fixed-point-to-pixel scale, same
## axis relabelling as FACES above) and confirmed against the correct (turret's own) corner
## array this time, not the hull's:
##   - 177: the turret's flat top panel (24 units above the vehicle's local origin -- well above
##     the hull's own 13.333-unit roof).
##   - 192 (x2), 197, 207: the turret box's 4 sloped side panels, tapering from the wider top
##     (177's edges) down to the hull's own roofline.
##   - 202 (x2): the gun barrel -- two panels meeting at a point, extending forward from the
##     turret box's front and rising slightly, ending flush with the hull's own front edge.
##   - 212: a ring/cap mounted vertically at the barrel's tip (the muzzle) -- real, unmodified
##     corner data, but renders visibly larger/lower than the barrel tip it caps; see the file
##     header for what's been ruled out and why this is flagged rather than hand-tuned further.
## This single set replaces this file's entire previous, wrong attempt at these same 8 cels
## (read against the hull's own corner array by mistake -- see the file header) -- every part
## here is a genuine rectangle or simple planar quad relative to the turret's own geometry, and
## renders cleanly with the same `_build_warped_mesh()` this file already has.
##
## Team colour: only cel 202's pair (203) is a confirmed real tan->green shift (measured this
## session). 177/192/197/207's own "+1" cels are already flagged in the registry as NOT part of
## a confirmed team pair -- unknown, not guessed, same as the hull's own unresolved decals were.
## 212 has no team variant at all (213 measures byte-identical to it, confirmed this session).
const TURRET_PARTS := [
	{"cel": 177, "team_pair": -1, "corners": [
		Vector3(-13.33, 24, -16), Vector3(13.33, 24, -16), Vector3(13.33, 24, 16), Vector3(-13.33, 24, 16),
	]},
	{"cel": 192, "team_pair": -1, "corners": [
		Vector3(-8, 24, -13.33), Vector3(-8, 24, 16), Vector3(-8, 13.33, 10.67), Vector3(-8, 13.33, -10),
	]},
	{"cel": 192, "team_pair": -1, "corners": [
		Vector3(8, 24, -13.33), Vector3(8, 24, 16), Vector3(8, 13.33, 10.67), Vector3(8, 13.33, -10),
	]},
	{"cel": 197, "team_pair": -1, "corners": [
		Vector3(-8, 24, 16), Vector3(8, 24, 16), Vector3(8, 13.33, 10.67), Vector3(-8, 13.33, 10.67),
	]},
	{"cel": 207, "team_pair": -1, "corners": [
		Vector3(-8, 24, -13.33), Vector3(8, 24, -13.33), Vector3(8, 13.33, -10), Vector3(-8, 13.33, -10),
	]},
	{"cel": 202, "team_pair": 203, "corners": [
		Vector3(8, 18.67, -14), Vector3(8, 18.67, -32), Vector3(0, 29.33, -32), Vector3(0, 24, -14),
	]},
	{"cel": 202, "team_pair": 203, "corners": [
		Vector3(-8, 18.67, -14), Vector3(-8, 18.67, -32), Vector3(0, 29.33, -32), Vector3(0, 24, -14),
	]},
	{"cel": 212, "team_pair": -1, "corners": [
		Vector3(-10, 29.33, -32), Vector3(10, 29.33, -32), Vector3(10, 8, -32), Vector3(-10, 8, -32),
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

	# Debug-only: RF_DEBUG_PART_MAP=1 colours each of the 8 TURRET_PARTS distinctly instead of
	# texturing them, so a screenshot shows exactly where each part's real 3D footprint sits --
	# this is what confirmed the turret sits well above the hull's own roofline (24 units vs
	# 13.333) rather than overlapping it, and that the barrel (202 x2) extends forward to the
	# hull's own front edge, matching the user's reference screenshots' proportions.
	var debug_part_map := OS.get_environment("RF_DEBUG_PART_MAP") == "1"
	var debug_colors := [Color.RED, Color.ORANGE, Color.YELLOW, Color.GREEN, Color.CYAN, Color.BLUE, Color.PURPLE, Color.WHITE]

	# Built once, not per-frame like the Sprite3D faces' _apply_cel: a vehicle's team never
	# changes after spawn, and rebuilding a SurfaceTool mesh every frame (unlike just swapping
	# a Sprite3D's texture/region) would be real, needless per-frame cost for no visual benefit.
	for i in TURRET_PARTS.size():
		var part: Dictionary = TURRET_PARTS[i]
		var mesh_instance := MeshInstance3D.new()
		add_child(mesh_instance)
		var cel: int = part["cel"]
		if part["team_pair"] != -1 and vehicle.team == "green":
			cel = part["team_pair"]
		if debug_part_map:
			_build_warped_mesh(mesh_instance, part["corners"], cel, debug_colors[i])
		else:
			_build_warped_mesh(mesh_instance, part["corners"], cel)

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
## RFIRE.BIN's own corner data -- see TURRET_PARTS) textured with one cel's atlas region.
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
	177: "vehicle.hovercraft.turret.top.01",
	182: "vehicle.hovercraft.track.01",
	183: "vehicle.hovercraft.track.02",
	187: "vehicle.hovercraft.hull.10",
	188: "vehicle.hovercraft.hull.21",  # registry correction, document 37 -- see that cel's own note
	192: "vehicle.hovercraft.turret.side.01",
	197: "vehicle.hovercraft.turret.back.01",
	202: "vehicle.hovercraft.turret.barrel.01",
	203: "vehicle.hovercraft.turret.barrel.02",  # renamed from turret_detail.01, document 39 -- see that cel's own note
	207: "vehicle.hovercraft.turret.front.01",
	212: "vehicle.hovercraft.turret.muzzle_ring.01",
}
