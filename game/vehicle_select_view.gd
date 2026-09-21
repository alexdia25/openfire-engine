class_name VehicleSelectView
extends Control
## The vehicle-choice grid (document 76): the four mini icons (cels 2163, 2161, 2164, 2162 for Tank, Jeep, MSV, Heli) in the original's 2 x 2 arrangement
## (top row Heli, MSV; bottom row Tank, Jeep) with the number of vehicles left of each drawn in the red digit cels (2146 + n; 255 is unlimited and is
## shown as a placeholder 8), and a frame round the cursor's cell. The traced part is the arrangement, the icons, the digits and the cursor logic
## (MatchController.select_move); the screen position, the 6x scale, the cell size, the frame and the display of 255 are the port's choice, and the original
## draws this on the panel's blank frame (cel 1940) at the rectangles of table 0x4491c0, which are not used yet.

const CELL := Vector2(150, 110)
const ICON_SCALE := 6
const DIGIT_SCALE := 3
const GRID := [[3, 2], [0, 1]]   ## rows of type indices: Heli, MSV / Tank, Jeep

var mc: MatchController
var _cells: Array = []   ## per type: {panel, icon, digits: Array of TextureRect, inf: Label}


func setup(controller: MatchController) -> void:
	mc = controller
	visible = false
	custom_minimum_size = CELL * 2.0
	size = CELL * 2.0
	var sel: Dictionary = mc.pack.hud_panels.get("select", {})
	if sel.is_empty():
		return
	for row in 2:
		for col in 2:
			var t: int = GRID[row][col]
			var cell := Control.new()
			cell.position = Vector2(col, row) * CELL
			cell.size = CELL
			add_child(cell)
			var bg := ColorRect.new()
			bg.color = Color(0.1, 0.1, 0.15, 0.85)
			bg.size = CELL - Vector2(6, 6)
			bg.position = Vector2(3, 3)
			cell.add_child(bg)
			var icon := TextureRect.new()
			icon.texture = _atlas(String(sel["icon_ids"][t]))
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon.stretch_mode = TextureRect.STRETCH_SCALE
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.size = (icon.texture as AtlasTexture).region.size * ICON_SCALE
			icon.position = Vector2((CELL.x - icon.size.x) / 2.0, 8)
			cell.add_child(icon)
			var digits: Array = []
			for i in 3:
				var d := TextureRect.new()
				d.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				d.stretch_mode = TextureRect.STRETCH_SCALE
				d.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				d.size = Vector2(16, 16) * DIGIT_SCALE
				d.position = Vector2(CELL.x / 2.0 - 60 + i * 40, CELL.y - 58)
				cell.add_child(d)
				digits.append(d)
			var frame := ReferenceRect.new()
			frame.border_color = Color(1, 0.9, 0.2)
			frame.border_width = 4.0
			frame.editor_only = false
			frame.size = CELL - Vector2(6, 6)
			frame.position = Vector2(3, 3)
			cell.add_child(frame)
			_cells.append({"type": t, "digits": digits, "frame": frame, "cell": cell})
	mc.selection_changed.connect(_refresh)


func _atlas(sprite_id: String) -> AtlasTexture:
	var s := mc.pack.get_sprite(sprite_id)
	var at := AtlasTexture.new()
	at.atlas = mc.pack.get_texture(int(s.get("page", 0)))
	at.region = Rect2(float(s["x"]), float(s["y"]), float(s["w"]), float(s["h"]))
	return at


func _refresh() -> void:
	visible = mc.selecting
	if not visible:
		return
	var sel: Dictionary = mc.pack.hud_panels["select"]
	for c in _cells:
		var t: int = c["type"]
		c["frame"].visible = t == mc.selection
		var n: int = mc.vehicle_stock[t]
		var text := "" if n == 255 else str(n)
		for i in 3:
			var d: TextureRect = c["digits"][i]
			if n == 255:
				d.visible = i == 0
				d.texture = _atlas(String(sel["digit_ids"][8]))   # unlimited: PLACEHOLDER shown as an 8 (the original's display of 255 is untraced)
			else:
				d.visible = i < text.length()
				if i < text.length():
					d.texture = _atlas(String(sel["digit_ids"][int(text[i])]))
