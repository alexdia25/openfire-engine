# The sound engine's level maths (document 100): a descriptor's level is a 16.16 fraction, the channel volume
# min(level / 3 - 2200, 0) hundredths of a dB, the music's mixer volume 0x7fff is 0 dB, and a descriptor's pitch is a
# rate. Pure arithmetic, no pack. (That a real pack's cues carry the traced levels is the game's own check.) Run:
#   godot --headless --path .harness --script res://addons/openfire_engine/tests/sound_level_check.gd
extends SceneTree

var fails := 0


func check(name: String, ok: bool, detail: String = "") -> void:
	print(("ok   " if ok else "FAIL ") + name + ("  " + detail if detail != "" else ""))
	if not ok:
		fails += 1


func _init() -> void:
	check("level 0x1111 is -7.4 dB", absf(SoundLevel.db(0x1111) + 7.44) < 0.01, str(SoundLevel.db(0x1111)))
	check("level 0x1555 is -3.8 dB, 0x0ccc -11.1 dB", absf(SoundLevel.db(0x1555) + 3.8) < 0.01 and absf(SoundLevel.db(0xccc) + 11.08) < 0.01)
	check("level 5 is -22 dB", absf(SoundLevel.db(5) + 22.0) < 0.02)
	check("a level of 6600 or more is full volume", SoundLevel.db(0x2000) == 0.0 and SoundLevel.db(0x2ccc) == 0.0 and SoundLevel.db(0x10000) == 0.0)
	check("no level is silent", SoundLevel.db(0) == SoundLevel.FLOOR_DB)
	check("half the gain is 6600 - 3300 less: 0x1555 at gain 0.5", absf(SoundLevel.db(0x1555, 0.5) - (0x1555 * 0.5 / 3.0 - 2200.0) / 100.0) < 0.001)
	check("pitch 0 is the sample's own rate", SoundLevel.pitch_scale(0) == 1.0)
	check("a negative pitch is a 16.16 fraction of the rate: -0x8000 is half, -0x10000 is 1.0", SoundLevel.pitch_scale(-32768) == 0.5 and SoundLevel.pitch_scale(-65536) == 1.0)
	check("a positive pitch is a rate in Hz: 3932 is 0.357 x 11025", absf(SoundLevel.pitch_scale(3932) - 3932.0 / 11025.0) < 1e-6)
	check("the music's 0x7fff mixer volume is 0 dB", MusicManager.VOLUME_DB == 0.0)
	print("failures: ", fails)
	quit(1 if fails > 0 else 0)
