class_name GameRoot
extends Node

const TuningServiceType := preload("res://src/tuning/tuning_service.gd")
const GameFlowType := preload("res://src/core/game_flow.gd")
const SaveServiceType := preload("res://src/core/save_service.gd")

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
var flow: GameFlowType = GameFlowType.new()
var profile: Dictionary = {}
var boot_error: Error = OK

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


func dispatch(event: Dictionary) -> Error:
	var previous_state := flow.state
	var transition_error := flow.dispatch(event)
	if transition_error != OK:
		return transition_error
	if flow.state != previous_state:
		_render_state()
	return OK


func state_name() -> StringName:
	return flow.state_name()


func _on_tuning_changed(_fingerprint: String) -> void:
	PhaseState.configure(tuning_service.catalog.phase)


func _render_state() -> void:
	if flow.state == GameFlow.State.PAUSED:
		return

	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()

	if not _PLACEHOLDER_NAMES.has(flow.state):
		return
	var placeholder := Node3D.new()
	placeholder.name = _PLACEHOLDER_NAMES[flow.state]
	_content.add_child(placeholder)
