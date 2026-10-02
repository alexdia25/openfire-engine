# A destroyed vehicle's wreck object (Return Fire's class 6 "Destroyed Vehicle"; alexdia25/openfire#29, wiki document 118) and the Heli's hit reaction
# (#70). The wreck's sequence on its own, with a fake water answer, then through a MatchController on the synthetic pack. Run:
#   godot --headless --path .harness --script res://addons/openfire_engine/tests/wreck_check.gd
extends SceneTree

const Fixture := preload("fixtures/synthetic_pack.gd")

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _land(_p: Vector2, _z: float) -> int:
	return 0


func _shallow(_p: Vector2, _z: float) -> int:
	return 1


func _deep(_p: Vector2, _z: float) -> int:
	return 2


func _info(extra := {}) -> Dictionary:
	var d := {"position": Vector2(100.0, 100.0), "heading_deg": -90.0, "team": "tan", "vehicle_type": 0, "z": 0.0, "speed": 0.0, "hp": 0.0,
		"fuel_out": false, "sink_depth": 14.0}
	d.merge(extra, true)
	return d


func _cfg() -> Dictionary:
	return {"friction": 0.1, "explosion": "boom", "gravity": 0x51e / 65536.0, "terminal_velocity": 1.0, "settle_ticks": 8, "lifetime_ticks": 720,
		"overkill_hp": -40.0, "landing_splash": "splash", "sink_splash": "sunk"}


## Runs `w` for `n` whole ticks; returns the effect records it played, in order, with the tick each came at.
func _run(w: Wreck, n: int, log := []) -> Array:
	for i in n:
		var before := log.size()
		w.tick(1.0)
		for j in range(before, log.size()):
			log[j]["tick"] = w.age
	return log


func _watch(w: Wreck, log: Array) -> void:
	w.effect.connect(func(record: String, at: Vector2): log.append({"record": record, "at": at}))


func _init() -> void:
	_dir()
	_stopped_on_land()
	_sliding()
	_fuel_out()
	_falling()
	_overkill_and_water()
	_hit_reaction()
	_in_a_match()
	print("wreck_check: %d failures" % _failures)
	quit(_failures)


func _dir() -> void:
	_check(Wreck.step_dir(0.0).is_equal_approx(Vector2(1, 0)) and Wreck.step_dir(-90.0).is_equal_approx(Vector2(0, -1)),
		"the heading rounds to one of 64 steps (0 = east here, -90 = north)")
	_check(Wreck.step_dir(2.0).is_equal_approx(Wreck.step_dir(0.0)) and not Wreck.step_dir(6.0).is_equal_approx(Wreck.step_dir(0.0)),
		"and rounds down (5.625 degrees a step)")


func _stopped_on_land() -> void:
	var w := Wreck.new(_info(), _cfg(), _land)
	var log := []
	_watch(w, log)
	_run(w, 1, log)
	_check(log.size() == 1 and log[0]["record"] == "boom" and log[0]["tick"] == 1, "the first tick plays the type's death explosion")
	_check(w.settled and w.phase == Wreck.Phase.BODY, "a wreck that was standing is settled at once and still shows the body")
	_run(w, 7, log)
	_check(w.phase == Wreck.Phase.BODY and not w.finished, "the body stays 8 ticks (FUN_0040cca0 waits for its counter to pass 7)")
	_run(w, 1, log)
	_check(w.phase == Wreck.Phase.DECAL and not w.finished, "then the descriptor is the decal")
	_run(w, 1, log)
	_check(w.mark and w.finished, "and the next tick the object becomes a Stay mark and is gone")
	_check(log.size() == 1, "nothing else was played")
	var crew := []
	var w2 := Wreck.new(_info(), _cfg(), _land)
	w2.crew_out.connect(func(_w): crew.append(1))
	_run(w2, 30)
	_check(crew.is_empty(), "no crewman: the vehicle did not run out of fuel")


func _sliding() -> void:
	var w := Wreck.new(_info({"speed": 1.0, "heading_deg": 0.0}), _cfg(), _land)
	_run(w, 1)
	_check(is_equal_approx(w.position.x, 101.0) and is_equal_approx(w.position.y, 100.0), "it drifts along its heading at the speed it died with")
	_check(not w.settled, "and is not settled while it moves")
	var steps := 0
	while not w.settled and steps < 40:
		_run(w, 1)
		steps += 1
	_check(steps <= 20 and absf(w.position.x - 113.5) < 0.01, "it keeps its speed for the 8 ticks FUN_0040cca0 waits (friction is the third behaviour's), then 0.1 a tick stops it: 13.5 units (%.2f)" % (w.position.x - 100.0))
	_check(w.z == 0.0, "on the ground it does not fall")
	var back := Wreck.new(_info({"speed": -0.5, "heading_deg": 0.0}), _cfg(), _land)
	_run(back, 20)
	_check(back.position.x < 100.0, "a reversing vehicle's wreck slides backwards")


func _fuel_out() -> void:
	var w := Wreck.new(_info({"fuel_out": true}), _cfg(), _land)
	var log := []
	var crew := []
	_watch(w, log)
	w.crew_out.connect(func(_w): crew.append(w.age))
	_run(w, 9, log)
	_check(log.is_empty(), "a vehicle that ran out of fuel dies silently (no death explosion)")
	_check(crew.is_empty(), "the crewman is not out in the first nine ticks")
	_run(w, 1, log)
	_check(crew == [10], "the crewman steps out on the tenth tick, once the wreck has settled and counted its 8 ticks")
	_run(w, 100)
	_check(crew.size() == 1, "only one")
	_check(w.phase == Wreck.Phase.BODY and not w.finished and not w.mark, "the hulk keeps the body's shape and stays")
	_run(w, 700)
	_check(w.finished and not w.mark, "and is removed once it is 720 ticks old, with no mark")


func _falling() -> void:
	var heli_cfg := _cfg()
	heli_cfg["friction"] = 0x7ae / 65536.0
	heli_cfg["mid_descriptor_is_decal"] = false
	var w := Wreck.new(_info({"vehicle_type": 3, "z": 50.0}), heli_cfg, _land)
	var log := []
	var debris := []
	_watch(w, log)
	w.debris.connect(func(_w): debris.append(w.age))
	var lowest := 0.0
	var prev := w.z
	var monotonic := true
	var landed_at := -1
	for i in 120:
		_run(w, 1, log)
		lowest = minf(lowest, w.vz)
		if w.z > prev + 1e-9:
			monotonic = false
		prev = w.z
		if landed_at < 0 and w.z <= 0.0:
			landed_at = w.age
	_check(lowest >= -1.0 - 1e-9 and is_equal_approx(lowest, -1.0), "it falls faster and faster up to 1.0 a tick and no faster")
	_check(monotonic and landed_at >= 74 and landed_at <= 77, "it lands after about 75 ticks from 50 units up (gravity 0x51e a tick: %d)" % landed_at)
	_check(log.size() == 2 and log[0]["tick"] == 1 and log[1]["tick"] == landed_at, "it plays the explosion when it is made and again when it lands")
	_check(debris == [landed_at], "and bursts into pieces once, on the landing (not built; the signal is there)")
	_check(w.mark or w.phase == Wreck.Phase.DECAL, "it lands as the decal")
	_check(w.z == 0.0, "and ends at height 0")
	var mid := Wreck.new(_info({"vehicle_type": 3, "z": 50.0}), heli_cfg, _land)
	_run(mid, 20)
	_check(mid.phase == Wreck.Phase.BODY, "a Heli keeps its body past the 8 ticks (its +0x160 is not the decal)")
	var tank := Wreck.new(_info({"vehicle_type": 0, "z": 0.5, "speed": 0.2}), _cfg(), _land)
	_run(tank, 12)
	_check(tank.phase == Wreck.Phase.DECAL, "the other types switch at 8 ticks even in the air")


func _overkill_and_water() -> void:
	var w := Wreck.new(_info({"hp": -50.0, "speed": 0.5}), _cfg(), _land)
	var log := []
	var debris := []
	_watch(w, log)
	w.debris.connect(func(_w): debris.append(1))
	_run(w, 1, log)
	_check(log.size() == 2 and debris.size() == 1 and w.phase == Wreck.Phase.DECAL,
		"a moving vehicle shot to below -40 hit points explodes twice at once, bursts, and is the decal at the first tick")
	var air := Wreck.new(_info({"hp": -50.0, "z": 40.0}), _cfg(), _land)
	var log5 := []
	_watch(air, log5)
	_run(air, 1, log5)
	_check(air.finished and not air.mark and log5.size() == 2, "an airborne one shot to below -40 bursts at once instead of falling intact (the object is removed: FUN_0040c8f0's `0 < z` branch)")
	var still := Wreck.new(_info({"hp": -50.0}), _cfg(), _land)
	var log2 := []
	_watch(still, log2)
	_run(still, 3, log2)
	_check(log2.size() == 1, "a standing one is settled first, so the landing bit is never reached")
	var wet := Wreck.new(_info({"hp": -50.0, "speed": 0.5}), _cfg(), _shallow)
	var log3 := []
	_watch(wet, log3)
	_run(wet, 1, log3)
	_check(wet.finished and not wet.mark and log3.size() == 3 and log3[2]["record"] == "splash", "over water the landing splashes and the wreck goes")
	var deep := Wreck.new(_info({"z": 0.0, "speed": 0.1, "sink_depth": 14.0}), _cfg(), _deep)
	var log4 := []
	_watch(deep, log4)
	_run(deep, 40, log4)
	_check(deep.sunk and deep.finished and log4.back()["record"] == "sunk", "over deep water it falls through the surface and sinks, with the sinking splash")


func _heli() -> Vehicle:
	var base := Fixture.build("user://packs")
	var pack := Pack.new()
	pack.load_from(base)
	var v := Vehicle.new()
	v.setup(pack)
	v.drive = VehicleModules.create("rotor", {})
	v.max_hp = 100.0
	v.hp = 100.0
	return v


func _hit_reaction() -> void:
	var v := _heli()
	v.heli_omega = 0.0
	v.heli_vel = Vector2(0.3, 0.3)
	_check(v.take_damage(1.0, -90.0), "the heli is hurt")
	_check(absf(v.heli_omega) <= 0.75 + 1e-6, "its spin is a new random value within +-0.75 steps a tick")
	var m := v.heli_vel.length()
	_check(m >= 0.25 - 1e-6 and m <= 0.75 + 1e-6, "a hit replaces its velocity with a push of 0.25 to 0.75 units a tick (%.3f)" % m)
	_check(v.heli_vel.x < 1e-6 and v.heli_vel.x > -1e-6 and v.heli_vel.y < 0.0, "along the hitter's heading step (north here)")
	var spins := {}
	var in_range := true
	for i in 30:
		v.take_damage(1.0, 0.0)
		spins[snappedf(v.heli_omega, 0.001)] = true
		in_range = in_range and absf(v.heli_omega) <= 0.75 + 1e-6
	_check(in_range and spins.size() > 5, "the spin is random each time and always in range")
	var east := v.heli_vel
	_check(east.x > 0.0 and absf(east.y) < 1e-6, "a hit heading 0 (east) pushes east")
	var keep := v.heli_vel
	v.take_damage(1.0)
	_check(v.heli_vel == keep, "a hit with no hitter leaves the velocity alone")
	var o := v.hp
	v.take_damage(0.0)
	_check(v.hp == o, "a hit that does no damage (not above the armour) does not react either")
	v.hp = 0.5
	v.heli_vel = Vector2(0.3, 0.3)
	v.take_damage(1.0, 0.0)
	_check(not v.alive and v.heli_vel == Vector2(0.3, 0.3), "a killing hit goes to the wreck instead")
	v.free()


func _in_a_match() -> void:
	var base := Fixture.build("user://packs")
	var pack := Pack.new()
	pack.load_from(base)
	var level := LevelData.new()
	level.load_from(pack.level_dir("LEVEL01"))
	var root := Node2D.new()
	get_root().add_child(root)
	var mc := MatchController.new()
	root.add_child(mc)
	mc.setup(pack, level, pack.pack_dir, root)
	var made: Array = []
	mc.wreck_created.connect(func(w): made.append(w))
	var effects: Array = []
	mc.impact_effect.connect(func(r, _p): effects.append(r))
	mc.vehicle.speed = 0.0
	mc.vehicle._die()
	_check(made.size() == 1 and mc.wrecks.size() == 1, "a vehicle's death makes a Wreck")
	for i in 20:
		mc._update_wrecks(1.0 / Vehicle.TICK_HZ)
	_check(effects == ["fx.boom"], "its death explosion is announced (%s)" % [effects])
	_check(mc.wrecks.is_empty() and made[0].mark, "and once it has become its mark the object is no longer ticked")
	print("wreck_check: match done")
