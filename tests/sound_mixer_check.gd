# The sound mixing maths (issue alexdia25/openfire#22, wiki document 117): the distance falloff to each ear, the budget dealt out in
# priority order, the buffer's volume and pan, and SoundManager's use of them (15 voices, a source's pan, falloff with distance). Run:
#   godot --headless --audio-driver Dummy --path .harness --script res://addons/openfire_engine/tests/sound_mixer_check.gd
extends SceneTree

const Fixture := preload("fixtures/synthetic_pack.gd")

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _near(a: float, b: float, eps := 0.001) -> bool:
	return absf(a - b) < eps


func _init() -> void:
	_maths()
	await _manager()
	if _failures == 0:
		print("sound mixer: all ok")
	quit(_failures)


func _maths() -> void:
	_check(SoundMixer.distance(Vector3(10.9, 0, 0), Vector3.ZERO) == 10.0 and SoundMixer.distance(Vector3(3, 4, 12), Vector3.ZERO) == 13.0,
			"the distance is the floor of the root of the whole-unit differences squared (FUN_0042cd30)")
	_check(SoundMixer.falloff(0.0) == 1.0 and SoundMixer.falloff(40.0) == 1.0, "full volume within 40 units (0x1a8 - d >= 0x180)")
	_check(_near(SoundMixer.falloff(232.0), 0.5), "half way at 232")
	_check(SoundMixer.falloff(424.0) == 0.0 and SoundMixer.falloff(900.0) == 0.0, "none at 424")
	_check(_near(SoundMixer.falloff(0.0, 0.5), 0.5) and SoundMixer.falloff(0.0, 0.0) == 0.0 and SoundMixer.falloff(0.0, 1.0) == 1.0, "the side weight scales below 1.0 and 0 mutes")
	var g := SoundMixer.ear_gains(Vector3(0, 0, 0), Vector3(0, 0, 0))
	_check(g == Vector2.ONE, "a source at the listener is heard by both ears in full")
	var r := SoundMixer.ear_gains(Vector3(200, 0, 0), Vector3.ZERO)
	_check(r.y > r.x and _near(r.x, (424.0 - 210.0) / 384.0) and _near(r.y, (424.0 - 190.0) / 384.0), "a source to the right is nearer the right ear (ears at -10 and +10 in x)")
	_check(SoundMixer.flat_gains(0) == Vector2.ONE and SoundMixer.flat_gains(2) == Vector2(1, 0) and SoundMixer.flat_gains(4) == Vector2(0, 1) and SoundMixer.flat_gains(0x40) == Vector2.ZERO,
			"a flat voice: flag 2 is left only, 4 right only, 0x40 silent")
	var voices := [{"gains": Vector2.ONE, "level": 20000.0}, {"gains": Vector2.ONE, "level": 20000.0}, {"gains": Vector2.ONE, "level": 20000.0}]
	SoundMixer.allocate(voices)
	_check(voices[0]["channel"] == Vector2(20000, 20000) and voices[1]["channel"] == Vector2(12767, 12767) and voices[2]["channel"] == Vector2.ZERO,
			"the 0x7fff budget goes to the voices in order: 20000, then what is left, then nothing")
	_check(_near(SoundMixer.volume_db(Vector2(5461, 5461)), (5461.0 / 3.0 - 2200.0) / 100.0) and SoundMixer.volume_db(Vector2.ZERO) == SoundMixer.DB_FLOOR
			and SoundMixer.volume_db(Vector2(9000, 100)) == 0.0, "volume is min(max side / 3 - 2200, 0) hundredths of a dB")
	_check(SoundMixer.pan_hundredths(Vector2(1000, 500)) == -5000.0 and SoundMixer.pan_hundredths(Vector2(500, 1000)) == 5000.0 and SoundMixer.pan_hundredths(Vector2(7, 7)) == 0.0
			and SoundMixer.pan_hundredths(Vector2(1000, 0)) == -10000.0, "pan is (right - left) * 10000 / the larger side")
	var o := SoundMixer.output_gains(Vector2(1000, 500))
	_check(o.x > o.y and _near(o.y / o.x, SoundMixer.db_to_linear(-50.0), 0.0001), "a pan of -5000 silences the right side by 50 dB")
	var back := SoundMixer.panner_for(Vector2(0.2, 0.6))
	var s := SoundMixer.db_to_linear(float(back["volume_db"]))
	_check(_near(s * (1.0 - float(back["pan"])), 0.2) and _near(s * (1.0 + float(back["pan"])), 0.6), "Godot's linear panner reproduces any pair of output gains")


func _wav(path: String) -> void:
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = 11025
	var d := PackedByteArray()
	d.resize(22050)
	d.fill(0x20)
	st.data = d
	st.save_to_wav(path)


class Src extends Node2D:
	var z := 0.0


func _manager() -> void:
	var base := Fixture.build("user://packs")
	var cues := {}
	for id in ["Loud", "Quiet", "Bell", "Mid"]:
		_wav(base.path_join("audio/%s.wav" % id.to_lower()))
	cues["Loud"] = {"file": "loud.wav", "category": "sfx", "priority": 200, "priority_later": 100, "priority_ticks": 10, "flags": 0, "level": 20000, "pitch": 0}
	cues["Quiet"] = {"file": "quiet.wav", "category": "sfx", "priority": 100, "priority_later": 100, "priority_ticks": 0, "flags": 0, "level": 20000, "pitch": 0}
	cues["Mid"] = {"file": "mid.wav", "category": "sfx", "priority": 120, "priority_later": 120, "priority_ticks": 0, "flags": 0, "level": 6000, "pitch": 0}
	cues["Bell"] = {"file": "bell.wav", "category": "sfx", "priority": 150, "priority_later": 150, "priority_ticks": 0, "flags": 4, "level": 5461, "pitch": 0}
	PackWriter.write_json(base.path_join("audio/audio.json"), cues)
	var pack := Pack.new()
	pack.load_from(base)
	var root := Node.new()
	get_root().add_child(root)
	var listener := Src.new()
	root.add_child(listener)
	var snd := SoundManager.new()
	root.add_child(snd)
	snd.setup(pack)
	snd.listener = listener
	await process_frame
	var pan := func(slot: int) -> float:
		return (AudioServer.get_bus_effect(AudioServer.get_bus_index(snd._buses[slot]), 0) as AudioEffectPanner).pan

	snd.play("Bell")
	_check(snd._voices.size() == 1 and _near(snd._players[0].volume_db, (5461.0 / 3.0 - 2200.0) / 100.0 - 6.0206, 0.01) and _near(pan.call(0), 1.0, 0.01),
			"a flat sound plays at its level; descriptor flag 4 makes it right-only: pan 1, the player 6 dB down because the panner doubles the one side (%.1f dB, pan %.2f)" % [snd._players[0].volume_db, pan.call(0)])
	snd._voices.clear()
	snd._players[0].stop()

	snd.play_at("Quiet", Vector2(300, 0))
	_check(pan.call(0) > 0.0 and snd._players[0].volume_db < SoundLevel.db(20000.0), "a source to the right of the listener is panned right and quieter (%.2f, %.1f dB)" % [pan.call(0), snd._players[0].volume_db])
	snd._release(snd._voices[0])
	snd.play_at("Quiet", Vector2(-300, 0))
	_check(pan.call(0) < 0.0, "and to the left, panned left")
	snd._release(snd._voices[0])
	snd.play_at("Quiet", Vector2(1000, 0))
	_check(snd._players[0].volume_db <= -80.0 + 0.001, "out of range (past 424 units) a sound is silent")
	snd._release(snd._voices[0])

	# own vehicle: a source at the listener is flat
	var own := Src.new()
	root.add_child(own)
	snd.play("Quiet", own)
	_check(_near(snd._players[snd._voices[0].slot].volume_db, SoundLevel.db(20000.0), 0.01) and _near(pan.call(snd._voices[0].slot), 0.0), "a source at the listener plays at full level, centred")
	snd._release(snd._voices[0])

	# budget: seven voices of level 6000 (-2 dB each): the sixth is left 2767 (-12.8 dB), the seventh nothing
	for i in 7:
		snd.play("Mid")
	var dbs := []
	for v in snd._voices:
		dbs.append(snd._players[v.slot].volume_db)
	_check(_near(dbs[0], (6000.0 / 3.0 - 2200.0) / 100.0, 0.01) and _near(dbs[4], dbs[0], 0.01) and _near(dbs[5], (2767.0 / 3.0 - 2200.0) / 100.0, 0.01) and dbs[6] <= -80.0 + 0.001,
			"the 0x7fff budget: five voices at their level, the sixth what is left, the seventh nothing (%s)" % [dbs])
	for v in snd._voices.duplicate():
		snd._release(v)
	# priority falls after its ticks: Loud (200 -> 100) then ties with Quiet (100): order by loudness, still no crash
	var v1 = snd._start("Loud", null, false, Vector3.ZERO)
	v1.age = 11.0
	_check(v1.priority() == 100, "a voice's priority falls to the second value after its ticks")
	snd._release(v1)

	# the listener's height (the camera's, -170): even a source right under the listener is 170 units away
	snd.listener_z = -170.0
	snd.play("Quiet", own)
	var g_own := SoundMixer.falloff(170.0)
	_check(_near(snd._voices[0].gains.x, g_own, 0.01) and g_own < 0.7, "with the listener at the camera's height a source at the listener's x, y is heard at %.2f, not 1.0" % snd._voices[0].gains.x)
	snd._release(snd._voices[0])
	snd.listener_z = null

	# the side weight (the game view's fade) scales sourced voices only
	snd.weight = 0.0
	snd.play("Quiet", own)
	snd.play("Quiet")
	var sourced_db: float = snd._players[snd._voices[0].slot].volume_db
	var flat_db: float = snd._players[snd._voices[1].slot].volume_db
	_check(sourced_db <= -80.0 + 0.001 and _near(flat_db, SoundLevel.db(20000.0), 0.01), "with the view faded out (weight 0) a sourced voice is silent and a flat one is not (%.1f, %.1f dB)" % [sourced_db, flat_db])
	snd.weight = 1.0
	for v in snd._voices.duplicate():
		snd._release(v)

	# a looping voice follows its source until stopped
	var mover := Src.new()
	root.add_child(mover)
	mover.position = Vector2(300, 0)
	var loop = snd.start_loop("Quiet", mover)
	snd._process(0.1)
	var db_far: float = snd._players[loop.slot].volume_db
	mover.position = Vector2(0, 0)
	snd._process(0.1)
	_check(loop != null and snd._players[loop.slot].volume_db > db_far and snd._voices.has(loop), "a loop follows its source: louder as it comes to the listener (%.1f -> %.1f dB) and stays after _process" % [db_far, snd._players[loop.slot].volume_db])
	snd.stop_loop(loop)
	_check(not snd._voices.has(loop), "stop_loop ends it")

	# the 15-voice limit: a 16th request is dropped
	for i in 20:
		snd.play_at("Bell", Vector2(5, 5))
	_check(snd._voices.size() == SoundManager.MAX_VOICES, "at most 15 voices play at once (%d)" % snd._voices.size())
	snd.queue_free()
	await process_frame
	var leaked := 0
	for i in AudioServer.bus_count:
		if AudioServer.get_bus_name(i).begins_with("SndVoice"):
			leaked += 1
	_check(leaked == 0, "the manager removes its voice buses when it leaves the tree")
