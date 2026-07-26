class_name HogMount
extends Node3D

signal mounted
signal dismounted

@export var ride_path_path: NodePath
@export var mount_trigger_path: NodePath
@export var dismount_trigger_path: NodePath
@export var hog_visual_path: NodePath
@export var mounted_visual_offset := Vector3.ZERO

var _player: Node3D
var _ride_path: Path3D
var _mount_trigger: Area3D
var _dismount_trigger: Area3D
var _hog_visual: Node3D
var _visual_home: Node
var _authored_visual_transform := Transform3D.IDENTITY
var _mounted: bool


func _ready() -> void:
	add_to_group(&"hog_mount")
	_resolve_scene_nodes()
	_ensure_curve_from_markers()
	_remember_authored_visual()
	_connect_triggers()


func configure(player: Node3D) -> void:
	_player = player
	_resolve_scene_nodes()
	_ensure_curve_from_markers()
	_remember_authored_visual()
	_connect_triggers()
	if _player != null:
		reset_for_player_position(_player.global_position)


func reset_for_player_position(player_position: Vector3) -> void:
	if _player == null or not _path_is_usable():
		_set_mounted(false, true)
		return
	var player_progress_m := progress_for_position(
		player_position
	)
	var mount_progress_m := _trigger_progress(
		_mount_trigger,
		0.0
	)
	var dismount_progress_m := _trigger_progress(
		_dismount_trigger,
		_ride_path.curve.get_baked_length()
	)
	if (
		player_progress_m >= mount_progress_m
		and player_progress_m < dismount_progress_m
	):
		_set_mounted(true)
	elif player_progress_m < mount_progress_m:
		_set_mounted(false, true)
	else:
		_set_mounted(false)


func is_mounted() -> bool:
	return _mounted


func progress_for_position(world_position: Vector3) -> float:
	if not _path_is_usable():
		return 0.0
	return _ride_path.curve.get_closest_offset(
		_ride_path.to_local(world_position)
	)


func _set_mounted(
	next_mounted: bool,
	restore_authored_visual: bool = false
) -> void:
	if next_mounted:
		if (
			_player == null
			or not _player.has_method("mount_hog")
		):
			return
		_player.call("mount_hog")
		_attach_visual()
		if not _mounted:
			mounted.emit()
		_mounted = true
		return
	if (
		_player != null
		and _player.has_method("dismount_hog")
	):
		_player.call("dismount_hog")
	_detach_visual(restore_authored_visual)
	if _mounted:
		dismounted.emit()
	_mounted = false


func _attach_visual() -> void:
	if (
		not is_instance_valid(_hog_visual)
		or _player == null
	):
		return
	if _hog_visual.get_parent() != _player:
		_hog_visual.reparent(_player, false)
	_hog_visual.position = mounted_visual_offset
	_hog_visual.rotation = Vector3.ZERO


func _detach_visual(restore_authored: bool) -> void:
	if (
		not is_instance_valid(_hog_visual)
		or not is_instance_valid(_visual_home)
	):
		return
	if _hog_visual.get_parent() != _visual_home:
		_hog_visual.reparent(_visual_home, true)
	if restore_authored:
		_hog_visual.transform = _authored_visual_transform


func _resolve_scene_nodes() -> void:
	_ride_path = get_node_or_null(
		ride_path_path
	) as Path3D
	_mount_trigger = get_node_or_null(
		mount_trigger_path
	) as Area3D
	_dismount_trigger = get_node_or_null(
		dismount_trigger_path
	) as Area3D
	if not is_instance_valid(_hog_visual):
		_hog_visual = get_node_or_null(
			hog_visual_path
		) as Node3D


func _remember_authored_visual() -> void:
	if (
		not is_instance_valid(_hog_visual)
		or is_instance_valid(_visual_home)
	):
		return
	_visual_home = _hog_visual.get_parent()
	_authored_visual_transform = _hog_visual.transform


func _ensure_curve_from_markers() -> void:
	if _ride_path == null:
		return
	if (
		_ride_path.curve != null
		and _ride_path.curve.point_count > 0
	):
		return
	var curve := Curve3D.new()
	for marker: Node in _ride_path.get_children():
		if marker is Marker3D:
			curve.add_point((marker as Marker3D).position)
	_ride_path.curve = curve


func _connect_triggers() -> void:
	if _mount_trigger != null:
		var mount_callback := Callable(
			self,
			&"_on_mount_trigger_body_entered"
		)
		if not _mount_trigger.body_entered.is_connected(
			mount_callback
		):
			_mount_trigger.body_entered.connect(
				mount_callback
			)
	if _dismount_trigger != null:
		var dismount_callback := Callable(
			self,
			&"_on_dismount_trigger_body_entered"
		)
		if not _dismount_trigger.body_entered.is_connected(
			dismount_callback
		):
			_dismount_trigger.body_entered.connect(
				dismount_callback
			)


func _on_mount_trigger_body_entered(body: Node3D) -> void:
	if body == _player:
		_set_mounted(true)


func _on_dismount_trigger_body_entered(body: Node3D) -> void:
	if body == _player:
		_set_mounted(false)


func _trigger_progress(
	trigger: Area3D,
	fallback_m: float
) -> float:
	if trigger == null:
		return fallback_m
	return progress_for_position(
		trigger.global_position
	)


func _path_is_usable() -> bool:
	return (
		_ride_path != null
		and _ride_path.curve != null
		and _ride_path.curve.point_count > 0
	)
