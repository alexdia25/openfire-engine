class_name RoadAssist
extends RefCounted
## The Jeep's road-following steering (document 94). While no turn key is held, the Jeep's drive handler (FUN_0040db80, the block at 0x40dd50-0x40de52) steers its heading
## toward the direction of the road it is on, plus a lean back toward the road's centre line, at the vehicle's full turn rate. No other vehicle's drive handler reads the
## road mask (FUN_0040c390 writes it into DAT_0048c7b0; its only readers are those six instructions).
##
## The road pieces are the terrain art ids 0x49-0x59 (73-89) and the coastal ids 0x4a / 0x4b; FUN_0040c390 stores the piece's DIRECTION MASK: bit 1 = a road running
## north, bit 2 = south, bit 4 = east, bit 8 = west (a straight piece has two bits, a corner two, a junction three or four). The mask table is the dword array at
## 0x44523c + art * 4 (DumpDwords.java 0x445360 17), a coastal id 0x4a gives 0xc and 0x4b gives 3 (no level uses either).
## The heading is the ORIGINAL's compass here (0 = north, clockwise, 22-bit: 0x400000 = 360 degrees); the port's heading_deg is that minus 90 (0 = +X), converted in steer().

## art id -> direction mask (FUN_0040c390's table at 0x44523c + art * 4)
const MASK_BY_ART := {73: 3, 74: 7, 75: 0xe, 76: 0xd, 77: 7, 78: 0xf, 79: 0xc, 80: 6, 81: 0xa, 82: 5, 83: 9, 84: 0xc, 85: 0xc, 86: 3, 87: 3, 88: 3, 89: 0xc}
const COASTAL_MASK := {0x4a: 0xc, 0x4b: 3}
const TILE := 32.0
## ((position in the tile & 0x1ffffc) - 0x100000) >> 2 is +-0x40000 = 22.5 degrees at the tile's edge: 22.5 degrees per 16 units of offset from the centre line.
const DEG_PER_UNIT := 22.5 / 16.0


## The mask of the tile under a vehicle: art ids 0x49-0x59 (`0x48 < art < 0x5a`), else the coastal ids 0x4a / 0x4b, else 0.
static func mask_for_tile(art_id: int, coastal_id: int) -> int:
	if art_id > 0x48 and art_id < 0x5a:
		return int(MASK_BY_ART.get(art_id, 0))
	return int(COASTAL_MASK.get(coastal_id, 0))


## The heading the road pulls toward, in the ORIGINAL's compass degrees, or -1.0 when the mask offers nothing for this heading. `offset` is the position within the tile
## (0..32 each) in the original's axes (x right, y down the screen).
static func target_compass_deg(mask: int, compass_deg: float, offset: Vector2) -> float:
	var h := fposmod(compass_deg, 360.0)
	var lx := (offset.x - TILE * 0.5) * DEG_PER_UNIT
	var ly := (offset.y - TILE * 0.5) * DEG_PER_UNIT
	if (mask & 1) != 0 and (h > 315.0 or h < 45.0):
		return fposmod(-lx, 360.0)
	if (mask & 2) != 0 and h > 135.0 and h < 225.0:
		return fposmod(180.0 + lx, 360.0)
	if (mask & 4) != 0 and h > 45.0 and h < 135.0:
		return fposmod(90.0 - ly, 360.0)
	if (mask & 8) != 0 and h > 225.0 and h < 315.0:
		return fposmod(ly - 90.0, 360.0)
	return -1.0


## One step of the assist for a vehicle with the port's `heading_deg` at `position` (pixels), turn rate `turn_rate_deg` degrees a second: the new port heading.
## FUN_004319e0(&heading, target, turn_rate): the heading moves toward the target the short way by at most the turn rate, and lands on it.
static func steer(mask: int, heading_deg: float, position: Vector2, turn_rate_deg: float, delta: float) -> float:
	var offset := Vector2(fposmod(position.x, TILE), fposmod(position.y, TILE))
	var compass := heading_deg + 90.0
	var target := target_compass_deg(mask, compass, offset)
	if target < 0.0:
		return heading_deg
	var diff := wrapf(target - compass, -180.0, 180.0)
	var step := turn_rate_deg * delta
	return fposmod(heading_deg + clampf(diff, -step, step), 360.0)
