class_name DebugAutoplay
extends Node
## Debug-only (RF_DEBUG_AUTOPLAY=1): drives the player through RFMAP001 inside the real scene, the same route as
## tools/tests/playthrough_rfmap001.gd (a Tank shoots the building and its ruin, returns home, becomes a Jeep, fetches the
## flag, carries it home) but one control update per frame, so the scene's own tile-state application, explosions and win banner
## are exercised. It presses the same input actions a player would. NOT part of the original: a regression check and a way to
## get screenshots of the whole route. RF_DEBUG_AUTOPLAY_SPEED=<n> sets Engine.time_scale (default 4); RF_DEBUG_AUTOPLAY_SHOT=<png>
## saves the frame after the win banner appears and quits.

const BUILDING_TILE := Vector2i(75, 56)     ## level 1's only candidate of pool b (document 26)

var mc: MatchController
var tsz := 32.0
var _phase := "drive_to_building"
var _path: Array = []
var _wp := 0
var _home := Vector2.ZERO
var _ticks := 0
var _stuck_ref := Vector2.ZERO
var _unstick := 0
var _unstick_dir := 1.0
var _flag: FlagMarker = null


func setup(controller: MatchController) -> void:
	mc = controller
	tsz = float(mc.pack.tile_size_px)
	_home = mc.vehicle.position
	Engine.time_scale = float(OS.get_environment("RF_DEBUG_AUTOPLAY_SPEED")) if OS.get_environment("RF_DEBUG_AUTOPLAY_SPEED") != "" else 4.0
	_stuck_ref = _home
	print("[autoplay] start at ", _home)


func _target_px() -> Vector2:
	return (Vector2(BUILDING_TILE) + Vector2(0.5, 0.5)) * tsz


func _process(_delta: float) -> void:
	var v := mc.vehicle
	if v == null or mc.match_finished:
		_release_all()
		if mc.match_finished and _phase != "done":
			print("[autoplay] match finished, winner ", mc.winner_idx, " after phase ", _phase)
			_phase = "done"
			Engine.time_scale = 1.0
			var shot := OS.get_environment("RF_DEBUG_AUTOPLAY_SHOT")  # save the banner frame to this path, then quit
			if shot != "":
				await get_tree().create_timer(2.5).timeout   # the win sequence (document 92): 1 s fade to black, then the ribbon fades in over 0.5 s
				get_viewport().get_texture().get_image().save_png(shot)
				get_tree().quit()
		return
	_ticks += 1
	match _phase:
		"drive_to_building":
			if _follow(_target_px(), 70.0):
				_next("shoot_building")
		"shoot_building":
			_aim(_target_px())
			Input.action_press("ui_accept")
			if mc.pools["b"].get_active_position() == null:
				Input.action_release("ui_accept")
				_next("shoot_ruin")
		"shoot_ruin":
			_aim(_target_px())
			Input.action_press("ui_accept")
			if mc.level.get_coastal_id(BUILDING_TILE.x, BUILDING_TILE.y) == 63:
				Input.action_release("ui_accept")
				_next("drive_home")
		"drive_home":
			if _follow(_home, 6.0):
				_release_all()
				_next("settle")
		"settle":
			if _ticks > 150:
				mc.switch_player_vehicle()
				mc.select_move(1)   # Tank -> Jeep (down in the hangar picture)
				if v.vehicle_type != 1:
					mc.debug_swap_vehicle(1)
					print("[autoplay] (swapped to the Jeep by the debug key; the home tile did not switch)")
				_next("choose")
		"choose":
			if mc.selecting:
				if mc.select_anim.fade >= 1.0:
					mc.confirm_selection()
			elif not mc.undocking:
				if v.vehicle_type != 1:
					mc.debug_swap_vehicle(1)
				_next("wait_flag")
		"wait_flag":
			_flag = mc.flags.get(1)
			if _flag != null:
				_next("drive_to_flag")
		"drive_to_flag":
			if _flag.carrier == v:
				_next("carry_home")
			elif _follow(_flag.position, 3.0) or _ticks > 3000:
				_path = []
				_ticks = 1000
		"carry_home":
			if _flag.carrier != v:
				_next("drive_to_flag")
			elif _follow(_home, 4.0):
				_release_all()
				_next("wait_win")
		"wait_win":
			if _ticks > 600:
				print("[autoplay] no win after arriving home")
				_phase = "done"


func _next(p: String) -> void:
	print("[autoplay] ", _phase, " -> ", p, " at frame ", Engine.get_process_frames(), " pos ", mc.vehicle.position)
	_phase = p
	_path = []
	_wp = 0
	_ticks = 0


func _release_all() -> void:
	for a in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_accept"]:
		Input.action_release(a)


## One control update toward `to`, along a planned tile path; true once within `radius` of it.
func _follow(to: Vector2, radius: float) -> bool:
	var v := mc.vehicle
	if v.position.distance_to(to) <= radius:
		return true
	if _path.is_empty():
		_path = _plan(v.position, to)
		_wp = 0
		if _path.is_empty():
			_path = [to]
	var wp: Vector2 = _path[mini(_wp, _path.size() - 1)]
	if _wp < _path.size() - 1 and v.position.distance_to(wp) <= 30.0:
		_wp += 1
		wp = _path[_wp]
	_drive_step(wp)
	return false


func _drive_step(to: Vector2) -> void:
	var v := mc.vehicle
	if _unstick > 0:
		_unstick -= 1
		Input.action_release("ui_up")
		Input.action_press("ui_down")
		Input.action_release("ui_left")
		Input.action_release("ui_right")
		Input.action_press("ui_right" if _unstick_dir > 0 else "ui_left")
		return
	Input.action_release("ui_down")
	_aim(to)
	var d := absf(wrapf(rad_to_deg((to - v.position).angle()) - v.heading_deg, -180.0, 180.0))
	if d < 30.0:
		Input.action_press("ui_up")
	else:
		Input.action_release("ui_up")
	if Engine.get_process_frames() % 45 == 0:
		if v.position.distance_to(_stuck_ref) < 3.0:
			_unstick = 70
			_unstick_dir = -_unstick_dir
		_stuck_ref = v.position


func _aim(to: Vector2) -> void:
	var v := mc.vehicle
	var d := wrapf(rad_to_deg((to - v.position).angle()) - v.heading_deg, -180.0, 180.0)
	Input.action_release("ui_left")
	Input.action_release("ui_right")
	if d > 4.0:
		Input.action_press("ui_right")
	elif d < -4.0:
		Input.action_press("ui_left")


func _blocked_tile(x: int, y: int) -> bool:
	var level := mc.level
	var pack := mc.pack
	if x < 0 or y < 0 or x >= level.width or y >= level.height:
		return true
	if Water.class_at(level, pack, (Vector2(x, y) + Vector2(0.5, 0.5)) * tsz) == 2:
		return true
	var id := level.get_coastal_id(x, y)
	if id == 0:
		return false
	var info := pack.get_coastal_shapes(id)
	if info.is_empty() or info.get("shapes", []).is_empty():
		return false
	if mc.vehicle.vehicle_type == 0 and id in [1, 2, 5, 11]:
		return false  # a Tank crushes bushes
	return not (id in [14, 39, 40, 41, 42])  # rearm / refuel pumps have enterable zones


func _plan(from: Vector2, to: Vector2) -> Array:
	var s := Vector2i(int(from.x / tsz), int(from.y / tsz))
	var g := Vector2i(int(to.x / tsz), int(to.y / tsz))
	var came := {s: s}
	var q := [s]
	var found := false
	while q.size() > 0:
		var t: Vector2i = q.pop_front()
		if t == g:
			found = true
			break
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = t + d
			if came.has(n):
				continue
			if n != g and _blocked_tile(n.x, n.y):
				continue
			came[n] = t
			q.append(n)
	if not found:
		return []
	var out := []
	var c := g
	while c != s:
		out.push_front((Vector2(c) + Vector2(0.5, 0.5)) * tsz)
		c = came[c]
	out.append(to)
	return out
