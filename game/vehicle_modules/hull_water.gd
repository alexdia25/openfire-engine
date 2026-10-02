extends VehicleModule
## A vehicle that can end up in water (document 62; the record's water handler +0x14c). `water_class` is FUN_0042f280's
## answer for the tile under the vehicle (0 land, 1 shallow, 2 deep), recomputed every frame. In deep water it sinks (`z`
## falls `sink_rate` a tick) and is lost deeper than the definition's `stats.sink_depth` (record +0x158); in shallow water
## or on land it comes back up. With `can_swim` (the Jeep) the second button toggles swim mode (FUN_0040dfe0): the flag
## `swim_target` (state +0x84) that `swim_amount` (state +0x80) follows at `swim_ramp` a tick; a swimming vehicle floats.
## A vehicle without this module (the Heli: its +0x4c is 0) never asks.
##
## Wading (issue #25, document 123): the original's three water handlers (dry 0x40cef0, wading 0x40d150, sinking 0x40cf90) also swap the object's draw
## descriptor. `wading` is the wading handler: entered from dry in any water (not deep, unless a swimming Jeep) when the vehicle moves forward at
## half the terrain-scaled top speed or more, with a splash counter (`wade_counter`, state +0x48) starting at 4.0 and growing `wade_rate` a tick; at
## `wade_wrap` it falls back by `wade_wrap_moving` while the vehicle keeps wading (shallow water, moving forward) and by the whole `wade_wrap` otherwise,
## and the handler ends when, not wading, the counter's integer part goes from `wade_dry_after` to the next. Its integer part picks the spray cel.

const SCHEMA := {
	"slot": "water", "doc": "Sinks in deep water; optionally swims (FUN_0042f280, FUN_0040cf90, the Jeep's FUN_0040dfe0)",
	"params": {
		"can_swim": {"type": "bool", "default": false, "provenance": "traced:62", "doc": "The second button toggles swim mode (the Jeep)"},
		"sink_rate": {"type": "float", "unit": "units/tick", "default": 0x6666 / 65536.0, "provenance": "traced:62"},
		"swim_ramp": {"type": "float", "unit": "per tick", "default": 1092.0 / 65536.0, "provenance": "traced:62"},
		"wade_start": {"type": "float", "default": 4.0, "provenance": "traced:123", "doc": "The splash counter when wading starts (0x40000)"},
		"wade_rate": {"type": "float", "unit": "per tick", "default": 0x3333 / 65536.0, "provenance": "traced:123"},
		"wade_wrap": {"type": "float", "default": 13.0, "provenance": "traced:123", "doc": "The counter at which it wraps"},
		"wade_wrap_moving": {"type": "float", "default": 5.0, "provenance": "traced:123", "doc": "...by this while the vehicle keeps wading, else by wade_wrap"},
		"wade_dry_after": {"type": "int", "default": 3, "provenance": "traced:123", "doc": "Not wading, the handler ends when the counter's integer part leaves this"},
	},
	"channels": ["z", "water_class", "swim_amount", "swim_target", "wade_counter", "water_view"],
}

const TICK_HZ := 62.5


## FUN_0040dfe0: enter swim mode while in water (either kind) and not yet swimming; leave it when not in deep water.
func toggle_swim(v: Vehicle) -> void:
	if not b("can_swim"):
		return
	if v.water_class != 0 and v.swim_target == 0.0:
		v.swim_target = 1.0
		v.sound_cue.emit("TireOut")   # FUN_0040dfe0: FUN_004232d0(1, 0x44b958, vehicle, 0) as it switches the swim flag on (issue #22, document 117)
	elif v.water_class != 2 and v.swim_target == 1.0:
		v.swim_target = 0.0
		v.sound_cue.emit("TireIn")    # ... and 0x44b940 as it switches it off


## FUN_0040cef0 / FUN_0040cf90 / FUN_0040d150: does the vehicle move forward at half the terrain-scaled top speed or more (the wading test)?
func _fast_enough(v: Vehicle) -> bool:
	return v.speed != 0.0 and v._terrain_speed_scale() * v.max_speed * 0.5 <= v.speed


func update(v: Vehicle, delta: float) -> void:
	var ticks := delta * TICK_HZ
	v.water_class = Water.class_at(v.level, v.pack, v.position, v.hit_polygon(), v.z)
	if v.swim_amount != v.swim_target:
		v.swim_amount = move_toward(v.swim_amount, v.swim_target, f("swim_ramp") * ticks)
	var swimming := b("can_swim") and v.swim_target == 1.0
	if v.wading:
		_wade(v, ticks, swimming)
		if not v.wading:
			return
	if not v._sinking:
		if v.water_class == 2 and not swimming:
			v._sinking = true
			v.wading = false
			v.wade_counter = 0.0
		elif v.water_class != 0 and not v.wading and _fast_enough(v):
			v.wading = true
			v.wade_counter = f("wade_start")
		if not v._sinking:
			return
	if v.water_class == 0:
		v._sinking = false
		v.z = 0.0
	elif v.water_class == 1 or swimming:
		v.z += f("sink_rate") * ticks
		if v.z >= 0.0:
			v.z = 0.0
			v._sinking = false
			if _fast_enough(v):   # FUN_0040cf90: back at the surface and still moving: the wading handler
				v.wading = true
				v.wade_counter = f("wade_start")
	else:
		v.z -= f("sink_rate") * ticks
		if floorf(v.z) <= -floorf(v.sink_depth):
			v.z = 1.0 - v.sink_depth
			v.alive = false
			v._sinking = false
			v.drowned.emit(v)


## FUN_0040d150, the wading handler: the splash counter grows; deep water (and not a swimming Jeep) ends it in the sinking handler.
func _wade(v: Vehicle, ticks: float, swimming: bool) -> void:
	var old := v.wade_counter
	v.wade_counter += f("wade_rate") * ticks
	if v.water_class == 2 and not swimming:
		v.wading = false
		v.wade_counter = 0.0
		v._sinking = true
		return
	var keeps_wading := v.water_class == 1 and v.speed > 0.0
	if v.wade_counter < f("wade_wrap"):
		if not keeps_wading and int(old) <= int(f("wade_dry_after")) and int(v.wade_counter) > int(f("wade_dry_after")):
			v.wading = false
			v.wade_counter = 0.0
		return
	v.wade_counter -= f("wade_wrap_moving") if keeps_wading else f("wade_wrap")
