class_name EdgeGuard
extends RefCounted
## The map-edge guard: Return Fire's submarine (object class 0xf, "SUB", descriptor 0x44ec38; issue #68, document 112).
## A vehicle flagged to attract it (the Heli) that strays more than `spawn_margin` units past the map makes the match create
## one (FUN_00434e80, at most one at a time); this class is its behaviour, a state machine of the original's five
## behaviour functions. Pure logic, no nodes: MatchController ticks it, a view draws `shown_frame()` at `position`.
## Every number comes from the pack's world/edge_guard.json (the traced originals are in the comments); a pack without the
## table has no guard.
##
##   HUNT  (FUN_00434c00)  pick the vehicle furthest off the map; once one has been off for `hunt_ticks` (0xf0) move onto it,
##                         link it, RISE. No target: the object is removed as soon as it is fully down (frame < 1).
##   RISE  (FUN_00434d10)  animation mode 1; at frame `surfaced_frame` (20.0) -> AIM with the fire timer = now + `aim_ticks`
##                         (0xb4). Target gone -> DIVE.
##   AIM   (FUN_00434db0)  mode 1; at the timer launch one rocket (FUN_00415480, type `projectile`) at the target and link to
##                         the rocket -> WAIT. Target gone -> WAIT with nothing linked.
##   WAIT  (FUN_00434e40)  mode 1 until the linked rocket is gone, then DIVE.
##   DIVE  (FUN_00434d80)  mode 2; at frame < 1 -> HUNT with the timer cleared.
## Each tick runs behaviours until one returns "done for this tick", then steps the animation frame (FUN_00434b30).

enum State { HUNT, RISE, AIM, WAIT, DIVE }
enum Mode { HOLD = 0, RISE = 1, DIVE = 2 }

var cfg: Dictionary
var state := State.HUNT
var mode := Mode.HOLD
var frame := 0.0                 ## obj+0x5c, 0..25 (the original's 16.16); frame k shows sprite k - 1, 0 shows nothing
var position := Vector2.ZERO     ## where it is drawn (obj+0x40/+0x44; z is 0)
var now := 0.0                   ## the match clock in ticks (0x480d38)
var finished := false            ## the object removed itself (FUN_0042c0f0)
var target: Node2D = null        ## obj+0x2c while it is linked to a vehicle
var rocket: Node2D = null        ## obj+0x2c once it is linked to its rocket
var _timer := 0.0                ## obj+0x60: the hunt's off-map clock, then the fire time
## Called as launcher.call(origin: Vector2, target: Node2D) -> Node2D (the rocket) or null; set by the match.
var launcher := Callable()


func _init(config: Dictionary) -> void:
	cfg = config


func _f(key: String, fallback: float) -> float:
	return float(cfg.get(key, fallback))


## Sprite index to draw (frame - 1), -1 for nothing.
func shown_frame() -> int:
	return int(floorf(frame)) - 1


## One match tick step. `ticks` is the elapsed time in ticks; `overshoot` maps every vehicle that is off the map right now to
## how far past the nearest edge it is (units), the quantity FUN_00434c00 maximises.
func tick(ticks: float, overshoot: Dictionary) -> void:
	if finished:
		return
	now += ticks
	for _i in 8:
		var chain := false
		match state:
			State.HUNT:
				chain = _hunt(ticks, overshoot)
			State.RISE:
				chain = _rise(overshoot)
			State.AIM:
				chain = _aim(overshoot)
			State.WAIT:
				chain = _wait()
			State.DIVE:
				chain = _dive()
		if finished or not chain:
			break
	if not finished:
		_animate(ticks)


func _target_valid(overshoot: Dictionary) -> bool:
	return target != null and is_instance_valid(target) and overshoot.has(target)


func _hunt(ticks: float, overshoot: Dictionary) -> bool:
	var best: Node2D = null
	var best_over := 0.0
	for v in overshoot:
		if float(overshoot[v]) > best_over:
			best_over = float(overshoot[v])
			best = v
	if best != null:
		_timer += ticks
		if _timer > _f("hunt_ticks", 240.0):
			position = best.position   # FUN_0042c930 (target + 0x20 raw, i.e. on it), z 0
			target = best
			state = State.RISE
			return true
		mode = Mode.HOLD
		return false
	mode = Mode.HOLD
	if frame < 1.0:
		finished = true   # behaviour 0: the tick handler removes the object
		return true
	return false


func _rise(overshoot: Dictionary) -> bool:
	mode = Mode.RISE
	if _target_valid(overshoot):
		if frame >= _f("surfaced_frame", 20.0):
			state = State.AIM
			_timer = now + _f("aim_ticks", 180.0)
		return false
	target = null
	state = State.DIVE
	return true


func _aim(overshoot: Dictionary) -> bool:
	mode = Mode.RISE
	if _target_valid(overshoot):
		if now < _timer:
			return false
		var r: Node2D = launcher.call(position, target) if launcher.is_valid() else null
		if r != null:
			state = State.WAIT
			rocket = r
			target = null   # FUN_0042cc50(obj, rocket): the link moves to the rocket
		return false
	target = null
	state = State.WAIT
	return true


func _wait() -> bool:
	if rocket == null or not is_instance_valid(rocket) or rocket.is_queued_for_deletion():
		rocket = null
		mode = Mode.DIVE
		state = State.DIVE
		return true
	mode = Mode.RISE
	return false


func _dive() -> bool:
	mode = Mode.DIVE
	if frame < 1.0:
		state = State.HUNT
		_timer = 0.0
		return true
	return false


## The animation step at the end of FUN_00434b30. Frames run 0..25; rising loops frames 20..25; a dive that starts in the
## loop plays on to 25, then jumps back to about 15 (`dive_wrap_base`) and runs down; below 20 it just runs back.
func _animate(ticks: float) -> void:
	var step := _f("frame_rate", 0x3333 / 65536.0) * ticks
	var lo := _f("surfaced_frame", 20.0)
	var hi := _f("loop_end_frame", 25.0)
	var period := _f("loop_period", 0x50001 / 65536.0)
	if mode == Mode.RISE:
		frame += step
		if frame > hi:
			frame -= floorf((frame - lo) / period) * period
		return
	if frame < lo:
		frame -= step
		if frame < 0.0:
			frame = 0.0
		return
	frame += step
	if frame > hi:
		frame -= floorf((frame - _f("dive_wrap_base", 0xeffff / 65536.0)) / period) * period
