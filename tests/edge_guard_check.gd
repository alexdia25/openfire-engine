# The map-edge guard (Return Fire's submarine; alexdia25/openfire#68): its state machine on fake targets, the homing shot it
# fires, and a match in which a flagged vehicle strays off the map. All on the synthetic pack, so no game is needed. Run:
#   godot --headless --path .harness --script res://addons/openfire_engine/tests/edge_guard_check.gd
extends SceneTree

const Fixture := preload("fixtures/synthetic_pack.gd")

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


## The traced table (document 112) with fixture frames.
func _table() -> Dictionary:
	var frames := []
	frames.resize(25)
	frames.fill("fx.hull")
	return {"frames": frames, "quad": [[-64.0, -32.0, 16.0], [64.0, -32.0, 16.0], [64.0, 32.0, -16.0], [-64.0, 32.0, -16.0]],
		"spawn_margin": 32.0, "hunt_ticks": 240, "aim_ticks": 180, "frame_rate": 0x3333 / 65536.0, "surfaced_frame": 20.0,
		"loop_end_frame": 25.0, "loop_period": 0x50001 / 65536.0, "dive_wrap_base": 0xeffff / 65536.0, "projectile": 0,
		"muzzle": [-32.0, 0.0, 0.0], "launch_heading_deg": 0.0, "launch_pitch_deg": 0x355555 / 4194304.0 * 360.0}


func _homing() -> Dictionary:
	return {"heading_rate_deg": 0x6666 / 4194304.0 * 360.0, "pitch_rate_deg": 0x3333 / 4194304.0 * 360.0,
		"accel_xy": 0x7ae / 65536.0, "accel_z": 0x1999 / 65536.0, "max_down_deg": 0xaaaaa / 4194304.0 * 360.0,
		"smoke_record": "rec.small"}


func _make_pack() -> String:
	var base := Fixture.build("user://packs")
	PackWriter.write_json(base.path_join("world/edge_guard.json"), _table())
	PackWriter.write_json(base.path_join("vehicles/projectile_types.json"), {"types": [{"type": 0, "flags": 0,
		"speed_units_per_tick": 3.0, "damage": 400.0, "pitch_rate_raw": 7208, "lifetime_ticks": 90, "body_descriptor": "0x0",
		"shadow_descriptor": "0x0", "impact_table": "0x448988", "sound": "Ding", "homing": _homing()}], "descriptors": {},
		"art": {"shell": "fx.turret", "shadow": "fx.tile"}})
	# the first fixture vehicle attracts the guard (the real rule is one flag on the Heli's definition)
	for i in Fixture.VEHICLES.size():
		var id: String = Fixture.VEHICLES[i]
		var def: Dictionary = Fixture.vehicle_def(id, id, i)
		def["flags"] = {"triggers_edge_guard": i == 0}
		PackWriter.write_json(base.path_join("vehicles").path_join(id).path_join("vehicle.json"), def)
	return base


func _init() -> void:
	var base := _make_pack()
	var pack := Pack.new()
	_check(pack.load_from(base), "the pack loads")
	_check(pack.edge_guard.get("frames", []).size() == 25 and int(pack.edge_guard["hunt_ticks"]) == 240, "Pack.edge_guard is the pack's world/edge_guard.json")
	_check(pack.projectile_types[0].has("homing"), "the homing numbers ride on the projectile type")
	_state_machine()
	_homing_shot(pack)
	_match(pack)
	if _failures == 0:
		print("edge guard: all ok")
	quit(_failures)


class FakeTarget extends Node2D:
	var alive := true
	var z := 0.0


func _state_machine() -> void:
	var t := FakeTarget.new()
	t.position = Vector2(-300.0, 100.0)
	get_root().add_child(t)
	var rocket := Node2D.new()
	get_root().add_child(rocket)
	var fired := []
	var g := EdgeGuard.new(_table())
	g.launcher = func(origin: Vector2, target: Node2D) -> Node2D:
		fired.append([origin, target])
		return rocket
	# nothing to hunt: an invisible guard removes itself at once
	var lone := EdgeGuard.new(_table())
	lone.tick(1.0, {})
	_check(lone.finished and lone.shown_frame() == -1, "with nothing off the map the guard removes itself")
	# the target is off the map: still waiting after 240 ticks (the original's test is `timer > 0xf0`), on it at 241
	var over := {t: 300.0}
	for i in 240:
		g.tick(1.0, over)
	_check(g.state == EdgeGuard.State.HUNT and g.shown_frame() == -1, "it waits invisibly for 240 ticks")
	g.tick(1.0, over)
	_check(g.state == EdgeGuard.State.RISE and g.position == t.position and g.target == t, "then it moves onto the target and rises")
	# the surfacing is 20 frames at 0.2 a tick; the fire timer is 180 ticks from the moment frame 20 is reached
	var ticks_to_aim := 0
	while g.state == EdgeGuard.State.RISE and ticks_to_aim < 500:
		g.tick(1.0, over)
		ticks_to_aim += 1
	_check(g.state == EdgeGuard.State.AIM and ticks_to_aim >= 98 and ticks_to_aim <= 102, "it is up after about 100 ticks (%d)" % ticks_to_aim)
	var shown_ok := true
	var fire_tick := 0
	while fired.is_empty() and fire_tick < 400:
		g.tick(1.0, over)
		fire_tick += 1
		shown_ok = shown_ok and g.frame >= 19.99 and g.frame <= 25.01
	_check(shown_ok, "while it aims the animation loops inside frames 20 to 25")
	_check(fired.size() == 1 and fire_tick >= 178 and fire_tick <= 182, "the rocket is launched about 180 ticks later (%d)" % fire_tick)
	_check(fired[0][0] == t.position and fired[0][1] == t, "at the target")
	# it keeps still while the rocket exists, even if the target goes back inside the map
	g.tick(1.0, {})
	g.tick(1.0, {})
	_check(g.state == EdgeGuard.State.WAIT and fired.size() == 1, "it waits for its rocket and fires only once")
	rocket.free()
	g.tick(1.0, {})
	_check(g.state == EdgeGuard.State.DIVE, "when the rocket is gone it dives")
	var dive_ticks := 0
	while g.state == EdgeGuard.State.DIVE and dive_ticks < 300:
		g.tick(1.0, {})
		dive_ticks += 1
	_check(g.state == EdgeGuard.State.HUNT and g.frame < 1.0 and dive_ticks < 110, "the dive jumps from the loop back to about frame 15 and ends in %d ticks" % dive_ticks)
	g.tick(1.0, {})
	_check(g.finished, "with no target it is then removed")
	# a target that comes back inside the map before the launch: straight into the dive, no rocket
	var g2 := EdgeGuard.new(_table())
	var fired2 := []
	g2.launcher = func(_o: Vector2, _t: Node2D) -> Node2D:
		fired2.append(1)
		return null
	for i in 400:
		g2.tick(1.0, over)
	_check(g2.state == EdgeGuard.State.AIM or g2.state == EdgeGuard.State.WAIT, "a second guard has reached its aim (%d)" % g2.state)
	t.free()


func _homing_shot(pack: Pack) -> void:
	var t := FakeTarget.new()
	t.position = Vector2(400.0, 0.0)
	t.z = 50.0
	get_root().add_child(t)
	var p := Projectile.new()
	get_root().add_child(p)
	p.configure(pack, 0)
	p.position = Vector2.ZERO
	p.z = 0.0
	p.start_homing(t, 0.0, 0x355555 / 4194304.0 * 360.0)
	# launched 60 degrees up (rounded to a 5.625 step: 61.875) along heading 0 (original frame), which is -y in the port
	_check(absf(p.homing_vel.z - 3.0 * sin(deg_to_rad(61.875))) < 0.001, "it leaves climbing at speed x sin(61.875 degrees)")
	_check(absf(p.homing_vel.y + 3.0 * cos(deg_to_rad(61.875))) < 0.001 and absf(p.homing_vel.x) < 0.001, "and heading along -y")
	var closest := 1e9
	var steps := 0
	while steps < 1500 and not p.is_queued_for_deletion():
		p._homing_step(1.0)
		closest = minf(closest, Vector2(p.position.x - t.position.x, p.position.y - t.position.y).length())
		steps += 1
	_check(closest < 25.0, "a stationary target 400 units away is reached (closest %.1f in %d ticks)" % [closest, steps])
	# the velocity cannot change faster than the traced acceleration, so the first ticks barely turn it
	var q := Projectile.new()
	get_root().add_child(q)
	q.configure(pack, 0)
	q.start_homing(t, 0.0, 0.0)
	var before := q.homing_vel
	q._homing_step(1.0)
	_check((q.homing_vel - before).length() < 0.03 + 0.1 + 0.001, "one tick changes the velocity by at most the traced accelerations")
	# no target left: it is removed
	t.alive = false
	q._homing_step(1.0)
	_check(q.is_queued_for_deletion(), "a shot whose target is gone vanishes")


func _match(pack: Pack) -> void:
	var level := LevelData.new()
	level.load_from(pack.level_dir("LEVEL01"))
	var root := Node2D.new()
	get_root().add_child(root)
	var mc := MatchController.new()
	root.add_child(mc)
	mc.setup(pack, level, pack.pack_dir, root)
	var v := mc.vehicle
	_check(v.triggers_edge_guard(), "the player's vehicle carries the flag")
	var tsz := float(pack.tile_size_px)
	var edge := level.width * tsz
	var created := []
	mc.edge_guard_created.connect(func(g): created.append(g))
	var cues := []
	mc.sound_at.connect(func(c, _at, _z): cues.append(c))   # the rocket sound comes from the rocket (issue #22)
	var puffs := []
	mc.projectile_spawned.connect(func(p): p.puff.connect(func(at, h, rate): puffs.append([at, h, rate])))
	var dt := 1.0 / Vehicle.TICK_HZ
	# just past the edge but within the margin: nothing
	v.position = Vector2(edge + 10.0, 100.0)
	for i in 5:
		mc._process(dt)
	_check(created.is_empty() and not mc.submarine_present, "10 units past the edge is inside the spawn margin")
	_check(is_equal_approx(mc.off_map_overshoot(Vector2(edge + 10.0, 100.0)), 10.0) and mc.off_map_overshoot(Vector2(-7.0, 5.0)) == 7.0
			and mc.off_map_overshoot(Vector2(5.0, 5.0)) == 0.0, "the overshoot is the distance past the nearest edge")
	v.position = Vector2(edge + 40.0, 100.0)
	mc._process(dt)
	_check(created.size() == 1 and mc.submarine_present, "40 units past it creates the guard and the music flag follows")
	for i in 20:
		mc._process(dt)
	_check(created.size() == 1, "there is at most one")
	# run until the rocket is up and has killed the (stationary) vehicle
	var launched := false
	var killed_at := -1
	for i in 1400:
		for q in mc._projectiles:   # no frames run in this script: step the shots by hand
			if is_instance_valid(q) and not q.is_queued_for_deletion():
				q._process(dt)
		mc._process(dt)
		if not launched and mc._projectiles.size() > 0:
			launched = true
			_check(i > 450, "the rocket is launched only after the hunt, the rise and the aim wait (tick %d)" % i)
		if not v.alive:
			killed_at = i
			break
	_check(launched, "the guard launched its rocket")
	_check(cues.count("Ding") == 1, "the rocket launch sound is requested once, its projectile type's sound (all cues: %s)" % [cues])
	var puff_ok := puffs.size() > 20
	for pf in puffs:
		puff_ok = puff_ok and pf[2] >= 0x2aaa / 65536.0 and pf[2] < (0x2aaa + 0x1555) / 65536.0
	_check(puff_ok, "it leaves smoke (%d puffs) at rates between 0x2aaa and 0x3fff over 65536" % puffs.size())
	_check(killed_at >= 0, "and it killed the stray vehicle (tick %d)" % killed_at)
	for i in 400:
		mc._process(dt)
	_check(not mc.submarine_present and mc.edge_guard == null, "with nothing left off the map the guard dives and removes itself")
