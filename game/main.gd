extends Node2D
## Placeholder boot scene. Replaced once the pack loader (section 2.4) and the
## first real menu screen (section 2.6) exist.

func _ready() -> void:
	$Label.text = "Return Fire -- Godot port\n\nNo content pack loaded yet.\nSee docs/PORTING_PLAN.md."
