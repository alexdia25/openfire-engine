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
var _loop_player: AudioStreamPlayer
var _loop_key := ""                  ## the loop now playing ("" = none)
var _loop_age := 0.0                 ## ticks since it started
var _loop_streams: Dictionary = {}   ## wav file -> AudioStreamWAV (null if missing)


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
	if _loop_player == null:
		_loop_player = AudioStreamPlayer.new()
		add_child(_loop_player)


func play(cue_id: String) -> void:
	if _vehicle != null and cue_id == String(_engine_loop(_vehicle).get("cue", "")):
		return   # the vehicle's own engine loop (the Heli's 0x44b550, document 97) plays as the loop below, not also as a one-shot
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


## The vehicle's engine loop: its definition's sounds.engine_loop (document 97; PORTING_PLAN.md 2.7.2), or {}.
func _engine_loop(v: Vehicle) -> Dictionary:
	var l: Variant = pack.vehicle_value(v.vehicle_type, "sounds.engine_loop", {}) if pack != null else {}
	return l if l is Dictionary else {}


## The loop's sample, from the top pack layer that has it (a mod can replace or add one), looped whole.
func _loop_stream(wav: String) -> AudioStreamWAV:
	if _loop_streams.has(wav):
		return _loop_streams[wav]
	var st: AudioStreamWAV = null
	for i in range(pack.layers.size() - 1, -1, -1):
		var path := "%s/audio/%s" % [pack.layers[i], wav]
		if FileAccess.file_exists(path):
			st = AudioStreamWAV.load_from_file(path)
			if st != null:
				st.loop_mode = AudioStreamWAV.LOOP_FORWARD   # the whole sample loops (the descriptor's `length` field, untraced, may be a loop window)
				st.loop_begin = 0
				st.loop_end = st.data.size()   # 8-bit mono: one byte a frame
			break
	_loop_streams[wav] = st
	return st


## Which loop the vehicle should be playing now (its id), or "": the object exists (alive, not docked in the base); a rotor
## only once its start-up has left the silent blade acceleration (stage 1, document 79: 0x40e8f5 starts the voice when
## the accumulator passes 1.0).
func _wanted_loop() -> String:
	var v := _vehicle
	if v == null or not v.alive or v.docked or v.heli_spinup_stage == 1:
		return ""
	return String(_engine_loop(v).get("id", ""))


func _process(delta: float) -> void:
	if _loop_player == null:
		return
	var key := _wanted_loop()
	if key != _loop_key:
		_loop_key = key
		_loop_age = 0.0
		var stream := _loop_stream(String(_engine_loop(_vehicle).get("wav", ""))) if key != "" else null
		if stream == null:
			_loop_player.stop()
		else:
			_loop_player.stream = stream
			_loop_player.play()
	if _loop_key == "":
		return
	_loop_age += delta * Vehicle.TICK_HZ
	var l := _engine_loop(_vehicle)
	_loop_player.pitch_scale = maxf(EngineLoop.pitch_scale(l, _vehicle.speed / Vehicle.TICK_HZ, _vehicle.rotor_speed_steps), 0.01)
	_loop_player.volume_db = linear_to_db(EngineLoop.volume(l, _loop_age))
