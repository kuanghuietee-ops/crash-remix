class_name CameraRegion
extends Area3D

const MODE_DEFAULT := &"default"
const MODE_CLOSE := &"close"
const MODE_SIDE_ON := &"side_on"
const MODE_GRIND := &"grind"
const MODE_WALL_RUN := &"wall_run"
const MODE_SWING := &"swing"
const MODE_TOWARD_CAMERA := &"toward_camera"

@export var camera_mode := MODE_DEFAULT


func offset_for(camera_tuning: CameraTuning) -> Vector3:
	match camera_mode:
		MODE_CLOSE:
			return camera_tuning.close_offset
		MODE_SIDE_ON:
			return camera_tuning.side_on_offset
		MODE_GRIND:
			return camera_tuning.grind_offset
		MODE_WALL_RUN:
			return camera_tuning.wall_run_offset
		MODE_SWING:
			return camera_tuning.swing_offset
		MODE_TOWARD_CAMERA:
			return camera_tuning.toward_camera_offset
	return camera_tuning.default_offset
