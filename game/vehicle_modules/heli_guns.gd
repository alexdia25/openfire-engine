extends VehicleModule
## The Heli's weapons: FUN_0040e600 and FUN_0040e7a0 (document 63). Two selectable slots (the third button toggles, with a
## click): each fires its projectile every `cooldown_ticks[slot]`. Either fire button fires the selected slot from
## alternating left and right mounts at (+-mount_x, mount_ahead, 0). The first button is the downward one: slot 0 fires
## `down_pitch_steps` down, toed in by `toe_steps`, slot 1 level; the second button fires level with no toe-in. The
## launcher's forward speed is added to the shot's. Slot 1's shot has a launch flash `bomb_flash` at (x, flash_ahead, 0).
## Runs itself (SELF_DRIVEN): reads the fire buttons and keeps its own cooldowns.

const SCHEMA := {
	"slot": "weapon", "doc": "Two selectable weapons from alternating side mounts (FUN_0040e600 / FUN_0040e7a0)",
	"params": {
		"projectiles": {"type": "int[]", "default": [7, 6], "provenance": "traced:63", "doc": "Per slot: gun, bomb"},
		"cooldown_ticks": {"type": "float[]", "unit": "ticks", "default": [15.0, 30.0], "provenance": "traced:63"},
		"mount_x": {"type": "float", "unit": "units", "default": 9.35, "provenance": "traced:63"},
		"mount_ahead": {"type": "float", "unit": "units", "default": 6.8, "provenance": "traced:63"},
		"toe_steps": {"type": "float", "unit": "steps", "default": 0.5, "provenance": "traced:63"},
		"down_pitch_steps": {"type": "float", "unit": "steps", "default": 7.0, "provenance": "traced:63"},
		"bomb_flash": {"type": "explosion", "default": "0x445168", "provenance": "traced:63"},
		"flash_ahead": {"type": "float", "unit": "units", "default": 2.55, "provenance": "traced:63"},
		"toggle_sound": {"type": "sound", "default": "HeliClick", "provenance": "traced:82 (0x44b970)"},
	},
	"channels": ["_heli_slot"],
}

const TICK_HZ := 62.5
const SELF_DRIVEN := true


func toggle(v: Vehicle) -> void:
	v._heli_slot = 1 - v._heli_slot
	v.sound_cue.emit(String(params["toggle_sound"]))   # FUN_0040e7a0: "toggles bit 28 and plays a sound"


func tick(v: Vehicle, delta: float) -> void:
	for i in 2:
		v._heli_ready[i] = maxf(v._heli_ready[i] - delta, 0.0)
	var slot := v._heli_slot
	if v._heli_ready[slot] > 0.0:
		return
	var down := v._debug_fire or Input.is_action_pressed("ui_accept")
	var level := v._wants_raised()
	if not (down or level):
		return
	v._heli_ready[slot] = float(params["cooldown_ticks"][slot]) / TICK_HZ
	if not v._spend_ammo(slot):
		return   # the empty click; the cooldown just set keeps it from repeating every frame
	var type := int(params["projectiles"][slot])
	var mx := f("mount_x")
	var mount := Vector2(-mx if v._heli_mount_left else mx, f("mount_ahead"))  # (x right, y ahead)
	var toe := 0.0
	var pitch := 0.0
	if down:
		toe = f("toe_steps") * 5.625 if v._heli_mount_left else -f("toe_steps") * 5.625
		pitch = f("down_pitch_steps") * 5.625 if slot == 0 else 0.0
	var h := v.heading_deg + toe
	var rad := deg_to_rad(h)
	var fwd := Vector2(cos(rad), sin(rad))
	var right := Vector2(-fwd.y, fwd.x)
	var spec := {"team": v.team, "colour": v.art_colour(), "heading": h, "type": type, "z": v.z,
			"position": v.position + fwd * mount.y + right * mount.x, "pitch_deg": pitch,
			"bonus": maxf(v.speed, 0.0) / TICK_HZ}
	if slot == 1:
		spec["flash"] = {"record": String(params["bomb_flash"]), "offset": Vector3(mount.x, f("flash_ahead"), v.z)}
	v._heli_mount_left = not v._heli_mount_left
	v.shot.emit(spec)
