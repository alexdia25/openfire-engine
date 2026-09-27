class_name CoplanarParts
extends RefCounted
## Painter's order without a depth tie (document 102). The original paints a vehicle's parts in list order, later over earlier, so a part lying in the same plane as an
## earlier one it overlaps simply covers it; a depth-tested renderer cannot order two quads in one plane (they z-fight). `shifts()` gives each such part a small outward
## shift along its normal, COPLANAR_STEP per earlier part it covers, so it wins the depth test exactly where the original's later paint would.

## PORT CHOICE: far under a pixel, above the depth resolution (about 0.0003 at 300 units with the camera's near plane at 10).
const COPLANAR_STEP := 0.05


## `quads` is one Array of four Vector3 corners per part, in draw order, in one space. Returns one Vector3 shift per part (zero for a part that covers nothing).
static func shifts(quads: Array) -> Array:
	var out: Array = []
	for j in quads.size():
		var cj: Array = quads[j]
		var n: Vector3 = (cj[1] - cj[0]).cross(cj[2] - cj[0])
		var covered := 0
		if n.length() > 0.0001:
			n = n.normalized()
			for i in j:
				if _in_plane(quads[i], cj[0], n) and _overlap_over_an_area(quads[i], cj):
					covered += 1
		var shift := Vector3.ZERO
		if covered > 0:
			var centre: Vector3 = (cj[0] + cj[1] + cj[2] + cj[3]) * 0.25
			shift = (n if n.dot(centre) >= 0.0 else -n) * COPLANAR_STEP * covered
		out.append(shift)
	return out


## The pairs (earlier, later) that `shifts()` resolves, for a check to print.
static func covered_pairs(quads: Array) -> Array:
	var out: Array = []
	for j in quads.size():
		var cj: Array = quads[j]
		var n: Vector3 = (cj[1] - cj[0]).cross(cj[2] - cj[0])
		if n.length() <= 0.0001:
			continue
		n = n.normalized()
		for i in j:
			if _in_plane(quads[i], cj[0], n) and _overlap_over_an_area(quads[i], cj):
				out.append([i, j])
	return out


static func _in_plane(quad: Array, point: Vector3, normal: Vector3) -> bool:
	for p in quad:
		if absf(normal.dot(p - point)) > 0.001:
			return false
	return true


## Whether the two quads' boxes overlap over an area (a shared edge or corner does not count: nothing is covered).
static func _overlap_over_an_area(a: Array, b: Array) -> bool:
	var spans := 0
	for axis in 3:
		var alo := minf(minf(a[0][axis], a[1][axis]), minf(a[2][axis], a[3][axis]))
		var ahi := maxf(maxf(a[0][axis], a[1][axis]), maxf(a[2][axis], a[3][axis]))
		var blo := minf(minf(b[0][axis], b[1][axis]), minf(b[2][axis], b[3][axis]))
		var bhi := maxf(maxf(b[0][axis], b[1][axis]), maxf(b[2][axis], b[3][axis]))
		var overlap := minf(ahi, bhi) - maxf(alo, blo)
		if overlap < -0.0001:
			return false
		if overlap > 0.0001:
			spans += 1
	return spans >= 2
