extends VehicleModule
## The MSV's mine layer: its record's slot 1, handler FUN_0040d820 (documents 60, 75). One mine every `interval_ticks`,
## placed at (x + dirx * offset_x, y + diry * offset_y) where (dirx, diry) is the unit heading vector -- as coded that
## moves it only along y (in front of a north- or south-facing vehicle, on top of an east- or west-facing one). No mine
## while the vehicle's water state or the drop point is deep water (FUN_00409e30), none without stock (no click), and only
## with two players (FUN_0040d820's `1 < DAT_00442fbc`; the match sets Vehicle.mine_layer_enabled). Runs itself.

const SCHEMA := {
	"slot": "weapon", "doc": "Drops mines behind or under the vehicle (FUN_0040d820)",
	"params": {
		"interval_ticks": {"type": "float", "unit": "ticks", "default": 140.0, "provenance": "traced:60"},
		"offset_x": {"type": "float", "unit": "units", "default": 0.0, "provenance": "traced:60 (slot +4)"},
		"offset_y": {"type": "float", "unit": "units", "default": 5.0, "provenance": "traced:60 (slot +8)"},
		"ammo_slot": {"type": "int", "default": 1, "provenance": "traced:72", "doc": "Which ammunition counter it spends"},
	},
	"channels": [],
}

const TICK_HZ := 62.5
const SELF_DRIVEN := true


func tick(v: Vehicle, delta: float) -> void:
	v._mine_cooldown_remaining = maxf(v._mine_cooldown_remaining - delta, 0.0)
	if v.mine_layer_enabled and v._wants_mine() and v._mine_cooldown_remaining <= 0.0:
		_drop(v)


func _drop(v: Vehicle) -> void:
	var rad := deg_to_rad(v.heading_deg)
	var at := v.position + Vector2(cos(rad) * f("offset_x"), sin(rad) * f("offset_y"))
	if v.water_class == 2 or (v.level != null and v.pack != null and Water.class_at(v.level, v.pack, at) == 2):
		return
	var slot := int(params["ammo_slot"])
	if v.ammo[slot] < 1 and not v.infinite_ammo:   # FUN_0040d820: `st[+0xc] > 0` is a condition, there is no click
		return
	if not v.infinite_ammo:
		v.ammo[slot] -= 1
	v._mine_cooldown_remaining = f("interval_ticks") / TICK_HZ
	v.mine_dropped.emit(at)
