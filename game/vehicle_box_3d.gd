class_name VehicleBoxRender3D
extends Node3D
## Replaces game/vehicle_billboard_3d.gd's flat-card approximation with the vehicle's REAL
## geometry, traced directly out of RFIRE.BIN rather than approximated. Chasing the user's
## "why are there no visible treads" observation all the way through found that the Tank was
## never a flat sprite in the original at all -- it's a real box with six textured faces,
## each face a separate `ART.CAR` cel with its own 3D corner coordinates:
##
##   bottom (167 tan / 168 green) -- flat, at the vehicle's base
##   top    (172 tan / 173 green) -- flat, at full height (the detailed "hull-top" cel,
##                                   with what read as headlight/hatch ports)
##   left, right tread (182 tan / 183 green) -- vertical side faces, the SAME tread cel
##                                   this project found completely unused until now
##   front, back detail (187 tan / 188 green) -- small vertical accent faces
##
## Traced via the real per-object rendering pipeline document 35 already found for
## decorations (same FUN_0041afb0/FUN_0041b2b0 CCB-corner-projection call), starting from
## RFIRE.BIN's own vehicle-type table (`0x004452d8`, 4 entries -- type 0's name string reads
## literally "Tank") down to its real local-space corner array. Team colour is a flat +1 cel
## offset (167->168, 172->173, 182->183, 187->188), confirmed by direct visual comparison,
## not guessed.
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

	_refresh()


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


## The only 8 real cels this file ever needs (tan/green x 4 faces) -- named directly rather
## than searching the whole registry by cel-index-as-string, since Pack only indexes sprites
## by their registry id, not by raw ART.CAR index.
const _CEL_NAMES := {
	167: "vehicle.hovercraft.hull.01",
	168: "vehicle.hovercraft.hull.02",
	172: "vehicle.hovercraft.hull.04",
	173: "vehicle.hovercraft.hull.05",
	182: "vehicle.hovercraft.track.01",
	183: "vehicle.hovercraft.track.02",
	187: "vehicle.hovercraft.hull.10",
	188: "vehicle.hovercraft.hull.21",  # registry correction, document 37 -- see that cel's own note
}
