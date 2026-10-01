# The camera swoop-in's traced easing (document 90; CameraSwoop's header) and its setting. The only per-vehicle input
# is the target height a definition's camera.swoop_height gives; the original's table (0x4452c0) is -170 for the
# ground vehicles and -100 for the Heli, passed here directly, so no pack is needed. Moved from openfire's tools/tests
# (issue alexdia25/openfire#65). Run (see tests/README.md):
#   godot --headless --path .harness --script res://addons/openfire_engine/tests/camera_swoop_check.gd
extends SceneTree

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _init() -> void:
	for height in [-170.0, -100.0]:
		var sw := CameraSwoop.new(height)
		var arrived := -1
		var t := 0
		while not sw.done and t < 1000:
			sw.advance(1.0)
			t += 1
			if arrived < 0 and sw._height.value <= sw._height.target + 1.0:
				arrived = t
		_check(sw.done and sw.height_fraction() < 0.01, "to %s: the swoop finishes (tick %d) with the height arrived" % [height, t])
		if height == -170.0:
			_check(arrived > 195 and arrived < 215, "to -170 the height arrives in ~205 ticks, as traced (%d)" % arrived)

	var fast := CameraSwoop.new(-170.0)
	fast.advance(0.4)
	fast.advance(0.4)
	_check(fast.height_fraction() == 1.0, "0.8 ticks accumulated: no whole tick yet, still at the start")
	fast.advance(0.4)
	_check(fast.height_fraction() < 1.0 and fast.height_fraction() > 0.99, "1.2 ticks: one tick taken, just under 1.0")

	var keep := GameSettings.camera_swoop_in
	GameSettings.camera_swoop_in = false
	GameSettings.save_settings()
	GameSettings.camera_swoop_in = true
	GameSettings.load_settings()
	_check(not GameSettings.camera_swoop_in, "the setting round-trips through user://settings.cfg")
	GameSettings.camera_swoop_in = keep
	GameSettings.save_settings()

	print("camera_swoop_check: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)
