class_name TargetPool
extends RefCounted
## Phase 4 step 5 (first pass): reimplements the exact candidate-pool mechanism traced in
## PORTING_PLAN.md section 1.5 from RFIRE.BIN -- this is the real, fully-traced mechanism,
## not a guess:
##
## - A level file defines a *pool* of candidate destructible-target positions (the
##   `0xB4`/`0xDC` tile values, section 1.5's "pool A"/"pool B").
## - At match start, exactly one candidate is picked at random as the pool's active target
##   (RFIRE.BIN's `FUN_00404360(count)` / `_DAT_0045ae50`/`_DAT_0045ae54`).
## - The pool has a replacement budget of `count >> 1` (half its candidate count, rounded
##   down -- `_DAT_0048ca20`/`_DAT_0048ca24`).
## - When the active target is destroyed, the budget decrements. If any budget remains and
##   any other candidate is still intact, one is picked at random as the new active target
##   (`FUN_00432600`). Once the budget or the intact candidates run out, the pool goes
##   silent for the rest of the match -- no more targets ever spawn from it.
##
## This is why the destructible target/base locations differ between plays of the same
## level: the file fixes the *candidate set*, the engine commits to a rotating subset
## at runtime.

var candidates: Array = []  ## Vector2i tile positions, from level.candidate_pools
var intact: Array = []      ## parallel bool array -- false once that candidate is destroyed
var budget: int = 0         ## replacement budget remaining, starts at candidates.size() >> 1
var active_index: int = -1  ## index into candidates/intact of the currently live target, -1 = none


func _init(tile_positions: Array) -> void:
	candidates = tile_positions.duplicate()
	intact.resize(candidates.size())
	intact.fill(true)
	budget = candidates.size() >> 1
	if not candidates.is_empty():
		active_index = randi() % candidates.size()


## Vector2i tile position of the currently live target, or null if the pool has none
## (empty pool, or gone silent after exhausting its budget/candidates).
func get_active_position() -> Variant:
	if active_index < 0:
		return null
	return candidates[active_index]


## Call when the currently-active target is destroyed. Marks it no longer intact,
## decrements the budget, and -- if budget and another intact candidate both remain --
## activates one of them at random, matching FUN_00432600. Returns true if a new target
## was activated, false if the pool has gone silent (temporarily, if it just has no
## active target right now with budget/candidates left, permanently if not).
func destroy_active() -> bool:
	if active_index < 0:
		return false
	intact[active_index] = false
	active_index = -1
	budget -= 1
	if budget <= 0:
		return false
	var remaining: Array = []
	for i in intact.size():
		if intact[i]:
			remaining.append(i)
	if remaining.is_empty():
		return false
	active_index = remaining[randi() % remaining.size()]
	return true
