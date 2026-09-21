class_name FlagMarker
extends Node2D
## The capture flag (object class 12, 0x44e3c0; documents 24, 26, 57, 65). Logic only: the view is game/flag_marker_3d.gd.
## `owner_idx` is its pool and its team (0 tan, 1 green: the cel variant). It is spawned where a pool's last target fell
## (FUN_00432710, document 26) and moved / animated every tick by FUN_00432920, which this file reproduces (document 65):
##
##  - `frame_counter` (obj+0x5c) picks the cloth frame, whole(counter) + 13 for the green team, out of 13 frames. It grows by
##    0x2aaa a tick (1/6 frame). While the flag "waves" (a dropped flag always; a carried one only while its carrier's
##    speed is above 0) it runs from 0 up to 10 and then loops in [4, 10); when the wave stops it runs on to 13 and rests at 0.
##  - `heading_deg` (obj+0x4c, 22-bit in the original; here degrees clockwise from north, the vehicle heading + 90) starts at
##    90 degrees. It eases at 0x4ccc a tick (1.69 degrees) toward `target_heading()`: 0 on the ground, and while carried the
##    carrier's heading pushed out of the two 50-degree wedges around north and south (kept in 25-155 and 205-335).
##  - a dropped flag on land falls to the ground; in water it drifts toward its "last safe position" (recorded whenever it
##    is on a land tile, per team) at up to 0.1 units a tick, accelerating 0x36 per tick (FUN_0042f280 / FUN_0042f730 /
##    FUN_00422e70). A flag whose carrier is destroyed is dropped where it hangs (document 57).
## The radar blip of its child object (descriptors 0x4404b0 / 0x4404c0, swapped every 15 ticks) belongs to the interface.

const TICK_HZ := 62.5
const FRAME_RATE := 10922.0 / 65536.0     ## 0x2aaa
const HEADING_RATE_DEG := 0x4ccc / 65536.0 * 5.625
const DRIFT_MAX := 0x1999 / 65536.0
const DRIFT_ACCEL := 0x36 / 65536.0

var pack: Pack
var owner_idx := 0
var carrier: Vehicle = null
var dropper: Vehicle = null
var frame_counter := 0.0
var heading_deg := 90.0           ## clockwise from north
var last_safe := Vector2.ZERO
var drift_speed := 0.0


func setup(shared_pack: Pack) -> void:
	pack = shared_pack


## The cloth frame to draw: whole(counter), plus 13 for the green team.
func cloth_frame() -> int:
	return int(floor(frame_counter)) + (13 if owner_idx != 0 else 0)


## FUN_00432920's wave counter. `waving` is true for a dropped flag and for a carried one whose carrier moves forward.
func advance_frames(waving: bool, delta: float) -> void:
	var step := FRAME_RATE * delta * TICK_HZ
	if waving:
		if frame_counter < 10.0:
			frame_counter += step
			if frame_counter > 10.0 - 1.0 / 65536.0:
				frame_counter -= 6.0 * floor((frame_counter - 4.0) / 6.0)
	elif frame_counter != 0.0:
		frame_counter += step
		if frame_counter > 13.0 - 1.0 / 65536.0:
			frame_counter = 0.0


## Where the flag's heading is heading: 0 on the ground; carried, the carrier's heading clamped as the original does.
func target_heading() -> float:
	if carrier == null or not is_instance_valid(carrier):
		return 0.0
	var h := fposmod(carrier.heading_deg + 90.0, 360.0)
	h = clampf(h, 25.0, 335.0)
	if h < 180.0:
		h = minf(h, 155.0)
	else:
		h = maxf(h, 205.0)
	return h


func advance_heading(delta: float) -> void:
	var step := HEADING_RATE_DEG * delta * TICK_HZ
	var d := wrapf(target_heading() - heading_deg, -180.0, 180.0)
	heading_deg = fposmod(heading_deg + clampf(d, -step, step), 360.0)
