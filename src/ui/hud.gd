class_name PhaseOneHUD
extends Control

const MonotonicClockType := preload(
	"res://src/core/monotonic_clock.gd"
)

signal pause_requested

var _session: Node
var _meta: LevelMeta
var _player: Node
var _economy: EconomyTuning
var _relic_elapsed_s: float
var _mercy_banner_remaining_s := -1.0
var _pause_touch_index: int = -1

@onready var _wumpa_label: Label = (
	$SafeArea/Stats/Margin/Rows/Wumpa
)
@onready var _crate_label: Label = (
	$SafeArea/Stats/Margin/Rows/Crates
)
@onready var _mask_label: Label = (
	$SafeArea/Stats/Margin/Rows/Masks
)
@onready var _invincible_label: Label = (
	$SafeArea/Stats/Margin/Rows/Invincible
)
@onready var _relic_label: Label = $SafeArea/RelicTimer
@onready var _mercy_panel: PanelContainer = (
	$SafeArea/MercyPanel
)
@onready var _mercy_label: Label = (
	$SafeArea/MercyPanel/Margin/Rows/Message
)
@onready var _skip_button: Button = (
	$SafeArea/MercyPanel/Margin/Rows/Skip
)
@onready var _pause_button: Button = $SafeArea/Pause


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_button.pressed.connect(
		_on_pause_pressed
	)
	_skip_button.pressed.connect(_on_skip_pressed)
	visibility_changed.connect(_on_visibility_changed)
	_mercy_panel.visible = false
	_relic_label.visible = false


func _on_visibility_changed() -> void:
	if not visible:
		_pause_touch_index = -1


func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventScreenTouch:
		return
	var touch := event as InputEventScreenTouch
	if (
		touch.pressed
		and _pause_touch_index < 0
		and _pause_button.get_global_rect().has_point(
			touch.position
		)
	):
		_pause_touch_index = touch.index
		get_viewport().set_input_as_handled()
	elif not touch.pressed and touch.index == _pause_touch_index:
		_pause_touch_index = -1
		get_viewport().set_input_as_handled()
		_on_pause_pressed()


func configure(
	session: Node,
	meta: LevelMeta,
	economy: EconomyTuning
) -> void:
	_disconnect_session()
	_clear_mercy_panel()
	_session = session
	_meta = meta
	_economy = economy
	_player = (
		_session.get("_player")
		if _session != null
		else null
	)
	if _session != null:
		_connect_once(
			_session,
			&"mercy_granted",
			_on_mercy_granted
		)
		_connect_once(
			_session,
			&"skip_offered",
			_on_skip_offered
		)
	_refresh()


func refresh_tuning(economy: EconomyTuning) -> void:
	_economy = economy


func set_run_display_visible(run_display_visible: bool) -> void:
	$SafeArea/Stats.visible = run_display_visible
	if run_display_visible:
		return
	_relic_label.visible = false
	_clear_mercy_panel()


func set_relic_time(elapsed_s: float, active: bool) -> void:
	_relic_elapsed_s = maxf(elapsed_s, 0.0)
	_relic_label.visible = active
	_relic_label.text = "RELIC  %.2f" % _relic_elapsed_s


func _process(delta_s: float) -> void:
	if visible:
		if get_tree() != null and not get_tree().paused:
			_advance_mercy_banner(delta_s)
		_refresh()


func _refresh() -> void:
	if _session == null or not is_instance_valid(_session):
		return
	var run_state: Variant = _session.get("run_state")
	if run_state == null:
		return
	var broken_value: Variant = run_state.get("broken_crate_ids")
	var broken_count := (
		(broken_value as Array).size()
		if broken_value is Array
		else 0
	)
	var crate_total := _meta.crate_count if _meta != null else 0
	var wumpa_total := _meta.wumpa_total if _meta != null else 0
	_wumpa_label.text = "WUMPA  %d / %d" % [
		int(run_state.get("wumpa_run")),
		wumpa_total,
	]
	_crate_label.text = "CRATES  %d / %d" % [
		broken_count,
		crate_total,
	]
	_mask_label.text = "AKU AKU  %d" % int(
		run_state.get("masks")
	)
	var relic_active := (
		StringName(run_state.get("mode"))
		== LevelRunState.MODE_RELIC
		and bool(run_state.get("relic_timer_armed"))
	)
	var relic_time_s := 0.0
	if (
		relic_active
		and run_state.has_method("relic_elapsed_s")
	):
		relic_time_s = float(
			run_state.call("relic_elapsed_s")
		)
	set_relic_time(relic_time_s, relic_active)
	_refresh_invincibility()


func _refresh_invincibility() -> void:
	if (
		_player == null
		or not is_instance_valid(_player)
		or not _player.has_method("invincibility_remaining_s")
	):
		_invincible_label.visible = false
		return
	var remaining_s := float(_player.call(
		"invincibility_remaining_s",
		MonotonicClockType.now_s()
	))
	_invincible_label.visible = remaining_s > 0.0
	_invincible_label.text = (
		"INVINCIBLE  %.1fs" % remaining_s
	)


func _on_mercy_granted(_mask_count: int) -> void:
	if _economy == null:
		_clear_mercy_panel()
		return
	_mercy_panel.visible = true
	_skip_button.visible = false
	_mercy_banner_remaining_s = (
		_economy.mercy_banner_duration_s
	)
	_mercy_label.text = (
		"Mercy: Aku Aku granted for this retry."
	)


func _on_skip_offered(_checkpoint_id: int) -> void:
	_mercy_panel.visible = true
	_skip_button.visible = true
	_mercy_banner_remaining_s = -1.0
	var completes_level := (
		_session != null
		and is_instance_valid(_session)
		and _session.has_method(
			"offered_mercy_skip_completes_level"
		)
		and bool(_session.call(
			"offered_mercy_skip_completes_level"
		))
	)
	if completes_level:
		_mercy_label.text = (
			"Skip the remaining level? "
			+ "Gem and relic will be void for this run."
		)
	else:
		_mercy_label.text = (
			"Skip to the next checkpoint? "
			+ "Gem and relic will be void for this run."
		)


func _on_skip_pressed() -> void:
	if (
		_session != null
		and is_instance_valid(_session)
		and _session.has_method("accept_mercy_skip")
		and bool(_session.call("accept_mercy_skip"))
	):
		_clear_mercy_panel()


func _advance_mercy_banner(delta_s: float) -> void:
	if (
		_mercy_banner_remaining_s < 0.0
		or delta_s <= 0.0
	):
		return
	_mercy_banner_remaining_s = maxf(
		_mercy_banner_remaining_s - delta_s,
		0.0
	)
	if _mercy_banner_remaining_s <= 0.0:
		_clear_mercy_panel()


func _clear_mercy_panel() -> void:
	_mercy_banner_remaining_s = -1.0
	_mercy_panel.visible = false
	_skip_button.visible = false


func _on_pause_pressed() -> void:
	pause_requested.emit()


func _connect_once(
	source: Node,
	signal_name: StringName,
	callback: Callable
) -> void:
	if (
		source.has_signal(signal_name)
		and not source.is_connected(signal_name, callback)
	):
		source.connect(signal_name, callback)


func _disconnect_session() -> void:
	if _session == null or not is_instance_valid(_session):
		return
	for connection: Dictionary in [
		{
			"signal": &"mercy_granted",
			"callback": Callable(self, "_on_mercy_granted"),
		},
		{
			"signal": &"skip_offered",
			"callback": Callable(self, "_on_skip_offered"),
		},
	]:
		var signal_name: StringName = connection["signal"]
		var callback: Callable = connection["callback"]
		if (
			_session.has_signal(signal_name)
			and _session.is_connected(signal_name, callback)
		):
			_session.disconnect(signal_name, callback)
