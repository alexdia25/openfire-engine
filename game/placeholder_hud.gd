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
var _keys: Label
var _banner: Label
var _finished := false


func setup(controller: MatchController) -> void:
	mc = controller
	_status = _label(Vector2(12, 8), 18)
	_objective = _label(Vector2(12, 34), 16)
	_keys = _label(Vector2(12, 0), 13)
	_keys.text = "arrows drive   space fire   V switch vehicle (standing on your base tile)   F flag   B swim (Jeep)   X heli weapon   M mine   Q/E/R turret, gun"
	_keys.anchor_top = 1.0
	_keys.anchor_bottom = 1.0
	_keys.offset_top = -26.0
	var panel := HudPanel.new()  # the traced panel (documents 66-70); its scale and position are the port's
	add_child(panel)
	panel.setup(controller)
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 12.0
	panel.offset_top = -168.0 - 30.0
	panel.offset_bottom = -30.0
	_banner = _label(Vector2(60, 90), 40)
	_banner.visible = false


func _label(pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	add_child(l)
	return l


func show_win(winner_idx: int) -> void:
	_finished = true
	_banner.text = "%s WINS  -  flag captured\npress Enter to play again" % ("TAN" if winner_idx == 0 else "GREEN")
	_banner.visible = true


func _process(_delta: float) -> void:
	var v := mc.vehicle
	if v == null:
		return
	_status.text = "%s   hp %d / %d%s" % [VEHICLE_NAMES[v.vehicle_type], int(ceil(v.hp)), int(v.max_hp),
			"" if v.alive else "   (destroyed)"]  # the original shows no health readout (document 70): a debug aid
	_objective.text = _objective_text(v)


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
