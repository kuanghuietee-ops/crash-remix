class_name RaceHUD
extends Control

## Minimal time-trial HUD (Task 7): lap counter, running timer, a wrong-way
## flash label, and a finish panel with the total time, per-lap splits, and
## a RETRY button. Polls RaceSession every frame for the always-visible
## stats the same way hud.gd's PhaseOneHUD polls its session's run_state --
## see that file's _refresh() -- and reacts to race_finished (a discrete,
## one-shot event, the same shape as LevelSession's run_completed) to reveal
## the finish panel once, rather than polling is_finished() every tick.
##
## session is duck-typed to RaceSession's poll surface (current_lap()/
## lap_count()/elapsed_s()/is_wrong_way(), plus the race_finished signal)
## via .call()/.connect() rather than a static RaceSession type hint, the
## same duck-typing convention kart_camera.gd and racing_input_adapter.gd
## already use for their own Node/Object collaborators -- this HUD is
## testable against a small fake session with no scene tree involved.

const TimeFormatType := preload("res://src/core/time_format.gd")
const RACE_SCENE_PATH := "res://scenes/racing/race_time_trial.tscn"

var _session: Object

@onready var _lap_label: Label = $SafeArea/Stats/Margin/Rows/Lap
@onready var _timer_label: Label = $SafeArea/Stats/Margin/Rows/Timer
@onready var _wrong_way_label: Label = $SafeArea/WrongWay
@onready var _finish_panel: PanelContainer = $SafeArea/FinishPanel
@onready var _finish_total_label: Label = (
	$SafeArea/FinishPanel/Margin/Rows/Total
)
@onready var _finish_splits_label: Label = (
	$SafeArea/FinishPanel/Margin/Rows/Splits
)
@onready var _retry_button: Button = (
	$SafeArea/FinishPanel/Margin/Rows/Retry
)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wrong_way_label.visible = false
	_finish_panel.visible = false
	_retry_button.pressed.connect(_on_retry_pressed)


func configure(session: Object) -> void:
	_session = session
	_finish_panel.visible = false
	_connect_once(_session, &"race_finished", _on_race_finished)
	_refresh()


func _process(_delta_s: float) -> void:
	_refresh()


func _refresh() -> void:
	if _session == null or not is_instance_valid(_session):
		return
	var lap: int = int(_session.call("current_lap"))
	var lap_total: int = int(_session.call("lap_count"))
	_lap_label.text = "LAP  %d / %d" % [lap, lap_total]
	_timer_label.text = TimeFormatType.mm_ss_mmm(
		float(_session.call("elapsed_s"))
	)
	_wrong_way_label.visible = bool(_session.call("is_wrong_way"))


func _on_race_finished(total_s: float, lap_times: Array) -> void:
	_finish_panel.visible = true
	_finish_total_label.text = "TOTAL  " + TimeFormatType.mm_ss_mmm(total_s)
	var lines: Array[String] = []
	for lap_index: int in range(lap_times.size()):
		lines.append(
			"LAP %d  %s" % [
				lap_index + 1,
				TimeFormatType.mm_ss_mmm(float(lap_times[lap_index])),
			]
		)
	_finish_splits_label.text = "\n".join(lines)


func _on_retry_pressed() -> void:
	get_tree().change_scene_to_file(RACE_SCENE_PATH)


func _connect_once(
	source: Object,
	signal_name: StringName,
	callback: Callable
) -> void:
	if (
		source.has_signal(signal_name)
		and not source.is_connected(signal_name, callback)
	):
		source.connect(signal_name, callback)
