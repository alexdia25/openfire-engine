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
