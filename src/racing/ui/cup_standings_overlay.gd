class_name CupStandingsOverlay
extends Control

## Task 5 (CTR R7, the Cup): the ONE overlay GameRoot uses for both required
## Cup screens -- the between-race standings interstitial (after race 1) and
## the final cup podium (after race 2) -- rather than two separate scenes.
## Both are "show CupSession.standings(), read straight off" (see cup_
## session.gd's own standings() doc for that shape); the only real
## difference is whether there is a next race to CONTINUE into or the cup is
## over, which present()'s own is_final parameter switches.
##
## OWNERSHIP. This is a GameRoot-level overlay (added to the `_ui` CanvasLayer
## alongside level_list_overlay/pause_overlay/results_screen -- see game_
## root.gd's own _install_task11_ui()), NOT a child of any race scene. A race
## scene is torn down and rebuilt between race 1 and race 2 (see cup_
## session.gd's own OWNERSHIP doc); this overlay survives that swap exactly
## the way GameRoot's other persistent screens already do, so it can sit on
## top of race 1's own finish panel without needing to know anything about
## the race scene underneath it.
##
## SIGNALS. continue_requested (interstitial only, CONTINUE button) and
## closed (podium only, CLOSE button) are the two ways a player dismisses
## this overlay -- GameRoot connects both once, at install time, the same
## "connect once, react in one handler" shape it already uses for every
## other overlay signal (results_screen.retry_requested, pause_overlay.
## quit_requested, etc.).

signal continue_requested
signal closed

@onready var _title: Label = $SafeArea/Center/Panel/Margin/Rows/Title
@onready var _row_labels: Array[Label] = [
	$SafeArea/Center/Panel/Margin/Rows/Row1,
	$SafeArea/Center/Panel/Margin/Rows/Row2,
	$SafeArea/Center/Panel/Margin/Rows/Row3,
	$SafeArea/Center/Panel/Margin/Rows/Row4,
	$SafeArea/Center/Panel/Margin/Rows/Row5,
	$SafeArea/Center/Panel/Margin/Rows/Row6,
]
@onready var _winner_label: Label = $SafeArea/Center/Panel/Margin/Rows/Winner
@onready var _continue_button: Button = (
	$SafeArea/Center/Panel/Margin/Rows/Continue
)
@onready var _close_button: Button = $SafeArea/Center/Panel/Margin/Rows/Close


func _ready() -> void:
	visible = false
	_winner_label.visible = false
	_continue_button.pressed.connect(
		func() -> void: continue_requested.emit()
	)
	_close_button.pressed.connect(
		func() -> void: closed.emit()
	)


## rows: CupSession.standings()' own return shape -- one Dictionary per
## participant, already ordered 1..N, each carrying position/label/
## total_points/is_player (see that method's own doc). is_final selects
## between the two screens this overlay renders (see the class doc above):
## true is the PODIUM (CLOSE + Winner visible, CONTINUE hidden); false is the
## interstitial (CONTINUE visible, CLOSE/Winner hidden). race_label names
## the just-finished race for the interstitial's own title ("STANDINGS —
## AFTER SANITY SHORES"); ignored when is_final is true (the podium's own
## title is fixed).
func present(rows: Array, is_final: bool, race_label: String) -> void:
	visible = true
	_title.text = "CUP COMPLETE" if is_final else (
		"STANDINGS — AFTER " + race_label.to_upper()
	)
	# src/racing/** numeric-literal lint: row count is derived from _row_
	# labels' own size (an authored scene node list) rather than a separate
	# literal constant that could silently drift from it.
	for row_index: int in range(_row_labels.size()):
		var label := _row_labels[row_index]
		if row_index >= rows.size():
			label.visible = false
			continue
		var row: Dictionary = rows[row_index]
		label.visible = true
		label.text = _row_text(row)

	_winner_label.visible = is_final and not rows.is_empty()
	if _winner_label.visible:
		_winner_label.text = "CHAMPION: " + String(rows[0].get("label", ""))

	_continue_button.visible = not is_final
	_close_button.visible = is_final


func _row_text(row: Dictionary) -> String:
	var marker := "> " if bool(row.get("is_player", false)) else "  "
	var position: int = int(row.get("position", 0))
	var label: String = String(row.get("label", ""))
	var total_points: float = float(row.get("total_points", 0.0))
	return "%s%d. %s   %d PTS" % [marker, position, label, roundi(total_points)]
