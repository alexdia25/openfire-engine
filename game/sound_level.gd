class_name SoundLevel
extends RefCounted
## The sound engine's level and pitch maths (document 100), read from RFIRE.BIN:
##  - a descriptor's `level` (16.16, +0x10) times the voice's gain (1.0 with no source object; the traced distance falloff is 1.0 for the player's own vehicle) is the channel level
##    (FUN_00407ec0); the channel's DirectSound volume is min(level / 3 - 2200, 0) hundredths of a dB (FUN_00407ec0 -> FUN_00423af0 type 1). Every descriptor's level is below
##    6600, so every sound is attenuated: 0 to -22 dB, most of them -4 to -11.
##  - the music has its own mixer volume, 0x7fff = 0 dB (FUN_00423af0 with channel -1: (volume - 0x7fff) / 10 hundredths of a dB).
##  - a descriptor's `pitch` is the playback rate: 0 the sample's own, > 0 a rate in Hz, < 0 minus a 16.16 fraction of the sample's rate (FUN_00408170).
## Not modelled: the mixer's 0x7fff-a-side level budget shared by the loudest 20 voices in priority order (FUN_00407ec0), and the stereo pan from the source's position.

const FLOOR_DB := -80.0
const SAMPLE_RATE := 11025.0   ## every .SDT is 11025 Hz, 8-bit mono


## The volume in dB of a sound of descriptor level `level` (16.16) at `gain` (0..1).
static func db(level: float, gain: float = 1.0) -> float:
	var l := level * gain
	if l <= 0.0:
		return FLOOR_DB
	return maxf(minf(l / 3.0 - 2200.0, 0.0), -10000.0) / 100.0


## The player's pitch scale for a descriptor pitch.
static func pitch_scale(pitch: int) -> float:
	if pitch == 0:
		return 1.0
	if pitch > 0:
		return float(pitch) / SAMPLE_RATE
	return float(-pitch) / 65536.0
