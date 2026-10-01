# The art the engine used to name itself now comes from the pack (alexdia25/openfire#67): the home pad's mechanism
# (terrain/home_pad.json -- pit walls, hazard strip, the lift plate and leaves per side, the dock-ready glow), the
# default projectile's shell and shadow (vehicles/projectile_types.json "art"), the classic HUD's panel frame
# (hud/panels.json "frame_sprite_id") and which tile art is a hole (terrain/tileset.json "hole"). A pack that has
# none of it draws none of it, without errors. Run (see tests/README.md):
#   godot --headless --path .harness --script res://addons/openfire_engine/tests/pack_art_tables_check.gd
extends SceneTree

const Fixture := preload("fixtures/synthetic_pack.gd")

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _match(pack: Pack) -> MatchController:
	var level := LevelData.new()
	level.load_from(pack.level_dir("LEVEL01"))
	level.side_colours = ["tan", "green"]
	var root := Node2D.new()
	get_root().add_child(root)
	var mc := MatchController.new()
	root.add_child(mc)
	mc.setup(pack, level, pack.pack_dir, root)
	return mc


func _pit(mc: MatchController, team: int) -> HangarPit3D:
	var pit := HangarPit3D.new()
	get_root().add_child(pit)
	pit.setup(mc, mc.pack)
	pit._build(team)
	return pit


func _init() -> void:
	var base := Fixture.build("user://packs")
	var pack := Pack.new()
	_check(pack.load_from(base), "the fixture loads")
	_check(pack.home_pad.get("hazard_strip") == "fx.turret" and pack.home_pad["pit_walls"].size() == 4, "Pack.home_pad is the pack's terrain/home_pad.json")
	_check(pack.projectile_art == {"shell": "fx.turret", "shadow": "fx.tile"}, "Pack.projectile_art is the projectile table's art")

	var mc := _match(pack)
	var tan_pit := _pit(mc, 0)
	_check(tan_pit._leaf_ids == [Fixture.TEAM_PAIR[0], Fixture.TEAM_PAIR[0]], "side 0's leaves are the pack's tan art: %s" % [tan_pit._leaf_ids])
	var green_pit := _pit(mc, 1)
	_check(green_pit._leaf_ids == [Fixture.TEAM_PAIR[1], Fixture.TEAM_PAIR[1]], "side 1's are the green")
	var drawn := 0
	for c in tan_pit.get_children():
		if c is MeshInstance3D and c.mesh != null:
			drawn += 1
	_check(drawn == 9, "four walls, the strip, the plate, both leaves and the strip over them are all drawn (%d)" % drawn)

	# a mod that removes every one of those tables: nothing is drawn, nothing fails
	var mod := ProjectSettings.globalize_path("user://pack_art_tables_check/bare")
	if DirAccess.dir_exists_absolute(mod):
		OS.move_to_trash(mod)
	PackWriter.write_json(mod.path_join("pack.json"), {"id": "bare", "name": "no pad art", "base_pack": Fixture.ID})
	PackWriter.write_json(mod.path_join("terrain/home_pad.json"), {"pit_walls": null, "hazard_strip": null, "lift_plate": null, "leaves": null, "dock_ready_glow": null})
	PackWriter.write_json(mod.path_join("vehicles/projectile_types.json"), {"art": {"shell": null, "shadow": null}})
	var bare := Pack.new()
	_check(bare.load_from(mod), "a pack without that art loads")
	_check(bare.home_pad.is_empty() and bare.projectile_art.is_empty(), "with empty tables")
	var bare_pit := _pit(_match(bare), 0)
	var none := 0
	for c in bare_pit.get_children():
		if c is MeshInstance3D and c.mesh != null:
			none += 1
	_check(none == 0 and bare_pit._leaf_ids == ["", ""], "its pit draws nothing")
	var glow := DockReadyIndicator3D.new()
	get_root().add_child(glow)
	glow.setup(_match(bare), bare)
	_check(true, "and the dock-ready glow sets up without one")

	print("pack_art_tables_check: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)
