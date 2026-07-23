class_name CameraRegion
extends Area3D

const MODE_DEFAULT := &"default"
const MODE_CLOSE := &"close"
const MODE_SIDE_ON := &"side_on"

@export var camera_mode := MODE_DEFAULT


func offset_for(camera_tuning: CameraTuning) -> Vector3:
	match camera_mode:
		MODE_CLOSE:
			return camera_tuning.close_offset
		MODE_SIDE_ON:
			return camera_tuning.side_on_offset
	return camera_tuning.default_offset
