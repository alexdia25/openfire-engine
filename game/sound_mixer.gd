class_name SoundMixer
extends RefCounted
## The original sound engine's mixing maths, traced from RFIRE.BIN (issue #22, document 117). Pure functions; SoundManager drives them.
##
##  - A voice with a source object has two gains, one per ear. Each is the linear falloff of the distance from that ear to the source
##    (FUN_004082b0 / FUN_00408450): 1.0 within 40 units, 0 at 424, `(424 - d) / 384` between, d the 3D distance in whole units
##    (FUN_0042cd30: each coordinate difference shifted down to whole units, squared, summed, FUN_00410df0 = sqrt). The ears are the listener
##    plus and minus 10 units in x (DAT_00442fd0 = 0xa0000: the commands 6 and 7 in FUN_00409420) and the listener is the view's camera
##    position. The per-side weight (cmd 8, 1.0 in play) multiplies each gain below 1.0 and a weight of 0 mutes it. A voice without a
##    source has both gains 1.0 (descriptor flag 0x40: both 0; 0x2: right 0; 0x4: left 0).
##  - FUN_00407ec0 turns the voices, taken in priority order (FUN_00407b60), into channel levels: the gain times the descriptor's level,
##    clipped to what is left of the side's budget of 0x7fff (DAT_0048ca3c / DAT_0048cacc, set by FUN_004089a0), which the voice then uses up.
##  - The buffer volume is min(max(left, right) / 3 - 2200, 0) hundredths of a dB and the pan (right - left) * 10000 / max(left, right),
##    clamped to +-10000 hundredths of a dB. DirectSound pan attenuates the OPPOSITE side by its size, so a pan of -5000 mutes the right
##    side by 50 dB. (FUN_00423af0 type 3 negates its argument and FUN_00407ec0 negates it first, so the direction is the physical one.)

const FULL_WITHIN := 40.0       ## 0x28: 0x1a8 - d >= 0x180
const SILENT_AT := 424.0        ## 0x1a8
const SPAN := 384.0             ## 0x180
const EAR_OFFSET := 10.0        ## DAT_00442fd0 = 0xa0000
const BUDGET := 32767.0         ## 0x7fff a side
const DB_FLOOR := -100.0        ## DirectSound's limit, -10000 hundredths


## FUN_0042cd30 / FUN_00410df0: the distance in whole units (floor of the square root of the sum of the squared whole-unit differences).
static func distance(a: Vector3, b: Vector3) -> float:
	var dx := floorf(a.x) - floorf(b.x)
	var dy := floorf(a.y) - floorf(b.y)
	var dz := floorf(a.z) - floorf(b.z)
	return floorf(sqrt(dx * dx + dy * dy + dz * dz))


## One ear's gain (0..1) for a source `d` whole units away, times the side weight (applied only below 1.0, and 0 mutes).
static func falloff(d: float, weight := 1.0) -> float:
	if weight <= 0.0:
		return 0.0
	var avail := SILENT_AT - d
	var g := 1.0
	if avail <= SPAN:
		if avail < 1.0:
			return 0.0
		g = avail / SPAN
	if weight < 1.0:
		g *= weight
	return g


## (left gain, right gain) for a source at `src` heard from `listener`.
static func ear_gains(src: Vector3, listener: Vector3, weight := 1.0) -> Vector2:
	var l := listener + Vector3(-EAR_OFFSET, 0.0, 0.0)
	var r := listener + Vector3(EAR_OFFSET, 0.0, 0.0)
	return Vector2(falloff(distance(src, l), weight), falloff(distance(src, r), weight))


## Gains of a voice with no source object, from its descriptor flags (FUN_004082b0's first branch).
static func flat_gains(flags: int) -> Vector2:
	if (flags & 0x40) != 0:
		return Vector2.ZERO
	var g := Vector2.ONE
	if (flags & 2) != 0:
		g.y = 0.0
	if (flags & 4) != 0:
		g.x = 0.0
	return g


## FUN_00407ec0's first half. `voices` are in priority order, each a Dictionary with "gains" (Vector2) and "level" (the descriptor's level);
## writes "channel" (Vector2, level units) into each: the gain times the level, no more than is left of the side's budget.
static func allocate(voices: Array, budget := BUDGET) -> void:
	var left := budget
	var right := budget
	for v in voices:
		var g: Vector2 = v["gains"]
		var lv := float(v["level"])
		var cl := minf(floorf(g.x * lv), left)
		var cr := minf(floorf(g.y * lv), right)
		v["channel"] = Vector2(cl, cr)
		left -= cl
		right -= cr


## FUN_00407ec0's second half: the buffer's volume (dB, at most 0) and pan (hundredths of a dB, -10000..10000, positive = right) for a channel.
static func volume_db(channel: Vector2) -> float:
	var m := maxf(channel.x, channel.y)
	if m <= 0.0:
		return DB_FLOOR
	return maxf(minf(m / 3.0 - 2200.0, 0.0), -10000.0) / 100.0


static func pan_hundredths(channel: Vector2) -> float:
	var m := maxf(channel.x, channel.y)
	if m <= 0.0 or channel.x == channel.y:
		return 0.0
	return clampf((channel.y - channel.x) * 10000.0 / m, -10000.0, 10000.0)


## The linear gains the two output sides really get: the louder side at the buffer volume, the other attenuated by |pan| / 100 dB more.
static func output_gains(channel: Vector2) -> Vector2:
	var near := 0.0 if volume_db(channel) <= DB_FLOOR else db_to_linear(volume_db(channel))
	var pan := pan_hundredths(channel)
	var far := near * db_to_linear(-absf(pan) / 100.0)
	return Vector2(near, far) if pan <= 0.0 else Vector2(far, near)


static func db_to_linear(db: float) -> float:
	return pow(10.0, db / 20.0)


## Godot's AudioEffectPanner is linear: left = volume * (1 - pan), right = volume * (1 + pan) (measured, document 117). So any pair of
## output gains is a bus pan plus a player volume: returns {volume_db, pan}.
static func panner_for(gains: Vector2) -> Dictionary:
	var s := gains.x + gains.y
	if s <= 0.0:
		return {"volume_db": DB_FLOOR, "pan": 0.0}
	return {"volume_db": 20.0 * log(s * 0.5) / log(10.0), "pan": (gains.y - gains.x) / s}
