class_name PauseOverlay
extends Control

signal resume_requested
signal retry_requested
signal level_list_requested
signal quit_requested


func _ready() -> void:
	$SafeArea/Center/Panel/Margin/Rows/Resume.pressed.connect(
		func() -> void: resume_requested.emit()
	)
	$SafeArea/Center/Panel/Margin/Rows/Retry.pressed.connect(
		func() -> void: retry_requested.emit()
	)
	$SafeArea/Center/Panel/Margin/Rows/LevelList.pressed.connect(
		func() -> void: level_list_requested.emit()
	)
	$SafeArea/Center/Panel/Margin/Rows/Quit.pressed.connect(
		func() -> void: quit_requested.emit()
	)
