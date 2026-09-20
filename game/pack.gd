class_name Pack
extends RefCounted
## Loads a content pack (PORTING_PLAN.md section 2.4.2) from an arbitrary directory at
## runtime -- never via res://'s import pipeline (see packs/.gdignore). This is the only
## thing allowed to read pack files; nothing else in game/ should touch packs/ directly.

var pack_dir: String = ""
var manifest: Dictionary = {}
var sprites: Dictionary = {}          ## sprite id -> {page, x, y, w, h, pivot_x, pivot_y}
var atlas_textures: Array[Texture2D] = []
var tileset: Dictionary = {}          ## "<art_id>" -> {sprite_id, terrain_class}
var decoration_types: Dictionary = {} ## "<coastal_id>" -> Array[{sprite_id, flags}]
var explosions: Dictionary = {}       ## effects/explosions.json: records, coastal_destroy_effect, impact_tables (documents 50-51)
var coastal_shapes: Dictionary = {}      ## "<coastal_id>" -> {jitter, shapes[]} (document 53)
var projectile_types: Array = []       ## 12 entries (documents 46, 58)
var projectile_descriptors: Dictionary = {}  ## "0x454580" -> parts with sprite ids
var vehicle_types: Dictionary = {}    ## "0".."3" -> stats, collision shape, parts (document 57)
var gates: Dictionary = {}              ## "43"/"44" -> gate object data (document 56)
var coastal_damage: Dictionary = {}   ## "<coastal_id>" -> {hp, base_art, destroyed_coastal, ...} (document 44)
var tile_size_px: int = 32


static func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Pack: cannot open %s (%s)" % [path, FileAccess.get_open_error()])
		return null
	return JSON.parse_string(f.get_as_text())


func load_from(dir: String) -> bool:
	pack_dir = dir

	var manifest_path := dir.path_join("pack.json")
	if not FileAccess.file_exists(manifest_path):
		push_error("Pack.load_from: no pack.json at %s" % manifest_path)
		return false
	manifest = _read_json(manifest_path)

	var sprites_doc: Variant = _read_json(dir.path_join("sprites/sprites.json"))
	if not (sprites_doc is Dictionary):
		push_error("Pack.load_from: sprites.json missing or malformed")
		return false
	sprites = sprites_doc.get("sprites", {})

	atlas_textures.clear()
	for page_name in sprites_doc.get("atlas_pages", []):
		var img := Image.new()
		var err := img.load(dir.path_join("sprites").path_join(page_name))
		if err != OK:
			push_error("Pack.load_from: failed to load atlas page %s (error %d)" % [page_name, err])
			return false
		atlas_textures.append(ImageTexture.create_from_image(img))

	var tileset_path := dir.path_join("terrain/tileset.json")
	if FileAccess.file_exists(tileset_path):
		var tdoc: Variant = _read_json(tileset_path)
		if tdoc is Dictionary:
			tileset = tdoc.get("tiles", {})
			tile_size_px = int(tdoc.get("tile_size_px", 32))

	# Document 35 (docs/process/): a level's tile coastal id can also be a real decoration --
	# optional (an older or hand-authored pack need not have this file at all), and, per
	# tools/build_pack.py's own note, may simply not list every coastal id a level references
	# -- get_decoration_parts() below treats an unknown id as "no decoration", not an error.
	var decorations_path := dir.path_join("terrain/decorations.json")
	if FileAccess.file_exists(decorations_path):
		var ddoc: Variant = _read_json(decorations_path)
		if ddoc is Dictionary:
			decoration_types = ddoc.get("decoration_types", {})

	var damage_path := dir.path_join("terrain/coastal_damage.json")
	if FileAccess.file_exists(damage_path):
		var cdoc: Variant = _read_json(damage_path)
		if cdoc is Dictionary:
			coastal_damage = cdoc.get("coastal", {})

	var shapes_path := dir.path_join("terrain/coastal_shapes.json")
	if FileAccess.file_exists(shapes_path):
		var sdoc: Variant = _read_json(shapes_path)
		if sdoc is Dictionary:
			coastal_shapes = sdoc.get("coastal", {})

	var pt_path := dir.path_join("vehicles/projectile_types.json")
	if FileAccess.file_exists(pt_path):
		var pdoc: Variant = _read_json(pt_path)
		if pdoc is Dictionary:
			projectile_types = pdoc.get("types", [])
			projectile_descriptors = pdoc.get("descriptors", {})

	var vt_path := dir.path_join("vehicles/vehicle_types.json")
	if FileAccess.file_exists(vt_path):
		var vdoc: Variant = _read_json(vt_path)
		if vdoc is Dictionary:
			vehicle_types = vdoc.get("types", {})

	var gates_path := dir.path_join("terrain/gates.json")
	if FileAccess.file_exists(gates_path):
		var gdoc: Variant = _read_json(gates_path)
		if gdoc is Dictionary:
			gates = gdoc.get("gates", {})

	var expl_path := dir.path_join("effects/explosions.json")
	if FileAccess.file_exists(expl_path):
		var edoc: Variant = _read_json(expl_path)
		if edoc is Dictionary:
			explosions = edoc

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


func list_levels() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(pack_dir.path_join("levels"))
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if d.current_is_dir() and not name.begins_with("."):
			out.append(name)
		name = d.get_next()
	d.list_dir_end()
	out.sort()
	return out
