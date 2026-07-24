class_name LevelListOverlay
extends Control

signal level_requested(level_id: StringName)
signal toybox_requested
signal closed


func _ready() -> void:
	$SafeArea/Center/Panel/Margin/Rows/NSanityBeach.pressed.connect(
		func() -> void:
			level_requested.emit(&"wr1_n_sanity_beach")
	)
	$SafeArea/Center/Panel/Margin/Rows/Toybox.pressed.connect(
		func() -> void: toybox_requested.emit()
	)
	$SafeArea/Center/Panel/Margin/Rows/Close.pressed.connect(
		func() -> void: closed.emit()
	)


func configure(debug_tools_enabled: bool) -> void:
	$SafeArea/Center/Panel/Margin/Rows/Toybox.visible = (
		debug_tools_enabled
	)
