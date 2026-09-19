class_name LevelData
extends RefCounted
## Loads one converted level (tools/convert_rfm.py output, copied into a pack's levels/
## folder by tools/build_pack.py) -- level.json for metadata/entities, art.bin for the
## resolved terrain art-id grid (PORTING_PLAN.md section 1.7: art id IS the ART.CAR cel
## index directly, no separate mapping table).

var level_name: String = ""
var width: int = 0
var height: int = 0
var art_grid: PackedByteArray = PackedByteArray()
var spawn_points: Array = []
var candidate_pools: Dictionary = {}
var tile_seed: int = 0  ## sum of raw tile bytes -- seeds the per-tile decoration jitter (document 44)
var decorations: Array = []  ## [{x, y, coastal_id}] -- see Pack.get_decoration_parts()


func load_from(level_dir: String) -> bool:
	var json_path := level_dir.path_join("level.json")
	var art_path := level_dir.path_join("art.bin")

	var jf := FileAccess.open(json_path, FileAccess.READ)
	if jf == null:
		push_error("LevelData.load_from: cannot open %s" % json_path)
		return false
	var doc: Variant = JSON.parse_string(jf.get_as_text())
	if not (doc is Dictionary):
		push_error("LevelData.load_from: malformed %s" % json_path)
		return false

	width = int(doc.get("width", 0))
	height = int(doc.get("height", 0))
	level_name = str(doc.get("name", ""))
	spawn_points = doc.get("spawn_points", [])
	candidate_pools = doc.get("candidate_pools", {})
	decorations = doc.get("decorations", [])
	tile_seed = int(doc.get("tile_seed", 0))

	var af := FileAccess.open(art_path, FileAccess.READ)
	if af == null:
		push_error("LevelData.load_from: cannot open %s" % art_path)
		return false
	art_grid = af.get_buffer(af.get_length())

	if art_grid.size() != width * height:
		push_error("LevelData.load_from: art.bin size %d != width*height %d for %s" %
			[art_grid.size(), width * height, level_name])
		return false
	return true


func get_art_id(x: int, y: int) -> int:
	return art_grid[y * width + x]


func set_art_id(x: int, y: int, art_id: int) -> void:
	art_grid[y * width + x] = art_id


## Coastal id of the decoration on this tile (0 if none) -- the same field a tile word's bits 7-13
## hold in the original (document 35).
func get_coastal_id(x: int, y: int) -> int:
	var i := _decoration_index(x, y)
	return int(decorations[i].get("coastal_id", 0)) if i >= 0 else 0


func set_coastal_id(x: int, y: int, coastal_id: int) -> void:
	var i := _decoration_index(x, y)
	if i >= 0:
		decorations[i]["coastal_id"] = coastal_id


func _decoration_index(x: int, y: int) -> int:
	for i in decorations.size():
		if int(decorations[i].get("x", -1)) == x and int(decorations[i].get("y", -1)) == y:
			return i
	return -1
