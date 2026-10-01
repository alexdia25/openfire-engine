class_name Soldier
extends RefCounted
## A foot soldier: Return Fire's object class 14, "MAN" (descriptor 0x44eb38; issue #74, wiki documents 113 and 116). Soldiers
## come out of damaged buildings and destroyed vehicles; each one picks the nearest vehicle, keeps away from it and, when it is
## on the other team and has grenades, stops 64-96 units away and lobs one. Pure logic, no nodes: MatchController ticks it and
## moves it through `mover`; SoldierView3D draws `frame()` at `position`. Every number comes from the pack's world/infantry.json
## (the traced originals are in the comments); a pack without the table has no soldiers.
##
## Behaviours (the original's function pointer in obj+0x18, one per State; each returns "chain" = the original's return 1):
##   FIRST    (FUN_00434460)  get out of whatever it was born inside (tiles: walk along its heading 4 units at a time with tile
##                            collision off; another soldier: one of 8 offsets round it, else removed; anything else: removed),
##                            then HOME if it was born in a tile, else ACQUIRE
##   HOME     (FUN_004345d0)  120 ticks walking away from the tile it was born in, then ACQUIRE
##   ACQUIRE  (FUN_00434350)  link the nearest vehicle (either team); beyond 256 units IDLE, else WALK; decide again in 30-119 ticks
##   IDLE     (FUN_00433d40)  stand until the decision time, then ACQUIRE
##   WALK     (FUN_00433d80)  at the decision time: THROW (other team, grenades left, not in water, 1 in 3, 64-96 units) else
##                            ACQUIRE; otherwise walk AWAY from the target (heading_to + 180 degrees, plus a one-tick steering
##                            offset), sliding round obstacles
##   THROW    (FUN_00434220)  ease the animation to frame 6, then throw one grenade scattered by distance / 4, -> PAUSE
##   PAUSE    (FUN_00434320)  stand until 120-179 ticks after the throw, then ACQUIRE
## The original runs behaviours until one returns "done for this tick", then steps the animation (FUN_00433ab0).

enum State { FIRST, HOME, ACQUIRE, IDLE, WALK, THROW, PAUSE }
enum Anim { WALK = 0, STAND = 1, THROW = 2, WADE = 3, WADE_STAND = 4 }   ## obj+0x72

const STEP_DEG := 5.625   ## one of the original's 64 heading steps

var cfg: Dictionary
var state := State.FIRST
var anim := Anim.STAND
var position := Vector2.ZERO
var team := 0                    ## obj+0x10: the tile's team (or the wreck's)
var heading := 0                 ## obj+0x4c in steps (0..63; 0 = north, clockwise)
var phase := 6.0                 ## obj+0x64: animation frame (16.16 in the original); 0-5 walk, 6 wind-up, 7-9 follow-through
var grenades := 0                ## obj+0x70
var jitter := 0                  ## obj+0x71: a steering offset in steps, used for one tick
var target: Node2D = null        ## obj+0x2c
var now := 0.0                   ## the match clock in ticks (0x480d38)
var finished := false            ## removed (FUN_0042c0f0)
var undrawn := 0.0               ## ticks since it was last near a vehicle (the original's last-drawn stamp, obj+0x5c)
var in_water := false            ## obj+0x73
var _timer := 0.0                ## obj+0x60
var _home := Vector2.ZERO        ## obj+0x6c: the centre of the tile it was born in
var _born_in_tile := false
var _blocked_tile := Rect2()     ## obj+0x68 + DAT_0047c918: the box of the tile that last blocked it (size zero: none)
var _blocked_by: Soldier = null  ## obj+0x58

## mover.call(s: Soldier, to: Vector2, pass_tiles: bool) -> {"blocked": bool, "tile_box": Rect2, "object": Soldier|null}: would the
## soldier's footprint at `to` hit a tile shape (unless pass_tiles) or another soldier (FUN_0042c830 / FUN_0042bd40)?
var mover := Callable()
## targets.call() -> Array of the vehicles a soldier may pick (alive, not docked): Node2D with `position`, `z`, `player_index()`.
var targets := Callable()
## water.call(pos) -> bool (FUN_0042f280 non-zero)
var water := Callable()
## thrower.call(from: Soldier, aim: Vector2): launch the grenade (FUN_004159a0)
var thrower := Callable()


func _init(config: Dictionary, at: Vector2, side: int) -> void:
	cfg = config
	position = at
	team = side
	var table: Array = cfg.get("grenades", [0])
	grenades = int(table[randi() % table.size()])           # FUN_00433a50: the 16-entry table
	heading = (randi() % 8 - 4) & 63                       # one of 8 headings round north
	phase = float(cfg.get("start_frame", 6.0))


func _f(key: String, fallback: float) -> float:
	return float(cfg.get(key, fallback))


## The 3D scene's frame: {dir: 0..4 (sprite set), mirror: bool, frame: 0..9}. The octant is FUN_00433950's
## ((heading + 0x40000) & 0x380000) >> 19; octants 5-7 are octants 3-1 mirrored (the part's corner order is swapped).
func draw_frame() -> Dictionary:
	var oct := ((heading + 4) & 63) >> 3
	var src: Array = cfg.get("dir_source", [0, 1, 2, 3, 4, 3, 2, 1])
	var mir: Array = cfg.get("mirror", [false, false, false, false, false, true, true, true])
	var wading := anim == Anim.WADE or anim == Anim.WADE_STAND
	return {"dir": int(src[oct]), "mirror": bool(mir[oct]), "frame": clampi(int(floorf(phase)), 0, 19 if wading else 9), "wade": wading}


static func heading_to(from: Vector2, to: Vector2) -> int:
	## FUN_00422e70: the heading from `from` toward `to`, rounded down to a step (heading 0 = north, clockwise).
	var phi := rad_to_deg(atan2(to.y - from.y, to.x - from.x))
	return int(floorf(fposmod(phi + 90.0, 360.0) / STEP_DEG)) & 63


static func step_vector(h: int) -> Vector2:
	var a := deg_to_rad(float(h & 63) * STEP_DEG - 90.0)
	return Vector2(cos(a), sin(a))


func tick(ticks: float) -> void:
	if finished:
		return
	now += ticks
	for _i in 8:
		var chain := false
		match state:
			State.FIRST:
				chain = _first()
			State.HOME:
				chain = _home_walk(ticks)
			State.ACQUIRE:
				chain = _acquire()
			State.IDLE:
				chain = _idle()
			State.WALK:
				chain = _walk(ticks)
			State.THROW:
				chain = _throw()
			State.PAUSE:
				chain = _pause()
		if finished or not chain:
			break
	if not finished:
		_animate(ticks)


func kill() -> void:
	finished = true


func _wet() -> bool:
	return water.is_valid() and bool(water.call(position))


func _try_move(h: int, ticks: float, pass_tiles := false) -> bool:
	## FUN_004341c0 / the body of FUN_00433d80: face `h` and take one step; true if it moved (FUN_0042c830 returned 0).
	heading = h & 63
	var to := position + step_vector(heading) * _f("speed", 0.2) * ticks
	var r := _probe(to, pass_tiles)
	if r["blocked"]:
		return false
	position = to
	return true


func _probe(to: Vector2, pass_tiles: bool) -> Dictionary:
	_blocked_tile = Rect2()
	_blocked_by = null
	if not mover.is_valid():
		return {"blocked": false}
	var r: Dictionary = mover.call(self, to, pass_tiles)
	if r.get("blocked", false):
		_blocked_tile = r.get("tile_box", Rect2())
		_blocked_by = r.get("object", null)
	return r


func _nearest() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	if targets.is_valid():
		for v in targets.call():
			var d := position.distance_to(v.position)
			if d < best_d:
				best_d = d
				best = v
	return best


func _dist() -> float:
	return position.distance_to(target.position)


func _first() -> bool:
	# FUN_00434460: stuck in a tile? walk along the heading 4 units at a time with tile collision off until it is out
	var r := _probe(position, false)
	_born_in_tile = false
	if r["blocked"] and r.get("tile_box", Rect2()).size != Vector2.ZERO:
		_born_in_tile = true
		_home = r.get("tile_center", (r["tile_box"] as Rect2).get_center())
		for _n in 64:
			position += step_vector(heading) * 4.0
			r = _probe(position, true)    # the flag 0x1000000: the soldier's tile callback lets it through
			if not (r["blocked"] and r.get("tile_box", Rect2()).size != Vector2.ZERO):
				break
		r = _probe(position, false)
	var other: Soldier = r.get("object", null)
	if r["blocked"] and other != null:
		# round the soldier it overlaps: FUN_0042e... the 8 offsets at 0x44ead8, the first that fits
		var placed := false
		for off in cfg.get("separation_offsets", []):
			var to: Vector2 = other.position + Vector2(off[0], off[1])
			var rr := _probe(to, false)
			if not rr["blocked"]:
				position = to
				placed = true
				break
		if not placed:
			finished = true       # behaviour 0: the tick handler removes the object
			return true
	if _born_in_tile:
		_timer = now + _f("home_ticks", 120.0)
		state = State.HOME
	else:
		state = State.ACQUIRE
	return true


func _home_walk(ticks: float) -> bool:
	# FUN_004345d0: walk away from the tile it was born in until the timer runs out or it is blocked for good
	if _timer < now:
		state = State.ACQUIRE
		return true
	var away := (heading_to(position, _home) + 32) & 63
	var moved := _slide(away, ticks)
	_set_walk_anim(moved)
	if moved:
		return false
	state = State.ACQUIRE
	return true


func _acquire() -> bool:
	target = _nearest()
	var mode := 0
	if target != null and _dist() <= _f("idle_distance", 256.0):
		mode = 1
	state = State.IDLE if mode == 0 else State.WALK
	_timer = now + _f("decide_ticks", 30.0) + float(randi() % int(_f("decide_random", 90.0)))
	if mode != 0:
		jitter = randi() % 5 - 2
	return true


func _idle() -> bool:
	if _timer < now:
		state = State.ACQUIRE
		return true
	anim = Anim.WADE_STAND if _wet() else Anim.STAND
	return false


func _can_throw_at_range() -> bool:
	var d := _dist()
	return d < _f("throw_max", 96.0) and _f("throw_min", 64.0) < d


func _hostile() -> bool:
	return target != null and target.player_index() != team


func _walk(ticks: float) -> bool:
	if target == null or _timer < now:
		if _hostile() and grenades > 0 and not _wet() and randi() % 3 == 0 and _can_throw_at_range():
			state = State.THROW
			return true
		state = State.ACQUIRE
		return true
	in_water = _wet()
	var away := (heading_to(position, target.position) + 32 + jitter) & 63
	jitter = 0                                    # obj+0x71 is cleared as soon as it has been used once
	var moved := _slide(away, ticks)
	_set_walk_anim(moved)
	# cornered: blocked, standing on frame 9, an enemy within range: throw without the dice
	if not moved and _hostile() and grenades > 0 and absf(phase - 9.0) < 0.0001 and anim == Anim.STAND \
			and _dist() < _f("throw_max", 96.0):
		state = State.THROW
		return true
	return false


## The movement of FUN_00433d80 / FUN_004345d0: one step along `h`; if a tile blocked it, slide along the axis the tile's box is
## not in the way of; if another soldier did, step away from it, then 90 degrees either side. True if the soldier moved.
func _slide(h: int, ticks: float) -> bool:
	var h0 := h
	var ok := _try_move(h, ticks)
	if ok:
		return true
	if _blocked_tile.size != Vector2.ZERO:
		var box := _blocked_tile
		if position.x < box.position.x or box.end.x < position.x:
			var hh := 0 if (h0 > 48 or h0 < 16) else 32
			if _try_move(hh, ticks):
				return true
		if position.y < box.position.y or box.end.y < position.y:
			var hh2 := 16 if h0 < 32 else 48
			if _try_move(hh2, ticks):
				return true
		return false
	if _blocked_by != null:
		var away := (heading_to(position, _blocked_by.position) + 32) & 63
		var cands := [away, (away + 16) & 63, (away + 48) & 63]
		for c in cands:
			var d: int = (h0 - int(c)) & 63
			if d > 48 or d < 16:
				if _try_move(int(c), ticks):
					return true
	return false


func _set_walk_anim(moved: bool) -> void:
	var w := _wet()
	in_water = w
	if moved:
		anim = Anim.WADE if w else Anim.WALK
	else:
		anim = Anim.WADE_STAND if w else Anim.STAND


func _throw() -> bool:
	if target == null:
		state = State.ACQUIRE
		return true
	anim = Anim.THROW
	if phase <= 6.0 + 0.0001:
		grenades -= 1
		phase = 6.0
		state = State.PAUSE
		_timer = now + float(randi() % int(_f("pause_random", 60.0))) + _f("pause_ticks", 120.0)
		var d := _dist()
		if d > _f("throw_max", 96.0):
			state = State.ACQUIRE
			return true
		var aim := target.position
		var s := int(d) >> 2                             # a quarter of the distance, in whole units
		if s > 0:
			aim.x += float(randi() % s - randi() % s)
			aim.y += float(randi() % s - randi() % s)
		if thrower.is_valid():
			thrower.call(self, aim)
	return false


func _pause() -> bool:
	anim = Anim.STAND
	if target != null and now <= _timer:
		return false
	state = State.ACQUIRE
	return true


## FUN_00433ab0's animation step (0.2 frames a tick): walking cycles 0-5; STAND runs on to frame 9 and stops; THROW eases to 6.
## Wading draws another descriptor (0x44e9c0: no body, a rotated ripple quad) on frames 10-17 (moving) and 18-19 (standing): the phase
## wraps inside those ranges and is pulled up to the first frame of its range.
func _animate(ticks: float) -> void:
	var step := _f("frame_rate", 0.2) * ticks
	match anim:
		Anim.WALK:
			phase += step
			if phase >= 6.0:
				phase = fmod(phase, 6.0)
		Anim.STAND:
			phase = minf(phase + step, 9.0)
		Anim.WADE:
			phase += step
			phase = 10.0 if phase < 10.0 else (10.0 + fmod(phase - 10.0, 8.0) if phase >= 18.0 else phase)
		Anim.WADE_STAND:
			phase += step
			phase = 18.0 if phase < 18.0 else (18.0 + fmod(phase - 18.0, 2.0) if phase >= 20.0 else phase)
		Anim.THROW:
			if phase < 6.0:
				phase = minf(phase + step, 6.0)
			else:
				phase = maxf(phase - step, 6.0)
