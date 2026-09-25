class_name SoundManager
extends Node
## Plays traced Return Fire sound cues (document 82) from a loaded Pack's audio/audio.json.
## Cue ids match tools/data/sound_cues.json and Vehicle.sound_cue -- the presentation-layer
## pattern game/terrain_view_3d.gd already uses for everything else (a gameplay node emits a
## signal, a rendering/presentation node reacts): Vehicle owns no AudioStreamPlayer itself, it
## just emits `sound_cue(id)` and whichever scene is running connects a SoundManager to it.
##
## Streams are loaded with AudioStreamWAV.load_from_file() straight from the pack's own audio/
## directory, never through res://'s import pipeline -- the same reasoning as Pack.gd's raw
## Image.load() for sprites (packs/.gdignore, PORTING_PLAN.md section 2.4.2).
##
## The player vehicle's continuous engine sound (Tread / JeepIdle / the Heli's rotor, document 97) is a looping voice managed here from the vehicle's own state.
## Not modelled yet (document 82's "Not applied" list): positional volume/pan by distance
## (FUN_00408050; the traced falloff, full volume within 40 units and none at 424, is 1.0 for the player's own vehicle), per-cue pitch/fade envelopes for the one-shots.

const POOL_SIZE := 8

var pack: Pack
var _streams: Dictionary = {}   ## cue id -> AudioStreamWAV (or null if missing/failed once)
var _players: Array[AudioStreamPlayer] = []
var _vehicle: Vehicle
var _loops: Dictionary = {}          ## audio/loops.json's "loops"
var _loop_by_type: Array = []
var _loop_player: AudioStreamPlayer
var _loop_key := ""                  ## the loop now playing ("" = none)
var _loop_age := 0.0                 ## ticks since it started
var _loop_streams: Dictionary = {}


func setup(p: Pack) -> void:
	pack = p
	if _players.is_empty():   # built here, not in _ready(): a cue can be played the same frame setup() runs
		for i in POOL_SIZE:
			var player := AudioStreamPlayer.new()
			add_child(player)
			_players.append(player)


## Connects every cue a Vehicle emits (empty ammo, Heli spin-up, ...) to playback.
func connect_vehicle(v: Vehicle) -> void:
	v.sound_cue.connect(play)
	_vehicle = v
	_load_loops()


func play(cue_id: String) -> void:
	if cue_id == "Heli" and not _loops.is_empty():
		return   # 0x44b550 is the rotor's LOOP (document 97), started by _update_loop when the start-up reaches its ramp; not a one-shot chime
	var stream := _stream_for(cue_id)
	if stream == null:
		return
	var player := _free_player()
	player.stream = stream
	player.play()


func _stream_for(cue_id: String) -> AudioStreamWAV:
	if _streams.has(cue_id):
		return _streams[cue_id]
	var stream: AudioStreamWAV = null
	if pack != null:
		var path := pack.get_sound_path(cue_id)
		if path != "":
			stream = AudioStreamWAV.load_from_file(path)
	_streams[cue_id] = stream
	return stream


func _free_player() -> AudioStreamPlayer:
	for p in _players:
		if not p.playing:
			return p
	return _players[0]   ## pool exhausted: steal the oldest voice rather than drop the new one


## audio/loops.json (tools/extract_engine_loops.py), from the top pack layer that has it.
func _load_loops() -> void:
	if pack == null or not _loops.is_empty():
		return
	for i in range(pack.layers.size() - 1, -1, -1):
		var path := "%s/audio/loops.json" % pack.layers[i]
		if FileAccess.file_exists(path):
			var doc = JSON.parse_string(FileAccess.get_file_as_string(path))
			if doc is Dictionary:
				_loops = doc.get("loops", {})
				_loop_by_type = doc.get("by_vehicle_type", [])
				for k in _loops:
					var wav := "%s/audio/%s" % [pack.layers[i], String(_loops[k]["wav"])]
					var st := AudioStreamWAV.load_from_file(wav) if FileAccess.file_exists(wav) else null
					if st != null:
						st.loop_mode = AudioStreamWAV.LOOP_FORWARD   # the whole sample loops (the descriptor's `length` field, untraced, may be a loop window)
						st.loop_begin = 0
						st.loop_end = st.data.size()   # 8-bit mono: one byte a frame
					_loop_streams[k] = st
				break
	if not _loops.is_empty() and _loop_player == null:
		_loop_player = AudioStreamPlayer.new()
		add_child(_loop_player)


## Which loop the vehicle should be playing now, or "": the object exists (alive, not docked in the base); the Heli's rotor only once its start-up has left the silent
## blade acceleration (stage 1, document 79: 0x40e8f5 starts the voice when the accumulator passes 1.0).
func _wanted_loop() -> String:
	var v := _vehicle
	if v == null or not v.alive or v.docked or _loop_by_type.is_empty():
		return ""
	if v.vehicle_type == 3 and v.heli_spinup_stage == 1:
		return ""
	return String(_loop_by_type[v.vehicle_type]) if v.vehicle_type < _loop_by_type.size() else ""


func _process(delta: float) -> void:
	if _loop_player == null:
		return
	var key := _wanted_loop()
	if key != _loop_key:
		_loop_key = key
		_loop_age = 0.0
		if key == "" or _loop_streams.get(key) == null:
			_loop_player.stop()
		else:
			_loop_player.stream = _loop_streams[key]
			_loop_player.play()
	if _loop_key == "":
		return
	_loop_age += delta * Vehicle.TICK_HZ
	var l: Dictionary = _loops[_loop_key]
	_loop_player.pitch_scale = maxf(EngineLoop.pitch_scale(l, _vehicle.speed / Vehicle.TICK_HZ, _vehicle.rotor_speed_steps), 0.01)
	_loop_player.volume_db = linear_to_db(EngineLoop.volume(l, _loop_age))
