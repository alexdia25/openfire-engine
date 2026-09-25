extends VehicleModule
## Ground driving: FUN_0040c190 (document 45) with the movement step of FUN_0040b980 (document 54), and the Jeep's own
## handler FUN_0040db80's two extras as options (documents 62, 94). Speeds, acceleration, friction and turn rate are the
## definition's `drive` numbers (record +0x168..+0x178), already on the Vehicle.

const SCHEMA := {
	"slot": "drive", "doc": "Wheeled / tracked driving over the ground (FUN_0040c190; the Jeep's FUN_0040db80 adds the two options)",
	"params": {
		"turn_accelerates": {"type": "bool", "default": false, "provenance": "traced:62",
			"doc": "Turning with no throttle key held accelerates (the Jeep's FUN_0040db80)"},
		"road_follow": {"type": "bool", "default": false, "provenance": "traced:94",
			"doc": "With no turn key held the heading is pulled along the road (FUN_0040db80's block at 0x40dd50)"},
	},
	"channels": ["heading_deg", "speed", "position"],
}

const TICK_HZ := 62.5


func tick(v: Vehicle, delta: float) -> void:
	var controls := v._get_controls()
	if b("turn_accelerates") and controls.y == 0.0 and controls.x != 0.0:
		controls.y = 1.0   # FUN_0040db80 (document 62): turning without a throttle key accelerates
	var turn := controls.x
	var turn_before := v.heading_deg
	v.heading_deg = fposmod(v.heading_deg + turn * v.turn_rate_deg * delta, 360.0)
	if b("road_follow"):
		# FUN_0040db80's block at 0x40dd50 (document 94): FUN_0040c390 is only called when a throttle is on (the friction bit is clear),
		# so the road mask keeps its last value while coasting; with no turn key held the heading is pulled along the road
		if controls.y != 0.0:
			v._road_mask = v._road_mask_here()
		if turn == 0.0 and v._road_mask != 0:
			v.heading_deg = RoadAssist.steer(v._road_mask, v.heading_deg, v.position, v.turn_rate_deg, delta)

	var thrust := controls.y
	var terrain_scale := v._terrain_speed_scale()
	if thrust > 0.0:
		v.speed = minf(v.speed + v.accel * delta, v.max_speed * terrain_scale)
	elif thrust < 0.0:
		v.speed = maxf(v.speed - v.brake * delta, -v.reverse_max_speed * terrain_scale)
	else:
		v.speed = move_toward(v.speed, 0.0, v.friction * delta)
	_move(v, turn_before, delta)


## FUN_0040b980's movement step (document 54). The turn is already applied to `heading_deg` and the speed updated; the
## displacement is speed x the new heading. Standing still, a turn that would overlap something is undone. Moving, if the
## new place overlaps: undo the turn and try the same displacement with the old heading; if that also overlaps, do not
## move and bounce back at a quarter of the speed (-speed >> 2).
func _move(v: Vehicle, heading_before: float, delta: float) -> void:
	v.moving = v.speed != 0.0 or v.heading_deg != heading_before
	if v.speed != 0.0:
		v.fuel -= absf(v.speed) * delta / 32.0
		if v.fuel <= 0.0:
			v.fuel = 0.0
			if v.alive:
				v._die()
			return
	var rad := deg_to_rad(v.heading_deg)
	var step := Vector2(cos(rad), sin(rad)) * v.speed * delta
	var target := v.position + step
	if not v.blocked_test.is_valid():
		v.position = target
		return
	if v.speed == 0.0:
		if v.heading_deg != heading_before and v.blocked_test.call(v, v.position, v.heading_deg):
			v.heading_deg = heading_before
		return
	if not v.blocked_test.call(v, target, v.heading_deg):
		v.position = target
		return
	if v.heading_deg != heading_before and not v.blocked_test.call(v, target, heading_before):
		v.heading_deg = heading_before
		v.position = target
		return
	v.heading_deg = heading_before
	v.speed = -v.speed * 0.25
