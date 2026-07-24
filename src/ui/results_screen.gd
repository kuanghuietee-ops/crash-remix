class_name ResultsScreen
extends Control

signal retry_requested
signal relic_requested
signal hub_requested

@onready var _title: Label = (
	$SafeArea/Center/Panel/Margin/Rows/Title
)
@onready var _summary: Label = (
	$SafeArea/Center/Panel/Margin/Rows/Summary
)
@onready var _misses: Label = (
	$SafeArea/Center/Panel/Margin/Rows/Misses
)
@onready var _relic: Label = (
	$SafeArea/Center/Panel/Margin/Rows/Relic
)
@onready var _retry: Button = (
	$SafeArea/Center/Panel/Margin/Rows/Actions/Retry
)
@onready var _relic_trial: Button = (
	$SafeArea/Center/Panel/Margin/Rows/Actions/RelicTrial
)
@onready var _hub: Button = (
	$SafeArea/Center/Panel/Margin/Rows/Actions/Hub
)


func _ready() -> void:
	_retry.pressed.connect(func() -> void: retry_requested.emit())
	_relic_trial.pressed.connect(
		func() -> void: relic_requested.emit()
	)
	_hub.pressed.connect(func() -> void: hub_requested.emit())


func present(payload: Dictionary) -> void:
	_title.text = str(
		payload.get("display_name", "LEVEL COMPLETE")
	)
	_summary.text = (
		"CRATES  %d / %d\nGEM  %s\nFLAWLESS  %s\nWUMPA BANKED  %d"
		% [
			int(payload.get("box_count", 0)),
			int(payload.get("crate_count", 0)),
			"YES" if bool(payload.get("gem", false)) else "NO",
			"YES" if bool(payload.get("flawless", false)) else "NO",
			int(payload.get("wumpa_banked", 0)),
		]
	)
	_misses.text = _missed_segments_text(
		payload.get("missed_crate_ids_by_segment", {})
	)
	var relic_time: Variant = payload.get("relic_time_s")
	var relic_tier: Variant = payload.get("relic_tier")
	_relic.visible = relic_time != null or relic_tier != null
	if _relic.visible:
		_relic.text = "RELIC  %s   %s" % [
			str(relic_time),
			str(relic_tier),
		]
	_relic_trial.visible = bool(
		payload.get("relic_entry_available", false)
	)


func _missed_segments_text(value: Variant) -> String:
	if not value is Dictionary:
		return "MISSED CRATES  NONE"
	var grouped: Dictionary = value
	if grouped.is_empty():
		return "MISSED CRATES  NONE"
	var names := PackedStringArray()
	for segment_value: Variant in grouped:
		names.append(str(segment_value))
	names.sort()
	var lines := PackedStringArray(["MISSED CRATES"])
	for segment_name: String in names:
		lines.append(
			"%s: %s" % [
				segment_name,
				str(grouped[segment_name]),
			]
		)
	return "\n".join(lines)
