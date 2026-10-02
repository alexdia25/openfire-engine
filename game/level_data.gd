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
var vehicle_params: Dictionary = {}  ## the VHCL chunk / filename brackets: T, J, A, H = vehicles of each type the player has, M (document 73)
var levl_value: int = 0   ## the LEVL chunk, 0-8 (DAT_00442fc0): the level's difficulty number; with M unset it decides how many mines are scattered (document 75)
## The colour each side's art is drawn in (PORTING_PLAN.md 2.7.7): side 0 / 1 are the original's two players (tile variant
## 0 / 1, player index), and all game logic keys on the side; the colour is only what its vehicles, buildings, gates, flag
## and pad look like. Default the original pair; a level may set `side_colours` (the step-6 override file will), and
## RF_TEAM_COLOURS=red,blue overrides it for testing (terrain_view_3d.gd). Names are Pack.team_colours keys.
var side_colours: Array = ["tan", "green"]
var tile_seed: int = 0  ## sum of raw tile bytes -- seeds the per-tile decoration jitter (document 44)
var decorations: Array = []  ## [{x, y, coastal_id}] -- see Pack.get_decoration_parts()
## A map's own roster changes (PORTING_PLAN.md 2.7.3, step 6), from every layer's `level.override.json` in base-to-top
## order: id -> null (removed from the pack's default roster) or a Dictionary (a new entry, or fields merged into an
## existing one). {} means the map uses the pack's default roster (`Pack.vehicle_roster`) unchanged. Resolved against
## a pack by `Pack.roster_for(self)`; never resolved here, since loading a level does not require a pack yet.
var roster_override: Dictionary = {}
## The level's own front-end scenes (PORTING_PLAN.md 2.8, the "game flow" state machine; EDITOR_PLAN.md's level-flow
## panel writes this): `{"intro": "<scene id>", "outro": "<scene id>", "mid_level": [{"trigger": "<name>", "scene":
## "<scene id>"}]}`, every key optional. A scene id names a file in the pack's `scenes/<id>.json` (`StoryScene`'s
## format: a placeholder for the eventual visual-novel presentation). Missing = that step of the flow is skipped
## entirely, not shown empty -- this is the normal case (none of Return Fire's own levels define any of these).
## `mid_level`'s triggers are not wired to any real gameplay signal yet; the field is carried and validated, ready
## for whichever trigger kinds a level actually needs once one does. Overridable the same way as `roster_override`.
var flow: Dictionary = {}
var _decoration_lookup: Dictionary = {}
var _jitter: Array[Vector2] = []


## A level's display name without parsing the whole file, for lists of many levels: "name" is looked for in the
## file's first bytes, where a converter that writes keys in order puts it. Only if it isn't there is the whole file
## parsed after all -- a level.json written with sorted keys (PackWriter's, so anything the mod tool saves) has its
## long "decorations" list first. "" if the level has no name.
static func peek_name(level_dir: String) -> String:
	var path := level_dir.path_join("level.json")
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var m := RegEx.create_from_string("\"name\"\\s*:\\s*\"([^\"]*)\"").search(f.get_buffer(600).get_string_from_utf8())
	if m != null:
		return m.get_string(1)
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return String(doc["name"]) if doc is Dictionary and doc.get("name") is String else ""


## How many players a level is made for (the original's World Info "No. of Players"): the number of its spawn points, or its own "players" when it names one. Read
## from the file's text, not parsed, so a list of many levels stays quick. 1 if the level has no spawn points.
static func peek_players(level_dir: String) -> int:
	var text := FileAccess.get_file_as_string(level_dir.path_join("level.json"))
	var own := RegEx.create_from_string("\"players\"\\s*:\\s*(\\d+)").search(text)
	if own != null:
		return int(own.get_string(1))
	var sp := RegEx.create_from_string("\"spawn_points\"\\s*:\\s*\\[([^\\]]*)\\]").search(text)
	if sp == null:
		return 1
	return maxi(1, sp.get_string(1).count("{"))


## `override_paths`: every layer's `level.override.json` for this level, base to top (`Pack.level_override_paths()`),
## applied here in that order so a later mod's edit wins. An override may set `side_colours` (replacing the level's
## own) and `roster` (per-id: null removes, an object adds or merges) -- see `roster_override` above. The generated
## `level.json` this loads is never itself edited; an override is a separate file next to it (2.7.3, 2.7.9).
func load_from(level_dir: String, override_paths: Array[String] = []) -> bool:
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

	roster_override = {}
	flow = doc.get("flow", {}).duplicate() if doc.get("flow") is Dictionary else {}
	for override_path in override_paths:
		var od: Variant = JSON.parse_string(FileAccess.get_file_as_string(override_path))
		if not (od is Dictionary):
			continue
		if od.get("side_colours") is Array:
			doc["side_colours"] = od["side_colours"]
		for id in od.get("roster", {}):
			roster_override[id] = od["roster"][id]
		if od.get("flow") is Dictionary:
			flow.merge(od["flow"], true)

	width = int(doc.get("width", 0))
	height = int(doc.get("height", 0))
	level_name = str(doc.get("name", ""))
	spawn_points = doc.get("spawn_points", [])
	candidate_pools = doc.get("candidate_pools", {})
	decorations = doc.get("decorations", [])
	tile_seed = int(doc.get("tile_seed", 0))
	vehicle_params = doc.get("vehicle_params", {})
	if doc.get("side_colours") is Array:
		side_colours = doc["side_colours"]
	levl_value = int(doc.get("levl_value", 0)) if doc.get("levl_value", null) != null else 0

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


## The art colour of a side (0 / 1 ...), or "" for a side without one.
func side_colour(side: int) -> String:
	return String(side_colours[side]) if side >= 0 and side < side_colours.size() else ""


## The team variant (0 tan, 1 green ...) recorded for this tile's decoration (tile word bits 14-15).
func get_variant(x: int, y: int) -> int:
	var i := _decoration_index(x, y)
	return int(decorations[i].get("variant", 0)) if i >= 0 else 0


func set_variant(x: int, y: int, variant: int) -> void:
	var i := _decoration_index(x, y)
	if i >= 0:
		decorations[i]["variant"] = variant


func _decoration_index(x: int, y: int) -> int:
	if _decoration_lookup.size() != decorations.size():
		_decoration_lookup.clear()
		for i in decorations.size():
			_decoration_lookup[Vector2i(int(decorations[i].get("x", -1)), int(decorations[i].get("y", -1)))] = i
	return int(_decoration_lookup.get(Vector2i(x, y), -1))


## The per-tile decoration jitter of document 44 (FUN_00436540 / FUN_004365c0), in world units: a 16x16
## table of rand(25) - 12 pairs built from the MSVC LCG seeded with `tile_seed`, indexed by
## (tile_y & 15, tile_x & 15). The collision shapes of a jittered tile move with it (FUN_0042bb10 calls
## the same callback), so both the decorations and the collision code read it here.
func jitter_at(x: int, y: int) -> Vector2:
	if _jitter.is_empty():
		var state := tile_seed & 0xFFFFFFFF
		for i in 256:
			var vals := []
			for n in [25, 25, 11, 256]:
				state = (state * 214013 + 2531011) & 0xFFFFFFFF
				vals.append((((state >> 16) & 0x7FFF) * 2 * n) >> 16)
			_jitter.append(Vector2(vals[0] - 12, vals[1] - 12))
	return _jitter[((y & 15) * 16) + (x & 15)]
