class_name Projectile
extends Node2D
## Phase 4 step 4 (first pass): a fired projectile, playable but not yet authentic --
## same honesty flag as vehicle.gd's movement. RFIRE.BIN's real weapon damage/rate-of-
## fire/projectile-speed constants haven't been traced (Phase 3 backlog: "Extract
## gameplay constants" -> weapons), so SPEED and LIFETIME_SEC below are reasonable
## placeholders, not reverse-engineered ones.
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

const SPEED := 420.0
const LIFETIME_SEC := 1.2
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
