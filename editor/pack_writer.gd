class_name PackWriter
extends RefCounted
## The inverse of Pack's loader for one layer (EDITOR_PLAN.md 3): writes a mod's own files, and nothing else. Only the
## tables the mod actually has are written; an empty table's file is removed so a layer never carries stale data.
## JSON is written with sorted keys and tab indents so a mod's files diff cleanly under version control.


static func write_json(path: String, data: Variant) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("PackWriter: cannot write %s (%s)" % [path, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(data, "\t", true) + "\n")
	return true


static func _write_or_remove(path: String, data: Dictionary, keep: bool) -> bool:
	if keep:
		return write_json(path, data)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return true


## Writes the layer at `dir`: pack.json, sprites/sprites.json (+ the pending loose frames, relative path -> Image),
## sprites/team_sets.json and teams/colours.json.
static func write_layer(dir: String, manifest: Dictionary, sprites: Dictionary, frames: Dictionary,
		team_pairs: Dictionary, team_masks: Dictionary, colours: Dictionary) -> bool:
	var ok := write_json(dir.path_join("pack.json"), manifest)
	for rel in frames:
		var path := dir.path_join("sprites").path_join(String(rel))
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		if (frames[rel] as Image).save_png(path) != OK:
			push_error("PackWriter: cannot write frame %s" % path)
			ok = false
	ok = _write_or_remove(dir.path_join("sprites/sprites.json"), {"atlas_pages": [], "sprites": sprites}, not sprites.is_empty()) and ok
	ok = _write_or_remove(dir.path_join("sprites/team_sets.json"), {"pairs": team_pairs, "masks": team_masks},
			not (team_pairs.is_empty() and team_masks.is_empty())) and ok
	ok = _write_or_remove(dir.path_join("teams/colours.json"), {"colours": colours}, not colours.is_empty()) and ok
	return ok
