class_name VehicleModule
extends RefCounted
## One piece of a vehicle's behaviour (PORTING_PLAN.md 2.7.2, step 4): the port of one handler the original's vehicle-type
## record points at (a drive handler, a weapon-slot handler, a water handler ...). A vehicle definition names a module for
## each slot and gives its parameters; `VehicleModules.create()` builds it. Modules keep no state of their own that the
## rest of the game reads: they act on the Vehicle's fields -- its "state block", as the original's handlers act on
## `obj` / `state` -- which are also the channels the renderers draw from and the mod tool's preview poses.
##
## Every module script has a `SCHEMA` constant: {slot, doc, params: {name: {type, unit, default, provenance, doc}},
## channels: [vehicle field names it drives]}. The defaults are the traced values; a definition may override any of them.

var params: Dictionary = {}


func _init(p: Dictionary = {}) -> void:
	var schema: Dictionary = get_script().get("SCHEMA") if get_script().get("SCHEMA") != null else {}
	for k in schema.get("params", {}):
		params[k] = schema["params"][k].get("default")
	for k in p:
		params[k] = p[k]


## A parameter as a float (definitions come from JSON, where every number is a float).
func f(name: String) -> float:
	return float(params.get(name, 0.0))


func b(name: String) -> bool:
	return bool(params.get(name, false))
