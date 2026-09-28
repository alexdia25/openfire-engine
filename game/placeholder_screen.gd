class_name PlaceholderScreen
extends Control
## PORT-ONLY PLACEHOLDER (same idiom as `PlaceholderHud`): a title, a message, and a column of buttons -- everything
## `GameFlow`'s title screen, main menu, settings, multiplayer and mission-failed states need until each gets a real
## screen of its own. Not meant to be pretty; meant to make every state in the game-flow diagram (PORTING_PLAN.md
## 2.8) a real, distinct, reachable node so nothing about the flow itself has to be redesigned when a real screen
## replaces one of these.


func setup(title: String, message: String, buttons: Array) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_deferred("size", get_viewport_rect().size)   # anchors alone do not size a Control added ad hoc under a non-Control ancestor (deferred: Control warns/reverts an immediate size set while its own FULL_RECT anchors are active)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(320, 0)
	box.position -= box.custom_minimum_size * 0.5
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(box)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 28)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	if message != "":
		var m := Label.new()
		m.text = message
		m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		m.modulate = Color(1, 1, 1, 0.7)
		box.add_child(m)
	box.add_child(HSeparator.new())
	for entry in buttons:
		var b := Button.new()
		b.text = String(entry[0])
		b.pressed.connect(entry[1])
		box.add_child(b)
