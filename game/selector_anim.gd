class_name SelectorAnim
extends RefCounted
## The state of the docked vehicle-choice screen (document 78): the platform height `d0` (state +0xd0, starts at 110), the chosen picture's sideways offset `d4`
## (+0xd4) and its height offset `d8` (+0xd8), the fade `fade` (+0xbc, 0 to 1), and the confirm script of the chosen type run one step after the other as the original's
## step list at `state +0xc8` (FUN_00418040 calls each step's routine every tick until it answers "done").
##
## Sound steps (document 85's own tracing technique, applied here 2026-09-22): `tools/data/selector.json`'s two sound
## indices are `0x449260`'s two entries (document 78), already resolved to real cues in `tools/data/sound_cues.json` --
## index 0 is `PreRaise` (`0x44b7f0`), index 1 `Raise` (`0x44b7d8`, already applied elsewhere to the dock's own sink,
## document 81 -- the original reuses the same lift/servo sound for both). Tank/Heli's script plays `PreRaise` twice
## (once before `platform_up`, again before `slide`); Jeep/MSV (no `platform_up` step) play it once, right before `slide`.
signal sound_cue(id: String)

const FADE_PER_TICK := 0x11EB / 65536.0     ## 0.07: the view fades in and out in about 14 ticks
const SOUND_CUES := ["PreRaise", "Raise"]

var d0 := 110.0
var d4 := 0.0
var d8 := 0.0
var fade := 0.0
var panel_visible := true      ## false after the script's "clear panel" step (0x417900)
var running := false           ## a confirm script is playing
var finished := false          ## the script has run out: the vehicle is released
var _steps: Array = []
var _i := 0


func fade_in(ticks: float) -> void:
	fade = minf(fade + FADE_PER_TICK * ticks, 1.0)


func start_script(steps: Array) -> void:
	_steps = steps
	_i = 0
	running = true
	finished = false


## One frame of the script (ticks = whole ticks since the last frame).
func step(ticks: float) -> void:
	if not running:
		return
	while _i < _steps.size():
		var s: Array = _steps[_i]
		var done := false
		match String(s[0]):
			"sound":
				var idx := int(s[1])
				if idx >= 0 and idx < SOUND_CUES.size():
					sound_cue.emit(SOUND_CUES[idx])
				done = true
			"platform_up":
				d0 -= float(s[1]) * ticks
				if d0 <= float(s[2]):
					d0 = float(s[2])
					done = true
			"slide":
				d4 += float(s[1]) * ticks
				if (float(s[1]) < 0.0 and d4 <= float(s[2])) or (float(s[1]) > 0.0 and d4 >= float(s[2])):
					d4 = float(s[2])
					done = true
			"clear_panel":
				panel_visible = false
				done = true
			"rise_with_picture":
				var delta := float(s[1]) * ticks
				if d0 - delta <= float(s[2]):
					delta = d0 - float(s[2])
					done = true
				d0 -= delta
				d8 -= delta
			"rise_and_fade":
				var delta2 := float(s[1]) * ticks
				d0 -= delta2
				d8 -= delta2
				fade -= float(s[2]) * ticks
				if fade <= 0.0:
					fade = 0.0
					done = true
		if not done:
			return
		_i += 1
		if String(s[0]) == "slide":
			return   # the table's "continue" flag is 0 after the slide: the next step waits for the next frame
	running = false
	finished = true
