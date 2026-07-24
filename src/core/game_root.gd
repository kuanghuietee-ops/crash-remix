class_name GameRoot
extends Node

const TuningServiceType := preload("res://src/tuning/tuning_service.gd")
const GameFlowType := preload("res://src/core/game_flow.gd")
const SaveServiceType := preload("res://src/core/save_service.gd")
const SessionSnapshotType := preload(
	"res://src/core/session_snapshot.gd"
)

const BASE_TUNING_PATH := "res://data/tuning/gameplay.tres"
const OVERRIDE_TUNING_PATH := "user://tuning/override.tres"
const DEFAULT_SAVE_DIR := "user://save"
const _PLACEHOLDER_NAMES: Dictionary = {
	GameFlow.State.WARP_ROOM: &"WarpRoomPlaceholder",
	GameFlow.State.LEVEL: &"LevelPlaceholder",
	GameFlow.State.RESULTS: &"ResultsPlaceholder",
}

@export var save_dir: String = DEFAULT_SAVE_DIR

var tuning_service: TuningServiceType = TuningServiceType.new()
var save_service: SaveServiceType = SaveServiceType.new()
var session_snapshot: SessionSnapshotType = SessionSnapshotType.new()
var flow: GameFlowType = GameFlowType.new()
var profile: Dictionary = {}
var boot_error: Error = OK
var last_snapshot_error: Error = OK
var active_level_session: Node

@onready var _content: Node = $Content
@onready var _tuning_debug: TuningDebugUI = $UI/TuningDebug


static func should_enable_debug_tools(is_debug_build: bool) -> bool:
	return is_debug_build


func _ready() -> void:
	Input.set_use_accumulated_input(false)
	boot_error = tuning_service.load_from_paths(
		BASE_TUNING_PATH,
		OVERRIDE_TUNING_PATH
	)
	if boot_error != OK:
		push_error("Phase 1 tuning failed to load: " + error_string(boot_error))
		return

	PhaseState.configure(tuning_service.catalog.phase)
	var debug_tools_enabled := should_enable_debug_tools(OS.is_debug_build())
	_tuning_debug.visible = debug_tools_enabled
	if debug_tools_enabled:
		_tuning_debug.configure(tuning_service, OVERRIDE_TUNING_PATH)
		_tuning_debug.tuning_changed.connect(_on_tuning_changed)

	profile = save_service.load_profile(save_dir)
	if save_service.refused_future_version:
		boot_error = ERR_UNAVAILABLE
		push_error("Save data was written by a newer version of Crash Remix.")
		return
	if not SaveModel.validate(profile):
		boot_error = ERR_INVALID_DATA
		push_error("Phase 1 profile failed validation.")
		return

	boot_error = dispatch({"type": GameFlow.EVENT_SAVE_LOADED})
	if boot_error != OK:
		return
	var saved_session := session_snapshot.load(save_dir)
	if not saved_session.is_empty():
		boot_error = dispatch({
			"type": GameFlow.EVENT_SESSION_RESUME_AVAILABLE,
			"snapshot": saved_session,
		})


func _notification(what: int) -> void:
	if not is_node_ready():
		return
	if (
		what == NOTIFICATION_APPLICATION_PAUSED
		or what == NOTIFICATION_WM_CLOSE_REQUEST
	):
		_pause_and_snapshot_active_run()


func dispatch(event: Dictionary) -> Error:
	var previous_state := flow.state
	var transition_error := flow.dispatch(event)
	if transition_error != OK:
		return transition_error
	if flow.state != previous_state:
		_render_state()
	var event_type := StringName(event.get("type", &""))
	if event_type in [
		GameFlow.EVENT_LEVEL_COMPLETE,
		GameFlow.EVENT_QUIT_LEVEL,
	]:
		_clear_session_snapshot()
	return OK


func state_name() -> StringName:
	return flow.state_name()


func set_active_level_session(session: Node) -> void:
	_disconnect_active_level_session()
	active_level_session = session
	if active_level_session == null:
		return
	if active_level_session.has_signal(&"run_completed"):
		active_level_session.connect(
			&"run_completed",
			_on_level_session_completed
		)
	if active_level_session.has_signal(&"run_exited"):
		active_level_session.connect(
			&"run_exited",
			_on_level_session_exited
		)


func _on_tuning_changed(_fingerprint: String) -> void:
	PhaseState.configure(tuning_service.catalog.phase)


func _pause_and_snapshot_active_run() -> void:
	if flow.state == GameFlow.State.LEVEL:
		dispatch({"type": GameFlow.EVENT_PAUSE})
	elif flow.state != GameFlow.State.PAUSED:
		return
	if (
		active_level_session == null
		or not is_instance_valid(active_level_session)
	):
		return
	var run_state: Variant = active_level_session.get("run_state")
	if run_state == null or not run_state.has_method("snapshot"):
		return
	var saved: Dictionary = run_state.call("snapshot")
	if saved.is_empty():
		return
	if saved.get("mode") == LevelRunState.MODE_RELIC:
		saved["relic_void"] = true
	last_snapshot_error = session_snapshot.store(save_dir, saved)


func _clear_session_snapshot() -> void:
	last_snapshot_error = session_snapshot.delete(save_dir)
	_disconnect_active_level_session()
	active_level_session = null


func _on_level_session_completed(_results: Dictionary) -> void:
	_clear_session_snapshot()


func _on_level_session_exited() -> void:
	_clear_session_snapshot()


func _disconnect_active_level_session() -> void:
	if (
		active_level_session == null
		or not is_instance_valid(active_level_session)
	):
		return
	var completed_callback := Callable(
		self,
		"_on_level_session_completed"
	)
	if (
		active_level_session.has_signal(&"run_completed")
		and active_level_session.is_connected(
			&"run_completed",
			completed_callback
		)
	):
		active_level_session.disconnect(
			&"run_completed",
			completed_callback
		)
	var exited_callback := Callable(self, "_on_level_session_exited")
	if (
		active_level_session.has_signal(&"run_exited")
		and active_level_session.is_connected(
			&"run_exited",
			exited_callback
		)
	):
		active_level_session.disconnect(
			&"run_exited",
			exited_callback
		)


func _render_state() -> void:
	if flow.state == GameFlow.State.PAUSED:
		return

	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.free()

	if not _PLACEHOLDER_NAMES.has(flow.state):
		return
	var placeholder := Node3D.new()
	placeholder.name = _PLACEHOLDER_NAMES[flow.state]
	_content.add_child(placeholder)
