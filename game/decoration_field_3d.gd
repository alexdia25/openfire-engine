class_name DecorationField3D
extends Node3D
## Gives every level decoration (document 35/36, docs/process/ -- bushes, coral, dock posts,
## palm clusters, ...) a real 3D presence instead of document 36's original choice: baking them
## flat into game/terrain_tile_renderer.gd's one-shot ground-plane texture, at the same Y as the
## dirt underneath. That was defensible when it shipped -- decorations never move, so a live
## Node3D per part seemed like paying vehicle-grade cost for zero vehicle-grade benefit -- but
## the user caught the real problem: baked-flush-with-the-ground content can never actually look
## like it stands up, no matter how correctly the real tilted Camera3D foreshortens it, because
## it never leaves the ground plane's own Y. A tank driving past a "tree" that's really a flat
## mark on the dirt shows no parallax and no occlusion -- it reads as a shadow, not a plant.
##
## This is a straight extraction, same spirit as document 29/33's own "pull shared logic into
## one place, don't duplicate it" choice: the per-tile decoration-part lookup and the palm-
## canopy/trunk-pairing logic below are unchanged from terrain_tile_renderer.gd's own
## `_draw_decorations()`, just re-targeted at real Node3D children built once instead of 2D
## draw calls baked into a texture.
##
## Real per-part 3D corner data was never decoded for decorations (document 35's own gap,
## unchanged) -- only which cels compose a given coastal id, not their real relative offsets.
## So, same as before: a multi-part decoration spreads its parts evenly around a small fixed-
## radius ring instead of the original's real (unknown) layout, and canopy height is a placeholder
## (TRUNK_HEIGHT_PX below), not a traced value. What's fixed here is the axis that was flatly
## wrong -- real elevation now exists at all -- not claiming the exact height is authentic.
##
## Two real shapes, not one, matching what direct atlas inspection of the two cel families
## actually shows (not assumed): CANOPY_SPRITE_IDS' art (e.g. frond_blue, cel 135) is drawn as
## if seen from directly above -- a radial cluster of fronds -- so it lies flat like the ground
## plane, elevated to canopy height. TRUNK_SPRITE_ID's art (cel 138, two crossed palm trunks) is
## drawn side-on, so it stands as a plain vertical card from ground level up to that same
## height. Every other decoration part (rocks, bushes, coral, debris, ...) keeps document 36's
## original top-down framing and simply lies flat at ground level, a real Node3D quad instead of
## baked texture, with no invented height.
const CANOPY_SPRITE_IDS := {
	"decoration.foliage.frond_blue": true,
	"decoration.foliage.bush_green.07": true,
	"decoration.foliage.bush_green.08": true,
	"decoration.foliage.bush_green.09": true,
	"decoration.foliage.bush_green.10": true,
	"decoration.foliage.bush_green.11": true,
}
const TRUNK_SPRITE_ID := "decoration.tree.palm"

## Placeholder, flagged honestly (see file header) -- how high off the ground a canopy-only
## decoration's trunk (and therefore its canopy) stands. Tall enough to clearly separate from
## ground-level decorations at this project's tile_size_px (32) without a real traced value.
const TRUNK_HEIGHT_PX := 40.0

## So a ground-level decoration's quad doesn't z-fight with the terrain plane it shares a Y
## with -- same reasoning as vehicle_box_3d.gd's GROUND_CLEARANCE_PX.
const GROUND_CLEARANCE_PX := 1.0

var pack: Pack
var level: LevelData


func setup(shared_pack: Pack, shared_level: LevelData) -> void:
	pack = shared_pack
	level = shared_level
	_build()


func _build() -> void:
	var tile := pack.tile_size_px
	for entry in level.decorations:
		var parts: Array = pack.get_decoration_parts(int(entry.get("coastal_id", 0)))
		if parts.is_empty():
			continue
		var centre_x := (float(entry.get("x", 0)) + 0.5) * tile
		var centre_z := (float(entry.get("y", 0)) + 0.5) * tile

		# See this file's header (CANOPY_SPRITE_IDS) -- give a floating frond cluster a trunk to
		# stand on, exactly document 36's original composition rule, just rendered as real
		# elevated 3D geometry instead of two flat marks at the same ground-level Y.
		var is_canopy_only := true
		for part in parts:
			if not CANOPY_SPRITE_IDS.has(part.get("sprite_id", "")):
				is_canopy_only = false
				break
		if is_canopy_only:
			_add_vertical(TRUNK_SPRITE_ID, centre_x, centre_z)

		var height := TRUNK_HEIGHT_PX if is_canopy_only else GROUND_CLEARANCE_PX
		var ring_radius: float = 0.0 if parts.size() <= 1 else tile * 0.22
		for i in parts.size():
			var sprite_id: String = parts[i].get("sprite_id", "")
			var angle := TAU * float(i) / float(parts.size())
			var px := centre_x + cos(angle) * ring_radius
			var pz := centre_z + sin(angle) * ring_radius
			_add_flat(sprite_id, px, height, pz)


## A horizontal card lying in the XZ plane (like the ground plane itself), the same
## GROUND_DECAL orientation vehicle_billboard_3d.gd already uses -- tipped -90 degrees on X so
## Godot's default vertical, -Z-facing Sprite3D plane lies flat instead. Real 3D height (`y`)
## is what actually fixes the bug this file exists for -- everything else about this call is
## document 36's original technique.
func _add_flat(sprite_id: String, x: float, y: float, z: float) -> void:
	var sprite := _make_sprite(sprite_id)
	if sprite == null:
		return
	sprite.rotation_degrees.x = -90.0
	sprite.position = Vector3(x, y, z)


## A plain vertical card, standing from ground level up to TRUNK_HEIGHT_PX -- Sprite3D's
## un-rotated default orientation already stands vertical, so no rotation is needed (and,
## unlike vehicles, nothing here ever needs to billboard to face the camera: document 27/28
## already confirmed this game's camera never yaws, only translates, so a plain fixed-
## orientation card is exactly as correct as a billboard and cheaper -- the same reasoning
## vehicle_billboard_3d.gd's GROUND_DECAL already relies on).
func _add_vertical(sprite_id: String, x: float, z: float) -> void:
	var sprite := _make_sprite(sprite_id)
	if sprite == null:
		return
	sprite.position = Vector3(x, TRUNK_HEIGHT_PX * 0.5, z)


## Shared Sprite3D setup (texture/region lookup + the pixel-art rendering flags every other
## real 3D presentation in this project already uses -- vehicle_billboard_3d.gd,
## vehicle_box_3d.gd) for the two placement helpers above. Returns null (nothing added) if the
## sprite id doesn't resolve, matching Pack.get_decoration_parts()'s own "draw nothing" contract
## for unknown content.
func _make_sprite(sprite_id: String) -> Sprite3D:
	var s := pack.get_sprite(sprite_id)
	if s.is_empty():
		return null
	var tex := pack.get_texture(int(s.get("page", 0)))
	if tex == null:
		return null

	var sprite := Sprite3D.new()
	sprite.shaded = false  # pre-rendered flat art, not something to relight
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST  # hard-edged pixel art
	sprite.pixel_size = 1.0  # 1 texture pixel = 1 world unit, matching every other scene node
	sprite.texture = tex
	sprite.region_enabled = true
	sprite.region_rect = Rect2(s.get("x", 0), s.get("y", 0), s.get("w", 0), s.get("h", 0))
	add_child(sprite)
	return sprite
