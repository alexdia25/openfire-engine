class_name VehicleBoxRender3D
extends Node3D
## Replaces game/vehicle_billboard_3d.gd's flat-card approximation with the vehicle's REAL
## geometry, traced directly out of RFIRE.BIN rather than approximated. Chasing the user's
## "why are there no visible treads" observation all the way through found that the Tank was
## never a flat sprite in the original at all -- it's a real multi-part 3D shape. Six parts
## are implemented here, each a separate `ART.CAR` cel with its own 3D corner coordinates,
## confirmed correct by a real driven screenshot:
##
##   bottom (167 tan / 168 green) -- flat, at the vehicle's base
##   top    (172 tan / 173 green) -- flat, at full height (the detailed "hull-top" cel,
##                                   with what read as headlight/hatch ports)
##   left, right tread (182 tan / 183 green) -- vertical side faces, the SAME tread cel
##                                   this project found completely unused until now
##   front, back detail (187 tan / 188 green) -- small vertical accent faces
##
## The real descriptor actually lists **eight** parts, not six -- found only after a user
## follow-up ("something's missing/wrong around the wheels") led to checking whether the
## angle-bucket draw-order data (see FACING_OFFSET_DEG's neighbourhood below) ever referenced
## more than six part indices. It does: parts 6 and 7 (cels 202, 212) are real, with real
## corner data, but every corner-order/triangulation tried for them produced a visible glitch
## (a thin stray spike) rather than a sensible panel -- so they're recorded as data
## (WARPED_PARTS) but deliberately NOT rendered yet, rather than ship something visibly wrong.
## A further user follow-up ("missing the top box part of the turret") suggests these two
## might not even be what a first guess assumed (a fender/ridge) -- unresolved, not a guess
## restated as fact. See document 37's addendum. **A separate, distinct gap, also unresolved:**
## the reference screenshots also show a raised turret box and gun barrel neither this file
## nor the 8-part descriptor account for at all -- if the real Tank has one, it isn't in this
## specific per-vehicle-type record; where it actually lives hasn't been traced.
##
## Traced via the real per-object rendering pipeline document 35 already found for
## decorations (same FUN_0041afb0/FUN_0041b2b0 CCB-corner-projection call), starting from
## RFIRE.BIN's own vehicle-type table (`0x004452d8`, 4 entries -- type 0's name string reads
## literally "Tank") down to its real local-space corner array. Team colour is a flat +1 cel
## offset for the six implemented parts (167->168, 172->173, 182->183, 187->188), confirmed by
## direct visual comparison. The unrendered parts' own "+1" cels were spot-checked the same
## way: 203 measures genuinely greener than 202 (a real pair), but 212/213 measure
## byte-identical (not a real pair) -- recorded in WARPED_PARTS for whoever finishes this.
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

## Parts 6 and 7 of the real 8-part descriptor -- real cel, real corners (px, in this file's
## local space), taken directly from RFIRE.BIN's corner array, not approximated as a flat
## panel. NOT currently instantiated by setup() -- see the file header for why (every
## triangulation tried produced a visible glitch, and a further user observation suggests the
## "fender"/"ridge" guess in these two comments may be wrong regardless). Kept as real,
## verified data for whoever solves the correct interpretation next, along with
## `_build_warped_mesh()` below (a generic "quad from 4 real corners" builder, otherwise
## unused). "team_colour" reflects a real measured check (see file header), not a guess.
const WARPED_PARTS := [
	{  # tentatively: right-tread-to-front panel -- unconfirmed, see file header
		"cel": 202,
		"team_colour": true,
		"corners": [
			Vector3(18, 0, -32), Vector3(18, 0, 32),
			Vector3(-8, 13.333, -22), Vector3(18, 13.333, -32),
		],
	},
	{  # tentatively: front-to-back centre panel -- unconfirmed, see file header
		"cel": 212,
		"team_colour": false,
		"corners": [
			Vector3(8, 0, -22), Vector3(-8, 0, -22),
			Vector3(-8, 13.333, 30), Vector3(8, 13.333, 30),
		],
	},
]

## Empirically matched (see file header) -- 0 until verified against a real driven-forward
## screenshot, the same process the GROUND_DECAL facing fix needed.
const FACING_OFFSET_DEG := 90.0

var vehicle: Vehicle
var pack: Pack
var _sprites: Array[Sprite3D] = []
var _warped_meshes: Array[MeshInstance3D] = []


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

	# WARPED_PARTS (cels 202/212, real data, real corners) is deliberately NOT instantiated
	# here yet -- both tried triangulations produced a visible glitch (a thin spike, not a
	# panel), and the user's own follow-up ("missing the top box part of the turret") suggests
	# these two parts may not even be what this file first guessed (a fender/ridge) at all.
	# Left as real, confirmed-but-unplaced data (see the file header and document 37's
	# addendum) rather than ship something visibly wrong.

	_refresh()


## Builds a two-triangle quad from four real corners (in loop order, taken directly from
## RFIRE.BIN's own corner data -- see WARPED_PARTS) textured with one cel's atlas region.
## Sprite3D can't represent this (it's always an axis-aligned rectangle in its own local
## plane); a real ArrayMesh is the only way to place a non-rectangular quad exactly.
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

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_uv(uvs[0]); st.add_vertex(corners[0])
	st.set_uv(uvs[1]); st.add_vertex(corners[1])
	st.set_uv(uvs[3]); st.add_vertex(corners[3])
	st.set_uv(uvs[1]); st.add_vertex(corners[1])
	st.set_uv(uvs[2]); st.add_vertex(corners[2])
	st.set_uv(uvs[3]); st.add_vertex(corners[3])
	st.generate_normals()

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
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
	182: "vehicle.hovercraft.track.01",
	183: "vehicle.hovercraft.track.02",
	187: "vehicle.hovercraft.hull.10",
	188: "vehicle.hovercraft.hull.21",  # registry correction, document 37 -- see that cel's own note
	202: "vehicle.hovercraft.hull.16",
	203: "vehicle.hovercraft.turret_detail.01",
	212: "vehicle.hovercraft.wheel_hub.01",
}
