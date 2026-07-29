class_name ChaseHazard
extends Node3D

const RailCurveBuilderType := preload(
	"res://src/gameplay/common/rail_curve_builder.gd"
)

const EVENT_START := &"start"
const EVENT_STOP := &"stop"

@export var chase_path_path: NodePath
@export var boulder_visual_path: NodePath
@export var start_trigger_path: NodePath
@export var stop_trigger_path: NodePath

var _tuning: ChaseTuning
var _player: Node3D
var _input_router: Node
var _chase_path: Path3D
var _boulder_visual: Node3D
var _start_trigger: Area3D
var _stop_trigger: Area3D
var _boulder_progress_m: float
var _active: bool
var _caught: bool
var _stopped: bool


func _ready() -> void:
	add_to_group(&"chase_hazard")
	_resolve_scene_nodes()
	_ensure_curve_from_markers()
	_connect_segment_triggers()
	_sync_visual()


func configure_logic(chase_tuning: ChaseTuning) -> void:
	_set_chase_input_mode(false)
	_tuning = chase_tuning
	_boulder_progress_m = 0.0
	_active = false
	_caught = false
	_stopped = false


func configure(
	chase_tuning: ChaseTuning,
	player: Node3D,
	input_router: Node
) -> void:
	configure_logic(chase_tuning)
	_player = player
	_input_router = input_router
	_resolve_scene_nodes()
	_ensure_curve_from_markers()
	_connect_segment_triggers()
	if _player != null:
		reset_for_player_position(_player.global_position)
	else:
		_sync_visual()


func refresh_tuning(chase_tuning: ChaseTuning) -> void:
	_tuning = chase_tuning


func start_at_progress(player_progress_m: float) -> void:
	if _tuning == null:
		return
	if not _path_is_usable():
		_active = false
		_caught = false
		_stopped = false
		_set_chase_input_mode(false)
		_set_visual_visible(false)
		push_error(
			"%s cannot start without a usable chase path"
			% get_path()
		)
		return
	_boulder_progress_m = maxf(
		player_progress_m - _tuning.boulder_start_gap_m,
		0.0
	)
	_active = true
	_caught = false
	_stopped = false
	_set_chase_input_mode(true)
	_set_visual_visible(true)
	_sync_visual()


func stop() -> void:
	if _stopped:
		_set_chase_input_mode(false)
		return
	_active = false
	_caught = false
	_stopped = true
	_set_chase_input_mode(false)
	_set_visual_visible(false)


func handle_segment_event(
	event: StringName,
	player_progress_m: float
) -> void:
	match event:
		EVENT_START:
			start_at_progress(player_progress_m)
		EVENT_STOP:
			stop()


func advance_progress(
	delta_s: float,
	player_progress_m: float
) -> Dictionary:
	if _active and not _caught and _tuning != null:
		_boulder_progress_m += (
			_tuning.boulder_speed_mps
			* maxf(delta_s, 0.0)
		)
		_sync_visual()
		if (
			gap_to_progress_m(player_progress_m)
			<= _tuning.boulder_kill_distance_m
		):
			_caught = true
	return {
		&"active": _active,
		&"caught": _caught,
		&"gap_m": gap_to_progress_m(player_progress_m),
		&"boulder_progress_m": _boulder_progress_m,
	}


func advance_runtime(delta_s: float) -> Dictionary:
	if _player == null:
		return {
			&"active": _active,
			&"caught": false,
			&"gap_m": 0.0,
			&"boulder_progress_m": _boulder_progress_m,
		}
	return advance_progress(
		delta_s,
		progress_for_position(_player.global_position)
	)


func resolve_player_contact(player_died: bool) -> void:
	if not player_died:
		_caught = false


func reset_for_player_position(player_position: Vector3) -> void:
	if _tuning == null or not _path_is_usable():
		_active = false
		_caught = false
		_stopped = false
		_boulder_progress_m = 0.0
		_set_chase_input_mode(false)
		_set_visual_visible(true)
		_sync_visual()
		return
	var player_progress_m := progress_for_position(
		player_position
	)
	var start_progress_m := _trigger_progress(
		_start_trigger,
		0.0
	)
	var stop_progress_m := _trigger_progress(
		_stop_trigger,
		_chase_path.curve.get_baked_length()
	)
	if player_progress_m < start_progress_m:
		_active = false
		_caught = false
		_stopped = false
		_boulder_progress_m = maxf(
			start_progress_m
			- _tuning.boulder_start_gap_m,
			0.0
		)
		_set_chase_input_mode(false)
		_set_visual_visible(true)
		_sync_visual()
		return
	if player_progress_m >= stop_progress_m:
		_active = false
		_caught = false
		_stopped = true
		_boulder_progress_m = stop_progress_m
		_set_chase_input_mode(false)
		_set_visual_visible(false)
		_sync_visual()
		return
	start_at_progress(player_progress_m)


func reset_before_start() -> void:
	_active = false
	_caught = false
	_stopped = false
	_boulder_progress_m = 0.0
	_set_chase_input_mode(false)
	_set_visual_visible(true)
	_sync_visual()


func is_active() -> bool:
	return _active


func boulder_progress_m() -> float:
	return _boulder_progress_m


func gap_to_progress_m(player_progress_m: float) -> float:
	return player_progress_m - _boulder_progress_m


func gap_to_position_m(player_position: Vector3) -> float:
	return gap_to_progress_m(
		progress_for_position(player_position)
	)


func progress_for_position(world_position: Vector3) -> float:
	if not _path_is_usable():
		return 0.0
	return _chase_path.curve.get_closest_offset(
		_chase_path.to_local(world_position)
	)


func _set_chase_input_mode(enabled: bool) -> void:
	if (
		_player != null
		and _player.has_method("set_chase_auto_run_duration")
	):
		var duration_s := 0.0
		if enabled and _tuning != null:
			duration_s = _tuning.opening_auto_run_duration_s
		_player.call(
			"set_chase_auto_run_duration",
			duration_s
		)
	if (
		_input_router != null
		and _input_router.has_method(
			"set_screen_relative_tracking_enabled"
		)
	):
		_input_router.call(
			"set_screen_relative_tracking_enabled",
			enabled
		)


func _resolve_scene_nodes() -> void:
	_chase_path = get_node_or_null(
		chase_path_path
	) as Path3D
	_boulder_visual = get_node_or_null(
		boulder_visual_path
	) as Node3D
	_start_trigger = get_node_or_null(
		start_trigger_path
	) as Area3D
	_stop_trigger = get_node_or_null(
		stop_trigger_path
	) as Area3D


func _ensure_curve_from_markers() -> void:
	if _chase_path == null:
		return
	if (
		_chase_path.curve != null
		and _chase_path.curve.point_count > 0
	):
		return
	_chase_path.curve = RailCurveBuilderType.curve_from_markers(
		_chase_path,
		0.0,
		0.0
	)


func _connect_segment_triggers() -> void:
	if _start_trigger != null:
		var start_callback := Callable(
			self,
			&"_on_start_trigger_body_entered"
		)
		if not _start_trigger.body_entered.is_connected(
			start_callback
		):
			_start_trigger.body_entered.connect(
				start_callback
			)
	if _stop_trigger != null:
		var stop_callback := Callable(
			self,
			&"_on_stop_trigger_body_entered"
		)
		if not _stop_trigger.body_entered.is_connected(
			stop_callback
		):
			_stop_trigger.body_entered.connect(
				stop_callback
			)


func _on_start_trigger_body_entered(body: Node3D) -> void:
	if body != _player:
		return
	handle_segment_event(
		EVENT_START,
		progress_for_position(body.global_position)
	)


func _on_stop_trigger_body_entered(body: Node3D) -> void:
	if body == _player:
		handle_segment_event(
			EVENT_STOP,
			progress_for_position(body.global_position)
		)


func _trigger_progress(
	trigger: Area3D,
	fallback_m: float
) -> float:
	if trigger == null:
		return fallback_m
	return progress_for_position(trigger.global_position)


func _path_is_usable() -> bool:
	return (
		_chase_path != null
		and _chase_path.curve != null
		and _chase_path.curve.point_count > 0
	)


func _sync_visual() -> void:
	if _boulder_visual == null or not _path_is_usable():
		return
	var clamped_progress_m := clampf(
		_boulder_progress_m,
		0.0,
		_chase_path.curve.get_baked_length()
	)
	_boulder_visual.global_position = (
		_chase_path.to_global(
			_chase_path.curve.sample_baked(
				clamped_progress_m
			)
		)
	)


func _set_visual_visible(is_visible: bool) -> void:
	if _boulder_visual != null:
		_boulder_visual.visible = is_visible
