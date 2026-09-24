class_name Projectile
extends Node2D
## Phase 4 step 4: a fired projectile. Speed, lifetime and damage are the ORIGINAL's Tank shell
## (projectile type 0 in the table at 0x4489a0, document 45): 3.0 units/tick, alive 80 ticks,
## 1.0 damage to a tile (FUN_00414dd0 -> FUN_0042e8c0). A tick is 16 ms (62.5 Hz).
##
## Visual is also a placeholder. No confirmed real "projectile in flight" cel has turned
## up in the asset registry yet -- packs/registry/asset_ids.json has mounted missile-pod/
## rack *props* (static vehicle decoration, see prop.missile_pod.*/prop.missile_rack.*),
## but nothing tagged as an in-flight shot. Rather than guess a sprite id that hasn't
## been verified, this reuses terrain_view.gd's existing approach for spawn/candidate
## markers: a small flat-coloured primitive, honestly a placeholder.
##
## Travels in a straight line at a fixed heading -- no gravity, no arc, no collision with
## terrain or vehicles yet (destructible targets/buildings are Phase 4 step 5, not this
## one). Just proves fire input -> a moving, visible, self-expiring projectile.

const TICK_HZ := 62.5
## Defaults are the Tank shell (type 0); `configure()` loads any type from the pack's projectile table.
var type_id := 0
var speed := 3.0 * TICK_HZ           ## 0x30000/65536 units/tick = 187.5 px/s
var lifetime_sec := 80.0 / TICK_HZ   ## 0x50 ticks = 1.28 s (range 240 px = 7.5 tiles)
var damage: float = 1.0                ## 0x10000 = 1.0 (projectile type 0)
var shooter: Node2D = null             ## never hits its own shooter (FUN_00414e60)
var prev_checked: Vector2 = Vector2.ZERO  ## where the collision test last saw it: the swept segment starts here
## Height above the ground (original units). Every shot the port fires leaves the muzzle level (the pitch index of
## the Tank's and the MSV's level fire is 0) and flies at that height (document 52).
var z := 7.0
const SHELL_Z := 7.0


## The Jeep missile (object class 0x12, FUN_00415730; document 61) is not a straight shot: it is lobbed to a target
## point. Per tick t (whole ticks since launch) it is at start + dir * (v * 0.38269 * t) horizontally and at height
## z0 + (0.92387 * v - 0.024994 * t) * t, where v = sqrt(3276 * D / 46340) for a target D whole units away, so it
## lands (z < 0) on the target. `dir` is the direction to the target rounded down to one of 64 headings. Its damage is
## 1.5 (0x18000) to whatever it touches on the way; its shape is the shell's (layer 4, mask 0x43, z +-1.5).
var lob := false
var lob_start := Vector2.ZERO
var lob_dir := Vector2.RIGHT
var lob_v := 0.0
var lob_z0 := 5.0
var lob_t := 0.0                 ## ticks since launch (fractional here)
var spin_deg := 0.0              ## obj+0x4c grows by 0x8888 of 0x400000 per tick = 3 degrees
const LOB_COS := 60547.0 / 65536.0    ## 0xec83
const LOB_SIN := 25079.0 / 65536.0    ## 0x61f7
const LOB_GRAVITY := 1638.0 / 65536.0 ## 0x666
const LOB_DAMAGE := 1.5


func start_lob(start: Vector2, z0: float, target: Vector2) -> void:
	lob = true
	lob_start = start
	lob_z0 = z0
	damage = LOB_DAMAGE
	var dx := floorf(target.x) - floorf(start.x)
	var dy := floorf(target.y) - floorf(start.y)
	var d := floorf(sqrt(dx * dx + dy * dy))
	lob_v = sqrt(3276.0 * d / 46340.0)
	# FUN_00410b80 gives atan2 of the start-minus-target vector; (>> 2) - 0x100000 and the 64-step table index
	# make it the heading toward the target, rounded DOWN to a multiple of 5.625 degrees.
	var phi := rad_to_deg(atan2(target.y - start.y, target.x - start.x))
	var idx := floori(fposmod(phi + 90.0, 360.0) / 5.625)
	var hq := idx * 5.625 - 90.0
	lob_dir = Vector2(cos(deg_to_rad(hq)), sin(deg_to_rad(hq)))
	position = start
	prev_checked = start
	z = z0


## Which of the 12 spin frames to draw (obj+0x70 grows 0x2aaa per tick and wraps at 12.0).
func lob_frame() -> int:
	return int(fmod(lob_t * (10922.0 / 65536.0), 12.0))


## Pitched shots (the Heli's guns and bombs, document 63; FUN_00414b10). The velocity is (0, -speed, 0) turned by the
## pitch (positive = downward) and then by the heading, so it moves speed * cos(pitch) along the heading and falls at
## speed * sin(pitch). A type without the ballistic flag (bit 1 of its flags) keeps its pitch (rounded down to a
## 5.625-degree step) and shrinks it toward 0 by the type's rate a tick; a ballistic type's pitch GROWS by the rate a
## tick, bending the shot down in an arc. A shot that reaches z < 0 has hit the ground.
const Z_CEILING := 55.0
var vertical := false
var pitch_steps := 0.0
var pitch_rate := 0.0            ## steps per tick
var ballistic := false
var impact_table := "0x448970"


func start_pitched(pitch_deg: float, bonus_units_per_tick: float) -> void:
	vertical = true
	pitch_steps = pitch_deg / 5.625
	speed += bonus_units_per_tick * TICK_HZ  # FUN_004155a0: the launcher's forward speed is added


func configure(pack: Pack, type: int) -> void:
	type_id = type
	if type < pack.projectile_types.size():
		var t: Dictionary = pack.projectile_types[type]
		speed = float(t["speed_units_per_tick"]) * TICK_HZ
		damage = float(t["damage"])
		lifetime_sec = float(t["lifetime_ticks"]) / TICK_HZ
		ballistic = (int(t["flags"]) & 2) != 0
		pitch_rate = float(t["pitch_rate_raw"]) / 65536.0
		impact_table = String(t["impact_table"])

var heading_deg: float = 0.0
var team: String = "tan"
var colour := ""   ## art colour of the shooter's side (PORTING_PLAN.md 2.7.7); "" = the team's own


func art_colour() -> String:
	return colour if colour != "" else team
var _age_sec: float = 0.0


func _process(delta: float) -> void:
	if lob:
		lob_t += delta * TICK_HZ
		position = lob_start + lob_dir * (lob_v * LOB_SIN * lob_t)
		z = lob_z0 + (LOB_COS * lob_v - LOB_GRAVITY * lob_t) * lob_t
		spin_deg = fmod(spin_deg + 3.0 * delta * TICK_HZ, 360.0)
		if lob_t > 1000.0:
			queue_free()
		return
	var rad := deg_to_rad(heading_deg)
	if vertical:
		var ticks := delta * TICK_HZ
		if ballistic:
			pitch_steps += pitch_rate * ticks
		else:
			pitch_steps = move_toward(pitch_steps, 0.0, pitch_rate * ticks)
		var eff := pitch_steps if ballistic else floorf(pitch_steps)
		var p_rad := deg_to_rad(eff * 5.625)
		position += Vector2(cos(rad), sin(rad)) * speed * cos(p_rad) * delta
		z -= speed * sin(p_rad) * delta
		if z > Z_CEILING:
			# 0x370000: nothing rises above 55; a shot that hits the ceiling also has its pitch pulled toward 0 at its rate
			z = Z_CEILING
			if not ballistic:
				pitch_steps = move_toward(pitch_steps, 0.0, pitch_rate * ticks)
	else:
		position += Vector2(cos(rad), sin(rad)) * speed * delta
	_age_sec += delta
	if _age_sec >= lifetime_sec:
		queue_free()
		return
