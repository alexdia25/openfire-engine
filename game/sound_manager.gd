class_name SoundManager
extends Node
## Plays traced Return Fire sound cues (document 82) from a loaded Pack's audio/audio.json, mixed the way the original's sound engine
## mixes them (issue #22, document 117; the maths are game/sound_mixer.gd).
##
## Cue ids match tools/data/sound_cues.json and Vehicle.sound_cue -- the presentation-layer pattern game/terrain_view_3d.gd already uses
## for everything else (a gameplay node emits a signal, a presentation node reacts): Vehicle owns no AudioStreamPlayer itself, it just
## emits `sound_cue(id)` and whichever scene is running connects a SoundManager to it.
##
## Voices. FUN_004089a0 builds a list of 15 voices; FUN_00408170 returns 0 (the sound is dropped) when none is free, so at most 15 sounds
## play at once and a 16th request is lost. A voice has a SOURCE (the object the command names, `play(cue, source)`; `play_at` gives a
## fixed position; none = a flat sound such as a menu click). While its source lives the voice follows it; when the source is gone it keeps the last position
## (FUN_00408050: flag 0x80). A sourced voice's left and right gains are the distance falloff to each ear of the LISTENER (the tracked
## vehicle, the camera's stand-in): see SoundMixer. Every frame the voices are sorted by priority (the cue's starting priority, its
## `priority_later` once `priority_ticks` have passed), the budget of 0x7fff a side is dealt out in that order, and each voice's player gets
## the resulting volume and pan (a bus with an AudioEffectPanner per voice, whose linear law is inverted exactly by SoundMixer.panner_for).
##
## Streams are loaded with AudioStreamWAV.load_from_file() straight from the pack's own audio/ directory, never through res://'s import
## pipeline -- the same reasoning as Pack.gd's raw Image.load() for sprites (packs/.gdignore, PORTING_PLAN.md section 2.4.2).
##
## Each connected vehicle owns an engine loop (Tread / JeepIdle / the Heli's rotor, document 97), a voice of its own that follows it, so a
## far vehicle's engine fades with distance like any other sound.
##
## PORT CHOICES, not traced: the listener's height (the original's is the view's z, `view + 0x20`, not mapped) is the tracked vehicle's own,
## so its own sounds are at distance 0; the side weight (cmd 8, 0 while a level is entered or left, FUN_00429de0) is 1.0 here.

const MAX_VOICES := 15   ## FUN_004089a0: the voice list's length (0xf)
const TICK_HZ := 62.5

var pack: Pack
var listener: Node2D = null          ## whose position the ears are around (the first connected vehicle by default)
var weight := 1.0                    ## the side weight of the positional gains (cmd 8)
var listener_z: Variant = null       ## the ears' height when set (the camera's: the view's +0x20); null = the listener node's own z
var _streams: Dictionary = {}        ## cue id -> AudioStreamWAV (or null if missing/failed once)
var _players: Array[AudioStreamPlayer] = []
var _buses: Array[String] = []
var _voices: Array[Voice] = []
var _vehicle: Vehicle                ## the first connected vehicle
var _loops: Array[Dictionary] = []   ## {vehicle, voice, key}
var _loop_streams: Dictionary = {}   ## wav file -> AudioStreamWAV (null if missing)


class Voice extends RefCounted:
	var cue := ""
	var slot := 0
	var level := 0.0
	var flags := 0
	var prio_start := 0
	var prio_later := 0
	var prio_ticks := 0.0
	var age := 0.0                   ## ticks since it started
	var source: Object = null
	var has_source := false          ## a source object or a fixed position (else a flat sound)
	var looping := false             ## kept until stopped (an engine loop, an object's hum) instead of ending with its sample
	var pos := Vector3.ZERO          ## the fixed position, or the source's last
	var gains := Vector2.ONE
	var channel := Vector2.ZERO

	func priority() -> int:
		return prio_later if (prio_start != prio_later and age > prio_ticks) else prio_start


func setup(p: Pack) -> void:
	pack = p
	if _players.is_empty():   # built here, not in _ready(): a cue can be played the same frame setup() runs
		for i in MAX_VOICES:
			var bus_name := "SndVoice%d_%d" % [get_instance_id(), i]
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.add_bus_effect(idx, AudioEffectPanner.new())
			_buses.append(bus_name)
			var player := AudioStreamPlayer.new()
			player.bus = bus_name
			add_child(player)
			_players.append(player)


func _exit_tree() -> void:
	for bus_name in _buses:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx >= 0:
			AudioServer.remove_bus(idx)
	_buses.clear()


## Connects every cue a Vehicle emits (empty ammo, Heli spin-up, ...) to playback, with the vehicle as the source, and gives it an engine loop.
func connect_vehicle(v: Vehicle) -> void:
	v.sound_cue.connect(func(cue: String): play(cue, v))
	if _vehicle == null:
		_vehicle = v
		listener = v
	_loops.append({"vehicle": v, "voice": null, "key": ""})


## Plays a cue. `source` is the object it comes from (anything with a `position`, a Node2D or a Vehicle), or null for a flat sound.
func play(cue_id: String, source: Object = null) -> void:
	if source is Vehicle and cue_id == String(_engine_loop(source).get("cue", "")):
		return   # the vehicle's own engine loop (the Heli's 0x44b550, document 97) plays as its loop, not also as a one-shot
	if source == null and _vehicle != null and cue_id == String(_engine_loop(_vehicle).get("cue", "")):
		return
	_start(cue_id, source, source != null, Vector3.ZERO)


## Plays a cue from a fixed place in the world (an impact, an explosion): `at` in world units, `z` its height.
func play_at(cue_id: String, at: Vector2, z := 0.0) -> void:
	_start(cue_id, null, true, Vector3(at.x, at.y, z))


## A looping voice that follows `source` (or sits at `at`) until stop_loop: the original's looping sounds (flags 0x20, the stepper FUN_00408450),
## e.g. the Drone's hum, which FUN_0040a7b0 starts when the first Drone is made and command 9 stops when the last is gone. Returns a handle
## (null if the sample is missing or all 15 voices are busy).
func start_loop(cue_id: String, source: Object = null, at := Vector3.ZERO) -> Object:
	var stream := _cue_loop_stream(cue_id)
	if stream == null or pack == null or _voices.size() >= MAX_VOICES:
		return null
	var v := _make_voice(cue_id, source, source != null or at != Vector3.ZERO, at)
	v.looping = true
	_attach(v, stream, SoundLevel.pitch_scale(int(pack.get_sound(cue_id).get("pitch", 0))))
	_remix()
	return v


func stop_loop(handle: Object) -> void:
	if handle is Voice and _voices.has(handle):
		_release(handle)


func _cue_loop_stream(cue_id: String) -> AudioStreamWAV:
	var key := "loop:" + cue_id
	if _streams.has(key):
		return _streams[key]
	var st: AudioStreamWAV = null
	var path := pack.get_sound_path(cue_id) if pack != null else ""
	if path != "":
		st = AudioStreamWAV.load_from_file(path)
		if st != null:
			st.loop_mode = AudioStreamWAV.LOOP_FORWARD
			st.loop_begin = 0
			st.loop_end = st.data.size() / (2 if st.format == AudioStreamWAV.FORMAT_16_BITS else 1)
	_streams[key] = st
	return st


func _make_voice(cue_id: String, source: Object, sourced: bool, pos: Vector3) -> Voice:
	var entry := pack.get_sound(cue_id)
	var v := Voice.new()
	v.cue = cue_id
	v.level = float(entry.get("level", 0x10000))
	v.flags = int(entry.get("flags", 0))
	v.prio_start = int(entry.get("priority", 0))
	v.prio_later = int(entry.get("priority_later", v.prio_start))
	v.prio_ticks = float(entry.get("priority_ticks", 0))
	v.source = source
	v.has_source = sourced
	v.pos = pos
	return v


func _start(cue_id: String, source: Object, sourced: bool, pos: Vector3) -> Voice:
	var stream := _stream_for(cue_id)
	if stream == null or pack == null or _voices.size() >= MAX_VOICES:
		return null   # a missing sample, or none of the 15 voices free: the request is dropped
	var v := _make_voice(cue_id, source, sourced, pos)
	_attach(v, stream, SoundLevel.pitch_scale(int(pack.get_sound(cue_id).get("pitch", 0))))
	_remix()
	return v


## Gives a voice a free pool slot and starts its stream.
func _attach(v: Voice, stream: AudioStreamWAV, pitch_scale: float) -> void:
	var used := {}
	for o in _voices:
		used[o.slot] = true
	for i in MAX_VOICES:
		if not used.has(i):
			v.slot = i
			break
	var player := _players[v.slot]
	player.stream = stream
	player.pitch_scale = pitch_scale
	player.volume_db = SoundMixer.DB_FLOOR
	player.play()
	_voices.append(v)


func _release(v: Voice) -> void:
	_players[v.slot].stop()
	_voices.erase(v)


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


## A vehicle's engine loop: its definition's sounds.engine_loop (document 97; PORTING_PLAN.md 2.7.2), or {}.
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
				st.loop_mode = AudioStreamWAV.LOOP_FORWARD   # the whole sample loops (the descriptor has no loop window: its +0x10 is the level, document 100)
				st.loop_begin = 0
				st.loop_end = st.data.size()   # 8-bit mono: one byte a frame
			break
	_loop_streams[wav] = st
	return st


## Which loop the vehicle should be playing now (its id), or "": the object exists (alive, not docked in the base); a rotor
## only once its start-up has left the silent blade acceleration (stage 1, document 79: 0x40e8f5 starts the voice when
## the accumulator passes 1.0).
func _wanted_loop(v: Vehicle) -> String:
	if v == null or not is_instance_valid(v) or not v.alive or v.docked or v.heli_spinup_stage == 1:
		return ""
	return String(_engine_loop(v).get("id", ""))


## The first connected vehicle's loop, as the engine-loop checks read it.
var _loop_key: String:
	get:
		return String(_loops[0]["key"]) if not _loops.is_empty() else ""

var _loop_player: AudioStreamPlayer:
	get:
		if _loops.is_empty() or _loops[0]["voice"] == null:
			return null
		return _players[(_loops[0]["voice"] as Voice).slot]


func _update_loops() -> void:
	for lp in _loops:
		var v: Vehicle = lp["vehicle"]
		var key := _wanted_loop(v)
		var voice: Voice = lp["voice"]
		if key != String(lp["key"]) or (key != "" and voice == null):
			if voice != null:
				_release(voice)
				lp["voice"] = null
			lp["key"] = key
			if key != "":
				var l := _engine_loop(v)
				var stream := _loop_stream(String(l.get("wav", "")))
				if stream == null or _voices.size() >= MAX_VOICES:
					lp["key"] = ""   # nothing to play, or no free voice: try again next frame
					continue
				voice = Voice.new()
				voice.cue = String(l.get("id", ""))
				voice.level = float(l["level"])
				voice.prio_start = int(l.get("priority_start", 0))
				voice.prio_later = int(l.get("priority_later", voice.prio_start))
				voice.prio_ticks = float(l.get("priority_ticks", 0))
				voice.source = v
				voice.has_source = true
				voice.looping = true
				_attach(voice, stream, 1.0)
				lp["voice"] = voice
		if lp["voice"] != null:
			var l2 := _engine_loop(v)
			_players[(lp["voice"] as Voice).slot].pitch_scale = maxf(EngineLoop.pitch_scale(l2, v.speed / Vehicle.TICK_HZ, v.rotor_speed_steps), 0.01)


func _process(delta: float) -> void:
	if pack == null:
		return
	var ticks := delta * TICK_HZ
	for v in _voices.duplicate():
		v.age += ticks
		if not v.looping and not _players[v.slot].playing:
			_voices.erase(v)   # played to the end
	_update_loops()
	_remix()


func _node_position(n: Object) -> Variant:
	if n is Node2D:
		var z := 0.0
		if "z" in n:
			z = float(n.z)
		return Vector3(n.position.x, n.position.y, z)
	return null


## Recomputes every voice's gains (FUN_004082b0: each tick), deals out the budget in priority order and sets the players.
func _remix() -> void:
	var lp: Variant = _node_position(listener) if listener != null and is_instance_valid(listener) else null
	var ear_centre: Vector3 = lp if lp != null else Vector3.ZERO
	if listener_z != null:
		ear_centre.z = float(listener_z)
	for v in _voices:
		if not v.has_source:
			v.gains = SoundMixer.flat_gains(v.flags)
			continue
		if v.source != null and is_instance_valid(v.source):
			var p: Variant = _node_position(v.source)
			if p != null:
				v.pos = p
		v.gains = SoundMixer.ear_gains(v.pos, ear_centre, weight) if lp != null else Vector2.ONE
	var order: Array = _voices.duplicate()
	order.sort_custom(func(a: Voice, b: Voice) -> bool:
		if a.priority() != b.priority():
			return a.priority() > b.priority()
		return a.gains.x + a.gains.y > b.gains.x + b.gains.y)
	var rows := []
	for v in order:
		rows.append({"gains": v.gains, "level": v.level})
	SoundMixer.allocate(rows)
	for i in order.size():
		var v: Voice = order[i]
		v.channel = rows[i]["channel"]
		var pn := SoundMixer.panner_for(SoundMixer.output_gains(v.channel))
		_players[v.slot].volume_db = maxf(float(pn["volume_db"]), -80.0)
		var eff := AudioServer.get_bus_effect(AudioServer.get_bus_index(_buses[v.slot]), 0) as AudioEffectPanner
		if eff != null:
			eff.pan = float(pn["pan"])
