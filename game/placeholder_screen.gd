class_name PlaceholderScreen
extends Control
## The front end's dialog screens: a title, a message, and a column of buttons -- everything `GameFlow`'s main menu, settings, multiplayer and mission-failed states
## need until each gets a real screen of its own. Drawn as a dialog over the title picture in the pack's skin (UiSkin, `ui/skin.json`, plain by default, the original's pack declares the Win95 look; issue #51, wiki document 122), the look of the original's own
## dialogs. Also the fallback for the title itself when the pack has no picture. Every state in the game-flow diagram (PORTING_PLAN.md 2.8) stays a real, distinct,
## reachable node, so nothing about the flow has to be redesigned when a real screen replaces one of these.

var backdrop: Texture2D   ## the title picture behind the dialog, set before `setup`
var skin := UiSkin.new()   ## the pack's skin, set before `setup`


func setup(title: String, message: String, buttons: Array) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_deferred("size", get_viewport_rect().size)   # anchors alone do not size a Control added ad hoc under a non-Control ancestor (deferred: Control warns/reverts an immediate size set while its own FULL_RECT anchors are active)
	skin.add_backdrop(self, backdrop)
	var w := skin.window(title)
	var body: VBoxContainer = w["body"]
	body.custom_minimum_size = Vector2(280, 0)
	if message != "":
		var m := Label.new()
		m.text = message
		m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(m)
	for entry in buttons:
		var b := Button.new()
		b.text = String(entry[0])
		b.pressed.connect(entry[1])
		body.add_child(b)
	skin.centre(self, w["root"])
	for c in body.get_children():
		if c is Button:
			c.grab_focus()
			break
