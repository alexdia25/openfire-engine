# PackWriter.write_json() is lossless: every number a pack or mod file holds reads back exactly as written (a traced
# 16.16 fixed-point value like -0.59999084472656..., which 15 significant digits would round), keys come out sorted,
# and nulls survive. Run (see tests/README.md):
#   godot --headless --path .harness --script res://addons/openfire_engine/tests/pack_writer_check.gd
extends SceneTree

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _init() -> void:
	var path := "user://pack_writer_check/doc.json"
	# (not values like 123456789.12345679: the writer is exact there too, but Godot's own JSON parser misreads some
	# 17-digit numbers of that size -- a reader limit no pack value comes near; traced values are 16.16 fractions)
	var values := [-39321.0 / 65536.0, 1.0 / 3.0, 0.1, 4477016.0 / 65536.0, 1e-7, 3.0, 7]
	_check(PackWriter.write_json(path, {"b": values, "a": null}), "written")
	var text := FileAccess.get_file_as_string(path)
	var back: Dictionary = JSON.parse_string(text)
	var same := true
	for i in values.size():
		same = same and float(back["b"][i]) == float(values[i])
	_check(same, "every number reads back exactly: %s" % [back["b"]])
	_check(back.has("a") and back["a"] == null, "a null survives")
	_check(text.find("\"a\"") < text.find("\"b\""), "keys are sorted")

	print("pack_writer_check: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)
