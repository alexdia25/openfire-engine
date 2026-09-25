class_name PlaceholderHud
extends CanvasLayer
## PORT-ONLY PLACEHOLDER (not the original interface). Plain labels giving a player what the level needs to be played from start to
## finish: the current vehicle, hit points and fuel, what to do next, the keys, and after the win a restart key. Every piece of it is
## a choice of this port (the fuel and radar are now the traced panel, game/hud_panel.gd), listed under "Untraced choices" in docs/process/NEXT_STEPS.md, to be replaced by the traced interface
## (the per-player panel of document 66: frame cel 1940, vehicle icon cels 2161-2164, weapon counts drawn with the digit cels 2146-2155,
## and the radar). The objective texts are not original messages either (the announcer's are in document 66).

const VEHICLE_NAMES := ["Tank", "Jeep", "MSV", "Helicopter"]

var mc: MatchController
var _status: Label
var _objective: Label
var _fade: ColorRect
var _stock: Label
var _keys: Label
var _banner: Label
var _ribbon: WinRibbon
var _finished := false


func setup(controller: MatchController) -> void:
	mc = controller
	_status = _label(Vector2(12, 8), 18)
	_objective = _label(Vector2(12, 34), 16)
	_stock = _label(Vector2(12, 58), 14)
	_keys = _label(Vector2(12, 0), 13)
	_keys.text = "arrows drive   space fire   dock: stand still on your pad centre + fire (V = quick swap, port-only); in the grid: arrows, Space   F flag   B swim (Jeep)   X heli weapon   M mine   Q/E/R turret, gun   [ ] previous / next level (dev)"
	_keys.anchor_top = 1.0
	_keys.anchor_bottom = 1.0
	_keys.offset_top = -26.0
	var frame := ClassicFrame.new()   # the classic layout's black surround and backdrop strip (document 96); draws nothing in the modern layout
	add_child(frame)
	frame.setup(controller.pack)
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	move_child(frame, 0)   # under the placeholder labels, so they stay readable over the black surround
	var panel := HudPanel.new()  # the traced panel (documents 66-70); its place and scale follow GameSettings.hud_layout (HudLayout)
	add_child(panel)
	panel.setup(controller)
	var fade := ColorRect.new()   # the game view's fade-in after the choice (0x4183e0): black at alpha 1 - view_fade
	fade.color = Color(0, 0, 0, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade = fade
	# The view fade dims the game view and the panel but must sit BELOW the hangar screen: docking fades the view out (view_fade 0, document 81), and the choice screen
	# then opens with its own fade-in on top of that black.
	var select := SelectorScreen.new()   # the docked vehicle-choice screen (documents 76, 78): shown while MatchController.selecting / undocking
	add_child(select)
	select.set_anchors_preset(Control.PRESET_FULL_RECT)
	select.setup(controller)
	var skull := DeathSkullView.new()   # the loss sequence's laughing skull (document 88), above the view fade
	add_child(skull)
	skull.setup(controller)
	_ribbon = WinRibbon.new()   # the victory ribbon (document 92), above everything
	add_child(_ribbon)
	_ribbon.setup(controller.pack)
	_banner = _label(Vector2(60, 90), 40)
	_banner.visible = false


static func _n(k: int) -> String:
	return "unlimited" if k == 255 else str(k)


func _label(pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	add_child(l)
	return l


## The loss (document 95): with no vehicle left the loss sequence ends by starting the end-of-match handler with no winner (FUN_0040b370(-1) = FUN_004225d0), whose only
## steps for that case are two fades to black and leaving the level: no message, no banner. The screen is already black here (the loss sequence's darkening), so
## the port shows only the restart hint (the original returns to the front end, which the port does not have).
func show_lost() -> void:
	_finished = true
	_banner.text = "press Enter to play again"
	_banner.position = Vector2(60, 0)
	_banner.anchor_top = 1.0
	_banner.anchor_bottom = 1.0
	_banner.offset_top = -80.0
	_banner.add_theme_font_size_override("font_size", 18)
	_banner.visible = true


func show_win(winner_idx: int) -> void:
	_finished = true
	if _ribbon.start(winner_idx):   # the original's sequence: fade to black, then the winner's ribbon (document 92)
		_banner.text = "press Enter to play again"
		_banner.position = Vector2(60, 0)
		_banner.anchor_top = 1.0
		_banner.anchor_bottom = 1.0
		_banner.offset_top = -80.0
		_banner.add_theme_font_size_override("font_size", 18)
		_banner.move_to_front()
	else:
		_banner.text = "%s WINS  -  flag captured\npress Enter to play again" % ("TAN" if winner_idx == 0 else "GREEN")
	_banner.visible = true


func _process(_delta: float) -> void:
	var v := mc.vehicle
	if v == null:
		return
	_status.text = "%s   hp %d / %d%s" % [VEHICLE_NAMES[v.vehicle_type], int(ceil(v.hp)), int(v.max_hp),
			"" if v.alive else "   (destroyed)"]  # the original shows no health readout (document 70): a debug aid
	if mc.can_dock(v):
		# the original's own signal is the pad's border animating (FUN_0040b400, document 80); this text is the port's stand-in for it
		_status.text += "   [DOCK READY - press fire]"
	_objective.text = _objective_text(v)
	_fade.color.a = 1.0 - mc.view_fade
	_fade.size = get_viewport().get_visible_rect().size
	_stock.text = "vehicles left (placeholder display): Tank %s  Jeep %s  MSV %s  Heli %s" % [_n(mc.vehicle_stock[0]), _n(mc.vehicle_stock[1]), _n(mc.vehicle_stock[2]), _n(mc.vehicle_stock[3])]


func _objective_text(v: Vehicle) -> String:
	if _finished:
		return ""
	var flag: FlagMarker = mc.flags.get(1)
	if flag == null:
		return "Objective: destroy the enemy building (a Tank's shells; shoot the ruin too), then take the flag"
	if flag.carrier == v:
		return "Objective: bring the flag back to your base tile"
	if v.vehicle_type != 1:
		return "Objective: the flag is out. Only a Jeep can carry it: return to your base tile and press V to switch"
	return "Objective: drive the Jeep onto the flag"


func _unhandled_input(event: InputEvent) -> void:
	if _finished and event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
		Engine.time_scale = 1.0
		get_tree().reload_current_scene()
