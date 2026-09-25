extends VehicleModule
## The Tank's gun: FUN_0040d240 (documents 45, 52, 64). The shot goes along the hull heading plus the turret angle (state
## +0x58). The muzzle is the point (0, -barrel, 0) turned by the shot's pitch (a raised gun: the mount's raised pitch up)
## plus (0, -pivot_ahead, pivot_height): at level fire `level_reach` in front of the centre and `pivot_height` up.

const SCHEMA := {
	"slot": "weapon", "doc": "A single-shot gun, level or raised (FUN_0040d240)",
	"params": {
		"projectile": {"type": "int", "default": 0, "provenance": "traced:45", "doc": "Projectile type (vehicles/projectile_types.json)"},
		"cooldown_ticks": {"type": "float", "unit": "ticks", "default": 20.0, "provenance": "traced:45 (slot +0x10)"},
		"level_reach": {"type": "float", "unit": "units", "default": 12.0, "provenance": "traced:52"},
		"barrel": {"type": "float", "unit": "units", "default": 6.75, "provenance": "traced:64"},
		"pivot_ahead": {"type": "float", "unit": "units", "default": 5.25, "provenance": "traced:64"},
		"pivot_height": {"type": "float", "unit": "units", "default": 7.0, "provenance": "traced:52"},
		"sound": {"type": "sound", "default": "Cannon", "provenance": "traced:82"},
		"flash": {"type": "explosion", "default": "0x445138", "provenance": "traced:52", "doc": "Muzzle flash record"},
	},
	"channels": [],
}

const TICK_HZ := 62.5
const SELF_DRIVEN := false


func can_fire(_v: Vehicle) -> bool:
	return true


func fill_shot(v: Vehicle, spec: Dictionary) -> void:
	v._fire_cooldown_remaining = f("cooldown_ticks") / TICK_HZ
	v.sound_cue.emit(String(params["sound"]))   # FUN_0040d240, document 64/82: the Tank's turret fire
	var h := v.heading_deg + v.turret_deg
	var hr := deg_to_rad(h)
	var shot_fwd := Vector2(cos(hr), sin(hr))
	var raised := v.gun_elev_deg > 0.0
	var reach := f("level_reach")
	var height := f("pivot_height")
	if raised:
		var pitch := v.raised_pitch_deg()
		var pr := deg_to_rad(pitch)
		reach = f("barrel") * cos(pr) + f("pivot_ahead")
		height = f("barrel") * sin(pr) + f("pivot_height")
		spec["pitch_deg"] = -pitch
	spec["heading"] = h
	spec["type"] = int(params["projectile"])
	spec["position"] = v.position + shot_fwd * reach
	spec["z"] = height + v.z
	spec["flash"] = {"record": String(params["flash"]), "yaw": v.turret_deg,
			"offset": Vector3(reach * sin(deg_to_rad(v.turret_deg)), reach * cos(deg_to_rad(v.turret_deg)), height + v.z)}
