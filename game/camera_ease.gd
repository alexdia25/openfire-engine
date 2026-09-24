class_name CameraEase
extends RefCounted
## The original's camera easing, one call per value per tick (document 90): FUN_00417420(cam, &value, target, &rate, triple). A "triple" is {accel, brake, max_rate}
## (dwords at the camera rig's +0x3c / +0x48 / +0x54, copied from the template at 0x448e90). All numbers are in the value's own units per tick (dt = 1).
##   - integer parts equal (`(value ^ target) & 0xffff0000 == 0`): the rate is cleared and the value is left alone;
##   - the top speed is `max_rate`, but never more than sqrt(distance * brake) (FUN_00410e20 is a fixed-point sqrt), and when that cap bites the slew limit is `brake`
##     instead of `accel`, so it slows down as it nears the target;
##   - `rate` slews toward +-speed by at most the slew limit (FUN_0042cdd0), the value moves by `rate`, and never passes the target.

var value := 0.0
var target := 0.0
var rate := 0.0
var accel := 0.0
var brake := 0.0
var max_rate := 0.0


func _init(start: float, goal: float, triple: Array) -> void:
	value = start
	target = goal
	accel = float(triple[0])
	brake = float(triple[1])
	max_rate = float(triple[2])


## One tick. Returns true once the integer parts match (the original's early-out).
func step() -> bool:
	if floorf(value) == floorf(target):
		rate = 0.0
		return true
	var dist := absf(target - value)
	var sgn := -1.0 if target < value else 1.0
	var slew := accel
	var speed := max_rate
	if speed != 0.0:
		var cap := sqrt(dist * brake)
		if speed > cap:
			speed = cap
			slew = brake
	rate = move_toward(rate, sgn * speed, slew)
	value += rate
	if (sgn < 0.0 and value < target) or (sgn > 0.0 and value > target):
		value = target
	return false
