extends Node3D
## Phases 1-4 of the rendering-migration plan (PORTING_PLAN.md section 2.2, section 4 item
## 13): the new 3D scene. As of Phase 4 (2026-09-06) it is a complete rendering front-end for
## a match -- terrain (Phase 2), vehicles (Phase 3), and now projectiles/target-pool markers/
## the flag marker (Phase 4) -- all driven by the same game/match_controller.gd the flat 2D
## scene (game/terrain_view.gd) uses, so gameplay rules can't drift between the two front-ends.
## A Camera3D at the real, RE-confirmed fixed tilt (section 1.10 point 6 -- exactly 45 degrees,
## hardcoded once in RFIRE.BIN and never rewritten) translates in X/Z to follow the player
## Vehicle, edge-clamped to the level's real bounds and smoothed instead of snapping, over real
## baked terrain art.
##
## Per the "Superseded rule (2026-09-06, user direction)" in PORTING_PLAN.md section 2.2, the
## flat 2D scene no longer has to be kept working step-for-step while this one catches up --
## this file's Phase 4 completion is what finally makes game/terrain_view.gd/.tscn retirable.
##
## Deliberately NOT here yet:
## - (Resolved, document 43: FOV and height now come from the traced focal length of 300, see
##   CAMERA_HFOV_DEG below.)
## - Split-screen / 4-player (section 4 item 7); win/lose declaration and flag pickup/carry
##   (section 4 item 1) -- MatchController only implements the flag-spawn *trigger*, same as
##   the flat 2D scene always has.
##
## Degrees of freedom (user direction, 2026-09-06): tilt and zoom (height) are exposed as
## adjustable properties, not baked-in constants, so a future debug control or gameplay need
## can vary them -- even though RFIRE.BIN itself hardcodes both and never changes either
## (section 1.10 point 6). Rotation/yaw is NOT exposed at all, and never will be from this
## scaffolding: that absence isn't "unused so far," it's structural -- FUN_00408d60 (the real
## terrain blitter) has no rotation term to read in the first place, only the two fixed values
## reproduced below. Nothing in this file computes or applies a yaw angle anywhere.

## Section 1.10 point 6: RFIRE.BIN hardcodes this exactly once, in the shared object
## constructor, and never rewrites it. Kept adjustable here (not a const) so tilt can be
## tuned/animated later without changing this file -- the value below is just the default,
## matching the confirmed original.
@export var camera_tilt_deg: float = 45.0

## Default matches the placeholder noted above -- how high above the tracked point the camera
## sits, in the same pixel-as-Godot-unit scale the flat 2D scene already uses (tile_size_px
## etc). Doubles as the "zoom" control: lower = closer/more zoomed in, higher = further back.
## At a 45-degree tilt the horizontal pull-back needed to keep the tracked point centred on
## screen equals the height exactly (tan(45) == 1) -- if camera_tilt_deg is ever changed from
## 45, _camera_target_position()'s pull-back math below must change from a 1:1 ratio to
## height / tan(camera_tilt_deg).
@export var camera_height_px: float = 212.13

## Section 1.10 point 6: the original's perspective focal length (DAT_00443000) is exactly 300.0
## in native 320-px-wide screen units, i.e. a horizontal FOV of 2*atan(160/300). With that FOV
## and a camera 300 units from the target (height 300/sqrt(2) at the 45-degree tilt), 320 world
## px span the screen width -- matching the 1:1 native scale of the user's Win95 reference shots.
const CAMERA_HFOV_DEG := 56.63

## Same follow-smoothing speed terrain_view.gd's Camera2D uses (position_smoothing_speed)
## -- Camera3D has no built-in equivalent, so this scene hand-rolls the same exponential
## approach-to-target every frame.
const CAMERA_SMOOTHING_SPEED := 6.0

## The swoop-in when a vehicle leaves the base (document 90; game/camera_swoop.gd has the traced easing). The eased FRACTIONS (1 at the start, 0 at the end) are the
## original's; these two are how far they push the port's camera, PORT CHOICES read off the reference footage (the pad looks about four times smaller at the start, and
## the view is much more top-down) because the original's camera height/pitch units were not mapped onto this camera. Switch: GameSettings.camera_swoop_in.
const SWOOP_START_ZOOM := 4.0

## Godot's default near plane (0.05) spends nearly all the depth precision on the first few units in front of the camera, so the pad's layers (the ground, the leaves 0.1
## above it, the strip, the plate) z-fought as soon as the swoop put the camera far up. The camera is never closer than ~200 units to anything it draws.
const CAMERA_NEAR_PLANE := 10.0
const SWOOP_START_TILT_DEG := 70.0

@export var pack_path: String = "res://packs/original_pc"
@export var level_id: String = "RFMAP001"

var pack: Pack
var level: LevelData
var camera: Camera3D
var _swoop: CameraSwoop = null
var _was_rising := false
var controller: MatchController
var _gate_views: Dictionary = {}  ## Vector2i -> GateView3D
var billboard: Node3D                         ## player vehicle's 3D presentation -- VehicleBoxRender3D by default, VehicleBillboard3D if RF_DEBUG_VEHICLE_RENDER=billboard
var _enemy_billboards: Array = []             ## one per controller.enemy_vehicles, same type as billboard
var _map_size_px: Vector2 = Vector2.ZERO
var _terrain_vp: SubViewport
var _tile_renderer: TerrainTileRenderer
var _decoration_field: DecorationField3D
var _hud: PlaceholderHud                     ## port-only placeholder (document 66)
var _last_death_phase := 0                   ## debug print (RF_DEBUG_KILL)
var _sound: SoundManager                     ## document 82: plays the player vehicle's traced sound_cue signals


## Dev tool: `]` / PageDown loads the next level, `[` / PageUp the previous one (wrapping), by reloading the scene with that level id. Debug builds only. Survives the
## reload as a static, so the pack's level list is the only source of the order (Pack.list_levels(), sorted).
static var _dev_level_override := ""


func _ready() -> void:
	var level_env := OS.get_environment("RF_DEBUG_LEVEL")  # debug-only, e.g. RFMAP117
	if level_env != "":
		level_id = level_env
	if _dev_level_override != "":
		level_id = _dev_level_override
	# The original content plus the enabled mods on top (or RF_PACK for one run); a bad mod falls back to the original
	# (ModLoader, PORTING_PLAN 2.7.9).
	pack = ModLoader.load_game_pack(pack_path)
	if pack.layers.is_empty():
		push_error("TerrainView3D: failed to load pack at %s" % pack_path)
		return
	pack_path = pack.pack_dir   # the top layer actually loaded (the base, or the last enabled mod)

	level = LevelData.new()
	if not level.load_from(pack.level_dir(level_id)):
		push_error("TerrainView3D: failed to load level %s" % level_id)
		return

	# Team colours (PORTING_PLAN.md 2.7.7): RF_TEAM_COLOURS=red,blue (testing; later a level override or match setup)
	# recolours side 0 / 1; every generated sprite is made here, at map load, not mid-game.
	var colours_env := OS.get_environment("RF_TEAM_COLOURS")
	if colours_env != "":
		level.side_colours = Array(colours_env.split(","))
	pack.prepare_team_colours(level.side_colours)

	get_window().title = "Return Fire 3D scaffold -- %s (%s)" % [level.level_name, level_id]
	_map_size_px = Vector2(level.width, level.height) * pack.tile_size_px

	# Debug-only overrides for the two adjustable camera properties (tilt/zoom -- see the
	# file header's "degrees of freedom" note), so headless verification can try values other
	# than the defaults without editing this file. Never affects a normal run (env vars unset).
	var tilt_env := OS.get_environment("RF_DEBUG_CAMERA_TILT_DEG")
	if tilt_env != "":
		camera_tilt_deg = float(tilt_env)
	var height_env := OS.get_environment("RF_DEBUG_CAMERA_HEIGHT_PX")
	if height_env != "":
		camera_height_px = float(height_env)

	_build_terrain_ground()
	_build_decorations()
	_spawn_match()
	_build_light()
	GameSettings.load_settings()
	_build_camera()

	# Debug-only: RF_DEBUG_DESTROY_TILE="x,y" runs the same tile-destroyed step a projectile hit
	# on a pool's active target triggers, for before/after screenshots of the damaged state.
	var destroy_env := OS.get_environment("RF_DEBUG_DESTROY_TILE")
	if destroy_env != "":
		var dp := destroy_env.split(",")
		_on_target_hit("debug", Vector2i(int(dp[0]), int(dp[1])))

	var gate_env := OS.get_environment("RF_DEBUG_GATE")
	if gate_env != "" and controller != null:
		var gp := gate_env.split(",")
		controller.debug_open_gate(Vector2i(int(gp[0]), int(gp[1])))

	var screenshot_path := OS.get_environment("RF_DEBUG_SCREENSHOT")
	if screenshot_path != "":
		# RF_DEBUG_SCREENSHOT_WAIT_SELECTING=1: wait for the hangar/choice screen to actually open
		# before counting down, since autoplay's own timing to reach it varies run to run (real-time
		# physics, not a fixed tick count) -- a fixed frame delay alone can miss or overshoot it.
		if OS.get_environment("RF_DEBUG_SCREENSHOT_WAIT_SELECTING") == "1":
			while controller == null or not controller.selecting:
				await get_tree().process_frame
		# RF_DEBUG_SCREENSHOT_WAIT_DEATH=<phase> waits for the loss sequence (document 88) to reach that phase (with RF_DEBUG_KILL).
		var death_wait := OS.get_environment("RF_DEBUG_SCREENSHOT_WAIT_DEATH")
		if death_wait != "":
			while controller == null or controller.death_phase != int(death_wait):
				await get_tree().process_frame
		var wait_frames := 2
		var wait_env := OS.get_environment("RF_DEBUG_SCREENSHOT_DELAY_FRAMES")
		if wait_env != "":
			wait_frames = int(wait_env)
		for i in wait_frames:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(screenshot_path)
		get_tree().quit()


## Phase 2 of the rendering-migration plan (section 2.2, section 4 item 13): the real terrain
## art, not a placeholder colour -- game/terrain_tile_renderer.gd (Phase 2's extraction of
## terrain_view.gd's own tile-drawing loop, byte-for-byte unchanged) draws into a SubViewport
## at the level's native pixel resolution, and that viewport's texture becomes the ground
## plane's albedo. Godot's own camera then does the perspective projection on this baked
## texture -- no hand-ported scanline math, exactly the rationale section 2.2 recorded for
## choosing this architecture in the first place.
func _build_terrain_ground() -> void:
	_terrain_vp = SubViewport.new()
	var sub_vp := _terrain_vp
	sub_vp.size = Vector2i(int(_map_size_px.x), int(_map_size_px.y))
	# The terrain art never changes after a level loads (no animated tiles anywhere in this
	# project's tile pipeline) -- render once and stop, instead of re-drawing an identical
	# image every frame.
	sub_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	# document 89: the open home pad is a real hole in the ground (transparent tile art 92); every other tile has an opaque underlay
	# (TerrainTileRenderer), so only that tile becomes see-through under the alpha scissor below
	sub_vp.transparent_bg = true
	# incremental re-renders (TerrainTileRenderer.mark_tile): keep the previous contents, only redraw the tiles that changed. NEVER, not ONCE: ONCE clears again on every
	# later render. The first render draws an opaque underlay on every tile, so nothing depends on the initial contents.
	sub_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	add_child(sub_vp)

	_tile_renderer = TerrainTileRenderer.new()
	sub_vp.add_child(_tile_renderer)
	_tile_renderer.setup(pack, level)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	# Sized to the level's real world dimensions (plan section 2.2's own phrasing for this
	# step), matching the SubViewport's resolution exactly -- one texel per source pixel, no
	# stretching. NOTE (honest, not yet fixed): at this camera's height/tilt relative to a
	# 4096px map, near-horizontal rays can reach past this mesh's edge before hitting the
	# horizon, showing background void in a corner of the frame -- the same real, finite-mesh
	# artifact Phase 1 hit and deliberately routed around with an oversized placeholder plane.
	# Doing that here would mean texturing the overhang with something other than real terrain
	# (there is no real art beyond the level's actual bounds), so this phase accepts the
	# artifact rather than paper over it -- worth a skybox/fallback-colour backdrop in a later
	# pass, not a blocker for verifying the terrain projection itself.
	plane.size = _map_size_px
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = sub_vp.get_texture()
	# The source art is hard-edged pixel art (tools/convert_car.py's atlas, section 2.4.2) --
	# nearest filtering keeps tile edges crisp instead of linear-blurring them.
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	ground.material_override = mat
	# PlaneMesh is centred on its own origin; the 2D scenes place (0,0) at the level's
	# top-left corner with +X right/+Y down, so shift this node to match: world X -> node X,
	# world Y (2D "down") -> node Z ("forward").
	ground.position = Vector3(_map_size_px.x * 0.5, 0.0, _map_size_px.y * 0.5)
	add_child(ground)


## Document 40 follow-up: real Node3D decorations (game/decoration_field_3d.gd), not baked
## into the ground texture above -- see that file's header for why baking them flush with the
## dirt could never look like standing scenery, no matter how correct the camera projection is.
func _build_decorations() -> void:
	_decoration_field = DecorationField3D.new()
	add_child(_decoration_field)
	_decoration_field.setup(pack, level)


## Phases 3-4 of the rendering-migration plan (section 2.2, section 4 item 13): a real,
## unmodified MatchController (game/match_controller.gd -- the same gameplay logic
## game/terrain_view.gd's flat 2D scene uses, extracted so the two front-ends can't drift)
## drives vehicle/enemy spawn, firing, target pools, and the flag-spawn trigger. This function
## pairs each real gameplay node MatchController spawns (or signals) with its 3D presentation:
## Vehicle/EnemyVehicle -> VehicleBoxRender3D (document 37's real 6-face box, the default) or
## VehicleBillboard3D (the flat-card approximation, kept as a fallback --
## `RF_DEBUG_VEHICLE_RENDER=billboard`), Projectile -> ProjectileBillboard3D, FlagMarker ->
## FlagMarker3D (both Phase 4). If a level has no spawn points at all, controller.vehicle
## stays null and nothing here spawns a presentation for it -- matching terrain_view.gd's own
## "no spawn points" fallback.
func _spawn_match() -> void:
	controller = MatchController.new()
	add_child(controller)
	controller.setup(pack, level, pack_path, self)
	controller.projectile_spawned.connect(_on_projectile_spawned)
	controller.flag_spawned.connect(_on_flag_spawned)
	controller.target_hit.connect(_on_target_hit)
	controller.tile_destroyed.connect(_on_tile_destroyed)
	controller.pad_art_changed.connect(_on_pad_art_changed)
	controller.tile_crushed.connect(_on_tile_crushed)
	controller.gate_created.connect(_on_gate_created)
	controller.gate_removed.connect(_on_gate_removed)
	controller.impact_effect.connect(_on_impact_effect)
	controller.mine_added.connect(_on_mine_added)
	controller.mine_exploded.connect(_on_mine_exploded)
	for existing in controller.mines:   # the mines scattered at the start (document 75) were added before this connection
		_on_mine_added(existing)

	_sound = SoundManager.new()
	add_child(_sound)
	_sound.setup(pack)

	if controller.vehicle != null:
		billboard = _spawn_vehicle_render(controller.vehicle)
		controller.vehicle.type_changed.connect(_on_player_type_changed)
		_sound.connect_vehicle(controller.vehicle)
		var dock_light := DockReadyIndicator3D.new()
		add_child(dock_light)
		dock_light.setup(controller, pack)
		var pit := HangarPit3D.new()
		add_child(pit)
		pit.setup(controller, pack)
		var start_type: int = ["tank", "jeep", "msv", "heli"].find(OS.get_environment("RF_VEHICLE"))
		if start_type > 0:
			controller.vehicle.set_vehicle_type(start_type)
	controller.match_over.connect(_on_match_over)
	controller.out_of_vehicles.connect(func(): if _hud != null: _hud.show_lost())
	if controller.vehicle != null:
		_hud = PlaceholderHud.new()
		add_child(_hud)
		_hud.setup(controller)
		if OS.get_environment("RF_DEBUG_AUTOPLAY") == "1":
			var ap := DebugAutoplay.new()
			add_child(ap)
			ap.setup(controller)
	# Debug-only: RF_DEBUG_SWIM=<0..1> fixes the Jeep's swim immersion for screenshots.
	if OS.get_environment("RF_DEBUG_SWIM") != "" and controller.vehicle != null:
		controller.vehicle.swim_target = float(OS.get_environment("RF_DEBUG_SWIM"))
		controller.vehicle.swim_amount = controller.vehicle.swim_target
	# Debug-only: RF_DEBUG_TURRET=<degrees> and RF_DEBUG_ELEV=<0..25> set the Tank's turret angle and gun elevation.
	if controller.vehicle != null:
		if OS.get_environment("RF_DEBUG_TURRET") != "":
			controller.vehicle.turret_deg = float(OS.get_environment("RF_DEBUG_TURRET"))
			controller.vehicle._turret_target = controller.vehicle.turret_deg
		if OS.get_environment("RF_DEBUG_ELEV") != "":
			controller.vehicle.gun_elev_deg = float(OS.get_environment("RF_DEBUG_ELEV"))
			controller.vehicle._gun_target = controller.vehicle.gun_elev_deg
	# Debug-only: RF_DEBUG_FLAG=ground|carry spawns a flag next to the player (for screenshots); `carry` also hangs it on the player.
	if OS.get_environment("RF_DEBUG_FLAG") != "" and controller.vehicle != null:
		controller._spawn_flag("b", controller.vehicle.position + Vector2(60.0, 0.0))
		if OS.get_environment("RF_DEBUG_FLAG") == "carry":
			controller.flags[1].position = controller.vehicle.position
			controller._attach_flag(controller.flags[1], controller.vehicle)
	# Debug-only: RF_DEBUG_SELECT=1 opens the vehicle-choice grid at the start, cursor on Jeep (for screenshots);
	# RF_DEBUG_SELECT_TYPE=0-3 additionally moves the cursor from Tank to that type (0 Tank, 1 Jeep, 2 MSV, 3 Heli).
	if OS.get_environment("RF_DEBUG_SELECT") == "1" and controller.vehicle != null:
		controller.switch_player_vehicle()
		var moves := {0: [], 1: [1], 2: [1, 2], 3: [2]}   # from Tank: down->Jeep, down+left->MSV, left->Heli
		var want := int(OS.get_environment("RF_DEBUG_SELECT_TYPE")) if OS.get_environment("RF_DEBUG_SELECT_TYPE") != "" else 1
		for d in moves.get(want, [1]):
			controller.select_move(d)
	# Debug-only: RF_DEBUG_SELECT_CONFIRM=<frame> confirms the choice at that process frame (with RF_DEBUG_SELECT=1), for screenshots of the confirm script.
	# Debug-only: RF_DEBUG_SELECT_MAP=1 opens the map window.
	if OS.get_environment("RF_DEBUG_SELECT_MAP") == "1" and controller.vehicle != null:
		controller.toggle_map()
	# Debug-only: RF_DEBUG_FLASH=1 holds the player in the hit-flash variant for screenshots.
	if OS.get_environment("RF_DEBUG_FLASH") == "1" and controller.vehicle != null:
		controller.vehicle.hit_flash_remaining = 99.0
	# Debug-only: RF_DEBUG_DOCK=1 places the vehicle on its own pad centre, for screenshots of the docking sink (with RF_DEBUG_FIRE=1 to trigger it).
	if OS.get_environment("RF_DEBUG_DOCK") == "1" and controller.vehicle != null:
		var t := Vector2i(int(floor(controller.vehicle.position.x / pack.tile_size_px)), int(floor(controller.vehicle.position.y / pack.tile_size_px)))
		controller.vehicle.position = (Vector2(t) + Vector2(0.5, 0.5)) * pack.tile_size_px

	for enemy in controller.enemy_vehicles:
		_enemy_billboards.append(_spawn_vehicle_render(enemy))
		enemy.wrecked.connect(_on_vehicle_wrecked)
		enemy.drowned.connect(_on_vehicle_drowned)
	if controller.vehicle != null:
		controller.vehicle.wrecked.connect(_on_vehicle_wrecked)
		controller.vehicle.drowned.connect(_on_vehicle_drowned)
		# Debug-only: RF_DEBUG_WRECK=1 drops one wreck of each vehicle type (falling from height for
		# the Heli) next to the player for screenshots.
		if OS.get_environment("RF_DEBUG_WRECK") == "1":
			for i in 4:
				var w := Wreck3D.new()
				add_child(w)
				var h := 60.0 if i == 3 else 0.0
				w.setup(pack, ["tan", "green", "tan", "green"][i], controller.vehicle.position + Vector2(-105.0 + i * 70.0, 40.0), 30.0, i, h)

	# Debug-only: RF_DEBUG_MARKERS=1 shows the spawn/candidate debug markers (none of it real art,
	# see debug_marker_renderer.gd's header). Off by default (flipped from the old opt-out
	# RF_DEBUG_NO_MARKERS=1): document 80 found the home tile's real art (cels 90/91, an animated
	# hangar hatch) was sitting the whole time underneath this overlay's beige spawn circle.
	if OS.get_environment("RF_DEBUG_MARKERS") == "1":
		var overlay := DebugMarkerOverlay3D.new()
		add_child(overlay)
		overlay.setup(pack, level, controller)


## Debug-only fallback to the flat-card GROUND_DECAL approximation
## (`RF_DEBUG_VEHICLE_RENDER=billboard`), kept for comparison now that document 37's real
## 6-face box (VehicleBoxRender3D) is the default -- never affects a normal run (env var
## unset). Returns the spawned node (typed Node3D, since the two classes don't share a
## common base beyond that).
## The player switched type: replace its 3D presentation (the Tank's box renderer or the generic descriptor one).
func _on_player_type_changed(v: Vehicle) -> void:
	if billboard != null and is_instance_valid(billboard):
		billboard.queue_free()
	billboard = _spawn_vehicle_render(v)


## The match ended (document 57): a placeholder banner (the original fades to its score screen).
func _on_match_over(winner_idx: int) -> void:
	if _hud != null:
		_hud.show_win(winner_idx)


func _spawn_vehicle_render(v: Vehicle) -> Node3D:
	if v.vehicle_type == 0:
		if not v.shot.is_connected(_on_muzzle_flash.bind(v)):  # a type swap builds a new renderer for the same vehicle
			v.shot.connect(_on_muzzle_flash.bind(v))
		if OS.get_environment("RF_DEBUG_VEHICLE_RENDER") == "billboard":
			var b := VehicleBillboard3D.new()
			add_child(b)
			b.setup(v, pack)
			return b
	return VehicleRender3D.create_for(v, pack, self)


## The Tank's muzzle flash (document 52): record 0x445138, spawned by the fire handler FUN_0040d240 attached
## to the vehicle at the muzzle (12 units ahead, 7 up -- plus the box render's own ground clearance, so it
## sits on the barrel's drawn tip) and following it while it plays.
func _on_muzzle_flash(spec: Dictionary, v: Vehicle) -> void:
	if not spec.has("flash"):
		return  # the Jeep's missile has a sound but no flash record
	var f: Dictionary = spec["flash"]
	var o: Vector3 = f["offset"]
	ExplosionEffect3D.spawn_attached(self, pack, pack.get_explosion(String(f["record"])), v,
			Vector3(o.x, o.y, o.z + VehicleBoxRender3D.GROUND_CLEARANCE_PX), float(f.get("yaw", 0.0)))


## A destroyed vehicle leaves its wreck (game/wreck_3d.gd, documents 48/87), falling from its
## death height rather than appearing on the ground at once. `info` is `Vehicle._die()`'s snapshot,
## taken before a respawn can reset the same node's fields (the player's vehicle is reused, not
## replaced, between lives).
func _on_vehicle_wrecked(info: Dictionary) -> void:
	var w := Wreck3D.new()
	add_child(w)
	w.setup(pack, String(info.get("colour", info["team"])), info["position"], info["heading_deg"], info["vehicle_type"], info["z"])


func _on_projectile_spawned(projectile: Projectile) -> void:
	var pb := ProjectileBillboard3D.new()
	add_child(pb)
	pb.setup(projectile, pack)


## A pool's active target ran out of hit points: the tile becomes its coastal entry's destroyed
## state (document 44: candidate building 22 -> 62, ground art 109 -> 110), exactly what
## FUN_0042e6a0 does in the original -- the decoration changes to the damaged building and the
## ground art underneath is re-baked. One hit is enough (the weapon-damage-vs-hit-points model,
## and the second stage 62 -> 63, are not traced yet).
func _on_target_hit(_pool_id: String, tile: Vector2i) -> void:
	# The explosion the tile's coastal entry names (document 50: field +0x2c) plays where the tile stood,
	# and the tile only changes state when its script reaches TILE_STATE (FUN_0042e6a0 returns at once
	# when it spawned one, FUN_0042e600 does the change); the tile's own offset callback (jitter) is not
	# applied. A coastal id without an effect changes immediately.
	var coastal_id := level.get_coastal_id(tile.x, tile.y)
	var centre := (Vector2(tile) + Vector2(0.5, 0.5)) * pack.tile_size_px
	var fx := ExplosionEffect3D.spawn(self, pack, pack.get_destroy_effect(coastal_id), centre)
	if fx == null:
		_apply_tile_destroyed(tile, coastal_id)
	else:
		fx.tile_cleared.connect(_clear_tile_decoration.bind(tile))
		fx.tile_state.connect(_apply_tile_destroyed.bind(tile, coastal_id))


## A vehicle flattened the tile (document 54): the bush callback (FUN_00436640) swaps in the entry's second
## effect record (`coastal_crush_effect`, script WAIT 1 / DRAW_LIST 7 / TILE_STATE) and sets the tile's variant
## bits to 1; the crate callback (FUN_00436a50) uses the ordinary destroy effect.
func _on_tile_crushed(tile: Vector2i) -> void:
	var coastal_id := level.get_coastal_id(tile.x, tile.y)
	var centre := (Vector2(tile) + Vector2(0.5, 0.5)) * pack.tile_size_px
	var record := pack.get_crush_effect(coastal_id)
	if not record.is_empty():
		level.set_variant(tile.x, tile.y, 1)
	else:
		record = pack.get_destroy_effect(coastal_id)
	var fx := ExplosionEffect3D.spawn(self, pack, record, centre)
	if fx == null:
		_apply_tile_destroyed(tile, coastal_id)
	else:
		fx.tile_cleared.connect(_clear_tile_decoration.bind(tile))
		fx.tile_state.connect(_apply_tile_destroyed.bind(tile, coastal_id))


## A team gate (document 56): the tile's decoration is gone while the gate object draws itself and slides.
func _on_gate_created(g: Gate) -> void:
	var view := GateView3D.new()
	add_child(view)
	view.setup(pack, g)
	_gate_views[g.tile] = view
	_decoration_field.refresh()


func _on_gate_removed(g: Gate) -> void:
	var view: Node = _gate_views.get(g.tile)
	if view != null:
		view.queue_free()
		_gate_views.erase(g.tile)
	_decoration_field.refresh()


## The home pad swapped between its hatch art and the transparent hole (document 89): the level's art grid was already changed by MatchController.
func _on_pad_art_changed(tile: Vector2i) -> void:
	_tile_renderer.mark_tile(tile)
	_terrain_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _on_tile_destroyed(tile: Vector2i) -> void:
	_on_target_hit("", tile)


## FUN_0042e600 / the tail of FUN_0042e6a0 (document 53): the destroyed tile takes the coastal entry's
## result. With a destroyed coastal id it becomes that id (FUN_0042e4f0: its ground art unless the entry's
## art is 0xFF "keep", plus the tile's team variant when the entry's flags are exactly 8), else it loses its
## decoration; the entry's own art byte, plus a random 0..1 or 0..3 when its flags have bit 1 or bit 2, then
## sets the ground art. The tile's hit points restart from the new entry (the controller reads them lazily).
## Op 21 of a bush/palm collapse script (FUN_0042d9f0): the decoration is gone at once.
func _clear_tile_decoration(tile: Vector2i) -> void:
	level.set_coastal_id(tile.x, tile.y, 0)
	_decoration_field.refresh()


func _apply_tile_destroyed(tile: Vector2i, coastal_id: int) -> void:
	var e := pack.get_coastal_damage(coastal_id)
	var flags := int(e.get("flags", 0))
	var variation := 0
	if flags & 4:
		variation = randi() % 4
	elif flags & 2:
		variation = randi() % 2
	var next_id := int(e.get("destroyed_coastal", 0))
	var offset := int(e.get("destroyed_art_offset", 0))
	var art := level.get_art_id(tile.x, tile.y)
	if next_id == 0:
		level.set_coastal_id(tile.x, tile.y, 0)
		art = (offset + variation) & 0x7F
	else:
		var ne := pack.get_coastal_damage(next_id)
		var base := int(ne.get("base_art", 255))
		if base != 255:
			art = base
			if int(ne.get("flags", 0)) == 8:
				art += level.get_variant(tile.x, tile.y)
		level.set_coastal_id(tile.x, tile.y, next_id)
		if offset != 0:
			art = (offset + variation) & 0x7F
	level.set_art_id(tile.x, tile.y, art)
	controller.tile_state_applied(tile)
	_decoration_field.refresh()
	_tile_renderer.mark_tile(tile)
	_terrain_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


## A projectile hit something (document 50: surface 3 = an object, 4 = a tile): its type's impact table
## names the record -- `0x444b68` / `0x444ac8` for every type -- played where the shot ended.
func _on_impact_effect(record_addr: String, at: Vector2) -> void:
	ExplosionEffect3D.spawn(self, pack, pack.get_explosion(record_addr), at)


## A vehicle sank in deep water (FUN_0040cf90): no wreck, just the splash record 0x444ee8 where it went down.
func _on_vehicle_drowned(v: Vehicle) -> void:
	ExplosionEffect3D.spawn(self, pack, pack.get_explosion("0x444ee8"), v.position)


func _on_mine_added(m: Mine) -> void:
	var mv := MineView3D.new()
	add_child(mv)
	mv.setup(m, pack)


## A mine went off: its explosion (record 0x445058; the damage box is the controller's).
func _on_mine_exploded(at: Vector2) -> void:
	ExplosionEffect3D.spawn(self, pack, pack.get_explosion("0x445058"), at)


func _on_flag_spawned(flag: FlagMarker, _pool_id: String) -> void:
	var fb := FlagMarker3D.new()
	add_child(fb)
	fb.setup(flag, pack)


## Placeholder-only stand-in for real level lighting (not an RE finding -- RFIRE.BIN's own
## lighting model, if any, hasn't been investigated). Without this every StandardMaterial3D
## surface renders pure black; a single fixed directional light is enough for Phase 1's own
## purpose (confirm the camera geometry looks right), nothing more.
func _build_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.light_energy = 1.1
	add_child(sun)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = CAMERA_HFOV_DEG
	camera.near = CAMERA_NEAR_PLANE
	add_child(camera)
	_apply_tilt()
	_place_camera_immediately()
	camera.current = true


## Sets the camera's *entire* orientation, always, from camera_tilt_deg alone -- rotation.y
## (yaw) and rotation.z (roll) are never touched anywhere in this file, not just left at their
## default. This is the actual mechanism behind the file header's "tilt and zoom, not rotate"
## rule: an earlier version of this function used look_at() aimed at the tracked object
## instead, which seemed simpler (it sidesteps ever having to hand-derive Godot's
## rotation-axis sign convention) but was wrong -- look_at() implicitly introduces yaw
## whenever the camera's clamped position drifts off-axis from the tracked point (verified by
## driving straight to a map edge: the clamp holds the camera's X still while the tracked box
## keeps moving, and the box visibly stayed centred on screen instead of sliding off -- the
## camera was quietly panning to compensate, which is exactly the rotation this scaffolding
## must not do). Re-called every frame; cheap, and correct even if camera_tilt_deg changes
## live. rotation_degrees.x = -camera_tilt_deg was verified empirically (screenshot) to tilt
## the view down toward the ground, not up and away from it.
func _apply_tilt(tilt_deg: float = camera_tilt_deg) -> void:
	camera.rotation_degrees = Vector3(-tilt_deg, 0.0, 0.0)
	camera.fov = _layout_fov_deg()


func _place_camera_immediately() -> void:
	camera.position = _camera_target_position(_camera_track_position())


## The point the camera follows: the player vehicle's real position, or -- matching
## terrain_view.gd's own "no spawn points" fallback -- the map centre if MatchController never
## spawned one (RFMAP001, the default level, always has spawn points; this only matters for a
## level file that doesn't).
func _camera_track_position() -> Vector2:
	# Debug-only: RF_DEBUG_FOCUS_TILE="x,y" points the camera at a tile centre instead of the
	# vehicle, for comparing a specific spot against reference shots.
	var focus := OS.get_environment("RF_DEBUG_FOCUS_TILE")
	if focus != "":
		var parts := focus.split(",")
		return (Vector2(float(parts[0]), float(parts[1])) + Vector2(0.5, 0.5)) * pack.tile_size_px
	if controller != null and controller.vehicle != null:
		return controller.vehicle.position
	return _map_size_px * 0.5


## Same X/Z position a fully-smoothed camera converges to for a given tracked-point position:
## directly above-and-behind by however far camera_height_px and camera_tilt_deg say the
## pull-back needs to be to keep the tracked point centred on screen, then clamped so the
## camera itself never sits past the ground plane's real edges -- the 3D equivalent of
## terrain_view.gd's Camera2D limit_left/top/right/bottom. (Like that existing clamp, this
## means the tracked point stops being screen-centred near an edge -- consistent with, not a
## regression from, the flat scene's existing behaviour.) The margin reuses the pull-back
## distance as a placeholder stand-in for "however far the tilted view actually reaches,"
## which Phase 2's screenshot-matching will replace with a real derived value.
func _camera_target_position(look_at_px: Vector2, height_px: float = camera_height_px, tilt_deg: float = camera_tilt_deg) -> Vector3:
	var pull_back := height_px / tan(deg_to_rad(clampf(tilt_deg, 1.0, 89.0)))
	var margin := pull_back
	var desired_x := look_at_px.x
	var desired_z := look_at_px.y + pull_back
	var x := clampf(desired_x, margin, maxf(_map_size_px.x - margin, margin))
	var z := clampf(desired_z, margin, maxf(_map_size_px.y - margin, margin))
	return Vector3(x, height_px, z + _layout_shift_z(height_px, tilt_deg))


## The HUD layout's effect on the view (document 96). Classic: the game view is only the top 320 x 152 of the 4:3 picture, so the camera's horizontal field of view is widened
## so that the same width of world fits that rectangle as the modern layout fits in the whole window (PORT CHOICE; the original's camera scale is not mapped, document 90), and
## the camera is moved along the ground so the followed point lands at the rectangle's centre instead of the window's. Modern: the field of view and position are unchanged.
func _layout_fov_deg() -> float:
	if not HudLayout.is_classic():
		return CAMERA_HFOV_DEG
	var vp := get_viewport().get_visible_rect().size
	var view := HudLayout.view_rect(vp)
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(CAMERA_HFOV_DEG) * 0.5) * vp.x / view.size.x))


## Where the ground point seen along the view rectangle's vertical centre lies, relative to where the window centre's point lies (ground z, in pixels), for a camera at
## `height_px` tilted `tilt_deg` down: the ray through NDC y is (0, y * tan_v, -1) turned by the tilt about X and cut with the ground plane.
func _layout_shift_z(height_px: float, tilt_deg: float) -> float:
	if not HudLayout.is_classic():
		return 0.0
	var vp := get_viewport().get_visible_rect().size
	var view := HudLayout.view_rect(vp)
	var tan_v := tan(deg_to_rad(_layout_fov_deg()) * 0.5) * vp.y / vp.x   # KEEP_WIDTH: the vertical half-extent
	var ny := 1.0 - 2.0 * (view.position.y + view.size.y * 0.5) / vp.y
	var t := deg_to_rad(tilt_deg)
	var y0 := ny * tan_v
	var hit_centre := height_px * (-cos(t)) / sin(t)
	var hit_view := height_px * (-y0 * sin(t) - cos(t)) / (sin(t) - y0 * cos(t))
	return hit_centre - hit_view


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build() or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_BRACKETRIGHT, KEY_PAGEDOWN:
			_switch_level(1)
		KEY_BRACKETLEFT, KEY_PAGEUP:
			_switch_level(-1)
		KEY_H:   # dev: toggle the panel layout live (not saved; the setting is user://settings.cfg [hud] layout, or RF_HUD)
			GameSettings.hud_layout = HudLayout.MODERN if HudLayout.is_classic() else HudLayout.CLASSIC
			print("[dev] hud layout ", GameSettings.hud_layout)


func _switch_level(step: int) -> void:
	var ids := pack.list_levels()
	if ids.is_empty():
		return
	var i := ids.find(level_id)
	_dev_level_override = ids[posmod(i + step, ids.size())]
	print("[dev] level %s -> %s" % [level_id, _dev_level_override])
	get_tree().reload_current_scene()


func _process(delta: float) -> void:
	if camera == null:
		return
	if OS.get_environment("RF_DEBUG_SELECT_CONFIRM") != "" and controller != null and Engine.get_process_frames() == int(OS.get_environment("RF_DEBUG_SELECT_CONFIRM")):
		controller.confirm_selection()
	# Debug-only: RF_DEBUG_SWAP="frame:type,frame:type" swaps the player's vehicle at those frames (with
	# RF_DEBUG_DRIVE=1 this swaps while moving).
	if OS.get_environment("RF_DEBUG_SWAP") != "" and controller != null:
		for pair in OS.get_environment("RF_DEBUG_SWAP").split(","):
			var fp := pair.split(":")
			if int(fp[0]) == Engine.get_process_frames():
				controller.debug_swap_vehicle(int(fp[1]))

	# Debug-only: RF_DEBUG_KILL=<frame> kills the player at that process frame, for screenshots of the loss sequence (document 88).
	if OS.get_environment("RF_DEBUG_KILL") != "" and controller != null and controller.vehicle != null 			and Engine.get_process_frames() == int(OS.get_environment("RF_DEBUG_KILL")):
		controller.vehicle.hp = 0.5
		controller.vehicle.take_damage(100.0)
		if OS.get_environment("RF_DEBUG_KILL_SPEED") != "":
			Engine.time_scale = float(OS.get_environment("RF_DEBUG_KILL_SPEED"))  # (RF_DEBUG_KILL_SPEED=4 runs the sequence four times faster)

	if OS.get_environment("RF_DEBUG_KILL") != "" and controller != null and controller.death_phase != _last_death_phase:
		_last_death_phase = controller.death_phase
		print("[death] frame ", Engine.get_process_frames(), " phase -> ", _last_death_phase, " view_fade ", snappedf(controller.view_fade, 0.01))

	# Vehicle drives its own movement/input/firing entirely (its _process() runs
	# independently, same as in the flat 2D scene) -- this scene only needs to read the
	# result, exactly like terrain_view.gd's own Camera2D follow already does.
	var track_pos := _camera_track_position()
	var rising := controller != null and controller.pad_rising
	if rising and not _was_rising and GameSettings.camera_swoop_in and controller.vehicle != null:
		_swoop = CameraSwoop.new(controller.vehicle.vehicle_type)
	_was_rising = rising
	if _swoop != null:
		_swoop.advance(delta * Vehicle.TICK_HZ)
		var height_px := camera_height_px * lerpf(1.0, SWOOP_START_ZOOM, _swoop.height_fraction())
		var tilt_deg := lerpf(camera_tilt_deg, SWOOP_START_TILT_DEG, _swoop.pitch_fraction())
		camera.position = _camera_target_position(track_pos, height_px, tilt_deg)
		_apply_tilt(tilt_deg)
		if _swoop.done:
			_swoop = null
	else:
		var target_cam_pos := _camera_target_position(track_pos)
		camera.position = camera.position.lerp(target_cam_pos, 1.0 - exp(-CAMERA_SMOOTHING_SPEED * delta))
		_apply_tilt()

	if OS.get_environment("RF_DEBUG_CAMERA_LOG") == "1" and Engine.get_process_frames() % 30 == 0:
		print("frame=%d vehicle_pos=%s camera_pos=%s map_size=%s" % [
			Engine.get_process_frames(), track_pos, camera.position, _map_size_px])
