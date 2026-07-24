class_name LevelSession
extends Node

const MonotonicClockType := preload(
	"res://src/core/monotonic_clock.gd"
)
const CrateLogicType := preload(
	"res://src/gameplay/crates/crate_logic.gd"
)
const PlayerStateMachineType := preload(
	"res://src/gameplay/player/player_state_machine.gd"
)
const CHECKPOINT_NEXT_ID_META := &"next_checkpoint_id"

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
var _move: MoveTuning
var _input: InputTuning
var _player: Node
var _crates_by_id: Dictionary = {}
var _checkpoint_transforms: Dictionary = {}
var _wumpa_pickups: Array[Area3D] = []
var _start_transform := Transform3D.IDENTITY
var _relic_stopwatch: Area3D
var _death_recorded_pending_respawn: bool = false
var _active_top_contact_ids: Array[int] = []
var _offered_skip_checkpoint_id: int = (
	LevelRunState.START_CHECKPOINT
)
var _offered_skip_completes_level: bool = false
var _timers_paused_at_s := -1.0


func set_gameplay_timers_paused(
	paused: bool,
	now_s: float
) -> void:
	if paused:
		_pause_gameplay_timers(now_s)
	else:
		_resume_gameplay_timers(now_s)


func configure(
	meta: LevelMeta,
	mode: StringName,
	economy: EconomyTuning,
	player: Node = null,
	move: MoveTuning = null,
	input: InputTuning = null
) -> bool:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_economy = economy
	_move = move
	_input = input
	_player = player
	run_state.start(meta, mode)
	_crates_by_id.clear()
	_checkpoint_transforms.clear()
	_wumpa_pickups.clear()
	_active_top_contact_ids.clear()
	_relic_stopwatch = null
	_offered_skip_checkpoint_id = LevelRunState.START_CHECKPOINT
	_offered_skip_completes_level = false
	_timers_paused_at_s = -1.0
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
		var crate_type := StringName(candidate.get("crate_type"))
		_crates_by_id[crate_id] = candidate
		if crate_type not in [
			CrateLogicType.TYPE_IRON,
			CrateLogicType.TYPE_TIME,
		]:
			authored_ids.append(crate_id)
		candidate.call(
			"configure",
			economy,
			move,
			input,
			(
				run_state.run_active
				and mode == LevelRunState.MODE_RELIC
			)
		)
		_connect_crate(candidate)
		if crate_type == CrateLogicType.TYPE_CHECKPOINT:
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
		elif candidate.is_in_group(&"relic_stopwatch"):
			_configure_relic_stopwatch(candidate as Area3D)
	if not authored_ids.is_empty():
		run_state.register_authored_crate_ids(authored_ids)

	if _player is Node3D:
		_start_transform = (_player as Node3D).global_transform
	if _player != null and _player.has_signal(&"respawn_started"):
		if not _player.is_connected(
			&"respawn_started",
			_on_player_respawn_started
		):
			_player.connect(
				&"respawn_started",
				_on_player_respawn_started
			)
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
	_connect_player_attacks()
	var finish := get_node_or_null("Finish") as Area3D
	if finish == null:
		push_error(
			"LevelSession requires a root Finish Area3D."
		)
		run_state.record_exit()
		return false
	_connect_once(
		finish,
		&"body_entered",
		_on_finish_body_entered
	)
	return run_state.run_active


func _pause_gameplay_timers(now_s: float) -> void:
	if _timers_paused_at_s >= 0.0:
		return
	_timers_paused_at_s = now_s


func _resume_gameplay_timers(now_s: float) -> void:
	if _timers_paused_at_s < 0.0:
		return
	var paused_duration_s := maxf(
		now_s - _timers_paused_at_s,
		0.0
	)
	_timers_paused_at_s = -1.0
	if (
		_player != null
		and _player.has_method("delay_invincibility")
	):
		_player.call(
			"delay_invincibility",
			paused_duration_s
		)
	for crate_value: Variant in _crates_by_id.values():
		var crate := crate_value as Node
		if (
			crate != null
			and crate.has_method("delay_fuse")
		):
			crate.call("delay_fuse", paused_duration_s)


func refresh_tuning(
	economy: EconomyTuning,
	move: MoveTuning,
	input: InputTuning
) -> void:
	_economy = economy
	_move = move
	_input = input
	for crate_value: Variant in _crates_by_id.values():
		var crate := crate_value as Node
		if crate != null:
			crate.call(
				"configure",
				economy,
				move,
				input,
				(
					run_state.run_active
					and run_state.mode
					== LevelRunState.MODE_RELIC
				)
			)


func restore_snapshot(saved: Dictionary) -> bool:
	if run_state.meta == null or _economy == null:
		return false
	var current_authored_ids: Array[int] = (
		run_state.authored_crate_ids.duplicate()
	)
	var restored := LevelRunState.restore(saved, run_state.meta)
	if not restored.run_active:
		return false
	if (
		restored.checkpoint_id != LevelRunState.START_CHECKPOINT
		and not _checkpoint_transforms.has(restored.checkpoint_id)
	):
		return false
	var restored_broken_ids: Array[int] = (
		restored.broken_crate_ids.duplicate()
	)
	restored.register_authored_crate_ids(current_authored_ids)
	restored.broken_crate_ids.clear()
	for crate_id: int in restored_broken_ids:
		if crate_id in current_authored_ids:
			restored.broken_crate_ids.append(crate_id)

	var restored_mask_count := restored.masks
	run_state = restored
	_sync_crate_visuals(true)
	_set_player_spawn(run_state.checkpoint_id)
	if _player != null and _player.has_method("clear_masks"):
		_player.call("clear_masks")
	for _mask_index: int in range(restored_mask_count):
		_grant_mask(MonotonicClockType.now_s())
	if _player != null and _player.has_method("respawn"):
		_death_recorded_pending_respawn = true
		_player.call("respawn")
	return true


func _physics_process(delta_s: float) -> void:
	if not run_state.run_active or _economy == null:
		return
	run_state.advance_relic_timer(delta_s)
	var now_s := MonotonicClockType.now_s()
	for crate_value: Variant in _crates_by_id.values():
		var crate := crate_value as Node
		if crate != null and crate.has_method("advance_fuse"):
			crate.call("advance_fuse", now_s)
	_process_player_crate_collisions(now_s)


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
	var completes_level := _offered_skip_completes_level
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
	_offered_skip_completes_level = false
	if completes_level:
		complete_level()
		return true
	if _player != null and _player.has_method("respawn"):
		_death_recorded_pending_respawn = true
		_player.call("respawn")
	return true


func offered_mercy_skip_completes_level() -> bool:
	return (
		_offered_skip_checkpoint_id
		!= LevelRunState.START_CHECKPOINT
		and _offered_skip_completes_level
	)


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
		var completes_level := false
		if (
			next_checkpoint_id == LevelRunState.START_CHECKPOINT
			and run_state.checkpoint_id
			!= LevelRunState.START_CHECKPOINT
		):
			next_checkpoint_id = run_state.checkpoint_id
			completes_level = true
		if next_checkpoint_id != LevelRunState.START_CHECKPOINT:
			_offered_skip_checkpoint_id = next_checkpoint_id
			_offered_skip_completes_level = completes_level
			skip_offered.emit(next_checkpoint_id)
	_sync_crate_visuals(bool(outcome["relic_void_reset"]))
	if bool(outcome["relic_void_reset"]):
		_reset_relic_stopwatch()
		_reset_placed_wumpa()
	_set_player_spawn(int(outcome["respawn_checkpoint"]))
	# Task 17 adds the enemy authored-spawn reset at this same death hook.
	respawn_requested.emit(outcome)
	return outcome


func _on_player_respawned() -> void:
	if _death_recorded_pending_respawn:
		_death_recorded_pending_respawn = false
		return
	_record_death()


func _on_player_respawn_started() -> void:
	if _death_recorded_pending_respawn:
		return
	var respawn_checkpoint := run_state.checkpoint_id
	if (
		run_state.run_active
		and run_state.mode == LevelRunState.MODE_RELIC
	):
		respawn_checkpoint = LevelRunState.START_CHECKPOINT
	_set_player_spawn(respawn_checkpoint)


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
	launch_speed_mps: float
) -> void:
	collect_wumpa(
		wumpa,
		MonotonicClockType.now_s()
	)
	if _player is CharacterBody3D:
		(_player as CharacterBody3D).velocity.y = (
			launch_speed_mps
		)


func _on_checkpoint_reached(crate_id: int) -> void:
	run_state.record_checkpoint(crate_id)
	_offered_skip_checkpoint_id = LevelRunState.START_CHECKPOINT
	_offered_skip_completes_level = false
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
	if pickup not in _wumpa_pickups:
		_wumpa_pickups.append(pickup)
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


func _reset_placed_wumpa() -> void:
	for pickup: Area3D in _wumpa_pickups:
		if not is_instance_valid(pickup):
			continue
		pickup.set_meta(&"phase1_collected", false)
		pickup.visible = true
		pickup.set_deferred(&"monitoring", true)
		pickup.set_deferred(&"monitorable", true)


func _configure_relic_stopwatch(stopwatch: Area3D) -> void:
	_relic_stopwatch = stopwatch
	var available := (
		run_state.run_active
		and run_state.mode == LevelRunState.MODE_RELIC
		and not run_state.relic_timer_armed
	)
	stopwatch.visible = available
	stopwatch.set_deferred(&"monitoring", available)
	stopwatch.set_deferred(&"monitorable", available)
	var collision := (
		stopwatch.get_node_or_null("CollisionShape3D")
		as CollisionShape3D
	)
	if collision != null:
		collision.set_deferred(&"disabled", not available)
	_connect_once(
		stopwatch,
		&"body_entered",
		_on_relic_stopwatch_body_entered
	)


func _reset_relic_stopwatch() -> void:
	if (
		_relic_stopwatch != null
		and is_instance_valid(_relic_stopwatch)
	):
		_configure_relic_stopwatch(_relic_stopwatch)


func _on_relic_stopwatch_body_entered(body: Node) -> void:
	if (
		body != _player
		or not run_state.pickup_relic_stopwatch()
	):
		return
	if (
		_relic_stopwatch != null
		and is_instance_valid(_relic_stopwatch)
	):
		_relic_stopwatch.visible = false
		_relic_stopwatch.set_deferred(&"monitoring", false)
		_relic_stopwatch.set_deferred(&"monitorable", false)
		var collision := (
			_relic_stopwatch.get_node_or_null(
				"CollisionShape3D"
			) as CollisionShape3D
		)
		if collision != null:
			collision.set_deferred(&"disabled", true)


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
		_economy.wumpa_per_pickup,
		MonotonicClockType.now_s()
	)


func _next_checkpoint_id() -> int:
	if run_state.checkpoint_id == LevelRunState.START_CHECKPOINT:
		return _first_checkpoint_id()
	return _checkpoint_successor_id(run_state.checkpoint_id)


func _first_checkpoint_id() -> int:
	var referenced_ids: Dictionary = {}
	for checkpoint_value: Variant in _checkpoint_transforms:
		var successor_id := _checkpoint_successor_id(
			int(checkpoint_value)
		)
		if successor_id != LevelRunState.START_CHECKPOINT:
			referenced_ids[successor_id] = true
	var first_id := LevelRunState.START_CHECKPOINT
	for checkpoint_value: Variant in _checkpoint_transforms:
		var checkpoint_id := int(checkpoint_value)
		if referenced_ids.has(checkpoint_id):
			continue
		if first_id != LevelRunState.START_CHECKPOINT:
			return LevelRunState.START_CHECKPOINT
		first_id = checkpoint_id
	return first_id


func _checkpoint_successor_id(checkpoint_id: int) -> int:
	var checkpoint := _crates_by_id.get(checkpoint_id) as Node
	if checkpoint == null:
		return LevelRunState.START_CHECKPOINT
	var successor_value: Variant = checkpoint.get_meta(
		CHECKPOINT_NEXT_ID_META,
		LevelRunState.START_CHECKPOINT
	)
	if typeof(successor_value) != TYPE_INT:
		return LevelRunState.START_CHECKPOINT
	var successor_id := int(successor_value)
	if not _checkpoint_transforms.has(successor_id):
		return LevelRunState.START_CHECKPOINT
	return successor_id


func _connect_crate(crate: Node) -> void:
	_connect_once(crate, &"broken", _on_crate_broken)
	_connect_once(crate, &"bounced", _on_crate_bounced)
	_connect_once(
		crate,
		&"checkpoint_reached",
		_on_checkpoint_reached
	)
	_connect_once(crate, &"mask_granted", _on_mask_granted)
	_connect_once(crate, &"detonated", _on_crate_detonated)
	_connect_once(crate, &"time_awarded", _on_time_awarded)


func _on_time_awarded(seconds: float) -> void:
	run_state.record_relic_time_credit(seconds)


func _connect_player_attacks() -> void:
	if _player == null:
		return
	var spin_area := _player.get_node_or_null("SpinArea") as Area3D
	var slam_area := _player.get_node_or_null("SlamArea") as Area3D
	if spin_area != null:
		_connect_once(
			spin_area,
			&"body_entered",
			_on_spin_body_entered
		)
	if slam_area != null:
		_connect_once(
			slam_area,
			&"body_entered",
			_on_slam_body_entered
		)


func _on_spin_body_entered(body: Node) -> void:
	_apply_crate_verb(body, CrateLogicType.VERB_SPIN)


func _on_slam_body_entered(body: Node) -> void:
	_apply_crate_verb(body, CrateLogicType.VERB_SLAM)


func _apply_crate_verb(
	candidate: Node,
	verb: StringName
) -> void:
	if not _is_authored_crate(candidate):
		return
	candidate.call(
		"apply_verb",
		verb,
		MonotonicClockType.now_s()
	)


func _process_player_crate_collisions(now_s: float) -> void:
	if not _player is CharacterBody3D:
		_active_top_contact_ids.clear()
		return
	var player_body := _player as CharacterBody3D
	var top_contacts: Array[int] = []
	for collision_index: int in range(
		player_body.get_slide_collision_count()
	):
		var collision := player_body.get_slide_collision(
			collision_index
		)
		var crate := collision.get_collider() as Node
		if not _is_authored_crate(crate):
			continue
		crate.call(
			"apply_verb",
			CrateLogicType.VERB_TOUCH,
			now_s
		)
		var normal := collision.get_normal()
		var state := (
			StringName(player_body.call("current_state"))
			if player_body.has_method("current_state")
			else &""
		)
		if state == PlayerStateMachineType.STATE_SLIDING:
			crate.call(
				"apply_verb",
				CrateLogicType.VERB_SLIDE,
				now_s
			)
		elif state in [
			PlayerStateMachineType.STATE_BODY_SLAM,
			PlayerStateMachineType.STATE_SLAM_RECOVERY,
		]:
			crate.call(
				"apply_verb",
				CrateLogicType.VERB_SLAM,
				now_s
			)
		elif normal.y < 0.0:
			crate.call(
				"apply_verb",
				CrateLogicType.VERB_JUMP_UNDER,
				now_s
			)
		elif normal.y > 0.0:
			var crate_id := int(crate.get("crate_id"))
			top_contacts.append(crate_id)
			if crate_id not in _active_top_contact_ids:
				crate.call(
					"apply_bounce",
					_bounce_press_offset_s(now_s),
					now_s
				)
	_active_top_contact_ids = top_contacts


func _bounce_press_offset_s(now_s: float) -> float:
	if (
		_player != null
		and _player.has_method("bounce_jump_press_offset_s")
	):
		return float(_player.call(
			"bounce_jump_press_offset_s",
			now_s
		))
	return INF


func _on_crate_detonated(
	source_crate_id: int,
	origin: Vector3
) -> void:
	var positions: Dictionary = {}
	for crate_id_value: Variant in _crates_by_id:
		var crate_id := int(crate_id_value)
		var crate := _crates_by_id[crate_id] as Node3D
		if crate != null:
			positions[crate_id] = crate.global_position
	var affected := CrateLogicType.blast_crate_ids(
		origin,
		positions,
		_economy
	)
	var now_s := MonotonicClockType.now_s()
	var source_crate := (
		_crates_by_id.get(source_crate_id) as Node3D
	)
	for crate_id: int in affected:
		if crate_id == source_crate_id:
			continue
		var crate := _crates_by_id.get(crate_id) as Node3D
		if (
			crate != null
			and _blast_path_is_clear(
				origin,
				source_crate,
				crate
			)
		):
			crate.call("apply_blast", now_s)


func _blast_path_is_clear(
	origin: Vector3,
	source_crate: Node3D,
	target_crate: Node3D
) -> bool:
	if not is_instance_valid(target_crate):
		return false
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		target_crate.global_position
	)
	if source_crate is CollisionObject3D:
		query.exclude = [
			(source_crate as CollisionObject3D).get_rid(),
		]
	var hit := target_crate.get_world_3d().direct_space_state.intersect_ray(
		query
	)
	return hit.is_empty() or hit.get("collider") == target_crate


func _on_finish_body_entered(body: Node) -> void:
	if body == _player:
		call_deferred(&"complete_level")


func _is_authored_crate(candidate: Node) -> bool:
	if candidate == null or not candidate.has_method("apply_verb"):
		return false
	return _crates_by_id.get(
		int(candidate.get("crate_id"))
	) == candidate


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
	if crate.has_method("set_relic_context"):
		crate.call(
			"set_relic_context",
			run_state.mode == LevelRunState.MODE_RELIC
		)
	var mesh := crate.get_node_or_null("Mesh") as Node3D
	if mesh != null:
		mesh.visible = not broken
	var collision := (
		crate.get_node_or_null("CollisionShape3D")
		as CollisionShape3D
	)
	if collision != null:
		collision.set_deferred(&"disabled", broken)
