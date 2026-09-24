class_name ModWorkspace
extends RefCounted
## The open mod in the mod tool (EDITOR_PLAN.md 3): a pack directory layered over its base pack. Holds the mod layer's
## OWN tables (what it overrides or adds, nothing inherited), the frames imported but not saved yet, and an undo stack.
## Every edit is one undoable action that updates both those tables and the live Pack, so the tool's previews, and a
## play test, show it at once. `save()` writes the mod layer through PackWriter; nothing below the mod is ever written.

signal changed()                       ## after any edit, undo, redo, save or reload
signal saved()

const DEFAULT_BASE := "original_pc"

var mod_dir := ""
var pack: Pack
var undo := UndoRedo.new()
var manifest: Dictionary = {}
var mod_sprites: Dictionary = {}       ## the mod's sprites.json "sprites"
var mod_pairs: Dictionary = {}         ## team_sets.json "pairs" (tan id -> green id)
var mod_masks: Dictionary = {}         ## team_sets.json "masks" (sprite id -> {mask, drawn_as})
var mod_colours: Dictionary = {}       ## teams/colours.json "colours"
var _pending_frames: Dictionary = {}   ## frame path under sprites/ -> Image, written by save()
var _saved_version := 0
var _watched: Dictionary = {}          ## absolute frame path -> [sprite id, modified time] (open in image editor)
var _lower_cache: Dictionary = {}      ## lazily read tables of the layers below the mod


func _init() -> void:
	# Announce edits once UndoRedo has counted them (an action's methods run before its version moves), so listeners
	# see the right dirty / undo / redo state. Covers do, undo and redo alike.
	undo.version_changed.connect(_announce)


func _announce() -> void:
	changed.emit()


## Creates a new, empty mod at `dir` over `base_pack`.
static func create(dir: String, name: String, base_pack: String = DEFAULT_BASE) -> ModWorkspace:
	PackWriter.write_json(dir.path_join("pack.json"), {
		"id": dir.get_file(), "name": name, "version": "0.1.0", "engine_api_version": "0.1.0", "author": "",
		"license": "", "base_pack": base_pack, "overrides": [], "pixels_per_world_unit": 32})
	var ws := ModWorkspace.new()
	return ws if ws.open(dir) else null


func open(dir: String) -> bool:
	mod_dir = dir
	var why := ModLoader.mod_problem(dir)
	if why != "":
		# Original content is never edited: a mod is its own folder layered on top (PORTING_PLAN.md 2.7.9).
		push_error("ModWorkspace: %s cannot be opened as a mod: %s" % [dir, why])
		return false
	manifest = _read(dir.path_join("pack.json"))
	mod_sprites = _read(dir.path_join("sprites/sprites.json")).get("sprites", {})
	var ts := _read(dir.path_join("sprites/team_sets.json"))
	mod_pairs = ts.get("pairs", {})
	mod_masks = ts.get("masks", {})
	mod_colours = _read(dir.path_join("teams/colours.json")).get("colours", {})
	_pending_frames.clear()
	undo.clear_history()
	_saved_version = undo.get_version()
	return reload()


## Reloads the whole stack from disk (after a save, or to drop the runtime state). Unsaved edits stay in the tables.
func reload() -> bool:
	pack = Pack.new()
	_lower_cache.clear()
	if not pack.load_from(mod_dir):
		return false
	changed.emit()
	return true


## Frees the undo stack (its actions hold references back to this workspace, so without this neither is ever freed).
## Call when the mod is closed; the workspace is unusable afterwards.
func close() -> void:
	if undo != null:
		undo.version_changed.disconnect(_announce)   # closing is not an edit: nobody should hear about it
		undo.clear_history()
		undo.free()
		undo = null
	pack = null


func is_dirty() -> bool:
	return undo.get_version() != _saved_version


func save() -> bool:
	var ok := PackWriter.write_layer(mod_dir, manifest, mod_sprites, _pending_frames, mod_pairs, mod_masks, mod_colours)
	if ok:
		for rel in _pending_frames:
			var path := mod_dir.path_join("sprites").path_join(String(rel))
			for watched in _watched:
				if watched == path:
					_watched[watched][1] = FileAccess.get_modified_time(path)
		_pending_frames.clear()
		_saved_version = undo.get_version()
		saved.emit()
		changed.emit()
	return ok


## The mod-relative frame file for a sprite id, filed like tools/build_pack.py's sprite_file(): the first two id
## segments are folders, the rest the name (mymod.hovertank.hull -> mymod/hovertank/hull.png).
static func frame_path(sprite_id: String) -> String:
	var parts := sprite_id.split(".")
	if parts.size() > 2:
		return "/".join(parts.slice(0, 2)) + "/" + ".".join(parts.slice(2)) + ".png"
	return "/".join(parts) + ".png"


## "mod" if the mod overrides or adds this sprite, "base" if it comes from below, "" if unknown.
func sprite_origin(sprite_id: String) -> String:
	if mod_sprites.has(sprite_id):
		return "mod"
	return "base" if pack.sprites.has(sprite_id) else ""


# --- sprites ---------------------------------------------------------------------------------------------------------

## Imports `img` as the frame of `sprite_id` (a replacement or a new sprite). The pivot is kept when the size is unchanged,
## otherwise centred.
func import_frame(sprite_id: String, img: Image, action := "Import frame") -> void:
	var rel := frame_path(sprite_id)
	var old: Dictionary = pack.get_sprite(sprite_id)
	var same_size := int(old.get("w", -1)) == img.get_width() and int(old.get("h", -1)) == img.get_height()
	var entry := {"file": rel, "w": img.get_width(), "h": img.get_height(), "source": "imported",
		"kind": String(old.get("kind", "sprite")),
		"pivot_x": float(old["pivot_x"]) if same_size else img.get_width() / 2.0,
		"pivot_y": float(old["pivot_y"]) if same_size else img.get_height() / 2.0,
		"pivot_source": String(old.get("pivot_source", "default_center")) if same_size else "default_center"}
	_do_sprite(action, sprite_id, {"mod": entry, "frame": img, "image": img, "meta": _meta_of(entry)})


func set_pivot(sprite_id: String, pivot: Vector2) -> void:
	var cur := _capture_sprite(sprite_id)
	if cur["image"] == null:
		return
	var entry: Dictionary = (cur["mod"] as Dictionary).duplicate() if cur["mod"] != null else {}
	entry["pivot_x"] = snappedf(pivot.x, 0.5)
	entry["pivot_y"] = snappedf(pivot.y, 0.5)
	entry["pivot_source"] = "mod"
	var meta: Dictionary = (cur["meta"] as Dictionary).duplicate()
	meta.merge({"pivot_x": entry["pivot_x"], "pivot_y": entry["pivot_y"], "pivot_source": "mod"}, true)
	_do_sprite("Set pivot", sprite_id, {"mod": entry, "frame": cur["frame"], "image": cur["image"], "meta": meta})


## Drops the mod's override: the sprite shows the layer below again (or disappears if the mod added it).
func revert_sprite(sprite_id: String) -> void:
	if not mod_sprites.has(sprite_id):
		return
	var lower := _lower_sprite(sprite_id)
	_do_sprite("Revert sprite", sprite_id, {"mod": null, "frame": null,
		"image": lower.get("image"), "meta": lower.get("meta", {})})


func _do_sprite(action: String, sprite_id: String, new_state: Dictionary) -> void:
	var old_state := _capture_sprite(sprite_id)
	undo.create_action(action)
	undo.add_do_method(_apply_sprite.bind(sprite_id, new_state))
	undo.add_undo_method(_apply_sprite.bind(sprite_id, old_state))
	undo.commit_action()


func _capture_sprite(sprite_id: String) -> Dictionary:
	var entry: Variant = mod_sprites.get(sprite_id)
	var rel := String(entry.get("file", "")) if entry is Dictionary else ""
	var has := pack.sprites.has(sprite_id)
	return {"mod": (entry as Dictionary).duplicate() if entry is Dictionary else null,
		"frame": _pending_frames.get(rel),
		"image": pack.get_sprite_image(sprite_id) if has else null,
		"meta": _meta_of(pack.get_sprite(sprite_id)) if has else {}}


func _apply_sprite(sprite_id: String, state: Dictionary) -> void:
	var old_entry: Variant = mod_sprites.get(sprite_id)
	if old_entry is Dictionary and old_entry.has("file"):
		_pending_frames.erase(String(old_entry["file"]))
	if state["mod"] == null:
		mod_sprites.erase(sprite_id)
	else:
		mod_sprites[sprite_id] = state["mod"]
		if state["frame"] != null and (state["mod"] as Dictionary).has("file"):
			_pending_frames[String(state["mod"]["file"])] = state["frame"]
	if state["image"] == null:
		pack.remove_sprite(sprite_id)
	else:
		pack.replace_frame(sprite_id, state["image"], state["meta"])
	_forget_masked_by(sprite_id)


static func _meta_of(entry: Dictionary) -> Dictionary:
	var meta := entry.duplicate()
	for k in ["page", "x", "y", "w", "h", "file", "_file"]:
		meta.erase(k)
	return meta


## A sprite as the layers below the mod define it: {image, meta}, or {} if the mod added it.
func _lower_sprite(sprite_id: String) -> Dictionary:
	if not _lower_cache.has("sprites"):
		var table := {}
		for i in pack.layers.size() - 1:
			var dir := pack.layers[i]
			var doc := _read(dir.path_join("sprites/sprites.json"))
			var pages: Array = doc.get("atlas_pages", [])
			for id in doc.get("sprites", {}):
				var e: Variant = doc["sprites"][id]
				if e == null:
					table.erase(id)
				elif e is Dictionary and (e.has("file") or e.has("page")):
					table[id] = {"dir": dir, "entry": e, "pages": pages}
				elif e is Dictionary and table.has(id):
					var merged: Dictionary = table[id]["entry"].duplicate()
					merged.merge(e, true)
					table[id]["entry"] = merged
		_lower_cache["sprites"] = table
	var found: Dictionary = _lower_cache["sprites"].get(sprite_id, {})
	if found.is_empty():
		return {}
	var e: Dictionary = found["entry"]
	var img := Image.new()
	if e.has("file"):
		img.load(String(found["dir"]).path_join("sprites").path_join(String(e["file"])))
	else:
		var page := Image.new()
		page.load(String(found["dir"]).path_join("sprites").path_join(String(found["pages"][int(e["page"])])))
		img = page.get_region(Rect2i(int(e["x"]), int(e["y"]), int(e["w"]), int(e["h"])))
	return {"image": img, "meta": _meta_of(e)}


# --- open in image editor (EDITOR_PLAN.md 3: the "edit" slot a pixel editor fills later) -----------------------------

## Makes sure the sprite has its own frame file in the mod (exporting the current pixels if it doesn't), saves that
## file now, and returns its absolute path; `poll_external()` then picks up saves made in another program.
func export_for_external_edit(sprite_id: String) -> String:
	var entry: Variant = mod_sprites.get(sprite_id)
	if not (entry is Dictionary and entry.has("file")):
		var img := pack.get_sprite_image(sprite_id)
		if img == null:
			return ""
		import_frame(sprite_id, img, "Export for editing")
		entry = mod_sprites[sprite_id]
	var rel := String(entry["file"])
	var path := mod_dir.path_join("sprites").path_join(rel)
	var pending: Variant = _pending_frames.get(rel)
	var img: Image = pending if pending != null else pack.get_sprite_image(sprite_id)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	_watched[path] = [sprite_id, FileAccess.get_modified_time(path)]
	return path


## Re-imports every watched frame whose file changed since last seen (call from a timer). Returns the ids reloaded.
func poll_external() -> Array[String]:
	var out: Array[String] = []
	for path in _watched:
		var t := FileAccess.get_modified_time(path)
		if t == int(_watched[path][1]):
			continue
		_watched[path][1] = t
		var img := Image.new()
		if img.load(path) == OK:
			var id := String(_watched[path][0])
			import_frame(id, img, "External edit")
			_pending_frames.erase(String(mod_sprites[id]["file"]))   # the file on disk IS the new frame already
			out.append(id)
	return out


# --- team colours, pairs and masks (PORTING_PLAN.md 2.7.7) -----------------------------------------------------------

## Adds or changes a colour in the mod; `hsv` is [hue, saturation, value], each 0-1.
func set_colour(colour: String, hsv: Array) -> void:
	_do_team("Set colour %s" % colour, mod_colours, colour,
		{"source": "mod", "hsv": [snappedf(hsv[0], 0.0001), snappedf(hsv[1], 0.0001), snappedf(hsv[2], 0.0001)]},
		pack.set_team_colour, "teams/colours.json", "colours")


func remove_colour(colour: String) -> void:
	_do_team("Remove colour %s" % colour, mod_colours, colour, null, pack.set_team_colour, "teams/colours.json", "colours")


## Gives one drawing a team-paint mask (another sprite, the same size); `drawn_as` names the colour it is drawn in, if any.
func set_mask(sprite_id: String, mask_id: String, drawn_as := "") -> void:
	var def := {"mask": mask_id}
	if drawn_as != "":
		def["drawn_as"] = drawn_as
	_do_team("Set team mask", mod_masks, sprite_id, def, pack.set_team_mask, "sprites/team_sets.json", "masks")


func clear_mask(sprite_id: String) -> void:
	_do_team("Clear team mask", mod_masks, sprite_id, null, pack.set_team_mask, "sprites/team_sets.json", "masks")


func set_pair(tan_id: String, green_id: String) -> void:
	_do_team("Set team pair", mod_pairs, tan_id, green_id, pack.set_team_pair, "sprites/team_sets.json", "pairs")


func clear_pair(tan_id: String) -> void:
	_do_team("Clear team pair", mod_pairs, tan_id, null, pack.set_team_pair, "sprites/team_sets.json", "pairs")


## One undoable change to a team table: `table` is the mod's own (null value = the mod no longer sets it, so the value
## from below shows again), `setter` the Pack runtime setter.
func _do_team(action: String, table: Dictionary, key: String, value: Variant, setter: Callable, rel: String, doc_key: String) -> void:
	var old_value: Variant = table.get(key)
	var lower: Variant = _lower_table(rel, doc_key).get(key)
	undo.create_action(action)
	undo.add_do_method(_apply_team.bind(table, key, value, setter, value if value != null else lower))
	undo.add_undo_method(_apply_team.bind(table, key, old_value, setter, old_value if old_value != null else lower))
	undo.commit_action()


func _apply_team(table: Dictionary, key: String, value: Variant, setter: Callable, runtime_value: Variant) -> void:
	if value == null:
		table.erase(key)
	else:
		table[key] = value
	setter.call(key, runtime_value)


func _lower_table(rel: String, doc_key: String) -> Dictionary:
	var cache_key := rel + ":" + doc_key
	if not _lower_cache.has(cache_key):
		var table := {}
		for i in pack.layers.size() - 1:
			var doc := _read(pack.layers[i].path_join(rel))
			var t: Dictionary = doc.get(doc_key, {})
			for k in t:
				if t[k] == null:
					table.erase(k)
				else:
					table[k] = t[k] if not (t[k] is String and doc_key == "masks") else {"mask": t[k]}
		_lower_cache[cache_key] = table
	return _lower_cache[cache_key]


## A sprite used as some drawing's team mask changed: that drawing's generated colours are stale.
func _forget_masked_by(sprite_id: String) -> void:
	for id in pack.team_masks:
		if String(pack.team_masks[id].get("mask", "")) == sprite_id:
			pack.set_team_mask(String(id), pack.team_masks[id])


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return v if v is Dictionary else {}
