class_name Pack
extends RefCounted
## Loads a content pack (PORTING_PLAN.md section 2.4.2) from an arbitrary directory at
## runtime -- never via res://'s import pipeline (see packs/.gdignore). This is the only
## thing allowed to read pack files; nothing else in game/ should touch packs/ directly.

var pack_dir: String = ""   ## the top layer's directory
var layers: Array[String] = []   ## every layer's directory, base first (section 2.7.4)
var manifest: Dictionary = {}   ## the top layer's pack.json
var sprites: Dictionary = {}          ## sprite id -> {page, x, y, w, h, pivot_x, pivot_y}
var atlas_textures: Array[Texture2D] = []
var tileset: Dictionary = {}          ## "<art_id>" -> {sprite_id, terrain_class}
var decoration_types: Dictionary = {} ## "<coastal_id>" -> Array[{sprite_id, flags}]
var explosions: Dictionary = {}       ## effects/explosions.json: records, coastal_destroy_effect, impact_tables (documents 50-51)
var coastal_shapes: Dictionary = {}      ## "<coastal_id>" -> {jitter, shapes[]} (document 53)
var projectile_types: Array = []       ## 12 entries (documents 46, 58)
var projectile_descriptors: Dictionary = {}  ## "0x454580" -> parts with sprite ids
var vehicle_types: Dictionary = {}    ## "0".."3" -> stats, collision shape, parts (document 57)
var radar_data: Dictionary = {}         ## document 69: radar palette indices, their RGB, the flag blip
var hud_panels: Dictionary = {}         ## document 70: the four vehicles' panel layouts
var selector_data: Dictionary = {}      ## document 78: the docked vehicle-choice screen
var flag_data: Dictionary = {}          ## document 65: the capture flag's drawing and constants
var water_tables: Dictionary = {}       ## document 62: coast shapes, boxes for FUN_0042f280
var gates: Dictionary = {}              ## "43"/"44" -> gate object data (document 56)
var coastal_damage: Dictionary = {}   ## "<coastal_id>" -> {hp, base_art, destroyed_coastal, ...} (document 44)
var audio: Dictionary = {}            ## cue id -> {file, category, priority} (document 82)
var tile_size_px: int = 32


static func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Pack: cannot open %s (%s)" % [path, FileAccess.get_open_error()])
		return null
	return JSON.parse_string(f.get_as_text())


## Loads the pack at `dir` together with its `base_pack` chain (PORTING_PLAN.md section 2.7.4): the base is loaded
## first and `dir` is layered on top of it. `pack_dir` is the top layer.
func load_from(dir: String) -> bool:
	var chain: Array[String] = []
	var d := dir
	while d != "":
		if d in chain:
			push_error("Pack.load_from: base_pack cycle at %s" % d)
			return false
		chain.push_front(d)
		var m: Variant = _read_json(d.path_join("pack.json")) if FileAccess.file_exists(d.path_join("pack.json")) else null
		if not (m is Dictionary):
			push_error("Pack.load_from: no pack.json at %s" % d)
			return false
		var base: Variant = m.get("base_pack", null)
		d = _find_pack(String(base), d) if base != null and String(base) != "" else ""
		if base != null and String(base) != "" and d == "":
			push_error("Pack.load_from: base pack %s of %s not found" % [base, chain[0]])
			return false
	return load_stack(chain)


## Loads the given pack directories bottom to top (section 2.7.4): id-keyed tables override per id (a null value removes
## the id), whole-document tables per top-level key, `projectile_types` whole. Each layer's own `base_pack` is ignored here.
func load_stack(dirs: Array[String]) -> bool:
	if dirs.is_empty():
		push_error("Pack.load_stack: no pack directories")
		return false
	layers = dirs.duplicate()
	pack_dir = dirs[-1]
	for dir in dirs:
		if not _load_layer(dir):
			return false
	if atlas_textures.is_empty():
		push_error("Pack.load_stack: no layer provides sprites/sprites.json")
		return false
	return true


## A pack id's directory: a sibling of `beside` first, then under res://packs.
static func _find_pack(id: String, beside: String) -> String:
	for root in [beside.get_base_dir(), "res://packs"]:
		var candidate: String = String(root).path_join(id)
		if FileAccess.file_exists(candidate.path_join("pack.json")):
			return candidate
	return ""


## Per-id overlay: every key of `top` replaces the same key of `into`; a null value removes it.
static func _overlay(into: Dictionary, top: Variant) -> void:
	if not (top is Dictionary):
		return
	for k in top:
		if top[k] == null:
			into.erase(k)
		else:
			into[k] = top[k]


## The document at dir/rel, or {} when this layer has no such file (every file of a layer is optional).
static func _layer_doc(dir: String, rel: String) -> Dictionary:
	var path := dir.path_join(rel)
	if not FileAccess.file_exists(path):
		return {}
	var doc: Variant = _read_json(path)
	if not (doc is Dictionary):
		push_error("Pack: malformed %s" % path)
		return {}
	return doc


func _load_layer(dir: String) -> bool:
	var manifest_path := dir.path_join("pack.json")
	if not FileAccess.file_exists(manifest_path):
		push_error("Pack.load_from: no pack.json at %s" % manifest_path)
		return false
	manifest = _read_json(manifest_path)

	var sprites_doc := _layer_doc(dir, "sprites/sprites.json")
	if not sprites_doc.is_empty():
		var page_offset := atlas_textures.size()
		for page_name in sprites_doc.get("atlas_pages", []):
			var img := Image.new()
			var err := img.load(dir.path_join("sprites").path_join(page_name))
			if err != OK:
				push_error("Pack.load_from: failed to load atlas page %s (error %d)" % [page_name, err])
				return false
			atlas_textures.append(ImageTexture.create_from_image(img))
		var layer_sprites: Dictionary = sprites_doc.get("sprites", {})
		for id in layer_sprites:
			var entry: Variant = layer_sprites[id]
			if entry is Dictionary:
				entry = entry.duplicate()
				entry["page"] = int(entry.get("page", 0)) + page_offset
			layer_sprites[id] = entry
		_overlay(sprites, layer_sprites)

	var tdoc := _layer_doc(dir, "terrain/tileset.json")
	_overlay(tileset, tdoc.get("tiles", {}))
	if tdoc.has("tile_size_px"):
		tile_size_px = int(tdoc["tile_size_px"])

	# Document 35 (docs/process/): a level's tile coastal id can also be a real decoration --
	# optional (an older or hand-authored pack need not have this file at all), and, per
	# tools/build_pack.py's own note, may simply not list every coastal id a level references
	# -- get_decoration_parts() below treats an unknown id as "no decoration", not an error.
	_overlay(decoration_types, _layer_doc(dir, "terrain/decorations.json").get("decoration_types", {}))
	_overlay(coastal_damage, _layer_doc(dir, "terrain/coastal_damage.json").get("coastal", {}))
	_overlay(coastal_shapes, _layer_doc(dir, "terrain/coastal_shapes.json").get("coastal", {}))
	_overlay(gates, _layer_doc(dir, "terrain/gates.json").get("gates", {}))
	_overlay(water_tables, _layer_doc(dir, "terrain/water.json"))

	var pdoc := _layer_doc(dir, "vehicles/projectile_types.json")
	if pdoc.has("types"):
		projectile_types = pdoc["types"]
	_overlay(projectile_descriptors, pdoc.get("descriptors", {}))
	_overlay(vehicle_types, _layer_doc(dir, "vehicles/vehicle_types.json").get("types", {}))

	_overlay(selector_data, _layer_doc(dir, "hud/selector.json"))
	_overlay(hud_panels, _layer_doc(dir, "hud/panels.json"))
	_overlay(radar_data, _layer_doc(dir, "hud/radar.json"))
	_overlay(flag_data, _layer_doc(dir, "markers/flag.json"))

	# Sound files resolve against the layer that supplied the cue.
	var adoc := _layer_doc(dir, "audio/audio.json")
	for cue in adoc:
		if adoc[cue] is Dictionary:
			adoc[cue] = adoc[cue].duplicate()
			adoc[cue]["_dir"] = dir.path_join("audio")
	_overlay(audio, adoc)

	# explosions.json holds several id-keyed tables (records, coastal_destroy_effect, ...): merged per id inside each.
	var edoc := _layer_doc(dir, "effects/explosions.json")
	for k in edoc:
		if edoc[k] is Dictionary and explosions.get(k) is Dictionary:
			_overlay(explosions[k], edoc[k])
		elif edoc[k] == null:
			explosions.erase(k)
		else:
			explosions[k] = edoc[k]

	return true


## {jitter: bool, shapes: [{type, layer, mask, z, off, box, poly?}]} for a coastal id's tile, or {} if the
## tile has no collision shape (document 53).
func get_coastal_shapes(coastal_id: int) -> Dictionary:
	return coastal_shapes.get(str(coastal_id), {})


## The explosion record ("0x443f30") a destroyed tile of this coastal id spawns, or {} (document 50).
func get_destroy_effect(coastal_id: int) -> Dictionary:
	var addr: String = explosions.get("coastal_destroy_effect", {}).get(str(coastal_id), "")
	return explosions.get("records", {}).get(addr, {})


## The record played when a vehicle crushes a tile of this coastal id (entry field +0x28, swapped in by the
## bush tile callback FUN_00436640; document 54), or {}.
func get_crush_effect(coastal_id: int) -> Dictionary:
	var addr: String = explosions.get("coastal_crush_effect", {}).get(str(coastal_id), "")
	return explosions.get("records", {}).get(addr, {})


## An explosion record by address string ("0x444b68"), or {}.
func get_explosion(addr: String) -> Dictionary:
	return explosions.get("records", {}).get(addr, {})


func get_sprite(sprite_id: String) -> Dictionary:
	return sprites.get(sprite_id, {})


func get_texture(page: int) -> Texture2D:
	if page < 0 or page >= atlas_textures.size():
		return null
	return atlas_textures[page]


func get_tile_sprite_id(art_id: int) -> String:
	var entry: Dictionary = tileset.get(str(art_id), {})
	return entry.get("sprite_id", "")


## Array[{sprite_id: String, flags: int}], one entry per real part this coastal id spawns
## (document 35, docs/process/) -- empty if this id has no known decoration (most don't have
## one *yet*, per tools/data/coastal_decorations.json's own gaps, and 6 real ids genuinely
## never had one to begin with; both cases are indistinguishable here on purpose, since
## "draw nothing" is the correct behaviour either way).
func get_decoration_parts(coastal_id: int) -> Array:
	return decoration_types.get(str(coastal_id), [])


## {hp, base_art, destroyed_coastal, ...} for a coastal id, or {} if unknown.
func get_coastal_damage(coastal_id: int) -> Dictionary:
	return coastal_damage.get(str(coastal_id), {})


## {file, category, priority} for a sound-cue id (document 82, tools/data/sound_cues.json), or {} if this
## pack has no audio for it -- a missing cue is silent, not an error (not every traced cue is applied yet).
func get_sound(cue_id: String) -> Dictionary:
	return audio.get(cue_id, {})


## The pack's own audio/<file> path for a sound-cue id, or "" if it has none.
func get_sound_path(cue_id: String) -> String:
	var entry := get_sound(cue_id)
	if entry.is_empty():
		return ""
	return String(entry.get("_dir", pack_dir.path_join("audio"))).path_join(String(entry.get("file", "")))


## Level ids across every layer (a mod may add levels), sorted.
func list_levels() -> Array[String]:
	var out: Array[String] = []
	for layer in layers:
		var d := DirAccess.open(layer.path_join("levels"))
		if d == null:
			continue
		d.list_dir_begin()
		var name := d.get_next()
		while name != "":
			if d.current_is_dir() and not name.begins_with(".") and not name in out:
				out.append(name)
			name = d.get_next()
		d.list_dir_end()
	out.sort()
	return out


## The directory of a level in the topmost layer that has it, or "" if none does.
func level_dir(level_id: String) -> String:
	for i in range(layers.size() - 1, -1, -1):
		var candidate := layers[i].path_join("levels").path_join(level_id)
		if DirAccess.dir_exists_absolute(candidate):
			return candidate
	return ""
