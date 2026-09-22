class_name Gate
extends RefCounted
## A team gate: the object that replaces a tile of coastal id 43 or 44 while a vehicle of the owning team is
## near it -- TRACED, document 56 (class 0x44e370: FUN_00432270 init, FUN_004322f0 update, FUN_00432460
## destroy, FUN_004324f0 hit, FUN_00432550 creation from the vehicle service code). It is two solid bars
## (z 0-16) 32 units either side of the tile centre along one axis (x for id 43, y for id 44) that slide
## apart by `open` (0..15 units) at 0.5 per tick when the vehicle that woke it is within the 64 x 64 region
## around the gate, and slide back when it has left and nothing stands in the way; once fully closed for
## more than 60 ticks the object is removed and the tile gets its decoration back.

const OPEN_MAX := 15.0
const SPEED_PER_TICK := 0.5
const REMOVE_AFTER_CLOSED_TICKS := 60.0
const TICK_HZ := 62.5

## FUN_004322f0 (document 56/82): "GateMove" (0x44b610) plays the tick the gate is fully open and decides to start
## closing again; "GateClose" (0x44b628) plays the first tick it finishes closing (open reaches 0). Neither address
## is called anywhere in this function on the *opening* side -- untraced, not invented.
signal sound_cue(id: String)

var tile: Vector2i
var coastal_id: int      ## the id the tile had (43 or 44), restored on removal
var variant: int         ## the tile's team variant (door panel colour and who may open it)
var data: Dictionary     ## Pack.gates[str(coastal_id)]
var centre: Vector2
var open := 0.0
var target := OPEN_MAX
var carrier: Vehicle = null
var _closed_ticks := 0.0
var finished := false


func setup(t: Vector2i, id: int, gate_data: Dictionary, tile_variant: int, tile_size: float, vehicle: Vehicle) -> void:
	tile = t
	coastal_id = id
	data = gate_data
	variant = tile_variant
	centre = (Vector2(t) + Vector2(0.5, 0.5)) * tile_size
	carrier = vehicle


## The two bars as [{origin: Vector2, box: Array}] at the given opening.
func bars(opening: float = open) -> Array:
	var out := []
	var axis: String = data["axis"]
	for i in 2:
		var sh: Dictionary = data["shapes"][i]
		var off := Vector2(sh["off"][0], sh["off"][1])
		var slide := (16.0 + opening) * (-1.0 if i == 0 else 1.0)
		if axis == "x":
			off.x = slide
		else:
			off.y = slide
		out.append({"origin": centre + off, "box": sh["box"]})
	return out


## FUN_004322f0. `others_block(bars)` says whether a vehicle stands where the bars would be.
func tick(delta: float, others_block: Callable) -> void:
	var ticks := delta * TICK_HZ
	var previous := open
	var closing := target < previous
	open = move_toward(open, target, SPEED_PER_TICK * ticks)
	if open == 0.0:
		if _closed_ticks == 0.0:
			sound_cue.emit("GateClose")
		_closed_ticks += ticks
		if _closed_ticks > REMOVE_AFTER_CLOSED_TICKS:
			finished = true
			return
	else:
		_closed_ticks = 0.0
	if open == OPEN_MAX:
		var region: Dictionary = data["region"]
		if carrier == null or not is_instance_valid(carrier) \
				or not Collision.polygon_hits_box(carrier.hit_polygon(), centre, region["box"]):
			target = 0.0
			sound_cue.emit("GateMove")
	if closing and others_block.call(bars(open)):
		target = OPEN_MAX
		open = previous
