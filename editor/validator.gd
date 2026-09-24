class_name ModValidator
extends RefCounted
## The mod tool's live checks of the open mod (EDITOR_PLAN.md 3, "validation panel"): the manifest, every sprite the mod
## adds or replaces, its team masks, pairs and colours. Each finding is {level: "error"|"warning", message, sprite_id}
## (sprite_id "" when it isn't about one sprite), so the panel can jump to the cause.

const REQUIRED_PACK_FIELDS := ["id", "name", "version", "engine_api_version", "author", "license", "base_pack",
	"overrides", "pixels_per_world_unit"]


static func check(ws: ModWorkspace) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var add := func(level: String, message: String, sprite_id := "") -> void:
		out.append({"level": level, "message": message, "sprite_id": sprite_id})
	for f in REQUIRED_PACK_FIELDS:
		if not ws.manifest.has(f):
			add.call("error", "pack.json has no \"%s\"" % f)
	if String(ws.manifest.get("author", "")) == "" or String(ws.manifest.get("license", "")) == "":
		add.call("warning", "pack.json: author and license are empty (needed before sharing the mod)")
	var prefix := String(ws.manifest.get("id", "")) + "."
	for id in ws.mod_sprites:
		var e: Variant = ws.mod_sprites[id]
		if not ws.pack.sprites.has(id):
			add.call("error", "%s: the sprite does not load" % id, id)
			continue
		if e is Dictionary and e.has("file"):
			var path := ws.mod_dir.path_join("sprites").path_join(String(e["file"]))
			if not FileAccess.file_exists(path) and not ws._pending_frames.has(String(e["file"])):
				add.call("error", "%s: frame file %s is missing" % [id, e["file"]], id)
		var base_origin := ws._lower_sprite(String(id))
		if base_origin.is_empty() and not String(id).begins_with(prefix):
			add.call("warning", "%s: a new sprite outside the mod's own \"%s\" namespace" % [id, prefix], id)
	for id in ws.pack.team_masks:
		var def: Dictionary = ws.pack.team_masks[id]
		var mask := String(def.get("mask", ""))
		var a := ws.pack.get_sprite(String(id))
		var m := ws.pack.get_sprite(mask)
		if a.is_empty():
			add.call("error", "team mask set for %s, which does not exist" % id, String(id))
		elif m.is_empty():
			add.call("error", "%s: its team mask %s does not exist" % [id, mask], String(id))
		elif int(a["w"]) != int(m["w"]) or int(a["h"]) != int(m["h"]):
			add.call("error", "%s: team mask %s is %dx%d, the drawing %dx%d" % [id, mask, m["w"], m["h"], a["w"], a["h"]], String(id))
		var drawn := String(def.get("drawn_as", ""))
		if drawn != "" and not ws.pack.team_colours.has(drawn):
			add.call("error", "%s: drawn_as \"%s\" is not a colour" % [id, drawn], String(id))
	for tan in ws.mod_pairs:
		var a := ws.pack.get_sprite(String(tan))
		var b := ws.pack.get_sprite(String(ws.mod_pairs[tan]))
		if a.is_empty() or b.is_empty():
			add.call("error", "team pair %s / %s: a sprite does not exist" % [tan, ws.mod_pairs[tan]], String(tan))
		elif int(a["w"]) != int(b["w"]) or int(a["h"]) != int(b["h"]):
			add.call("error", "team pair %s / %s: sizes differ" % [tan, ws.mod_pairs[tan]], String(tan))
	for c in ws.mod_colours:
		var hsv: Variant = ws.mod_colours[c].get("hsv") if ws.mod_colours[c] is Dictionary else null
		if not (hsv is Array and hsv.size() == 3):
			add.call("error", "colour %s has no [hue, saturation, value]" % c)
	if ws.is_dirty():
		add.call("warning", "there are unsaved changes")
	return out
