class_name FlagMarker
extends Node2D
## Phase 4 step 7 (first pass): makes PORTING_PLAN.md section 4 item 1's traced flag-spawn
## condition into real, visible behaviour. RFIRE.BIN's FUN_00432710 -- the exact function
## TargetPool already reimplements (document 22) -- reads DAT_00442b00 (a hidden debug-menu
## value confirmed to have NO write site anywhere in the binary except that debug menu itself,
## so it stays 0 in every real, non-debug game) and, when 0 (the only value real play ever
## sees), only takes its normal "replace the destroyed target" path if a replacement is
## actually available. When it isn't -- budget exhausted, or no intact candidate left --
## the real function falls through to spawn a dedicated, single-cross-reference object
## instead (`FUN_0042c290(0x44e3c0, ...)`). That's exactly the case `TargetPool.destroy_active()`
## already returns `false` for. This node is that fallthrough made visible: spawned once, when
## a pool goes silent, using the real, confirmed `marker.capture_flag.<team>` art (document 24)
## instead of a placeholder shape.
##
## What this deliberately is NOT: nothing carries it, no vehicle can pick it up, there's no
## "return to base" check, and no win/lose declaration reads its existence. Section 4 item 1's
## real object (`FUN_00432920`) also homes toward something every frame -- this one doesn't
## move at all. All of that is still untraced; this is the spawn trigger, nothing past it.
##
## Team-colour choice per pool is UNCONFIRMED. Section 1.5 never established whether either
## physical pool (tile 0xB4 "pool A" vs 0xDC "pool B") belongs to a specific team, or whether
## pool membership and team are related at all -- this picks a fixed, arbitrary mapping
## (pool "a" -> red, anything else -> green) purely so two pools in the same level render
## visibly differently. Treat the colour as a placeholder, not a finding.

const FRAME_INTERVAL_SEC := 0.12  ## placeholder wave-animation speed, not traced from RFIRE.BIN

var pack: Pack
var _frames: Array[String] = []
var _frame_index: int = 0
var _timer: float = 0.0


func setup(shared_pack: Pack, flag_colour: String) -> void:
	pack = shared_pack
	var prefix := "marker.capture_flag.%s." % flag_colour
	for id in pack.sprites.keys():
		if id.begins_with(prefix):
			_frames.append(id)
	_frames.sort()


func _process(delta: float) -> void:
	if _frames.size() <= 1:
		return
	_timer += delta
	if _timer >= FRAME_INTERVAL_SEC:
		_timer -= FRAME_INTERVAL_SEC
		_frame_index = (_frame_index + 1) % _frames.size()
		queue_redraw()


func _draw() -> void:
	if pack == null or _frames.is_empty():
		return
	var sprite_id: String = _frames[_frame_index]
	var s := pack.get_sprite(sprite_id)
	if s.is_empty():
		return
	var tex := pack.get_texture(int(s.get("page", 0)))
	if tex == null:
		return
	var w: float = s.get("w", 0)
	var h: float = s.get("h", 0)
	var src := Rect2(s.get("x", 0), s.get("y", 0), w, h)
	draw_texture_rect_region(tex, Rect2(-w * 0.5, -h * 0.5, w, h), src)
