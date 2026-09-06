class_name EnemyVehicle
extends Vehicle
## Phase 4 step 6 (first pass): enemy AI, playable but not yet authentic -- same honesty
## flag as every other Phase 4 placeholder. RFIRE.BIN's real AI state machines and target
## selection haven't been traced at all (Phase 3 backlog: "AI state machines and target
## selection" is still untouched -- no anchor has even been picked yet), so this is not a
## reimplementation of anything found in the binary, unlike Phase 4 step 5's TargetPool.
## It's a from-scratch placeholder behaviour with one job: prove something can oppose the
## player at all. Overrides Vehicle's two behaviour seams (_get_controls/_wants_to_fire)
## and reuses everything else -- movement integration, rotation-frame rendering, firing,
## cooldown -- unchanged.
##
## Behaviour: idle until `target` (the player vehicle) comes within DETECT_RANGE_PX, then
## turn toward it and close in, and fire once roughly facing it within FIRE_RANGE_PX. No
## pathfinding, no cover, no squad behaviour, no difficulty tuning -- a seek-and-shoot
## placeholder, nothing more.

const DETECT_RANGE_PX := 500.0
const FIRE_RANGE_PX := 300.0
const AIM_TOLERANCE_DEG := 8.0  ## how close to "facing the target" counts as "aimed"

var target: Node2D = null

## Debug-only: RF_DEBUG_AI_LOG=1 prints this vehicle's targeting decision every 30 frames,
## the same cadence/pattern as terrain_view.gd's RF_DEBUG_CAMERA_LOG. Never affects a
## normal run (env var unset).
var _debug_ai_log: bool = OS.get_environment("RF_DEBUG_AI_LOG") == "1"


func _get_controls() -> Vector2:
	if target == null or not is_instance_valid(target):
		return Vector2.ZERO

	var to_target := target.position - position
	var dist := to_target.length()
	if dist > DETECT_RANGE_PX:
		if _debug_ai_log and Engine.get_process_frames() % 30 == 0:
			print("frame=%d enemy_pos=%s dist=%.1f (out of detect range, idle)" % [
				Engine.get_process_frames(), position, dist])
		return Vector2.ZERO

	var desired_heading := rad_to_deg(to_target.angle())
	var delta_heading := wrapf(desired_heading - heading_deg, -180.0, 180.0)

	var turn := clampf(delta_heading / AIM_TOLERANCE_DEG, -1.0, 1.0)
	# Close in while still far away or badly misaimed; hold back once close and lined up,
	# so it doesn't ram the player -- there's no vehicle-vs-vehicle collision to stop it.
	var thrust := 0.0
	if dist > FIRE_RANGE_PX * 0.6 or absf(delta_heading) > 45.0:
		thrust = 1.0

	if _debug_ai_log and Engine.get_process_frames() % 30 == 0:
		print("frame=%d enemy_pos=%s dist=%.1f heading=%.1f desired=%.1f turn=%.2f thrust=%.2f" % [
			Engine.get_process_frames(), position, dist, heading_deg, desired_heading, turn, thrust])
	return Vector2(turn, thrust)


func _wants_to_fire() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var to_target := target.position - position
	if to_target.length() > FIRE_RANGE_PX:
		return false
	var desired_heading := rad_to_deg(to_target.angle())
	return absf(wrapf(desired_heading - heading_deg, -180.0, 180.0)) <= AIM_TOLERANCE_DEG
