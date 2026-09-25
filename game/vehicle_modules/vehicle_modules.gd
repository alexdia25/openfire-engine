class_name VehicleModules
extends RefCounted
## The library of vehicle behaviour modules (PORTING_PLAN.md 2.7.2, step 4; EDITOR_PLAN.md 4.2). A definition names one per
## slot -- `drive.model`, `aim.model`, `weapons.slots[n].handler`, `water.model` -- and this builds it with the
## definition's parameters over the module's traced defaults. Adding a new kind of behaviour means adding a module here;
## definitions (and so mods) only choose and configure existing ones.

const MODULES := {
	"ground": preload("res://game/vehicle_modules/ground_drive.gd"),
	"rotor": preload("res://game/vehicle_modules/rotor_drive.gd"),
	"gun_mount": preload("res://game/vehicle_modules/gun_mount.gd"),
	"cannon": preload("res://game/vehicle_modules/cannon.gd"),
	"rocket_salvo": preload("res://game/vehicle_modules/rocket_salvo.gd"),
	"lobbed_missile": preload("res://game/vehicle_modules/lobbed_missile.gd"),
	"heli_guns": preload("res://game/vehicle_modules/heli_guns.gd"),
	"mine_layer": preload("res://game/vehicle_modules/mine_layer.gd"),
	"hull_water": preload("res://game/vehicle_modules/hull_water.gd"),
}


## A module by name with `params` over its defaults, or null for "" / "none" / an unknown name (pushes an error for the latter).
static func create(name: String, params: Dictionary = {}) -> VehicleModule:
	if name == "" or name == "none":
		return null
	if not MODULES.has(name):
		push_error("VehicleModules: no module called \"%s\"" % name)
		return null
	return MODULES[name].new(params)


## A module's schema ({slot, doc, params, channels}), or {} if unknown.
static func schema(name: String) -> Dictionary:
	return MODULES[name].SCHEMA if MODULES.has(name) else {}


## The modules that can fill a slot ("drive", "aim", "weapon", "water"), for the mod tool's pickers.
static func names_for_slot(slot: String) -> Array[String]:
	var out: Array[String] = []
	for n in MODULES:
		if String(MODULES[n].SCHEMA.get("slot", "")) == slot:
			out.append(n)
	return out
