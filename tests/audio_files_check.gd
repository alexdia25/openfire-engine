# AudioFiles.load_stream(): a pack's music and jingles load from whichever format the pack was written in -- a WAV, or
# a QOA-compressed AudioStreamWAV saved as a resource (what a pack generated inside a shipped game writes, having no
# Vorbis encoder) -- straight from user://, and a missing or unknown file is a quiet null. Run (see tests/README.md):
#   godot --headless --path .harness --script res://addons/openfire_engine/tests/audio_files_check.gd
extends SceneTree

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _init() -> void:
	var dir := "user://audio_files_check"
	DirAccess.make_dir_recursive_absolute(dir)
	var pcm := PackedByteArray()
	pcm.resize(22050 * 4)   # half a second of stereo 16-bit silence at 44.1 kHz
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = 44100
	wav.data = pcm
	wav.save_to_wav(dir.path_join("tone.wav"))

	var from_wav := AudioFiles.load_stream(dir.path_join("tone.wav"))
	_check(from_wav is AudioStreamWAV and absf(from_wav.get_length() - 0.5) < 0.01, "a .wav loads as an AudioStreamWAV of the right length")

	var qoa := AudioStreamWAV.load_from_buffer(FileAccess.get_file_as_bytes(dir.path_join("tone.wav")), {"compress/mode": 2})
	_check(qoa.format == AudioStreamWAV.FORMAT_QOA, "Godot compresses PCM to QOA at runtime")
	ResourceSaver.save(qoa, dir.path_join("tone.res"))
	var from_res := AudioFiles.load_stream(dir.path_join("tone.res"))
	_check(from_res is AudioStreamWAV and (from_res as AudioStreamWAV).format == AudioStreamWAV.FORMAT_QOA
			and absf(from_res.get_length() - 0.5) < 0.01, "a saved QOA resource loads from user:// as itself")

	_check(AudioFiles.load_stream(dir.path_join("missing.ogg")) == null, "a missing file is null")
	FileAccess.open(dir.path_join("notes.txt"), FileAccess.WRITE).store_string("not audio")
	_check(AudioFiles.load_stream(dir.path_join("notes.txt")) == null, "an unknown format is null")

	print("audio_files_check: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)
