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
##
## COUNTDOWN + BOOST HINT (R5 Task 1). _countdown_label/_boost_hint_label
## poll RaceSession.is_race_started()/countdown_phase() every _refresh()
## tick, the exact same "poll every tick, toggle .visible directly, no
## signal" shape _wrong_way_label/_item_label already use one section up.
## _boost_hint_label is visible for the WHOLE pre-race countdown and hidden
## the instant is_race_started() reads true, never shown again afterward.
## countdown_phase() is only ever consulted while NOT started (see the class
## doc's own "RaceSession stops ticking the countdown past go" note on race_
## session.gd -- countdown_phase() can keep reporting &"go" forever after the
## real race starts, which is exactly why this HUD gates on the separate
## is_race_started() flag rather than ever comparing phase() to &"running").
##
## LIVE POSITION (R5 Task 2). _position_label mirrors _wrong_way_label's/
## _item_label's own "poll every _refresh() tick, toggle .visible directly,
## no signal" shape one more time: visible only during the live body of a
## race against a real field -- post-GO (RaceSession.is_race_started()),
## pre-finish (not RaceSession.is_finished() -- the FINISHED panel takes
## over from here, see _on_race_finished() below), and only when there is
## someone to rank against at all (RaceSession.field_size() > 1, the exact
## same "m > 1" gate placement_out_of()'s own FINISHED panel already uses
## one section down -- a solo race has nobody to place against either way).
## Text reads "POS  n / m" off RaceSession.player_position()/field_size(),
## both live per-tick reads (see race_session.gd's own LIVE RANKING class-
## doc section), never the FINISHED panel's one-shot placement()/
## placement_out_of().
##
## GO FLASH (fix round 1, reviewer [LOW-1]): _countdown_label does NOT just
## hide the instant is_race_started() flips true -- that used to make the
## "GO!" text unrenderable by construction, since RaceSession's own unfreeze/
## boost effects land the SAME tick is_race_started() flips (see race_
## session.gd's own _start_race() doc), so a HUD gated on that flag alone
## never had a tick where it was both true AND still worth showing anything
## for. Instead, once started, this HUD holds "GO!" visible for one more
## whole countdown_step_s (RaceSession.countdown_step_s(), the SAME per-phase
## beat every 3/2/1 digit was already shown for -- see that getter's own
## doc), measured against elapsed_s() itself (which starts counting at
## exactly this same GO instant, see race_session.gd's own TIMER section) --
## no new timer of its own, no new tuning field, and pause-correct for free
## since elapsed_s() already is. _refresh_countdown_display() below is the
## one place that owns this window.

const TimeFormatType := preload("res://src/core/time_format.gd")

var _session: Object

@onready var _lap_label: Label = $SafeArea/Stats/Margin/Rows/Lap
@onready var _position_label: Label = $SafeArea/Stats/Margin/Rows/Position
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
@onready var _countdown_label: Label = $SafeArea/Countdown
@onready var _boost_hint_label: Label = $SafeArea/BoostHint


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wrong_way_label.visible = false
	_position_label.visible = false
	_item_label.visible = false
	_finish_panel.visible = false
	_new_best_label.visible = false
	_placement_label.visible = false
	_countdown_label.visible = false
	_boost_hint_label.visible = false
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
	_refresh_countdown_display()
	_refresh_position_display()


## See the class doc's COUNTDOWN + BOOST HINT / GO FLASH sections.
func _refresh_countdown_display() -> void:
	var started := bool(_session.call("is_race_started"))
	_boost_hint_label.visible = not started
	if not started:
		_countdown_label.visible = true
		_countdown_label.text = _countdown_display_text(
			StringName(_session.call("countdown_phase"))
		)
		return
	# GO FLASH: still within one countdown_step_s of the race actually
	# starting -- keep showing "GO!" a beat longer instead of vanishing the
	# same tick it would have appeared.
	var still_flashing_go := (
		float(_session.call("elapsed_s")) < float(_session.call("countdown_step_s"))
	)
	_countdown_label.visible = still_flashing_go
	if still_flashing_go:
		_countdown_label.text = "GO!"


## Only ever called pre-GO (see _refresh_countdown_display() above -- once
## started, "GO!" is driven by the separate flash window, not by matching
## phase() == &"go" here, since is_race_started() is already true by the
## time any poll could observe that phase value -- see countdown_phase()'s
## own "stops ticking past go" doc on race_session.gd). &"go" is therefore
## unreachable through this function and deliberately not one of its cases.
func _countdown_display_text(phase: StringName) -> String:
	match phase:
		&"two":
			return "2"
		&"one":
			return "1"
		_:
			return "3"


## See the class doc's LIVE POSITION section. Hidden pre-GO, once finished,
## and for a solo race (field_size() <= 1) -- shown otherwise, tracking
## RaceSession's own live per-tick ranking every poll.
func _refresh_position_display() -> void:
	var field_size := int(_session.call("field_size"))
	var show_position := (
		bool(_session.call("is_race_started"))
		and not bool(_session.call("is_finished"))
		and field_size > 1
	)
	_position_label.visible = show_position
	if show_position:
		_position_label.text = "POS  %d / %d" % [
			int(_session.call("player_position")),
			field_size,
		]


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
