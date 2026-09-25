class_name MusicManager
extends Node
## Plays the game's music (document 98): watches the match the way the original's interface bits do, feeds game/music_director.gd (the traced decision logic) once a game
## tick, and plays what it decides from the pack's music/track_NN.ogg (tools/extract_music.py; the original's tracks are pieces of the CD's audio).
## A line plays its tracks from `start` up to `end` (exclusive) as one gapless playlist; a looping line then repeats from its alternate track; a sting plays once.
## PORT CHOICES / UNTRACED: the fade-out length of a type-0 transition (the original's mixer command 6 fades by a rate not read), the music volume, and that the first start of a
## match is the vehicle's theme at once (the original opens on the hangar screen with the Bunker theme; the port starts in the vehicle).

const TICK_HZ := 62.5
const FADE_OUT_S := 0.75       ## PORT CHOICE
const VOLUME_DB := -6.0        ## PORT CHOICE (the original's mixer volume is 0x7fff, the maximum)
## FUN_0040b980's own request for a new vehicle: the record's bytes +0x2bc (line) and +0x2bd (priority), read from the four vehicle records (0x445974, 0x445c5c, 0x445f44, 0x44622c).
const RECORD_LINE := [0, 4, 6, 8]
const RECORD_PRIORITY := 0x80
## The death line of the dying vehicle's type: the byte table at 0x4466e4 (Tank 3, Jeep 5, MSV 7, Heli 10).
const DEATH_LINE := [3, 5, 7, 10]

var pack: Pack
var mc: MatchController
var director := MusicDirector.new()
var _tracks: Dictionary = {}            ## track number -> {"file": path, "stream": AudioStreamOggVorbis or null}
var _player: AudioStreamPlayer
var _acc := 0.0
var _pending := {}                      ## {"line": int, "alt": bool} waiting for the fade-out to finish
var _fading := false
var _gain := 1.0
var _last_undocking := false
var _last_death_phase := 0
var _last_finished := false
var _flag_count := 0
var _started := false


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
		if FileAccess.file_exists(path):
			t["stream"] = AudioStreamOggVorbis.load_from_file(path)
	return t["stream"]


func _process(delta: float) -> void:
	if _player == null or mc == null or mc.vehicle == null:
		return
	if not _started:
		_started = true
		_last_undocking = mc.undocking
		_flag_count = mc.flags.size()
		if not mc.selecting:
			_vehicle_created()   # the port starts with the vehicle already out
	_poll()
	_acc += delta * TICK_HZ
	while _acc >= 1.0:
		_acc -= 1.0
		_tick()
	if _fading:
		_gain = maxf(_gain - delta / FADE_OUT_S, 0.0)
		_player.volume_db = VOLUME_DB + linear_to_db(maxf(_gain, 0.0001))
		if _gain <= 0.0:
			_fading = false
			_player.stop()
			_start_pending()


## The game's interface bits (document 71): a vehicle created, the player's vehicle destroyed, a flag appearing or carried, the vehicle choice open.
func _poll() -> void:
	var v := mc.vehicle
	if mc.undocking and not _last_undocking:
		_vehicle_created()   # the choice was confirmed: FUN_0040b1c0 creates the vehicle (FUN_0040b980 sets the bit)
	_last_undocking = mc.undocking
	if mc.death_phase != 0 and _last_death_phase == 0:
		director.vehicle_destroyed(DEATH_LINE[v.vehicle_type])
	_last_death_phase = mc.death_phase
	if mc.flags.size() > _flag_count:
		director.bit_flag_appeared = true
	_flag_count = mc.flags.size()
	if mc.match_finished and not _last_finished:
		director.stop()   # FUN_00405660 at the end of the match
	_last_finished = mc.match_finished
	director.choosing = 1 if mc.selecting else 0
	director.in_game_view = not (mc.selecting or mc.undocking or mc.death_phase != 0)


func _vehicle_created() -> void:
	director.vehicle_created(int(RECORD_LINE[mc.vehicle.vehicle_type]), RECORD_PRIORITY)


func _tick() -> void:
	if mc.match_finished:
		return   # the end-of-match handler has replaced the game view's loops that run the director (document 92)
	director.bit_flag_carried = _flag_carried_by_other_team()
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
	return MusicDirector.vehicle_line(v.vehicle_type, own_carried, near, mc.vehicle_stock[v.vehicle_type], int(RECORD_LINE[v.vehicle_type]), randi() % 8)


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
	_gain = 1.0
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
