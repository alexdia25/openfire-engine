class_name VehiclePreviewPanel
extends HSplitContainer
## The mod tool's vehicle preview (EDITOR_PLAN.md 4.1, the start of phase E1): a vehicle put together exactly as the game
## does it -- a real `Vehicle` built from the pack's vehicle table, drawn by the game's own renderer
## (`VehicleRender3D.create_for`) -- on a turntable, in any team colour, with its moving parts posed by sliders.
##
## The Vehicle node is never added to the scene tree, so no simulation runs: the sliders set the same fields the game's
## simulation would (turret angle, gun elevation, rockets fired, rotor speed ...) and the renderer draws whatever they say.
## Once vehicle definitions and published channels exist (PORTING_PLAN.md 2.7.6 steps 3-5), these sliders become one per
## channel the definition's modules publish, and the stats come from the definition instead of the table.

const TICK_HZ := 62.5

var ws: ModWorkspace
var vehicle: Vehicle
var _render: Node3D
var _world: Node3D
var _camera: Camera3D
var _overlay: MeshInstance3D
var _overlay_mesh := ImmediateMesh.new()
var _type_pick: OptionButton
var _colour_pick: OptionButton
var _flash: CheckBox
var _spin: CheckBox
var _shape: CheckBox
var _sliders_box: VBoxContainer
var _stats: Label
var _yaw := 35.0
var _pitch := 38.0
var _distance := 90.0
var _dragging := false
var _colours: Array = []
var _retired: Array[Vehicle] = []   ## vehicles replaced by _rebuild(), freed next frame (their renderer may still hold them this one)


func setup(workspace: ModWorkspace) -> void:
	ws = workspace
	ws.changed.connect(_on_changed)
	_fill_pickers()
	_rebuild()


func _ready() -> void:
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 320
	add_child(left)
	_type_pick = _option(left, "Vehicle")
	_type_pick.item_selected.connect(func(_i): _rebuild())
	_colour_pick = _option(left, "Team colour")
	_colour_pick.item_selected.connect(func(_i): _rebuild())
	var toggles := HBoxContainer.new()
	left.add_child(toggles)
	_flash = _check(toggles, "Hit flash")
	_spin = _check(toggles, "Turntable")
	_shape = _check(toggles, "Collision shape")
	_shape.button_pressed = true
	_sliders_box = VBoxContainer.new()
	left.add_child(_sliders_box)
	left.add_child(HSeparator.new())
	_stats = Label.new()
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats.add_theme_font_size_override("font_size", 13)
	left.add_child(_stats)
	var hint := Label.new()
	hint.text = "Drag to orbit, wheel to zoom. Drawn by the game's own renderer; the sliders set the fields its simulation would."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(1, 1, 1, 0.55)
	left.add_child(hint)

	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.gui_input.connect(_orbit_input)
	add_child(container)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	container.add_child(vp)
	_world = Node3D.new()
	vp.add_child(_world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.2, 0.22, 0.25)
	_world.add_child(env)
	_camera = Camera3D.new()
	_camera.fov = 40.0
	_world.add_child(_camera)
	_world.add_child(_ground())
	_overlay = MeshInstance3D.new()
	_overlay.mesh = _overlay_mesh
	var om := StandardMaterial3D.new()
	om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	om.albedo_color = Color(0.3, 1.0, 0.5)
	om.no_depth_test = true
	_overlay.material_override = om
	_world.add_child(_overlay)


## A sand-coloured ground square with a one-tile (32 unit) grid, for scale.
func _ground() -> Node3D:
	var root := Node3D.new()
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(192, 192)
	plane.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.55, 0.45, 0.32)
	plane.material_override = mat
	root.add_child(plane)
	var grid := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(-3, 4):
		for pair in [[Vector3(i * 32, 0.05, -96), Vector3(i * 32, 0.05, 96)], [Vector3(-96, 0.05, i * 32), Vector3(96, 0.05, i * 32)]]:
			im.surface_add_vertex(pair[0])
			im.surface_add_vertex(pair[1])
	im.surface_end()
	grid.mesh = im
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(0.4, 0.32, 0.22)
	grid.material_override = gm
	root.add_child(grid)
	return root


func _option(parent: Control, label: String) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 100
	row.add_child(l)
	var o := OptionButton.new()
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(o)
	return o


func _check(parent: Control, text: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	parent.add_child(c)
	return c


func _fill_pickers() -> void:
	_type_pick.clear()
	for i in ws.pack.vehicle_order.size():   # the vehicle definitions, roster first (PORTING_PLAN 2.7.2)
		var def := ws.pack.vehicle_def(i)
		_type_pick.add_item("%s  (%s)" % [def.get("name", "?"), def.get("id", "")])
		_type_pick.set_item_metadata(_type_pick.item_count - 1, i)
	var keep := _colour_pick.get_item_text(_colour_pick.selected) if _colour_pick.selected >= 0 else "tan"
	_colour_pick.clear()
	_colours = ws.pack.team_colours.keys()
	_colours.sort_custom(func(a, b):
		var oa := ws.pack.is_original_colour(a)
		var ob := ws.pack.is_original_colour(b)
		return oa and not ob or (oa == ob and String(a) < String(b)))
	for c in _colours:
		_colour_pick.add_item(String(c))
		if String(c) == keep:
			_colour_pick.select(_colour_pick.item_count - 1)


func select_type(t: int) -> void:
	for i in _type_pick.item_count:
		if int(_type_pick.get_item_metadata(i)) == t:
			_type_pick.select(i)
	_rebuild()


func select_colour(colour: String) -> void:
	for i in _colour_pick.item_count:
		if _colour_pick.get_item_text(i) == colour:
			_colour_pick.select(i)
	_rebuild()


func _on_changed() -> void:
	var t := _type_pick.selected
	_fill_pickers()
	if t >= 0 and t < _type_pick.item_count:
		_type_pick.select(t)
	_rebuild()   # a colour, a frame or a pivot may have changed: build the vehicle again from the current pack


## Builds the vehicle and its renderer from scratch (type, colour or the pack changed).
func _rebuild() -> void:
	if ws == null or _type_pick.selected < 0:
		return
	var heading := vehicle.heading_deg if vehicle != null else 200.0
	if _render != null:
		_render.get_parent().remove_child(_render)   # out of the tree at once: it must not draw the old vehicle again
		_render.queue_free()
		_render = null
	if vehicle != null:
		_retired.append(vehicle)
	vehicle = Vehicle.new()
	vehicle.team = "tan"
	vehicle.colour = _colour_pick.get_item_text(_colour_pick.selected) if _colour_pick.selected >= 0 else "tan"
	vehicle.setup(ws.pack)
	vehicle.set_vehicle_type(int(_type_pick.get_item_metadata(_type_pick.selected)))
	vehicle.heading_deg = heading
	if vehicle.vehicle_type == 3:
		vehicle.heli_spinup_stage = 0   # show it flying; the start-up slider folds the blades back
		vehicle.rotor_speed_steps = 4.0
	_render = VehicleRender3D.create_for(vehicle, ws.pack, _world)
	_build_sliders()
	_update_stats()


func _build_sliders() -> void:
	for c in _sliders_box.get_children():
		c.queue_free()
	_slider("Heading (degrees)", 0.0, 360.0, vehicle.heading_deg, func(v): vehicle.heading_deg = v)
	match vehicle.vehicle_type:
		0:
			_slider("Turret angle (degrees)", -180.0, 180.0, 0.0, func(v): vehicle.turret_deg = fposmod(v, 360.0))
			_slider("Gun elevation (degrees)", 0.0, Vehicle.TANK_RAISE_DEG, 0.0, func(v): vehicle.gun_elev_deg = v)
		1:
			_slider("Wheel frame (distance driven)", 0.0, 3.99, 0.0, func(v): vehicle.position.x = v)
			_slider("Swim mode (0 wheels down, 1 swimming)", 0.0, 1.0, 0.0, func(v): vehicle.swim_amount = v)
		2:
			_slider("Launcher elevation (degrees)", 0.0, Vehicle.TANK_RAISE_DEG, 0.0, func(v): vehicle.gun_elev_deg = v)
			_slider("Rockets fired this salvo", 0.0, 2.0, 0.0, func(v): vehicle._salvo_index = int(v), 1.0)
			_slider("Reload (ticks left)", 0.0, 40.0, 0.0, func(v): vehicle._salvo_reload = v)
		3:
			_slider("Rotor speed (steps a tick)", 0.0, 4.0, 4.0, func(v): vehicle.rotor_speed_steps = v)
			_slider("Start-up: blades unfolding (1 = done)", 0.0, 1.0, 1.0, func(v):
				vehicle.heli_spinup_stage = 1 if v < 1.0 else 0
				vehicle._heli_spinup_progress = v)
			_slider("Height (units; hover is 50)", 0.0, Vehicle.HELI_CEILING, 0.0, func(v): vehicle.z = v)
			_slider("Forward speed (nose pitch)", -1.0, 1.05, 0.0, func(v): vehicle.speed = v * TICK_HZ)
			_slider("Bank (steps)", -3.0, 3.0, 0.0, func(v): vehicle.bank_steps = v)


func _slider(label: String, lo: float, hi: float, value: float, apply: Callable, step := 0.01) -> void:
	var l := Label.new()
	_sliders_box.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	var show := func(v: float): l.text = "%s: %s" % [label, snappedf(v, 0.01)]
	s.value_changed.connect(func(v):
		apply.call(v)
		show.call(v))
	show.call(value)
	apply.call(value)
	_sliders_box.add_child(s)


func _update_stats() -> void:
	var d := ws.pack.vehicle_def(vehicle.vehicle_type)
	var st: Dictionary = d.get("stats", {})
	var dr: Dictionary = d.get("drive", {})
	var ammo: Array = d.get("weapons", {}).get("ammo", [0, 0])
	var lines := [
		"%s  (%s)" % [d.get("name", "?"), d.get("id", "")],
		"hit points %s   armour %s   fuel %s   dock tolerance %s" % [st.get("hit_points"), snappedf(float(st.get("armor", 0.0)), 0.01),
				st.get("fuel"), st.get("dock_tolerance")],
		"forward %.2f / reverse %.2f units a tick   turn %.2f steps a tick" % [float(dr.get("max_forward_per_tick", 0.0)),
				absf(float(dr.get("max_reverse_per_tick", 0.0))), float(dr.get("turn_steps_per_tick", 0.0))],
		"ammunition %s / %s   parts %d   created sound %s" % [ammo[0], ammo[1], d.get("render", {}).get("parts", []).size(),
				d.get("events", {}).get("on_create", {}).get("sound", "none")],
		"(the vehicle definition; %s)" % d.get("_source", "")]
	_stats.text = "\n".join(lines)


func _process(delta: float) -> void:
	for v in _retired:
		v.free()
	_retired.clear()
	if vehicle == null:
		return
	if _spin.button_pressed:
		vehicle.heading_deg = fposmod(vehicle.heading_deg + 30.0 * delta, 360.0)
	vehicle.hit_flash_remaining = 1.0e9 if _flash.button_pressed else 0.0
	var target := Vector3(0.0, 6.0 + vehicle.z * 0.6, 0.0)
	var dir := Vector3(sin(deg_to_rad(_yaw)) * cos(deg_to_rad(_pitch)), sin(deg_to_rad(_pitch)), cos(deg_to_rad(_yaw)) * cos(deg_to_rad(_pitch)))
	_camera.position = target + dir * _distance
	_camera.look_at(target)
	_draw_shape()


## The collision polygon (from the vehicle table, turned with the heading) at the bottom and top of its z range.
func _draw_shape() -> void:
	_overlay_mesh.clear_surfaces()
	_overlay.visible = _shape.button_pressed
	if not _shape.button_pressed:
		return
	var poly := vehicle.polygon_for(vehicle.position, vehicle.heading_deg)
	if poly.size() < 2:
		return
	_overlay_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for zi in 2:
		var h := float(vehicle.hit_z[zi]) + vehicle.z + 0.1
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			_overlay_mesh.surface_add_vertex(Vector3(a.x, h, a.y))
			_overlay_mesh.surface_add_vertex(Vector3(b.x, h, b.y))
	for p in poly:
		_overlay_mesh.surface_add_vertex(Vector3(p.x, float(vehicle.hit_z[0]) + vehicle.z + 0.1, p.y))
		_overlay_mesh.surface_add_vertex(Vector3(p.x, float(vehicle.hit_z[1]) + vehicle.z + 0.1, p.y))
	_overlay_mesh.surface_end()


func _orbit_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(_distance / 1.15, 20.0)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(_distance * 1.15, 400.0)
	elif event is InputEventMouseMotion and _dragging:
		_yaw -= event.relative.x * 0.4
		_pitch = clampf(_pitch + event.relative.y * 0.3, 5.0, 89.0)


func _exit_tree() -> void:
	for v in _retired:
		v.free()
	_retired.clear()
	if _render != null:
		_render.free()
		_render = null
	if vehicle != null:
		vehicle.free()
		vehicle = null
