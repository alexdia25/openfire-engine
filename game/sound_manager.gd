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
## Not modelled yet (document 82's "Not applied" list): positional volume/pan by distance
## (FUN_00408050, untraced), per-cue pitch/fade envelopes (the descriptor's own fields, traced
## but not read here), and looping cues -- every cue here is a fire-and-forget one-shot.

const POOL_SIZE := 8

var pack: Pack
var _streams: Dictionary = {}   ## cue id -> AudioStreamWAV (or null if missing/failed once)
var _players: Array[AudioStreamPlayer] = []


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


func play(cue_id: String) -> void:
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
