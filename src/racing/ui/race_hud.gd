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
##
## Fix round (H1 review): RETRY used to call
## get_tree().change_scene_to_file() directly -- which frees GameRoot (the
## real scene tree root) out from under itself, and the fresh race scene
## nobody calls configure() on ever plays again. RETRY now only calls
## session.request_retry(); see race_session.gd's retry_requested doc and
## game_root.gd's DEBUG_RACING_LEVEL_ID render branch for the real,
## GameRoot-owned reload path this routes into instead.
##
## HELD-ITEM DISPLAY (R4 Task 6). _item_label mirrors _wrong_way_label's own
## "poll every _refresh() tick, toggle .visible directly, no signal" shape:
## hidden for an EMPTY slot, hidden for the whole session when RaceSession.
## items_enabled() reads false (a solo race -- see that method's own doc),
## and otherwise showing either the roulette FLICKER (ItemSlot.
## rolling_display_item(), while &"rolling") or the landed item's own name
## (ItemSlot.held_item(), while &"held") -- graybox text, no icon yet. See
## _refresh_item_display().

const TimeFormatType := preload("res://src/core/time_format.gd")

var _session: Object

@onready var _lap_label: Label = $SafeArea/Stats/Margin/Rows/Lap
@onready var _timer_label: Label = $SafeArea/Stats/Margin/Rows/Timer
@onready var _item_label: Label = $SafeArea/Stats/Margin/Rows/Item
@onready var _wrong_way_label: Label = $SafeArea/WrongWay
@onready var _finish_panel: PanelContainer = $SafeArea/FinishPanel
@onready var _finish_total_label: Label = (
	$SafeArea/FinishPanel/Margin/Rows/Total
)
@onready var _placement_label: Label = (
	$SafeArea/FinishPanel/Margin/Rows/Placement
)
@onready var _new_best_label: Label = (
	$SafeArea/FinishPanel/Margin/Rows/NewBest
)
@onready var _best_label: Label = (
	$SafeArea/FinishPanel/Margin/Rows/Best
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
	_item_label.visible = false
	_finish_panel.visible = false
	_new_best_label.visible = false
	_placement_label.visible = false
	_retry_button.pressed.connect(_on_retry_pressed)


func configure(session: Object) -> void:
	_session = session
	_finish_panel.visible = false
	_new_best_label.visible = false
	_placement_label.visible = false
	_best_label.text = ""
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
	_refresh_item_display()


## See the class doc's HELD-ITEM DISPLAY section. Hidden (no text update --
## a hidden label showing stale text is harmless, nothing reads .text while
## !visible) for a solo session (items_enabled() false) or an EMPTY slot;
## otherwise shows the roulette flicker while &"rolling" or the landed
## item's own name while &"held" -- ItemSlot never reports anything else
## (see item_slot.gd's own state() doc), so no third branch is needed.
func _refresh_item_display() -> void:
	if not bool(_session.call("items_enabled")):
		_item_label.visible = false
		return
	var slot: Object = _session.call("player_item_slot")
	if slot == null:
		_item_label.visible = false
		return
	var state: StringName = slot.call("state")
	if state == &"empty":
		_item_label.visible = false
		return
	_item_label.visible = true
	var display_item: StringName = (
		slot.call("rolling_display_item") if state == &"rolling"
		else slot.call("held_item")
	)
	_item_label.text = "ITEM  " + String(display_item).to_upper()


func _on_race_finished(total_s: float, lap_times: Array) -> void:
	_finish_panel.visible = true
	# Best-time labels are populated by present_best_times() below, called
	# by GameRoot in response to this same race_finished signal once it has
	# compared this run against the saved best (see race_session.gd's
	# present_best_times doc for why that comparison doesn't happen here) --
	# reset to the not-yet-known state so a stale marker from a previous
	# finish on a retried session can never bleed into this one.
	_new_best_label.visible = false
	_best_label.text = ""
	_finish_total_label.text = "TOTAL  " + TimeFormatType.mm_ss_mmm(total_s)

	# Task 5 (CTR R3 integration): "FINISHED n / m" only makes sense once
	# there is a field to place against -- a solo time trial (m == 1, no AI
	# opponents; see race_session.gd's placement_out_of()) shows the old
	# panel completely unchanged, gated here rather than by track/scene so a
	# test that pins opponent_count to 0 (the established in-test override
	# pattern) gets the exact same solo behavior as before this task without
	# RaceSession needing to know or care that HUD exists.
	var placement_out_of := int(_session.call("placement_out_of"))
	_placement_label.visible = placement_out_of > 1
	if placement_out_of > 1:
		_placement_label.text = "FINISHED  %d / %d" % [
			int(_session.call("placement")),
			placement_out_of,
		]
	var lines: Array[String] = []
	for lap_index: int in range(lap_times.size()):
		lines.append(
			"LAP %d  %s" % [
				lap_index + 1,
				TimeFormatType.mm_ss_mmm(float(lap_times[lap_index])),
			]
		)
	_finish_splits_label.text = "\n".join(lines)


## Called by RaceSession (see its own doc) once GameRoot has compared this
## run's total/lap against the saved best and decided whether to persist it.
## Renders unconditionally -- even a run that did NOT beat the record still
## shows what the best times still are, only the NEW BEST marker is
## conditional. Payload times arrive as milliseconds (matching
## SaveModel's racing record shape) so this stays a pure display step with
## no independent comparison logic of its own to drift out of sync with
## GameRoot's.
func present_best_times(payload: Dictionary) -> void:
	var best_total_s := (
		float(payload.get("best_total_ms", 0))
		/ TimeFormatType.MILLISECONDS_PER_SECOND
	)
	var best_lap_s := (
		float(payload.get("best_lap_ms", 0))
		/ TimeFormatType.MILLISECONDS_PER_SECOND
	)
	_best_label.text = "BEST  %s   BEST LAP  %s" % [
		TimeFormatType.mm_ss_mmm(best_total_s),
		TimeFormatType.mm_ss_mmm(best_lap_s),
	]
	_new_best_label.visible = (
		bool(payload.get("new_best_total", false))
		or bool(payload.get("new_best_lap", false))
	)


func _on_retry_pressed() -> void:
	if _session != null and is_instance_valid(_session):
		_session.call("request_retry")


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
