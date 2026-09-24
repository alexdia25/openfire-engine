class_name CameraSwoop
extends RefCounted
## The camera's swoop-in when a vehicle comes out of the base (document 90). The undock object's first handler (FUN_0042ee50) snaps the camera to height 250.0 and
## pitch 64.0 (FUN_00416100: `+0x114`, `+0x134`, `+0x24`, `+0x144`), and its second (0x42eea0, and the vehicle's own rig in FUN_0040b1c0) registers the normal camera
## rig: height target from the per-type table at 0x4452c0 (Tank, Jeep, MSV -170.0; Heli -100.0), pitch target 24.0 (0x180000). The camera update (FUN_00416fa0) then eases
## height and pitch toward those targets with CameraEase and the template's rates. Traced: the two easings, their rates, their start and end values, and the timing (the
## height takes ~205 ticks, about 3.3 s, which matches the reference footage). NOT traced: how those camera values map onto the pixels of the port's camera; see
## terrain_view_3d.gd's SWOOP_START_ZOOM / SWOOP_START_TILT_DEG, which are chosen from the footage and only take the eased FRACTIONS from here.

const START_HEIGHT := 250.0                        ## 0xfa0000
const START_PITCH := 64.0                          ## 0x400000
const NORMAL_PITCH := 24.0                         ## 0x180000
const HEIGHT_TRIPLE := [0x1999 / 65536.0, 0xccc / 65536.0, 3.0]    ## rig +0x48: {accel 0.1, brake 0.05, max 3.0}
const PITCH_TRIPLE := [0xa3d / 65536.0, 0x28f / 65536.0, 1.0]      ## rig +0x54: {accel 0.04, brake 0.01, max 1.0}
const HEIGHT_BY_TYPE := [-170.0, -170.0, -170.0, -100.0]           ## the table at 0x4452c0, by vehicle type (index min(type, 3))

var _height: CameraEase
var _pitch: CameraEase
var _acc := 0.0
var done := false


func _init(vehicle_type: int) -> void:
	_height = CameraEase.new(START_HEIGHT, float(HEIGHT_BY_TYPE[clampi(vehicle_type, 0, 3)]), HEIGHT_TRIPLE)
	_pitch = CameraEase.new(START_PITCH, NORMAL_PITCH, PITCH_TRIPLE)


## Advances by `ticks` (fractional ticks accumulate; the original steps whole ticks).
func advance(ticks: float) -> void:
	_acc += ticks
	while _acc >= 1.0:
		_acc -= 1.0
		var h_done := _height.step()
		var p_done := _pitch.step()
		if h_done and p_done:
			done = true


## 1.0 at the start of the swoop, 0.0 once the height has arrived.
func height_fraction() -> float:
	return clampf((_height.value - _height.target) / (START_HEIGHT - _height.target), 0.0, 1.0)


func pitch_fraction() -> float:
	return clampf((_pitch.value - _pitch.target) / (START_PITCH - _pitch.target), 0.0, 1.0)
