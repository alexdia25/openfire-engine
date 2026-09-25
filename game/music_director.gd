class_name MusicDirector
extends RefCounted
## The original's music director (document 98): the decision logic only, no audio. Which of the 18 music "lines" (a vehicle's theme, its death sting, the flag stings, the
## hangar theme "Bunker", ...) plays, decided by a priority queue and a small state machine. Every rule below is a transcription of RFIRE.BIN:
##  - request()        = FUN_0040f1c0(line, priority, source): the priority queue;
##  - tick()           = FUN_0040efe0's priority decay, and FUN_0040f3c0's state machine, once a game tick;
##  - segment_ended()  = FUN_0040f600, run by the music thread when the current line's tracks have played out;
##  - vehicle_line()   = FUN_0040f2f0, which theme a newly created vehicle gets.
## The audio side (fading, the track files) is game/music_manager.gd. Lines are read from the pack's music/music.json (tools/extract_music.py).

signal line_changed(from_line: int, to_line: int, transition: int)   ## the requested line is now the playing one; `transition` is the traced type 0..3 (document 98)

const STATE_IDLE := 0
const STATE_SILENCE := 1      ## nothing is playing any more: ask for silence
const STATE_THEME_ENDED := 2  ## the vehicle-created bit went away while a theme played
const STATE_BUNKER := 3
const STATE_THEME := 4        ## a vehicle's theme
const STATE_FLAG_CARRIED := 5
const STATE_SUB := 6
const STATE_FLAG_FOUND := 7
const STATE_DEATH := 9

const LINE_DEATH := 15
const LINE_BUNKER := 14
const LINE_FLAG_FOUND := 11
const LINE_FLAG_CARRIED := 12
const LINE_SUB := 16
const PRIORITY_DECAY_WINDOW := 0x28

var lines: Array = []          ## music.json's "lines"
var music_enabled := true      ## DAT_00443008 (the "voices" option): off mutes every line whose enabled bit is 0
var players := 1               ## DAT_00442fbc

var requested := -1            ## DAT_0048c740: the line asked for (-1 = silence)
var playing := -1              ## DAT_0048c744
var previous := -1             ## DAT_0048c758: the line that was playing before the current one
var priority := 0              ## DAT_0048c780
var floor_priority := 0        ## DAT_0048c750
var state := STATE_IDLE        ## DAT_0048c73c
var tracked := false           ## DAT_0048c794: the theme's vehicle is alive and being followed

# the interface bits (_DAT_0048c77c): set by the game, consumed by tick()
var bit_flag_appeared := false     ## 0x100, set when a flag object is created (FUN_00432710)
var bit_sub := false               ## 0x1000
var bit_flag_carried := false      ## 0x200, set every tick by a flag carried by the other team's vehicle (FUN_00432920)
var bit_vehicle := false           ## 0x400, set EVERY tick by the vehicle's own state handler (FUN_0040b980 starts with `OR [0x48c77c], 0x400`) while the vehicle exists
var death_pending := false         ## DAT_0048c78c, set when the player's vehicle is destroyed (FUN_0040c7e0)
var death_line := 15               ## the dying vehicle's own death line (table 0x4466e4: Tank 3, Jeep 5, MSV 7, Heli 10)
var death_is_tracked := true       ## the dying vehicle is the one the theme follows
var choosing := 0                  ## DAT_0048c734: players currently on the vehicle-choice screen
var in_game_view := true           ## the player's mode handler is the game view (FUN_00408d60): false during the loss sequence and the choice
var has_tracked_vehicle := false   ## DAT_0048c748 valid
var use_alt := false               ## DAT_004462f8: the next start is a loop restart (the line's alternate start track); the audio side reads and clears it


func load_lines(l: Array) -> void:
	lines = l


func _entry(line: int) -> Dictionary:
	if line < 0 or line >= lines.size():
		return {}
	return lines[line]


## FUN_0040f1c0. Returns 0 on success or when nothing changes, -1 when refused (a lower priority, or the equal-priority window).
func request(line: int, prio: int) -> int:
	if line > 17:
		return -10
	var entry := _entry(line)
	if not entry.is_empty() and not music_enabled and int(entry["enabled_bit0"]) == 0:
		entry = {}
	var new_line := -1 if entry.is_empty() else int(entry["id"])
	if new_line == requested:
		return 0
	if prio < priority:
		return -1
	if priority == prio:
		if entry.is_empty():
			requested = -1
			floor_priority = 0
			priority = 0
			return 0
		if line < int(entry["lowest"]) or int(entry["highest"]) < line:
			return -1
	if entry.is_empty():
		priority = 0
		floor_priority = 0
		requested = -1
		return 0
	priority = prio
	requested = new_line
	floor_priority = prio - PRIORITY_DECAY_WINDOW
	return 0


## FUN_0040f2f0: the theme a new vehicle gets. The function branches on the vehicle type; the vehicle definitions name the branch
## as `music.theme_rule` (PORTING_PLAN.md 2.7.2): "flag_threat" (the Tank's), "stock_or_roll" (the Heli's), "record_line" (the rest). `own_flag_carried`: the player's own pool's flag object exists and has a carrier;
## `other_flag_near`: the other pool's flag object exists within 128 units (squared distance below 0x4000); `stock`: the stock byte of this type; `record_line`: the
## record's byte at +0x2bc (Jeep 4, MSV 6). `roll` is the game's random 0..7.
static func vehicle_line(rule: String, own_flag_carried: bool, other_flag_near: bool, stock: int, record_line: int, roll: int) -> int:
	if rule != "flag_threat":
		if rule != "stock_or_roll":
			return record_line
		if stock == 2:
			return 8
		return 9 - (1 if roll < 4 else 0)
	if own_flag_carried or other_flag_near:
		return 2
	if stock == 2:
		return 0
	return 1 if roll > 3 else 0


## FUN_0040b980's activation block, run once when a vehicle is created: it becomes the tracked object and asks for the record's line at the record's priority (both 0x80
## for all four vehicles). The bit is the caller's to set every tick (see bit_vehicle).
func vehicle_created(record_line: int, record_priority: int) -> void:
	if record_line >= 0:
		request(record_line, record_priority)
	has_tracked_vehicle = true


func vehicle_destroyed(type_death_line: int, was_tracked: bool = true) -> void:
	has_tracked_vehicle = false   # the tracked object's serial no longer matches (0x40f545)
	death_pending = true
	death_line = type_death_line
	death_is_tracked = was_tracked


## The vehicle choice opened (FUN_00418290: DAT_0048c734 += 1) or closed.
func set_choosing(count: int) -> void:
	choosing = count


func _clear_bits() -> void:
	bit_flag_appeared = false
	bit_sub = false
	bit_flag_carried = false
	bit_vehicle = false


## One game tick: FUN_0040f3c0 (the state machine), then FUN_0040efe0's decay and line change. `vehicle_theme` is a Callable returning the theme for the vehicle bit.
func tick(vehicle_theme: Callable = Callable()) -> void:
	_state_machine(vehicle_theme)
	if priority > 0 and floor_priority < priority:
		priority -= 1
	if requested != playing:
		var t := _transition_type(requested, playing)
		previous = playing
		var old := playing
		playing = requested
		line_changed.emit(old, playing, t)


## The transition type for starting `to` while `from` plays: the line's default byte, or the entry of its own list that names the playing line (FUN_0040efe0).
func _transition_type(to: int, from: int) -> int:
	var entry := _entry(to)
	if entry.is_empty():
		return 0
	var t := int(entry["default_transition"])
	if from >= 0:
		for tr in entry["transitions"]:
			if int(tr["from_line"]) == from:
				t = int(tr["type"])
				break
	return t


func _state_machine(vehicle_theme: Callable) -> void:
	if playing == -1 and state > STATE_SILENCE:
		state = STATE_SILENCE
	if death_pending:
		death_pending = false
		var line := death_line
		if death_is_tracked:
			tracked = false
		if state < STATE_DEATH:
			if state != STATE_THEME:
				tracked = false
				line = LINE_DEATH
			if not tracked:
				request(line, 0x80)
				state = STATE_DEATH
				_clear_bits()
				return
	if bit_flag_appeared and state < 8:
		request(LINE_FLAG_FOUND, 0xfe)
		state = STATE_FLAG_FOUND
		_clear_bits()
		return
	if bit_sub:
		if state < STATE_SUB:
			request(LINE_SUB, 0x8a)
			state = STATE_SUB
	elif state == STATE_SUB:
		state = STATE_SILENCE
	if bit_flag_carried:
		request(LINE_FLAG_CARRIED, 0x8a)
		state = STATE_FLAG_CARRIED
		_clear_bits()
		return
	elif state == STATE_FLAG_CARRIED:
		state = STATE_SILENCE
	if bit_vehicle:
		if state < STATE_THEME and has_tracked_vehicle:
			var theme := int(vehicle_theme.call()) if vehicle_theme.is_valid() else 0
			request(theme, 0x80)
			state = STATE_THEME
			_clear_bits()
			tracked = true
			return
	elif state == STATE_THEME:
		state = STATE_THEME_ENDED
	if players <= choosing and state < STATE_BUNKER:
		request(LINE_BUNKER, 0x68)
		state = STATE_BUNKER
	if state == STATE_SILENCE:
		request(-1, 0x64)
		state = STATE_IDLE
	_clear_bits()


## FUN_0040f600: the playing line's tracks have all played. Returns "loop" (start again from the line's alternate track) or "ended" (a sting: it asked for the previous
## line, or Bunker when the game is not in the game view).
func segment_ended() -> String:
	if playing < 0:
		return "none"
	var entry := _entry(playing)
	if not bool(entry["sting"]):
		var id := playing
		playing = -1
		requested = -1
		state = STATE_IDLE
		use_alt = true
		request(id, 0x80)   # FUN_0040f1c0(line, 0x80): the same line again, played from its alternate start
		return "loop"
	priority = 0
	if in_game_view and previous >= 0:
		state = STATE_IDLE
		request(previous, 100)
	else:
		state = STATE_IDLE
		request(LINE_BUNKER, 0x40)
	return "ended"


## FUN_00405660: everything stops (`request(-1, 0x100)`), used when the match ends.
func stop() -> void:
	request(-1, 0x100)
