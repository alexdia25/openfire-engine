class_name EngineLoop
extends RefCounted
## The vehicles' continuous engine sounds (document 97): which loop a vehicle type has and the pitch and volume it plays at. All numbers are read from the sound
## descriptors and the vehicle records (tools/extract_engine_loops.py writes them into audio/loops.json); the maths are the two voice callbacks:
##  - 0x40ee60 (Tank, MSV: Tread.SDT; Jeep: JeepIdle.SDT): pitch = record[+0x244] + ((record[+0x248] - record[+0x244]) * |speed| >> 16), speed in units a tick;
##  - 0x40eeb0 (Heli.SDT): pitch = 0xa3d + ((0xa3d - resource rate) * rotor speed >> 16), the rotor speed being state +0x84 (4.0 in flight).
## A pitch is a playback rate in the sample's own units (Hz, the samples are 11025 Hz): the player's pitch scale is pitch / base_rate.
## The volume envelope is the descriptor's: `volume_attack` for `attack_ticks` ticks, then `volume_sustain` (out of 255: PORT CHOICE for the scale, untraced).


## The pitch in Hz of loop `l` (an entry of loops.json) for a vehicle moving `speed_units_per_tick` (absolute) with rotor speed `rotor` (steps, 4.0 in flight).
static func pitch_hz(l: Dictionary, speed_units_per_tick: float, rotor: float) -> float:
	if String(l.get("kind", "speed")) == "rotor":
		return float(l["pitch_base"]) + (float(l["pitch_base"]) - float(l.get("resource_rate", 0))) * rotor
	var lo := float(l["pitch_min"])
	var hi := float(l["pitch_max"])
	return lo + (hi - lo) * absf(speed_units_per_tick)


static func pitch_scale(l: Dictionary, speed_units_per_tick: float, rotor: float) -> float:
	return pitch_hz(l, speed_units_per_tick, rotor) / float(l.get("base_rate", 11025))


## The linear volume (0..1) `age_ticks` after the loop started: the attack level, then the sustain level.
static func volume(l: Dictionary, age_ticks: float) -> float:
	var v := float(l["volume_attack"]) if age_ticks < float(l["attack_ticks"]) else float(l["volume_sustain"])
	return v / 255.0
