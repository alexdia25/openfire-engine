extends VehicleModule
## A vehicle that can end up in water (document 62; the record's water handler +0x14c). `water_class` is FUN_0042f280's
## answer for the tile under the vehicle (0 land, 1 shallow, 2 deep), recomputed every frame. In deep water it sinks (`z`
## falls `sink_rate` a tick) and is lost deeper than the definition's `stats.sink_depth` (record +0x158); in shallow water
## or on land it comes back up. With `can_swim` (the Jeep) the second button toggles swim mode (FUN_0040dfe0): the flag
## `swim_target` (state +0x84) that `swim_amount` (state +0x80) follows at `swim_ramp` a tick; a swimming vehicle floats.
## A vehicle without this module (the Heli: its +0x4c is 0) never asks.

const SCHEMA := {
	"slot": "water", "doc": "Sinks in deep water; optionally swims (FUN_0042f280, FUN_0040cf90, the Jeep's FUN_0040dfe0)",
	"params": {
		"can_swim": {"type": "bool", "default": false, "provenance": "traced:62", "doc": "The second button toggles swim mode (the Jeep)"},
		"sink_rate": {"type": "float", "unit": "units/tick", "default": 0x6666 / 65536.0, "provenance": "traced:62"},
		"swim_ramp": {"type": "float", "unit": "per tick", "default": 1092.0 / 65536.0, "provenance": "traced:62"},
	},
	"channels": ["z", "water_class", "swim_amount", "swim_target"],
}

const TICK_HZ := 62.5


## FUN_0040dfe0: enter swim mode while in water (either kind) and not yet swimming; leave it when not in deep water.
func toggle_swim(v: Vehicle) -> void:
	if not b("can_swim"):
		return
	if v.water_class != 0 and v.swim_target == 0.0:
		v.swim_target = 1.0
	elif v.water_class != 2 and v.swim_target == 1.0:
		v.swim_target = 0.0


func update(v: Vehicle, delta: float) -> void:
	var ticks := delta * TICK_HZ
	var before := v.water_class
	v.water_class = Water.class_at(v.level, v.pack, v.position, v.hit_polygon(), v.z)
	if before == 0 and v.water_class != 0:
		v.sound_cue.emit("TireIn")   # PORT CHOICE, untraced trigger: Sound/Tirein.SDT on the land->water transition (document 82)
	elif before != 0 and v.water_class == 0:
		v.sound_cue.emit("TireOut")  # PORT CHOICE, untraced trigger: Sound/Tireout.SDT on the water->land transition (document 82)
	if v.swim_amount != v.swim_target:
		v.swim_amount = move_toward(v.swim_amount, v.swim_target, f("swim_ramp") * ticks)
	var swimming := b("can_swim") and v.swim_target == 1.0
	if not v._sinking:
		if v.water_class == 2 and not swimming:
			v._sinking = true
		return
	if v.water_class == 0:
		v._sinking = false
		v.z = 0.0
	elif v.water_class == 1 or swimming:
		v.z += f("sink_rate") * ticks
		if v.z >= 0.0:
			v.z = 0.0
			v._sinking = false
	else:
		v.z -= f("sink_rate") * ticks
		if floorf(v.z) <= -floorf(v.sink_depth):
			v.z = 1.0 - v.sink_depth
			v.alive = false
			v._sinking = false
			v.drowned.emit(v)
