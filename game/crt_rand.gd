class_name CrtRand
extends RefCounted
## The C runtime's `rand` (Microsoft: state = state * 214013 + 2531011, result = bits 16-30) and the game's FUN_0041d3d0 built on it: `below(n)` =
## ((rand & 0x7fff) * 2 * n) >> 16. The original's backdrops and other scatterings call it after `srand(seed)` (FUN_00437330), so seeding it the same way
## reproduces them exactly.

var _state := 1


func seed_with(seed_value: int) -> void:
	_state = seed_value & 0xFFFFFFFF


func next() -> int:
	_state = (_state * 214013 + 2531011) & 0xFFFFFFFF
	return (_state >> 16) & 0x7FFF


func below(n: int) -> int:
	return ((next() & 0x7FFF) * 2 * n) >> 16
