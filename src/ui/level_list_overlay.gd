class_name LevelListOverlay
extends Control

signal level_requested(level_id: StringName)
signal toybox_requested
signal look_dev_requested
signal racing_time_trial_requested
signal closed


func _ready() -> void:
	$SafeArea/Center/Panel/Margin/Rows/NSanityBeach.pressed.connect(
		func() -> void:
			level_requested.emit(&"wr1_n_sanity_beach")
	)
	$SafeArea/Center/Panel/Margin/Rows/Boulders.pressed.connect(
		func() -> void:
			level_requested.emit(&"wr1_boulders")
	)
	$SafeArea/Center/Panel/Margin/Rows/HogWild.pressed.connect(
		func() -> void:
			level_requested.emit(&"wr1_hog_wild")
	)
	$SafeArea/Center/Panel/Margin/Rows/Toybox.pressed.connect(
		func() -> void: toybox_requested.emit()
	)
	$SafeArea/Center/Panel/Margin/Rows/LookDev.pressed.connect(
		func() -> void: look_dev_requested.emit()
	)
	$SafeArea/Center/Panel/Margin/Rows/RacingTimeTrial.pressed.connect(
		func() -> void: racing_time_trial_requested.emit()
	)
	$SafeArea/Center/Panel/Margin/Rows/Close.pressed.connect(
		func() -> void: closed.emit()
	)


func configure(debug_tools_enabled: bool) -> void:
	$SafeArea/Center/Panel/Margin/Rows/Toybox.visible = (
		debug_tools_enabled
	)
	$SafeArea/Center/Panel/Margin/Rows/LookDev.visible = (
		debug_tools_enabled
	)
	# Task 7 (CTR racing mode, R1): same debug-only gate as Toybox/LookDev
	# above -- see game_root.gd's DEBUG_RACING_LEVEL_ID branch. Debt, noted
	# in the R1 report: a real mode-select entry (not gated behind debug
	# tools, not living in the level list) is follow-up work once racing
	# has more than a graybox kart-feel prototype to show.
	$SafeArea/Center/Panel/Margin/Rows/RacingTimeTrial.visible = (
		debug_tools_enabled
	)
