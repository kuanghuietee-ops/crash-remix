class_name LevelListOverlay
extends Control

const RacingTrackRegistryType := preload(
	"res://src/racing/track/track_registry.gd"
)

signal level_requested(level_id: StringName)
signal toybox_requested
signal look_dev_requested
# Task 4 (CTR R7): one generic signal replaces what used to be a hand-
# declared signal PER racing button (racing_time_trial_requested,
# racing_sanity_shores_requested, and the two Fix-wave MEDIUM-5 solo
# counterparts) -- see _RACING_BUTTONS below for the table every racing
# button now wires through instead. GameRoot's own _on_racing_track_
# requested() is the sole subscriber (verified before this refactor: no
# other file read the old per-track signal names), so collapsing them is
# safe -- no test asserts on a signal NAME, only on each real button's
# NODE PATH and the Content child it produces, both unchanged below.
signal racing_track_requested(track_id: StringName, is_solo: bool)
signal closed

# Task 4 (CTR R7): one row per racing button -- which node, which track
# (matched against RacingTrackRegistryType.TRACKS by track_id), and
# whether it's the TIME TRIAL/solo entry (spawn_opponents=false) or the
# AI-populated RACE entry (Fix-wave MEDIUM-5's own split). _ready() wires
# every row's Button.pressed the same way; configure() toggles every
# row's visibility the same way; _button_text() derives each row's label
# from the registry's own display_name instead of a hand-typed string
# per button. Adding a track's two menu entries is now "add two rows
# here" instead of "add two signals + two consts + two connect() calls +
# two handler functions on the GameRoot side too".
const _RACING_BUTTONS: Array[Dictionary] = [
	{node_name = &"RacingTimeTrial", track_id = &"graybox_loop", is_solo = false},
	{node_name = &"RacingSanityShores", track_id = &"sanity_shores", is_solo = false},
	{node_name = &"RacingTimeTrialSolo", track_id = &"graybox_loop", is_solo = true},
	{
		node_name = &"RacingSanityShoresTimeTrial",
		track_id = &"sanity_shores",
		is_solo = true,
	},
	{node_name = &"RacingTempleTwilight", track_id = &"temple_twilight", is_solo = false},
	{
		node_name = &"RacingTempleTwilightTimeTrial",
		track_id = &"temple_twilight",
		is_solo = true,
	},
]


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
	# Task 4 (CTR R7): every racing button, existing and new, wires through
	# the SAME table row -> connect() + text derivation below -- see
	# _RACING_BUTTONS' own class doc.
	for row in _RACING_BUTTONS:
		var button := _racing_button(row.node_name)
		button.text = _button_text(row.track_id, row.is_solo)
		button.pressed.connect(
			func() -> void:
				racing_track_requested.emit(row.track_id, row.is_solo)
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
	# Task 7 (CTR racing mode, R1)/Task 4 (CTR R7): same debug-only gate as
	# Toybox/LookDev above, now applied to every racing row in one loop
	# instead of one hand-written `.visible = debug_tools_enabled` line per
	# button. Debt, noted in the R1 report: a real mode-select entry (not
	# gated behind debug tools, not living in the level list) is follow-up
	# work once racing has more than a prototype to show.
	for row in _RACING_BUTTONS:
		_racing_button(row.node_name).visible = debug_tools_enabled


func _racing_button(node_name: StringName) -> Button:
	return $SafeArea/Center/Panel/Margin/Rows.get_node(
		NodePath(node_name)
	) as Button


## Reproduces the pre-Task-4 hand-typed button text exactly (e.g.
## "RACE — SANITY SHORES  [DEBUG]" / "TIME TRIAL — GRAYBOX LOOP  [DEBUG]")
## from RacingTrackRegistryType.TRACKS' own display_name -- see that
## const's class doc for why display_name lives there and not here.
func _button_text(track_id: StringName, is_solo: bool) -> String:
	var mode_label := "TIME TRIAL" if is_solo else "RACE"
	var display_name := track_id
	for track in RacingTrackRegistryType.TRACKS:
		if track.track_id == track_id:
			display_name = track.display_name
			break
	return "%s — %s  [DEBUG]" % [mode_label, display_name]
