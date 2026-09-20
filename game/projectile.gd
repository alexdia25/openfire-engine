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
const SPEED := 3.0 * TICK_HZ           ## 0x30000/65536 units/tick = 187.5 px/s
const LIFETIME_SEC := 80.0 / TICK_HZ   ## 0x50 ticks = 1.28 s (range 240 px = 7.5 tiles)
var damage: float = 1.0                ## 0x10000 = 1.0 (projectile type 0)
var shooter: Node2D = null             ## never hits its own shooter (FUN_00414e60)
const RADIUS_PX := 3.0

const TEAM_COLOURS := {
	"tan": Color(0.82, 0.71, 0.55),
	"green": Color(0.30, 0.55, 0.30),
}

var heading_deg: float = 0.0
var team: String = "tan"
var _age_sec: float = 0.0


func _process(delta: float) -> void:
	var rad := deg_to_rad(heading_deg)
	position += Vector2(cos(rad), sin(rad)) * SPEED * delta
	_age_sec += delta
	if _age_sec >= LIFETIME_SEC:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS_PX, TEAM_COLOURS.get(team, Color.WHITE))
