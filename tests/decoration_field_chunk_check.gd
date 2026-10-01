# DecorationField3D batches decorations per CHUNK_TILES x CHUNK_TILES block instead of one mesh set for the whole level:
# destroying one tile's decoration used to rebuild every decoration on the map (a reported stutter on any destruction).
# refresh_tile() must touch only that tile's chunk. On the engine's synthetic fixture (LEVEL02: a decoration on every
# other tile, across four chunks). Moved from openfire's tools/tests (issue alexdia25/openfire#65). Run:
#   godot --headless --path .harness --script res://addons/openfire_engine/tests/decoration_field_chunk_check.gd
extends SceneTree

const Fixture := preload("fixtures/synthetic_pack.gd")

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _done(name: String) -> void:
	print("%s: %s" % [name, "PASS" if _failures == 0 else "%d FAILED" % _failures])
	quit(0 if _failures == 0 else 1)



func _init() -> void:
	var base := Fixture.build("user://packs")
	var pack := Pack.new()
	_check(pack.load_from(base), "the fixture loads")
	var level := LevelData.new()
	_check(level.load_from(pack.level_dir("LEVEL02")), "LEVEL02 loads")
	_check(level.decorations.size() >= 64, "it has a field of decorations (%d)" % level.decorations.size())

	var root := Node2D.new()
	get_root().add_child(root)
	var df := DecorationField3D.new()
	root.add_child(df)
	df.setup(pack, level)
	_check(df._chunks.size() == 4, "setup() split the 16 x 16 level into four chunks (%d)" % df._chunks.size())

	var entry: Dictionary = level.decorations[0]
	var tile := Vector2i(int(entry["x"]), int(entry["y"]))
	var key := df._chunk_key(tile.x, tile.y)
	var other_key: Vector2i = key
	for k in df._chunks:
		if k != key:
			other_key = k
			break
	var other_root: Node = df._chunks[other_key]
	var before: Node = df._chunks[key]
	level.set_coastal_id(tile.x, tile.y, 0)   # clear this one decoration, as _clear_tile_decoration does
	df.refresh_tile(tile)
	_check(is_instance_valid(other_root) and df._chunks[other_key] == other_root, "another chunk's own node is untouched (same instance)")
	_check(df._chunks.has(key) and df._chunks[key] != before, "the tile's own chunk was rebuilt")

	# clear every decoration in one chunk: an empty chunk builds nothing
	var target: Vector2i = df._indices_by_chunk.keys()[0]
	for i in df._indices_by_chunk[target]:
		var e: Dictionary = level.decorations[i]
		level.set_coastal_id(int(e["x"]), int(e["y"]), 0)
	var any: Dictionary = level.decorations[df._indices_by_chunk[target][0]]
	df.refresh_tile(Vector2i(int(any["x"]), int(any["y"])))
	_check(not df._chunks.has(target), "a chunk with every decoration cleared builds no meshes at all")
	df.refresh_tile(Vector2i(-999, -999))
	_check(df._chunks.size() == 3, "refreshing a tile outside any chunk is a no-op")
	_done("decoration_field_chunk_check")
