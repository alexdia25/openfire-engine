class_name MusicManager
extends Node
## Plays the game's music (document 98): watches the match the way the original's interface bits do, feeds game/music_director.gd (the traced decision logic) once a game
## tick, and plays what it decides from the tracks the pack's music/music.json lists (any AudioFiles format).
## A line plays its tracks from `start` up to `end` (exclusive) as one gapless playlist; a looping line then repeats from its alternate track; a sting plays once.
## PORT CHOICE: the first start of a match is the vehicle's theme at once (the original opens on the hangar screen with the Bunker theme; the port starts in the vehicle).

const TICK_HZ := 62.5
## A type-0 transition fades the old line out before the new one starts (document 98). Traced: FUN_0040ef00 sends mixer command 6 (target volume 0), and FUN_00411540 moves the
## music's mixer word 0x7fff -> 0 by 0x444 per timer unit, a unit being timeGetTime() >> 4 = 16 ms (0x411110 reads it): 0x7fff / 0x444 = 30 units = 0.48 s. The word maps to
## (word - 0x7fff) / 10 hundredths of a dB (FUN_00423af0, document 100), so the fade is linear in dB, down to -32.77 dB, and the old line then stops.
const FADE_OUT_S := 0.48
const FADE_RANGE_DB := 32.767
const VOLUME_DB := 0.0         ## the original's music mixer volume is 0x7fff = 0 dB (document 100: FUN_00423af0, channel -1)
## Per vehicle, from its definition's `music` group (PORTING_PLAN.md 2.7.2; read from RFIRE.BIN by tools/extract_vehicle_types.py):
## `theme_line` / `priority`, FUN_0040b980's own request for a new vehicle (record bytes +0x2bc / +0x2bd: 0, 4, 6, 8 at 0x80);
## `death_line`, the line of a dying vehicle (the byte table at 0x4466e4: 3, 5, 7, 10); `theme_rule`, FUN_0040f2f0's branch.
func _music(v: Vehicle, key: String, default: Variant) -> Variant:
	return pack.vehicle_value(v.vehicle_type, "music." + key, default)

var pack: Pack
var mc: MatchController
var director := MusicDirector.new()
var _tracks: Dictionary = {}            ## track number -> {"file": path, "stream": AudioStream or null} (any AudioFiles format)
var _player: AudioStreamPlayer
var _acc := 0.0
var _pending := {}                      ## {"line": int, "alt": bool} waiting for the fade-out to finish
var _fading := false
var _fade := 0.0                        ## 0 = full volume .. 1 = the fade's end
var _vehicle_source: MusicDirector.Source = null   ## the player's current vehicle object, which a request tied to it is cut with (FUN_0040f2a0)
var _last_exists := false
var _last_undocking := false
var _last_death_phase := 0
var _last_finished := false
var _flag_count := 0
var _started := false
var _menu := false                      ## front-end mode (no match): the hangar theme loops under the menus


## Returns false when the pack has no music (tools/extract_music.py not run) or music is off.
func setup(p: Pack, controller: MatchController) -> bool:
	pack = p
	mc = controller
	if not GameSettings.music_enabled:
		return false
	var doc := _load_json()
	if doc.is_empty():
		return false
	director.load_lines(doc["lines"])
	director.music_enabled = true
	for t in doc["tracks"]:
		_tracks[int(t["n"])] = {"file": String(t["file"]), "dir": String(t["dir"]), "stream": null}
	_player = AudioStreamPlayer.new()
	_player.volume_db = VOLUME_DB
	add_child(_player)
	_player.finished.connect(_on_finished)
	director.line_changed.connect(_on_line_changed)
	return true


## Front-end mode: the screens before a level have no match to watch, so the Drums line (the title screen's) is requested and the director loops it. The hangar
## theme is the level's own business, once the player is in a hangar. A pack without the Drums tracks plays nothing here.
## Returns false when the pack has no music or music is off.
func setup_menu(p: Pack) -> bool:
	if not setup(p, null):
		return false
	var line := MusicDirector.LINE_DRUMS
	if line >= director.lines.size() or not _tracks.has(int(director.lines[line]["start_track"])):
		return false
	_menu = true
	director.in_game_view = false
	director.request(line, 0x80)
	return true


func _load_json() -> Dictionary:
	for i in range(pack.layers.size() - 1, -1, -1):
		var dir := "%s/music" % pack.layers[i]
		var path := "%s/music.json" % dir
		if FileAccess.file_exists(path):
			var doc = JSON.parse_string(FileAccess.get_file_as_string(path))
			if doc is Dictionary:
				for t in doc["tracks"]:
					t["dir"] = dir
				return doc
	return {}


func _stream(n: int) -> AudioStream:
	var t: Dictionary = _tracks.get(n, {})
	if t.is_empty():
		return null
	if t["stream"] == null:
		var path := "%s/%s" % [t["dir"], t["file"]]
		t["stream"] = AudioFiles.load_stream(path)
	return t["stream"]


func _process(delta: float) -> void:
	if _player == null or (mc == null and not _menu):
		return
	if not _menu and mc.vehicle == null:
		return
	if not _menu and not _started:
		_started = true
		_last_undocking = mc.undocking
		_flag_count = mc.flags.size()
		if not mc.selecting:
			_vehicle_created()   # the port starts with the vehicle already out
	if not _menu:
		_poll()
	_acc += delta * TICK_HZ
	while _acc >= 1.0:
		_acc -= 1.0
		_tick()
	if _fading:
		_fade = minf(_fade + delta / FADE_OUT_S, 1.0)
		_player.volume_db = VOLUME_DB - FADE_RANGE_DB * _fade
		if _fade >= 1.0:
			_fading = false
			_player.stop()
			_start_pending()


## The game's interface bits (document 71): a vehicle created, the player's vehicle destroyed, a flag appearing or carried, the vehicle choice open.
func _poll() -> void:
	var v := mc.vehicle
	if mc.undocking and not _last_undocking:
		_vehicle_created()   # the choice was confirmed: FUN_0040b1c0 creates the vehicle (FUN_0040b980 sets the bit)
	_last_undocking = mc.undocking
	var exists := _vehicle_exists()
	if _last_exists and not exists:
		director.forget(_vehicle_source)   # the vehicle object is gone (destroyed, or it docked)
	_last_exists = exists
	if mc.death_phase != 0 and _last_death_phase == 0:
		director.vehicle_destroyed(int(_music(v, "death_line", 3)))
	_last_death_phase = mc.death_phase
	if mc.flags.size() > _flag_count:
		director.bit_flag_appeared = true
	_flag_count = mc.flags.size()
	if mc.match_finished and not _last_finished:
		if mc.winner_idx >= 0:
			director.win()   # FUN_004225d0 -> the win handler's FUN_004056a0: the Win line, beside the victory jingle
		else:
			director.stop()   # FUN_00405660: no side won (the player ran out of vehicles)
	_last_finished = mc.match_finished
	director.choosing = 1 if mc.selecting else 0
	director.in_game_view = not (mc.selecting or mc.undocking or mc.death_phase != 0)


func _vehicle_created() -> void:
	director.forget(_vehicle_source)   # a new vehicle object replaces the old (a quick swap creates one too)
	_vehicle_source = MusicDirector.Source.new()
	director.vehicle_created(int(_music(mc.vehicle, "theme_line", 0)), int(_music(mc.vehicle, "priority", 0x80)), _vehicle_source)


func _tick() -> void:
	if _menu:
		director.tick()
		return
	if mc.match_finished:
		return   # the end-of-match handler has replaced the game view's loops that run the director (document 92)
	director.bit_flag_carried = _flag_carried_by_other_team()
	director.bit_sub = mc.submarine_present   # FUN_00434b30 sets bit 0x1000 every tick the submarine object runs
	director.bit_vehicle = _vehicle_exists()   # FUN_0040b980 sets the bit every tick the vehicle's handler runs
	director.tick(_vehicle_theme)


## The player's vehicle exists: alive, out of the base, and not held on the choice screen.
func _vehicle_exists() -> bool:
	var v := mc.vehicle
	return v != null and v.alive and not v.docked and not mc.selecting


## The flag update sets bit 0x200 every tick while a vehicle of the other team carries it (FUN_00432920, document 65).
func _flag_carried_by_other_team() -> bool:
	for f in mc.flags.values():
		if f.carrier != null and f.carrier.player_index() != f.owner_idx:
			return true
	return false


## FUN_0040f2f0 for the player's vehicle (document 98).
func _vehicle_theme() -> int:
	var v := mc.vehicle
	var own: FlagMarker = mc.flags.get(v.player_index())
	var other: FlagMarker = mc.flags.get(1 - v.player_index())
	var own_carried := own != null and own.carrier != null
	var near := other != null and v.position.distance_squared_to(other.position) < 0x4000
	var stock: int = mc.vehicle_stock[v.vehicle_type] if v.vehicle_type < mc.vehicle_stock.size() else 0
	return MusicDirector.vehicle_line(String(_music(v, "theme_rule", "record_line")), own_carried, near, stock, int(_music(v, "theme_line", 0)), randi() % 8)


func _on_line_changed(from_line: int, to_line: int, transition: int) -> void:
	if OS.get_environment("RF_DEBUG_MUSIC") == "1":
		print("[music] line %d -> %d (transition %d, priority %x, state %d)" % [from_line, to_line, transition, director.priority, director.state])
	var alt := director.use_alt
	director.use_alt = false
	_pending = {"line": to_line, "alt": alt}
	if _player.playing and transition == 0:
		_fading = true   # type 0: fade the old one out, then start the new (0x40ef00)
		return
	_fading = false
	_player.stop()
	_start_pending()


func _start_pending() -> void:
	var line: int = int(_pending.get("line", -1))
	_fade = 0.0
	_player.volume_db = VOLUME_DB
	if line < 0:
		return
	var l: Dictionary = director.lines[line]
	var first := int(l["alt_track"]) if bool(_pending.get("alt", false)) else int(l["start_track"])
	var last := int(l["end_track"])
	var pl := AudioStreamPlaylist.new()
	var n := 0
	for t in range(first, last):
		if _stream(t) != null:
			n += 1
	if n == 0:
		return
	pl.stream_count = n
	var i := 0
	for t in range(first, last):
		var s := _stream(t)
		if s != null:
			pl.set_list_stream(i, s)
			i += 1
	pl.loop = false
	_player.stream = pl
	_player.play()


func _on_finished() -> void:
	if _fading:
		return
	director.segment_ended()
