class_name Mine
extends Node2D
## The MSV's mine (object class 10, descriptor 0x454200, class table 0x4430c8; document 60). Logic only: the view
## is game/mine_view_3d.gd. TRACED:
##  - Age counter `+0x60` starts at 5.0 and grows by 8738/65536 = 0.1333 per tick (FUN_00409cd0). At 26.0 (about
##    158 ticks, 2.5 s) the update swaps the object's descriptor (`+0x3c`) for 0x4542c8, which HAS a collision-shape
##    chain, and sets the drawn variant to 1. The mine's normal descriptor 0x454200 has an empty shape chain (`+8` =
##    0), and an object without shapes is never tested, so **the mine is inert for those 158 ticks and armed after**.
##  - Blink: while unarmed a counter `+0x5c` counts ticks and wraps at 30; the drawn variant is 2 while whole(age) >
##    counter, else 0, and a beep (sound 0x44b580) plays each time it switches to 2. So the light is on for 5 of every
##    30 ticks at first and 25 of 30 near the end: a fuse that speeds up. Armed, it shows variant 1 steadily.
##  - Armed collision shapes (chain 0x454288 -> 0x454248), both z -50..0.1, layer 1: a 12 x 12 box (mask 6: vehicles
##    and shells) and a 32 x 32 box (mask 2: vehicles). A vehicle that moves while touching the big box sets it off
##    (FUN_00409dd0); a shell or explosion that hits it with damage above 1.5 does too (FUN_00409e00).
##  - Detonating spawns explosion record 0x445058 (FUN_00409d80), the one explosion with a damage box.
## The art is cel 1081 + variant (an 8 x 8 "ember" sprite) drawn as a 12 x 12 quad at z 1.

const TICK_HZ := 62.5
const AGE_START := 5.0
const AGE_PER_TICK := 8738.0 / 65536.0
const AGE_EXPIRE := 26.0
const BLINK_PERIOD := 30
const TRIGGER_BOX := [-16.0, -16.0, 16.0, 16.0]  ## shape 0x454248, mask 2
const SHELL_BOX := [-6.0, -6.0, 6.0, 6.0]        ## shape 0x454288, mask 6
const Z_LO := -50.0
const Z_HI := 0.1
const HIT_DAMAGE_MIN := 1.5                      ## FUN_00409e00: damage above 0x18000

var dropper: Vehicle = null   ## informational; the original has no owner rule (the arming delay makes one unnecessary)

var age := AGE_START
var variant := 0       ## 0 / 2 while the fuse blinks, 1 once armed
var armed := false      ## the 158-tick fuse has run out: shapes are in place
var _counter := 0.0
var _ticks_seen := 0.0

signal beep


## Advances by `ticks` original ticks (may be fractional here; the original steps whole ticks).
func advance(ticks: float) -> void:
	if armed:
		return
	age += AGE_PER_TICK * ticks
	if age >= AGE_EXPIRE:
		armed = true
		variant = 1
		return
	_counter = fmod(_counter + ticks, float(BLINK_PERIOD))
	var lit := int(floor(age)) > int(floor(_counter))
	var v := 2 if lit else 0
	if v != variant:
		if v == 2:
			beep.emit()
		variant = v
