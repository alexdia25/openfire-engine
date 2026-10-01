@tool
extends EditorPlugin
## Lists the engine's project settings (EngineConfig) under Project Settings > Openfire, so a game built on the engine
## sees what it can set without reading the source. Optional: the engine reads the settings whether or not the plugin
## is enabled, and every class it defines is available either way.


func _enter_tree() -> void:
	_declare(EngineConfig.BASE_PACK, "")
	_declare(EngineConfig.ASSET_REGISTRY, "")


func _declare(key: String, default: String) -> void:
	if not ProjectSettings.has_setting(key):
		ProjectSettings.set_setting(key, default)
	ProjectSettings.set_initial_value(key, default)
	ProjectSettings.add_property_info({"name": key, "type": TYPE_STRING})
