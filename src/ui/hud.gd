class_name PhaseOneHUD
extends Control

const MonotonicClockType := preload(
	"res://src/core/monotonic_clock.gd"
)

var _session: Node
var _meta: LevelMeta
var _player: Node
var _relic_elapsed_s: float

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


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skip_button.pressed.connect(_on_skip_pressed)
	_mercy_panel.visible = false
	_relic_label.visible = false


func configure(session: Node, meta: LevelMeta) -> void:
	_disconnect_session()
	_session = session
	_meta = meta
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


func set_relic_time(elapsed_s: float, active: bool) -> void:
	_relic_elapsed_s = maxf(elapsed_s, 0.0)
	_relic_label.visible = active
	_relic_label.text = "RELIC  %.2f" % _relic_elapsed_s


func _process(_delta_s: float) -> void:
	if visible:
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
	_wumpa_label.text = "WUMPA  %d" % int(
		run_state.get("wumpa_run")
	)
	_crate_label.text = "CRATES  %d / %d" % [
		broken_count,
		crate_total,
	]
	_mask_label.text = "AKU AKU  %d" % int(
		run_state.get("masks")
	)
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
	_mercy_panel.visible = true
	_skip_button.visible = false
	_mercy_label.text = (
		"Mercy: Aku Aku granted for this retry."
	)


func _on_skip_offered(_checkpoint_id: int) -> void:
	_mercy_panel.visible = true
	_skip_button.visible = true
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
		_mercy_panel.visible = false


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
