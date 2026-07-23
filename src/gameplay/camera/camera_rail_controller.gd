class_name CameraRailController
extends Node3D

const CameraBlendType := preload("res://src/gameplay/camera/camera_blend.gd")
const CameraRegionType := preload("res://src/gameplay/camera/camera_region.gd")

var _player: CharacterBody3D
var _rail: Path3D
var _camera: Camera3D
var _camera_tuning: CameraTuning
var _input_router: InputRouter
var _regions: Array[CameraRegionType] = []
var _active_regions: Array[CameraRegionType] = []
var _current_offset := Vector3.ZERO
var _blend_origin := Vector3.ZERO
var _blend_target := Vector3.ZERO
var _blend_elapsed_s: float
var _corridor_forward := Vector3.FORWARD
var _initialized: bool


func _ready() -> void:
	_rail = get_node_or_null("Rail") as Path3D
	_camera = get_node_or_null("Camera3D") as Camera3D
	_ensure_curve_from_markers()


func configure(
	player: CharacterBody3D,
	rail: Path3D,
	camera: Camera3D,
	camera_tuning: CameraTuning,
	regions: Array,
	input_router: InputRouter = null
) -> void:
	_player = player
	_rail = rail
	_camera = camera
	_camera_tuning = camera_tuning
	_input_router = input_router
	_regions.clear()
	_active_regions.clear()
	for candidate: Variant in regions:
		if candidate is CameraRegionType:
			var region := candidate as CameraRegionType
			_regions.append(region)
			region.body_entered.connect(_on_region_body_entered.bind(region))
			region.body_exited.connect(_on_region_body_exited.bind(region))
	_ensure_curve_from_markers()
	if _rail != null and _rail.curve != null:
		_rail.curve.bake_interval = _camera_tuning.rail_bake_interval_m
	_current_offset = _camera_tuning.default_offset
	_blend_origin = _current_offset
	_blend_target = _current_offset
	_blend_elapsed_s = _camera_tuning.region_blend_s
	_camera.fov = _camera_tuning.field_of_view_degrees
	_initialized = false
	update_camera(0.0)


func corridor_forward() -> Vector3:
	return _corridor_forward


func refresh_tuning(camera_tuning: CameraTuning) -> void:
	_camera_tuning = camera_tuning
	if _camera != null:
		_camera.fov = _camera_tuning.field_of_view_degrees
	if _rail != null and _rail.curve != null:
		_rail.curve.bake_interval = _camera_tuning.rail_bake_interval_m


func update_camera(delta_s: float) -> void:
	if (
		_player == null
		or _rail == null
		or _rail.curve == null
		or _camera == null
		or _camera_tuning == null
		or _rail.curve.point_count < 1
	):
		return
	var local_player := _rail.to_local(_player.global_position)
	var rail_offset := _rail.curve.get_closest_offset(local_player)
	var rail_length := _rail.curve.get_baked_length()
	var rail_position := _rail.to_global(_rail.curve.sample_baked(rail_offset))
	var look_offset := minf(rail_offset + _camera_tuning.look_ahead_m, rail_length)
	var look_position := _rail.to_global(_rail.curve.sample_baked(look_offset))
	var forward := (look_position - rail_position).normalized()
	if forward.is_zero_approx():
		var behind_offset := maxf(rail_offset - _camera_tuning.look_ahead_m, 0.0)
		var behind := _rail.to_global(_rail.curve.sample_baked(behind_offset))
		forward = (rail_position - behind).normalized()
	if not forward.is_zero_approx():
		_corridor_forward = Vector3(forward.x, 0.0, forward.z).normalized()
	var right := _corridor_forward.cross(Vector3.UP).normalized()
	var region_offsets: Array[Vector3] = []
	for region: CameraRegionType in _active_regions:
		region_offsets.append(region.offset_for(_camera_tuning))
	var target_offset := CameraBlendType.resolve_offset(
		_camera_tuning.default_offset,
		region_offsets
	)
	if not target_offset.is_equal_approx(_blend_target):
		_blend_origin = _current_offset
		_blend_target = target_offset
		_blend_elapsed_s = 0.0
	_blend_elapsed_s += maxf(delta_s, 0.0)
	_current_offset = CameraBlendType.offset_at_elapsed(
		_blend_origin,
		_blend_target,
		_blend_elapsed_s,
		_camera_tuning
	)
	var desired_position := (
		rail_position
		+ right * _current_offset.x
		+ Vector3.UP * _current_offset.y
		- _corridor_forward * _current_offset.z
	)
	if _initialized:
		_camera.global_position = _camera.global_position.move_toward(
			desired_position,
			_camera_tuning.rail_follow_speed_mps * delta_s
		)
	else:
		_camera.global_position = desired_position
		_initialized = true
	var look_target := (
		_player.global_position
		+ _corridor_forward * _camera_tuning.look_ahead_m
		+ Vector3.UP * _camera_tuning.look_at_height_m
		+ right * _camera_tuning.player_screen_left_bias_m
	)
	_camera.look_at(look_target, Vector3.UP)
	if _player.has_method("set_corridor_forward"):
		_player.call("set_corridor_forward", _corridor_forward)
	_update_input_corridor_axis()


func _physics_process(delta_s: float) -> void:
	update_camera(delta_s)


func _ensure_curve_from_markers() -> void:
	if _rail == null:
		return
	if _rail.curve != null and _rail.curve.point_count > 0:
		return
	var curve := Curve3D.new()
	if _camera_tuning != null:
		curve.bake_interval = _camera_tuning.rail_bake_interval_m
	for marker: Node in _rail.get_children():
		if marker is Marker3D:
			curve.add_point((marker as Marker3D).position)
	_rail.curve = curve


func _update_input_corridor_axis() -> void:
	if _input_router == null or _camera == null or _player == null:
		return
	var screen_origin := _camera.unproject_position(_player.global_position)
	var screen_forward := _camera.unproject_position(
		_player.global_position + _corridor_forward
	)
	_input_router.set_corridor_axis(screen_forward - screen_origin)


func _on_region_body_entered(body: Node3D, region: CameraRegionType) -> void:
	if body == _player and not _active_regions.has(region):
		_active_regions.append(region)


func _on_region_body_exited(body: Node3D, region: CameraRegionType) -> void:
	if body == _player:
		_active_regions.erase(region)
