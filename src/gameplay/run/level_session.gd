class_name LevelSession
extends Node

const MonotonicClockType := preload(
	"res://src/core/monotonic_clock.gd"
)

signal respawn_requested(outcome: Dictionary)
signal run_completed(results: Dictionary)
signal run_exited
signal wumpa_changed(wumpa_count: int)
signal mask_state_changed(
	mask_count: int,
	invincible_until_s: float
)
signal mercy_granted(mask_count: int)
signal skip_offered(next_checkpoint_id: int)

var run_state := LevelRunState.new()

var _economy: EconomyTuning
var _player: Node
var _crates_by_id: Dictionary = {}
var _checkpoint_transforms: Dictionary = {}
var _start_transform := Transform3D.IDENTITY
var _death_recorded_pending_respawn: bool = false
var _offered_skip_checkpoint_id: int = (
	LevelRunState.START_CHECKPOINT
)


func configure(
	meta: LevelMeta,
	mode: StringName,
	economy: EconomyTuning,
	player: Node = null,
	move: MoveTuning = null,
	input: InputTuning = null
) -> void:
	_economy = economy
	_player = player
	run_state.start(meta, mode)
	_crates_by_id.clear()
	_checkpoint_transforms.clear()
	_offered_skip_checkpoint_id = LevelRunState.START_CHECKPOINT
	var authored_ids: Array[int] = []

	for candidate: Node in find_children(
		"*",
		"StaticBody3D",
		true,
		false
	):
		if not candidate.has_signal(&"broken"):
			continue
		var crate_id := int(candidate.get("crate_id"))
		_crates_by_id[crate_id] = candidate
		authored_ids.append(crate_id)
		candidate.call(
			"configure",
			economy,
			move,
			input,
			mode == LevelRunState.MODE_RELIC
		)
		_connect_crate(candidate)
		if candidate.get("crate_type") == &"checkpoint":
			_checkpoint_transforms[crate_id] = (
				_checkpoint_spawn_transform(candidate)
			)
	for candidate: Node in find_children(
		"*",
		"Area3D",
		true,
		false
	):
		if candidate.is_in_group(&"wumpa_pickup"):
			_configure_wumpa_pickup(candidate as Area3D)
	if not authored_ids.is_empty():
		run_state.register_authored_crate_ids(authored_ids)

	if _player is Node3D:
		_start_transform = (_player as Node3D).global_transform
	if (
		_player != null
		and _player.has_signal(&"respawned")
		and not _player.is_connected(
			&"respawned",
			_on_player_respawned
		)
	):
		_player.connect(&"respawned", _on_player_respawned)
	if (
		_player != null
		and _player.has_signal(&"mask_state_changed")
		and not _player.is_connected(
			&"mask_state_changed",
			_on_player_mask_state_changed
		)
	):
		_player.connect(
			&"mask_state_changed",
			_on_player_mask_state_changed
		)
	if _player != null and _player.has_method("clear_masks"):
		_player.call("clear_masks")


func record_player_death() -> Dictionary:
	var outcome := _record_death()
	_death_recorded_pending_respawn = true
	return outcome


func collect_wumpa(amount: int, now_s: float) -> void:
	if (
		not run_state.run_active
		or _economy == null
		or amount <= 0
	):
		return
	run_state.record_wumpa_collected(amount)
	var mask_threshold := _economy.wumpa_mask_threshold
	if mask_threshold <= 0:
		wumpa_changed.emit(run_state.wumpa_run)
		return
	while run_state.wumpa_run >= mask_threshold:
		run_state.wumpa_run -= mask_threshold
		_grant_mask(now_s)
	wumpa_changed.emit(run_state.wumpa_run)


func accept_mercy_skip() -> bool:
	if (
		_offered_skip_checkpoint_id
		== LevelRunState.START_CHECKPOINT
		or not run_state.accept_mercy_skip(
			_offered_skip_checkpoint_id
		)
	):
		return false
	_set_player_spawn(_offered_skip_checkpoint_id)
	_offered_skip_checkpoint_id = LevelRunState.START_CHECKPOINT
	if _player != null and _player.has_method("respawn"):
		_death_recorded_pending_respawn = true
		_player.call("respawn")
	return true


func complete_level() -> Dictionary:
	var result := run_state.record_level_complete(_economy)
	if not result.is_empty():
		run_completed.emit(result)
	return result


func exit_level() -> void:
	run_state.record_exit()
	run_exited.emit()


func _record_death() -> Dictionary:
	var outcome := run_state.record_death(_economy)
	if _player != null and _player.has_method("clear_masks"):
		_player.call("clear_masks")
	if bool(outcome["grant_mercy_mask"]):
		_grant_mask(MonotonicClockType.now_s())
		mercy_granted.emit(run_state.masks)
	if bool(outcome["offer_skip"]):
		var next_checkpoint_id := _next_checkpoint_id()
		if next_checkpoint_id != LevelRunState.START_CHECKPOINT:
			_offered_skip_checkpoint_id = next_checkpoint_id
			skip_offered.emit(next_checkpoint_id)
	_sync_crate_visuals(bool(outcome["relic_void_reset"]))
	_set_player_spawn(int(outcome["respawn_checkpoint"]))
	# Task 17 adds the enemy authored-spawn reset at this same death hook.
	respawn_requested.emit(outcome)
	return outcome


func _on_player_respawned() -> void:
	if _death_recorded_pending_respawn:
		_death_recorded_pending_respawn = false
		return
	_record_death()


func _on_crate_broken(crate_id: int, wumpa: int) -> void:
	var broken_count := run_state.broken_crate_ids.size()
	run_state.record_crate_broken(crate_id, 0)
	if run_state.broken_crate_ids.size() > broken_count:
		collect_wumpa(
			wumpa,
			MonotonicClockType.now_s()
		)


func _on_crate_bounced(
	_crate_id: int,
	wumpa: int,
	_launch_speed_mps: float
) -> void:
	collect_wumpa(
		wumpa,
		MonotonicClockType.now_s()
	)


func _on_checkpoint_reached(crate_id: int) -> void:
	run_state.record_checkpoint(crate_id)
	_offered_skip_checkpoint_id = LevelRunState.START_CHECKPOINT
	_set_player_spawn(crate_id)


func _on_mask_granted(amount: int) -> void:
	var remaining := amount
	while remaining > 0:
		_grant_mask(MonotonicClockType.now_s())
		remaining -= 1


func _on_player_mask_state_changed(
	mask_count: int,
	invincible_until_s: float
) -> void:
	run_state.masks = clampi(
		mask_count,
		0,
		_economy.mask_stack_maximum
	)
	mask_state_changed.emit(
		run_state.masks,
		invincible_until_s
	)


func _grant_mask(now_s: float) -> void:
	if _player != null and _player.has_method("grant_mask"):
		_player.call("grant_mask", now_s)
		if _player.has_method("mask_count"):
			run_state.masks = int(_player.call("mask_count"))
		return
	run_state.masks = mini(
		run_state.masks + 1,
		_economy.mask_stack_maximum
	)
	mask_state_changed.emit(run_state.masks, -1.0)


func _configure_wumpa_pickup(pickup: Area3D) -> void:
	pickup.set_meta(&"phase1_collected", false)
	var collision := (
		pickup.get_node_or_null("CollisionShape3D")
		as CollisionShape3D
	)
	if collision != null and collision.shape is SphereShape3D:
		var shape := collision.shape.duplicate() as SphereShape3D
		shape.radius = _economy.wumpa_collect_radius_m
		collision.shape = shape
	_connect_once(
		pickup,
		&"body_entered",
		_on_wumpa_body_entered.bind(pickup)
	)


func _on_wumpa_body_entered(
	body: Node,
	pickup: Area3D
) -> void:
	if (
		body != _player
		or bool(pickup.get_meta(&"phase1_collected", false))
	):
		return
	pickup.set_meta(&"phase1_collected", true)
	pickup.visible = false
	pickup.set_deferred(&"monitoring", false)
	pickup.set_deferred(&"monitorable", false)
	collect_wumpa(
		_economy.wumpa_per_standard_crate,
		MonotonicClockType.now_s()
	)


func _next_checkpoint_id() -> int:
	var candidates: Array[int] = []
	for checkpoint_value: Variant in _checkpoint_transforms:
		var checkpoint_id := int(checkpoint_value)
		if checkpoint_id > run_state.checkpoint_id:
			candidates.append(checkpoint_id)
	candidates.sort()
	if candidates.is_empty():
		return LevelRunState.START_CHECKPOINT
	return candidates.front()


func _connect_crate(crate: Node) -> void:
	_connect_once(crate, &"broken", _on_crate_broken)
	_connect_once(crate, &"bounced", _on_crate_bounced)
	_connect_once(
		crate,
		&"checkpoint_reached",
		_on_checkpoint_reached
	)
	_connect_once(crate, &"mask_granted", _on_mask_granted)


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


func _set_player_spawn(target_checkpoint_id: int) -> void:
	if _player == null or not _player.has_method("set_spawn_transform"):
		return
	var target := _start_transform
	if _checkpoint_transforms.has(target_checkpoint_id):
		target = _checkpoint_transforms[target_checkpoint_id]
	_player.call("set_spawn_transform", target)


func _checkpoint_spawn_transform(crate: Node) -> Transform3D:
	var spawn := crate.get_node_or_null("Spawn") as Node3D
	if spawn != null:
		return spawn.global_transform
	return (crate as Node3D).global_transform


func _sync_crate_visuals(reset_unbroken: bool) -> void:
	for crate_id: Variant in _crates_by_id:
		var crate := _crates_by_id[crate_id] as Node
		var should_be_broken := (
			int(crate_id) in run_state.broken_crate_ids
		)
		if should_be_broken:
			_set_crate_visual(crate, true)
		elif reset_unbroken:
			_set_crate_visual(crate, false)


func _set_crate_visual(crate: Node, broken: bool) -> void:
	crate.set("_broken", broken)
	crate.set("_bounce_count", 0)
	crate.set("_fuse_active", false)
	var mesh := crate.get_node_or_null("Mesh") as Node3D
	if mesh != null:
		mesh.visible = not broken
	var collision := (
		crate.get_node_or_null("CollisionShape3D")
		as CollisionShape3D
	)
	if collision != null:
		collision.set_deferred(&"disabled", broken)
