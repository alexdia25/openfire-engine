class_name DockReadyIndicator3D
extends Node3D
## The original's own "you're in position to dock" signal: `FUN_0040b400`, called once a tick only while a vehicle sits
## still on its own pad within the docking tolerance and is NOT pressing a fire button (document 80, Step 2).
##
## Document 80's Addendum 3 chased what it actually draws (its palette-rotate half, Addendum 1, touches no real on-screen
## art and remains unaccounted for -- not modelled here). The SAME function also writes decoration id 89 into the home
## pad tile's own coastal-decoration field for as long as the vehicle sits ready -- the exact mechanism document 35
## already traced for placing bushes and saplings near the coast -- which queues a real object at the pad's tile centre
## every frame: cel 1778 / `effect.glow.001`, one of the two real `PRE0=5` background-recolour glow masks in the whole
## game (the hangar cursor's own spotlight, `effect.glow.002`, is the other -- issue #64). This node draws exactly that:
## the real glow sprite, through the same generic background-recolour blend shader, sized to its own pixel dimensions in
## world units (this project's 1-native-pixel-per-world-unit convention, matching every other traced 3D quad). No colour
## animation: the original's decoration system draws a static part, not an animated one -- the real effect's "9.1 steps a
## second" belongs entirely to the untraced palette rotate, not to this.

const SHADER := preload("res://addons/openfire_engine/game/shaders/background_recolour_3d.gdshader")

var mc: MatchController
var _quad: MeshInstance3D


func setup(controller: MatchController, pack: Pack) -> void:
	mc = controller
	var s := pack.get_sprite(String(pack.home_pad.get("dock_ready_glow", "")))   # the pack's own glow (terrain/home_pad.json)
	if s.is_empty():
		return
	var recolour_step := float(s.get("recolour_step", 0.0))
	if recolour_step <= 0.0:
		return   # a pack without this sprite's own blend data declines the effect, rather than guessing a strength
	var tex := pack.get_texture(int(s.get("page", 0)))
	if tex == null:
		return
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var sx := float(s["x"])
	var sy := float(s["y"])
	var sw := float(s["w"])
	var sh := float(s["h"])
	var uv := [Vector2(sx / tw, sy / th), Vector2((sx + sw) / tw, sy / th),
			Vector2((sx + sw) / tw, (sy + sh) / th), Vector2(sx / tw, (sy + sh) / th)]
	var hw := sw * 0.5
	var hh := sh * 0.5
	var corners := [Vector3(-hw, 0.0, -hh), Vector3(hw, 0.0, -hh), Vector3(hw, 0.0, hh), Vector3(-hw, 0.0, hh)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uv[i])
		st.add_vertex(corners[i])
	_quad = MeshInstance3D.new()
	_quad.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("mask_tex", tex)
	mat.set_shader_parameter("recolour_step", recolour_step)
	_quad.material_override = mat
	add_child(_quad)
	position = Vector3(mc.home_position().x, 0.3, mc.home_position().y)
	_quad.visible = false


func _process(_delta: float) -> void:
	if _quad != null:
		_quad.visible = mc.vehicle != null and mc.can_dock(mc.vehicle)
