class_name Pack
extends RefCounted

## A sprite's pixels or metadata changed after load (`replace_frame()`, `forget_team_colour()`): renderers holding a
## texture region for it should look it up again. The mod tool (EDITOR_PLAN.md 3, 3.1) is the main source of these.
signal sprite_changed(sprite_id: String)
## Loads a content pack (PORTING_PLAN.md section 2.4.2) from an arbitrary directory at
## runtime -- never via res://'s import pipeline (see packs/.gdignore). This is the only
## thing allowed to read pack files; nothing else in game/ should touch packs/ directly.

var pack_dir: String = ""   ## the top layer's directory
var layers: Array[String] = []   ## every layer's directory, base first (section 2.7.4)
var manifest: Dictionary = {}   ## the top layer's pack.json
var sprites: Dictionary = {}          ## sprite id -> {page, x, y, w, h, pivot_x, pivot_y, kind}
var atlas_textures: Array[Texture2D] = []   ## the layers' own atlas pages, then the pages packed from loose frames
var _page_images: Array[Image] = []   ## CPU copy of every page in atlas_textures, same index (read for recolouring, written by the packer)
const PACKED_PAGE_SIZE := 2048
const PACKED_PADDING := 1   ## transparent pixels between packed frames, so nearest sampling never picks up a neighbour
var _shelf := {"page": -1, "x": 0, "y": 0, "h": 0}   ## where the packer's open page continues (PORTING_PLAN.md 2.7.5)
var _dirty_pages := {}   ## page index -> true: its Image changed since its texture was last uploaded
## Team colours (PORTING_PLAN.md 2.7.7): tan sprite id -> green sprite id for every sprite whose art is team-coloured,
## the reverse, and colour name -> {source, variant?, hsv}. "original" colours are the art as drawn (tan variant 0, green
## variant 1); any other colour is generated from the tan art by `team_sprite()` / `prepare_team_colours()`.
var team_sets: Dictionary = {}
var _team_set_of: Dictionary = {}   ## green id -> tan id
var team_colours: Dictionary = {}
var team_reference := "tan"
## Masked team art (PORTING_PLAN.md 2.7.7), for art that has one drawing instead of a tan/green pair -- a mod's new
## vehicle: sprite id -> {mask: sprite id, drawn_as: colour or ""}. The mask is an ordinary sprite; wherever it is opaque
## the drawing is team paint. Every colour is generated from the drawing, except `drawn_as`, which returns it as drawn.
var team_masks: Dictionary = {}
var _sprite_layer: Dictionary = {}   ## sprite id -> directory of the layer that last supplied (or amended) it
var tileset: Dictionary = {}          ## "<art_id>" -> {sprite_id, terrain_class}
var decoration_types: Dictionary = {} ## "<coastal_id>" -> Array[{sprite_id, flags}]
var explosions: Dictionary = {}       ## effects/explosions.json: records, coastal_destroy_effect, impact_tables (documents 50-51)
var coastal_shapes: Dictionary = {}      ## "<coastal_id>" -> {jitter, shapes[]} (document 53)
var projectile_types: Array = []       ## 12 entries (documents 46, 58)
var projectile_descriptors: Dictionary = {}  ## "0x454580" -> parts with sprite ids
## Vehicle definitions (PORTING_PLAN.md 2.7.2, step 3): id -> the vehicles/<id>/vehicle.json of the topmost layer that has
## it. `vehicle_order` gives each a runtime index: the roster first (the original four in bay order, so Tank = 0 ... Heli = 3
## as the traced code expects), then any other definition by id. `vehicle_def(index)` / `vehicle_index(id)` look them up.
var vehicle_defs: Dictionary = {}
var vehicle_roster: Array = []        ## vehicles/roster.json "vehicles": [{id, stock_key, default_stock}], from the top layer that has one
var vehicle_order: Array[String] = []
## The flat per-type view the code used before definitions ("0".."3" -> stats, shape, parts ...), built from the
## definitions so existing readers keep working until step 4 moves them onto `vehicle_def()`. A layer's old-style
## vehicles/vehicle_types.json still applies on top of it, per key.
var vehicle_types: Dictionary = {}
var _legacy_vehicle_types: Dictionary = {}
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
	if not _pack_loose_frames():
		return false
	_build_vehicle_view()
	if atlas_textures.is_empty():
		push_error("Pack.load_stack: no layer provides sprites/sprites.json")
		return false
	return true


## Loads every loose-frame sprite that survived the layering (an overridden frame is never read) and shelf-packs them,
## tallest first, into PACKED_PAGE_SIZE pages appended after the layers' own pages; each entry gets its page / x / y, and
## w / h from the image itself, so a replacement frame may be any size (PORTING_PLAN.md 2.7.5).
func _pack_loose_frames() -> bool:
	var frames: Array = []
	for id in sprites:
		var entry: Dictionary = sprites[id]
		if not entry.has("_file"):
			continue
		var img := Image.new()
		var err := img.load(String(entry["_file"]))
		if err != OK:
			push_error("Pack: failed to load sprite frame %s (error %d)" % [entry["_file"], err])
			return false
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		if img.get_width() > PACKED_PAGE_SIZE or img.get_height() > PACKED_PAGE_SIZE:
			push_error("Pack: sprite frame %s is larger than a page" % entry["_file"])
			return false
		frames.append([id, img])
	frames.sort_custom(func(a, b): return a[1].get_height() > b[1].get_height() or (a[1].get_height() == b[1].get_height() and a[0] < b[0]))
	for f in frames:
		var entry: Dictionary = sprites[f[0]]
		entry.erase("_file")
		_place_frame(entry, f[1])
	_upload_dirty_pages()
	return true


## Copies `img` into the packer's open page (a new page when it doesn't fit) and points `entry` at it. The page's texture
## is re-uploaded by `_upload_dirty_pages()`, so a batch of frames costs one upload per page.
func _place_frame(entry: Dictionary, img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	if _shelf["page"] >= 0 and int(_shelf["x"]) + w > PACKED_PAGE_SIZE:
		_shelf["x"] = 0
		_shelf["y"] = int(_shelf["y"]) + int(_shelf["h"]) + PACKED_PADDING
		_shelf["h"] = 0
	if _shelf["page"] < 0 or int(_shelf["y"]) + h > PACKED_PAGE_SIZE:
		_page_images.append(Image.create_empty(PACKED_PAGE_SIZE, PACKED_PAGE_SIZE, false, Image.FORMAT_RGBA8))
		atlas_textures.append(null)
		_shelf = {"page": _page_images.size() - 1, "x": 0, "y": 0, "h": 0}
	var page := int(_shelf["page"])
	_page_images[page].blit_rect(img, Rect2i(0, 0, w, h), Vector2i(int(_shelf["x"]), int(_shelf["y"])))
	_dirty_pages[page] = true
	entry["page"] = page
	entry["x"] = int(_shelf["x"])
	entry["y"] = int(_shelf["y"])
	entry["w"] = w
	entry["h"] = h
	_shelf["x"] = int(_shelf["x"]) + w + PACKED_PADDING
	_shelf["h"] = maxi(int(_shelf["h"]), h)


func _upload_dirty_pages() -> void:
	for page in _dirty_pages:
		if atlas_textures[page] == null:
			atlas_textures[page] = ImageTexture.create_from_image(_page_images[page])
		else:
			(atlas_textures[page] as ImageTexture).update(_page_images[page])
	_dirty_pages.clear()


## Replaces (or adds) one sprite's pixels while running, without reloading the pack: written over its old region when
## it still fits, otherwise packed anew; metadata such as the pivot is kept unless `entry_changes` says otherwise.
## Generated team colours of that sprite are dropped so they are remade from the new pixels. For the mod tool's import,
## "open in image editor" live reload and (later) pixel editing (EDITOR_PLAN.md 3.1).
func replace_frame(sprite_id: String, img: Image, entry_changes: Dictionary = {}) -> void:
	if img.get_format() != Image.FORMAT_RGBA8:
		img = img.duplicate() as Image
		img.convert(Image.FORMAT_RGBA8)
	var entry: Dictionary = sprites.get(sprite_id, {"pivot_x": img.get_width() / 2.0, "pivot_y": img.get_height() / 2.0,
			"pivot_source": "default_center", "kind": "sprite"})
	entry = entry.duplicate()
	entry.merge(entry_changes, true)
	if entry.has("page") and int(entry.get("w", 0)) >= img.get_width() and int(entry.get("h", 0)) >= img.get_height():
		var page := int(entry["page"])
		var region := Rect2i(int(entry["x"]), int(entry["y"]), int(entry["w"]), int(entry["h"]))
		_page_images[page].fill_rect(region, Color(0, 0, 0, 0))
		_page_images[page].blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), region.position)
		entry["w"] = img.get_width()
		entry["h"] = img.get_height()
		_dirty_pages[page] = true
	else:
		_place_frame(entry, img)
	sprites[sprite_id] = entry
	_upload_dirty_pages()
	_forget_generated_from(sprite_id)
	sprite_changed.emit(sprite_id)


## Changes a sprite's metadata only (pivot, kind ...), e.g. from the mod tool's pivot setter.
func amend_sprite(sprite_id: String, entry_changes: Dictionary) -> void:
	if not sprites.has(sprite_id):
		return
	var entry: Dictionary = sprites[sprite_id].duplicate()
	entry.merge(entry_changes, true)
	sprites[sprite_id] = entry
	sprite_changed.emit(sprite_id)


## Removes a sprite added at runtime (the mod tool undoing a new sprite).
func remove_sprite(sprite_id: String) -> void:
	if sprites.erase(sprite_id):
		_forget_generated_from(sprite_id)
		sprite_changed.emit(sprite_id)


## Runtime setters for the team tables (the mod tool; `null` removes). Each drops the generated sprites it invalidates.
func set_team_colour(colour: String, def: Variant) -> void:
	if def == null:
		team_colours.erase(colour)
	else:
		team_colours[colour] = def
	forget_team_colour(colour)


func set_team_mask(sprite_id: String, def: Variant) -> void:
	if def == null:
		team_masks.erase(sprite_id)
	else:
		team_masks[sprite_id] = def
	_forget_generated_from(sprite_id)


func set_team_pair(tan: String, green: Variant) -> void:
	if team_sets.has(tan):
		_team_set_of.erase(String(team_sets[tan]))
	if green == null:
		team_sets.erase(tan)
	else:
		team_sets[tan] = String(green)
		_team_set_of[String(green)] = tan
	_forget_generated_from(tan)


## Which layer directory supplied a sprite ("" for one made at runtime, e.g. a generated team colour).
func sprite_layer(sprite_id: String) -> String:
	return String(_sprite_layer.get(sprite_id, ""))


## Drops every generated sprite of one colour (its definition changed); the next `team_sprite()` or
## `prepare_team_colours()` makes them again. Their old page space is simply left unused.
func forget_team_colour(colour: String) -> void:
	for id in sprites.keys():
		if String(id).ends_with("@" + colour):
			sprites.erase(id)
			sprite_changed.emit(id)


func _forget_generated_from(sprite_id: String) -> void:
	var tan: String = _team_set_of.get(sprite_id, sprite_id)
	for id in sprites.keys():
		if String(id).begins_with(tan + "@") or String(id).begins_with(sprite_id + "@"):
			sprites.erase(id)
			sprite_changed.emit(id)


## A sprite's pixels, copied out of its page.
func get_sprite_image(sprite_id: String) -> Image:
	var s := get_sprite(sprite_id)
	if s.is_empty():
		return null
	return _page_images[int(s["page"])].get_region(Rect2i(int(s["x"]), int(s["y"]), int(s["w"]), int(s["h"])))


## The sprite to draw for team-coloured art in `colour` (PORTING_PLAN.md 2.7.7). `sprite_id` may be the tan or the green
## member of a team set; an original colour returns the art as drawn, any other colour a sprite generated from the tan
## art (made now if `prepare_team_colours()` hasn't already). Art that isn't team-coloured, or an unknown colour, comes
## back unchanged.
func team_sprite(sprite_id: String, colour: String) -> String:
	if team_masks.has(sprite_id):
		if not team_colours.has(colour) or colour == String(team_masks[sprite_id].get("drawn_as", "")):
			return sprite_id
		var mid := sprite_id + "@" + colour
		if not sprites.has(mid):
			_make_recolour(sprite_id, colour)
			_upload_dirty_pages()
		return mid
	var tan: String = _team_set_of.get(sprite_id, sprite_id)
	if not team_sets.has(tan):
		return sprite_id
	var c: Dictionary = team_colours.get(colour, {})
	if c.is_empty():
		return sprite_id
	if c.get("source", "") == "original":
		return tan if int(c.get("variant", 0)) == 0 else String(team_sets[tan])
	var id := tan + "@" + colour
	if not sprites.has(id):
		_make_recolour(tan, colour)
		_upload_dirty_pages()
	return id


## For art given as the original's variant list [tan id, green id, ...]: an original colour indexes it exactly as drawn,
## any other colour is generated from the tan member. Use this wherever the code used to index such a list by team.
## Safe for any sprite list, including a single id that isn't team art at all (it comes back unchanged), so callers
## don't need to know which parts are team-coloured.
func team_variant(ids: Array, colour: String) -> String:
	if team_masks.has(String(ids[0])):
		return team_sprite(String(ids[0]), colour)   # one drawing + a mask: no per-team list to index
	var c: Dictionary = team_colours.get(colour, {})
	if c.get("source", "") == "original" or colour == "":
		var v := int(c.get("variant", 0))
		return String(ids[clampi(v, 0, ids.size() - 1)])
	return team_sprite(String(ids[0]), colour)


## True for the colours the original art was drawn in (and for "", meaning "not set": the art as drawn).
func is_original_colour(colour: String) -> bool:
	return colour == "" or team_colours.get(colour, {}).get("source", "") == "original"


## Generates every team set in each of `colours` at once (called when a match is set up, so nothing is made mid-game).
func prepare_team_colours(colours: Array) -> void:
	for colour in colours:
		var c: Dictionary = team_colours.get(String(colour), {})
		if c.is_empty():
			continue
		for id in team_masks:   # masked art is generated in every colour it wasn't drawn in, the original two included
			if String(team_masks[id].get("drawn_as", "")) != String(colour) and not sprites.has(String(id) + "@" + String(colour)):
				_make_recolour(String(id), String(colour))
		if c.get("source", "") == "original":
			continue
		for tan in team_sets:
			if not sprites.has(String(tan) + "@" + String(colour)):
				_make_recolour(String(tan), String(colour))
	_upload_dirty_pages()


## A representative RGB for a colour (its HSV mean), for things drawn flat in team colour: the placeholder shell tint,
## a radar blip.
func team_rgb(colour: String) -> Color:
	var hsv: Array = team_colours.get(colour, {}).get("hsv", [0.0, 0.0, 0.5])
	return Color.from_hsv(float(hsv[0]), float(hsv[1]), float(hsv[2]))


## The recolour itself. Team paint is, for a tan/green pair, every pixel where the two drawings differ; for masked art,
## every pixel where the mask is opaque (alpha >= 0.5). Pixels outside it (tracks, metal, outlines) are never touched.
## A paint pixel takes the target colour's hue and keeps its saturation and brightness relative to the source's mean:
## for a pair the source is tan and the mean the measured tan mean (teams/colours.json); for masked art the mean is
## taken from the drawing's own paint pixels, and if the drawing is (nearly) grey its saturation is ignored and the
## target's used outright, so team paint can be drawn in grey. A port feature: the original only has two drawings.
func _make_recolour(source: String, colour: String) -> void:
	var base := get_sprite_image(source)
	if base == null:
		return
	var paint := Image.create_empty(base.get_width(), base.get_height(), false, Image.FORMAT_L8)
	var ref: Array
	var masked := team_masks.has(source)
	if masked:
		var mask := get_sprite_image(String(team_masks[source].get("mask", "")))
		if mask == null or mask.get_size() != base.get_size():
			push_error("Pack: team mask for %s is missing or not the drawing's size" % source)
			return
		var cx := 0.0
		var cy := 0.0
		var ss := 0.0
		var vv := 0.0
		var n := 0
		for y in base.get_height():
			for x in base.get_width():
				var a := base.get_pixel(x, y)
				if a.a > 0.0 and mask.get_pixel(x, y).a >= 0.5:
					paint.set_pixel(x, y, Color.WHITE)
					cx += cos(a.h * TAU)
					cy += sin(a.h * TAU)
					ss += a.s
					vv += a.v
					n += 1
		if n == 0:
			return
		ref = [fposmod(atan2(cy, cx) / TAU, 1.0), ss / n, vv / n]
	else:
		var other := get_sprite_image(String(team_sets[source]))
		if other == null or other.get_size() != base.get_size():
			return
		for y in base.get_height():
			for x in base.get_width():
				var a := base.get_pixel(x, y)
				if a.a > 0.0 and a != other.get_pixel(x, y):
					paint.set_pixel(x, y, Color.WHITE)
		ref = team_colours.get(team_reference, {}).get("hsv", [0.05, 0.74, 0.37])
	var target: Array = team_colours[colour]["hsv"]
	var grey_source := masked and float(ref[1]) < 0.15
	var s_scale := float(target[1]) / maxf(float(ref[1]), 0.001)
	var v_scale := float(target[2]) / maxf(float(ref[2]), 0.001)
	var out := base.duplicate() as Image
	for y in base.get_height():
		for x in base.get_width():
			if paint.get_pixel(x, y).r < 0.5:
				continue
			var a := base.get_pixel(x, y)
			var sat := float(target[1]) if grey_source else clampf(a.s * s_scale, 0.0, 1.0)
			out.set_pixel(x, y, Color.from_hsv(float(target[0]), sat, clampf(a.v * v_scale, 0.0, 1.0), a.a))
	var entry: Dictionary = sprites[source].duplicate()
	entry["source"] = "generated"
	entry["team_colour"] = colour
	_place_frame(entry, out)
	sprites[source + "@" + colour] = entry


func _build_vehicle_view() -> void:
	vehicle_order.clear()
	for entry in vehicle_roster:
		var id := String(entry.get("id", ""))
		if vehicle_defs.has(id) and not id in vehicle_order:
			vehicle_order.append(id)
	var rest: Array = vehicle_defs.keys()
	rest.sort()
	for id in rest:
		if not String(id) in vehicle_order:
			vehicle_order.append(String(id))
	vehicle_types.clear()
	for i in vehicle_order.size():
		vehicle_types[str(i)] = _flat_view(vehicle_defs[vehicle_order[i]])
	_overlay(vehicle_types, _legacy_vehicle_types)


## The pre-definition field names, flattened out of a definition's groups.
static func _flat_view(def: Dictionary) -> Dictionary:
	var v := {"id": def.get("id", ""), "name": def.get("name", "")}
	for group in ["stats", "drive"]:
		v.merge(def.get(group, {}), true)
	var w: Dictionary = def.get("weapons", {})
	v["ammo"] = w.get("ammo", [0, 0])
	v["weapon_cooldown_ticks"] = w.get("cooldown_ticks", [20, 0])
	v["shape"] = def.get("shape", {})
	var r: Dictionary = def.get("render", {})
	v["parts"] = r.get("parts", [])
	for extra in ["swim", "rack"]:
		if r.has(extra):
			v[extra] = r[extra]
	return v


## The definition at a runtime index ({} if none).
func vehicle_def(index: int) -> Dictionary:
	return vehicle_defs.get(vehicle_order[index], {}) if index >= 0 and index < vehicle_order.size() else {}


## The runtime index of a definition id (-1 if none).
func vehicle_index(id: String) -> int:
	return vehicle_order.find(id)


## One field of a definition by dotted path ("stats.dock_tolerance"), or `default` when the definition or field is missing.
func vehicle_value(index: int, path: String, default: Variant = null) -> Variant:
	var v: Variant = vehicle_def(index)
	for key in path.split("."):
		if not (v is Dictionary) or not v.has(key):
			return default
		v = v[key]
	return v if v != null else default


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
			if img.get_format() != Image.FORMAT_RGBA8:
				img.convert(Image.FORMAT_RGBA8)
			atlas_textures.append(ImageTexture.create_from_image(img))
			_page_images.append(img)
		var layer_sprites: Dictionary = sprites_doc.get("sprites", {})
		for id in layer_sprites.keys():
			var entry: Variant = layer_sprites[id]
			if entry is Dictionary:
				entry = entry.duplicate()
				if entry.has("file"):   # a loose frame: packed into a page once every layer is known (_pack_loose_frames)
					entry["_file"] = dir.path_join("sprites").path_join(String(entry["file"]))
				elif entry.has("page"):
					entry["page"] = int(entry.get("page", 0)) + page_offset
				elif sprites.get(id) is Dictionary:
					# Metadata only (no image of its own): amends the entry below, e.g. a mod moving a pivot without
					# shipping a copy of the original frame.
					var merged: Dictionary = sprites[id].duplicate()
					merged.merge(entry, true)
					entry = merged
			layer_sprites[id] = entry
			_sprite_layer[id] = dir
		_overlay(sprites, layer_sprites)

	var tdoc := _layer_doc(dir, "terrain/tileset.json")
	_overlay(tileset, tdoc.get("tiles", {}))
	if tdoc.has("tile_size_px"):
		tile_size_px = int(tdoc["tile_size_px"])

	# Document 35 (on the project wiki): a level's tile coastal id can also be a real decoration --
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
	_overlay(_legacy_vehicle_types, _layer_doc(dir, "vehicles/vehicle_types.json").get("types", {}))
	var roster_doc := _layer_doc(dir, "vehicles/roster.json")
	if roster_doc.has("vehicles"):
		vehicle_roster = roster_doc["vehicles"]
	var vd := DirAccess.open(dir.path_join("vehicles"))
	if vd != null:
		for sub in vd.get_directories():
			var def := _layer_doc(dir, "vehicles".path_join(sub).path_join("vehicle.json"))
			if not def.is_empty():
				vehicle_defs[String(def.get("id", sub))] = def

	_overlay(selector_data, _layer_doc(dir, "hud/selector.json"))
	_overlay(hud_panels, _layer_doc(dir, "hud/panels.json"))
	_overlay(radar_data, _layer_doc(dir, "hud/radar.json"))
	_overlay(flag_data, _layer_doc(dir, "markers/flag.json"))

	# Team colours (PORTING_PLAN.md 2.7.7): a mod can add team sets (its own art) and colours, per id.
	var team_doc := _layer_doc(dir, "sprites/team_sets.json")
	_overlay(team_sets, team_doc.get("pairs", {}))
	var masks: Dictionary = team_doc.get("masks", {})
	for id in masks:   # a bare mask id is shorthand for {mask: id}
		if masks[id] is String:
			masks[id] = {"mask": masks[id]}
	_overlay(team_masks, masks)
	for tan in team_sets:
		_team_set_of[String(team_sets[tan])] = tan
	var cdoc := _layer_doc(dir, "teams/colours.json")
	_overlay(team_colours, cdoc.get("colours", {}))
	if cdoc.has("reference"):
		team_reference = String(cdoc["reference"])

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
## (document 35, on the project wiki) -- empty if this id has no known decoration (most don't have
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
