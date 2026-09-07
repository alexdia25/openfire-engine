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

	return true


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
