class_name Collision
extends RefCounted
## The original's shape tests, for a moving point (a shell) against the shapes of tiles and vehicles --
## TRACED, document 53. Objects carry a chain of collision shapes on their draw descriptor (`+8`); two
## shapes collide when each one's mask contains the other's layer, their z ranges overlap, and the
## geometry test passes (FUN_0041e4c0 / FUN_0041e060). A shell's shape (type 4, layer 4, mask 0x43,
## z +-1.5 about its height) is a *swept point*: the segment from where it was to where it is.
##   - against an axis-aligned box (type 2, FUN_0041deb0): a hit if the new position is inside the box or
##     the segment crosses one of its four edges;
##   - against a convex polygon (type 3): a hit if the segment crosses an edge, or if the segment from the
##     new position to the polygon's centre crosses none (i.e. it is inside).
## Edge crossing is FUN_0041d670, an exact 2D segment-segment test.

const SHELL_LAYER := 4
const SHELL_MASK := 0x43
const SHELL_HALF_Z := 1.5


## Layer/mask rule of FUN_0041e4c0 between the shell and a shape given as {layer, mask}.
static func shell_collides_with(layer: int, mask: int) -> bool:
	return (SHELL_MASK & layer) != 0 and (mask & SHELL_LAYER) != 0


## z ranges overlap: [shell_z - 1.5, shell_z + 1.5] against [z0, z1].
static func shell_z_overlaps(shell_z: float, z0: float, z1: float) -> bool:
	return z0 <= shell_z + SHELL_HALF_Z and shell_z - SHELL_HALF_Z <= z1


static func segments_cross(a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2) -> bool:
	return Geometry2D.segment_intersects_segment(a1, a2, b1, b2) != null


## `box` = [minx, miny, maxx, maxy] relative to `origin`.
static func segment_hits_box(from: Vector2, to: Vector2, origin: Vector2, box: Array) -> bool:
	var x0: float = origin.x + float(box[0])
	var y0: float = origin.y + float(box[1])
	var x1: float = origin.x + float(box[2])
	var y1: float = origin.y + float(box[3])
	if to.x >= x0 and to.x <= x1 and to.y >= y0 and to.y <= y1:
		return true
	var c := [Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]
	for i in 4:
		if segments_cross(from, to, c[i], c[(i + 1) % 4]):
			return true
	return false


## `poly` in world coordinates, convex.
static func segment_hits_polygon(from: Vector2, to: Vector2, poly: PackedVector2Array) -> bool:
	for i in poly.size():
		if segments_cross(from, to, poly[i], poly[(i + 1) % poly.size()]):
			return true
	return Geometry2D.is_point_in_polygon(to, poly)


## A vehicle's shape against another shape (document 54): each mask must contain the other's layer, the z ranges
## overlap, and the vehicle's polygon must overlap the box or polygon (FUN_0041d8d0 / FUN_0041dc10).
static func vehicle_collides_with(v_layer: int, v_mask: int, layer: int, mask: int) -> bool:
	return (v_mask & layer) != 0 and (mask & v_layer) != 0


static func z_ranges_overlap(a0: float, a1: float, b0: float, b1: float) -> bool:
	return a0 <= b1 and b0 <= a1


static func polygon_hits_box(poly: PackedVector2Array, origin: Vector2, box: Array) -> bool:
	var r := PackedVector2Array([
		origin + Vector2(box[0], box[1]), origin + Vector2(box[2], box[1]),
		origin + Vector2(box[2], box[3]), origin + Vector2(box[0], box[3])])
	return not Geometry2D.intersect_polygons(poly, r).is_empty()


static func polygons_hit(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	return not Geometry2D.intersect_polygons(a, b).is_empty()
