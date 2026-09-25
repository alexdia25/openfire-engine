extends VehicleModule
## The Jeep's missile: FUN_0040df00 / FUN_00415b00 / FUN_004159a0 (document 61): a lobbed missile from the vehicle's own
## position, `height` up, every `interval_ticks`; the target point comes from FUN_00415b00's rules (the match's
## aim_target, else a random point ahead).

const SCHEMA := {
	"slot": "weapon", "doc": "A missile lobbed at a target point (FUN_0040df00 / FUN_00415b00)",
	"params": {
		"interval_ticks": {"type": "float", "unit": "ticks", "default": 30.0, "provenance": "traced:61"},
		"height": {"type": "float", "unit": "units", "default": 5.0, "provenance": "traced:61"},
	},
	"channels": [],
}

const TICK_HZ := 62.5
const SELF_DRIVEN := false


func can_fire(_v: Vehicle) -> bool:
	return true


func fill_shot(v: Vehicle, spec: Dictionary) -> void:
	v._fire_cooldown_remaining = f("interval_ticks") / TICK_HZ
	spec["kind"] = "missile"
	spec["type"] = -1
	spec["position"] = v.position
	spec["z"] = f("height")
	spec["target"] = v.aim_target.call(v) if v.aim_target.is_valid() else v.random_aim_point()
