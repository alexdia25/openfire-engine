class_name AudioFiles
extends RefCounted
## Loads a pack's audio file at runtime, whatever format it was written in: always straight from the file, never
## through res://'s import pipeline (the same reasoning as Pack's raw Image.load()), so a pack works wherever it lives.
##
##   .ogg  Ogg Vorbis (e.g. a pack built by an offline pipeline with an encoder)
##   .wav  PCM or IMA-ADPCM WAV
##   .mp3  MP3
##   .res / .tres  a saved AudioStream resource -- e.g. an AudioStreamWAV compressed to QOA, which is what a pack
##         generated inside a shipped game can write, since Godot can compress to QOA at runtime but has no Vorbis
##         encoder


## The stream at `path`, or null (quietly: a missing or unreadable file is the caller's fallback, not an engine error).
static func load_stream(path: String) -> AudioStream:
	if not FileAccess.file_exists(path):
		return null
	match path.get_extension().to_lower():
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"wav":
			return AudioStreamWAV.load_from_file(path)
		"mp3":
			return AudioStreamMP3.load_from_file(path)
		"res", "tres":
			return ResourceLoader.load(path, "AudioStream") as AudioStream
	return null
