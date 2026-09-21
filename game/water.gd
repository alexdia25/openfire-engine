class_name Water
extends RefCounted
## Whether a position is on land (0), in shallow water (1) or in deep water (2): FUN_0042f280 for an object and
## FUN_0042f410 for a bare point (document 62). Decided by the terrain tile under it (art id, 7 bits; the coastal
## decoration id is the second test):
##  - height above 1.0 -> 0 (in the air);  art above 0x33, or coastal id 0x4a / 0x4b (the pavement pieces) -> 0
##  - art 1 -> shallow, art 2 -> deep, arts 0 and 3 -> land
##  - art 4-0x17 (shore pieces): the object's shape is tested against one of four polygons turned by a quarter-turn
##    multiple; with the table's flag set an overlap means shallow, with it clear NO overlap means shallow
##  - art 0x18-0x27 -> shallow
##  - art 0x28-0x33: the position inside the tile's box -> shallow, outside -> deep
## Data: tools/data/water_tables.json (extract_water_tables.py).


## `poly` is the object's shape in world coordinates (empty = a point at `pos`). `z` is the object's height.
static func class_at(level: LevelData, pack: Pack, pos: Vector2, poly: PackedVector2Array = PackedVector2Array(),
		z: float = 0.0) -> int:
	if z > 1.0:
		return 0
	var tsz := float(pack.tile_size_px)
	var tx := int(floor(pos.x / tsz))
	var ty := int(floor(pos.y / tsz))
	if tx < 0 or ty < 0 or tx >= level.width or ty >= level.height:
		return 0
	var art := level.get_art_id(tx, ty) & 0x7F
	var coastal := level.get_coastal_id(tx, ty)
	if art > 0x33 or coastal == 0x4A or coastal == 0x4B:
		return 0
	if art == 1:
		return 1
	if art == 2:
		return 2
	if art < 4:
		return 0
	var centre := (Vector2(tx, ty) + Vector2(0.5, 0.5)) * tsz
	var tables: Dictionary = pack.water_tables
	if art < 0x18:
		var e: Dictionary = tables.get("coast", {}).get(str(art), {})
		if e.is_empty():
			return 0
		var shape := _shape_polygon(tables["shapes"][e["shape"]], centre, float(e["rot_steps"]) * 5.625 - 90.0)
		var overlap: bool
		if poly.is_empty():
			overlap = Geometry2D.is_point_in_polygon(pos, shape)
		else:
			overlap = Collision.polygons_hit(poly, shape)
		var flag := int(e["flag"]) != 0
		if overlap and flag:
			return 1
		if not overlap and not flag:
			return 1
		return 0
	if art < 0x28:
		return 1
	var b: Array = tables.get("boxes", {}).get(str(art), [])
	if b.is_empty():
		return 0
	var d := pos - centre
	return 1 if (d.x >= b[0] and d.x <= b[2] and d.y >= b[1] and d.y <= b[3]) else 2


## A shape's corners (x lateral, y = -forward) turned by `heading_deg` about `centre`, the same way vehicle shapes are.
static func _shape_polygon(pts: Array, centre: Vector2, heading_deg: float) -> PackedVector2Array:
	var rad := deg_to_rad(heading_deg)
	var fwd := Vector2(cos(rad), sin(rad))
	var right := Vector2(-fwd.y, fwd.x)
	var out := PackedVector2Array()
	for p in pts:
		out.append(centre + fwd * -float(p[1]) + right * float(p[0]))
	return out
