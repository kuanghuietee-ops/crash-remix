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
const JumpKinematicsType := preload(
	"res://src/gameplay/player/jump_kinematics.gd"
)
const CHECKPOINT_NEXT_ID_META := &"next_checkpoint_id"

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
var _gameplay_tuning: GameplayTuning
var _player: Node
var _crates_by_id: Dictionary = {}
var _enemies: Array[Node] = []
var _chase_hazards: Array[Node] = []
var _hog_mounts: Array[Node] = []
var _papu_arenas: Array[Node] = []
var _checkpoint_transforms: Dictionary = {}
var _wumpa_pickups: Array[Area3D] = []
var _start_transform := Transform3D.IDENTITY
var _relic_stopwatch: Area3D
var _death_recorded_pending_respawn: bool = false
var _death_recorded_pending_generation: int = 0
var _active_top_contact_ids: Array[int] = []
var _active_enemy_top_contact_ids: Array[int] = []
var _skip_player_crate_collisions_once: bool = false
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
	input: InputTuning = null,
	gameplay_tuning: GameplayTuning = null
) -> bool:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_economy = economy
	_move = move
	_input = input
	if gameplay_tuning != null:
		_gameplay_tuning = gameplay_tuning
	_player = player
	_clear_death_recorded_pending_respawn()
	run_state.start(meta, mode)
	_crates_by_id.clear()
	_enemies.clear()
	_chase_hazards.clear()
	_hog_mounts.clear()
	_papu_arenas.clear()
	_checkpoint_transforms.clear()
	_wumpa_pickups.clear()
	_active_top_contact_ids.clear()
	_active_enemy_top_contact_ids.clear()
	_skip_player_crate_collisions_once = false
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
	_discover_and_configure_enemies()

	if _player is Node3D:
		_start_transform = (_player as Node3D).global_transform
	_discover_and_configure_chase_hazards()
	_discover_and_configure_hog_mounts()
	_discover_and_configure_papu_arenas()
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


func _discover_and_configure_enemies() -> void:
	_enemies.clear()
	_collect_enemy_descendants(self)
	for enemy: Node in _enemies:
		_refresh_enemy_tuning(enemy, true)
		_connect_once(
			enemy,
			&"attack_contact",
			_on_enemy_attack_contact
		)


func _discover_and_configure_chase_hazards() -> void:
	_chase_hazards.clear()
	_collect_chase_hazard_descendants(self)
	if _gameplay_tuning == null:
		return
	var input_router := get_node_or_null(
		"Input/InputRouter"
	)
	for hazard: Node in _chase_hazards:
		if (
			is_instance_valid(hazard)
			and hazard.has_method("configure")
			and _player is Node3D
		):
			hazard.call(
				"configure",
				_gameplay_tuning.chase,
				_player as Node3D,
				input_router
			)


func _collect_chase_hazard_descendants(parent: Node) -> void:
	for child: Node in parent.get_children():
		if (
			child.is_in_group(&"chase_hazard")
			and child.has_method("advance_runtime")
			and child.has_method("reset_for_player_position")
		):
			_chase_hazards.append(child)
		_collect_chase_hazard_descendants(child)


func _discover_and_configure_hog_mounts() -> void:
	_hog_mounts.clear()
	_collect_hog_mount_descendants(self)
	for mount: Node in _hog_mounts:
		if (
			is_instance_valid(mount)
			and mount.has_method("configure")
			and _player is Node3D
		):
			mount.call(
				"configure",
				_player as Node3D
			)


## The boss arena is discovered the same way hog mounts are, so victory reaches
## complete_level() through the one path a run can end by, rather than inventing
## a second completion route.
func _discover_and_configure_papu_arenas() -> void:
	_papu_arenas.clear()
	_collect_papu_arena_descendants(self)
	for arena: Node in _papu_arenas:
		if not is_instance_valid(arena) or not arena.has_method("configure"):
			continue
		if _gameplay_tuning == null or not (_player is Node3D):
			continue
		arena.call(
			"configure",
			_player as Node3D,
			_gameplay_tuning.boss_papu,
			_gameplay_tuning.depth
		)
		if not arena.is_connected(&"boss_defeated", complete_level):
			arena.connect(&"boss_defeated", complete_level)


func _collect_papu_arena_descendants(parent: Node) -> void:
	for child: Node in parent.get_children():
		if (
			child.is_in_group(&"papu_arena")
			and child.has_method("current_phase")
		):
			_papu_arenas.append(child)
		_collect_papu_arena_descendants(child)


func _collect_hog_mount_descendants(parent: Node) -> void:
	for child: Node in parent.get_children():
		if (
			child.is_in_group(&"hog_mount")
			and child.has_method(
				"reset_for_player_position"
			)
		):
			_hog_mounts.append(child)
		_collect_hog_mount_descendants(child)


func _collect_enemy_descendants(parent: Node) -> void:
	for child: Node in parent.get_children():
		if (
			child.is_in_group(&"enemy")
			and child.has_method("enemy_kind")
			and child.has_method("tuning_section")
		):
			_enemies.append(child)
		_collect_enemy_descendants(child)


func _refresh_enemy_tuning(
	enemy: Node,
	initial_configuration: bool = false
) -> void:
	if (
		_gameplay_tuning == null
		or not is_instance_valid(enemy)
		or not enemy.has_method("tuning_section")
	):
		return
	var section_name := StringName(
		enemy.call("tuning_section")
	)
	var enemy_tuning := (
		_gameplay_tuning.get(section_name) as EnemyTuning
	)
	if enemy_tuning == null:
		return
	enemy.call(
		"configure" if initial_configuration else "refresh_tuning",
		enemy_tuning,
		_move
	)


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
	for enemy: Node in _enemies:
		if (
			is_instance_valid(enemy)
			and enemy.has_method("delay_timers")
		):
			enemy.call("delay_timers", paused_duration_s)


func refresh_tuning(
	economy: EconomyTuning,
	move: MoveTuning,
	input: InputTuning,
	gameplay_tuning: GameplayTuning = null
) -> void:
	_economy = economy
	_move = move
	_input = input
	if gameplay_tuning != null:
		_gameplay_tuning = gameplay_tuning
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
	for enemy: Node in _enemies:
		_refresh_enemy_tuning(enemy)
	if _gameplay_tuning != null:
		for hazard: Node in _chase_hazards:
			if (
				is_instance_valid(hazard)
				and hazard.has_method("refresh_tuning")
			):
				hazard.call(
					"refresh_tuning",
					_gameplay_tuning.chase
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
	_reset_hog_mounts_for_checkpoint(
		run_state.checkpoint_id
	)
	_reset_chase_hazards_for_checkpoint(
		run_state.checkpoint_id
	)
	if _player != null and _player.has_method("clear_masks"):
		_player.call("clear_masks")
	for _mask_index: int in range(restored_mask_count):
		_grant_mask(MonotonicClockType.now_s())
	if _player != null and _player.has_method("respawn"):
		_arm_death_recorded_pending_respawn()
		_player.call("respawn")
	return true


func _physics_process(delta_s: float) -> void:
	if not run_state.run_active or _economy == null:
		return
	run_state.advance_relic_timer(delta_s)
	var now_s := MonotonicClockType.now_s()
	_advance_chase_hazards(delta_s, now_s)
	_advance_enemy_logic(now_s)
	for crate_value: Variant in _crates_by_id.values():
		var crate := crate_value as Node
		if crate != null and crate.has_method("advance_fuse"):
			crate.call("advance_fuse", now_s)
	if _skip_player_crate_collisions_once:
		_skip_player_crate_collisions_once = false
		return
	_process_player_crate_collisions(now_s)


func _advance_chase_hazards(
	delta_s: float,
	now_s: float
) -> void:
	if _player == null or not _player.has_method("receive_hit"):
		return
	# The boss arena reports the same {caught} contract, so it shares this
	# loop rather than growing a second damage path.
	var hazards: Array[Node] = []
	hazards.append_array(_chase_hazards)
	hazards.append_array(_papu_arenas)
	for hazard: Node in hazards:
		if (
			not is_instance_valid(hazard)
			or not hazard.has_method("advance_runtime")
		):
			continue
		var outcome: Dictionary = hazard.call(
			"advance_runtime",
			delta_s
		)
		if not bool(outcome.get(&"caught", false)):
			continue
		var player_died := bool(_player.call(
			"receive_hit",
			now_s
		))
		if hazard.has_method("resolve_player_contact"):
			hazard.call(
				"resolve_player_contact",
				player_died
			)


func _advance_enemy_logic(now_s: float) -> void:
	if not _player is Node3D:
		return
	var player_position := (_player as Node3D).global_position
	for enemy: Node in _enemies:
		if (
			is_instance_valid(enemy)
			and enemy.has_method("advance_logic")
		):
			enemy.call(
				"advance_logic",
				now_s,
				player_position
			)


func _reset_enemies_to_authored_spawn() -> void:
	_active_enemy_top_contact_ids.clear()
	for enemy: Node in _enemies:
		if (
			is_instance_valid(enemy)
			and enemy.has_method(
				"reset_to_authored_spawn"
			)
		):
			enemy.call("reset_to_authored_spawn")


func record_player_death() -> Dictionary:
	var outcome := _record_death()
	var pending_generation := (
		_arm_death_recorded_pending_respawn()
	)
	call_deferred(
		&"_expire_death_recorded_pending_respawn",
		pending_generation
	)
	return outcome


func collect_wumpa(amount: int, now_s: float) -> void:
	if (
		not run_state.run_active
		or _economy == null
		or amount <= 0
	):
		return
	run_state.record_wumpa_collected(amount)
	var masks_earned := run_state.resolve_wumpa_mask_rollover(
		_economy.wumpa_mask_threshold
	)
	for _mask_index: int in range(masks_earned):
		_grant_mask(now_s)
	wumpa_changed.emit(run_state.wumpa_run)


func accept_mercy_skip() -> bool:
	var completes_level := _offered_skip_completes_level
	if (
		_offered_skip_checkpoint_id
		== LevelRunState.START_CHECKPOINT
		or not run_state.accept_mercy_skip(
			_offered_skip_checkpoint_id,
			_economy
		)
	):
		return false
	_set_player_spawn(_offered_skip_checkpoint_id)
	_reset_hog_mounts_for_checkpoint(
		_offered_skip_checkpoint_id
	)
	_reset_chase_hazards_for_checkpoint(
		_offered_skip_checkpoint_id
	)
	_offered_skip_checkpoint_id = LevelRunState.START_CHECKPOINT
	_offered_skip_completes_level = false
	if completes_level:
		complete_level()
		return true
	if _player != null and _player.has_method("respawn"):
		_arm_death_recorded_pending_respawn()
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
	_reset_enemies_to_authored_spawn()
	_set_player_spawn(int(outcome["respawn_checkpoint"]))
	_reset_hog_mounts_for_checkpoint(
		int(outcome["respawn_checkpoint"])
	)
	_reset_chase_hazards_for_checkpoint(
		int(outcome["respawn_checkpoint"])
	)
	# F16: a `respawn_requested(outcome)` signal used to fire here with no
	# consumer anywhere in the repo (dead-wired, same class as P1-5/P1-9/
	# P1-17) -- removed rather than kept, since every field `outcome` carries
	# is already fully applied above in this same function and the only
	# documented reason for a generic "a respawn just happened" broadcast is
	# Task 17's enemy authored-spawn reset, which is out of scope here. Task
	# 17 should add its own signal (or a direct call) at this hook when it
	# actually needs one, so it ships with a real consumer from day one.
	return outcome


func _on_player_respawned() -> void:
	if _death_recorded_pending_respawn:
		_clear_death_recorded_pending_respawn()
		return
	_record_death()


func _on_player_respawn_started() -> void:
	_active_top_contact_ids.clear()
	_active_enemy_top_contact_ids.clear()
	_skip_player_crate_collisions_once = true
	if _death_recorded_pending_respawn:
		return
	var respawn_checkpoint := run_state.checkpoint_id
	if (
		run_state.run_active
		and run_state.mode == LevelRunState.MODE_RELIC
	):
		respawn_checkpoint = LevelRunState.START_CHECKPOINT
	_set_player_spawn(respawn_checkpoint)
	_reset_hog_mounts_for_checkpoint(respawn_checkpoint)
	_reset_chase_hazards_for_checkpoint(respawn_checkpoint)
	_reset_papu_arenas_for_death()


## A retry must not inherit the ripples that killed the player: that is the
## distance-since-checkpoint difficulty §2.8 rules out, arriving by the back
## door.
func _reset_papu_arenas_for_death() -> void:
	for arena: Node in _papu_arenas:
		if is_instance_valid(arena) and arena.has_method("on_player_death"):
			arena.call("on_player_death")


func _arm_death_recorded_pending_respawn() -> int:
	_death_recorded_pending_generation += 1
	_death_recorded_pending_respawn = true
	return _death_recorded_pending_generation


func _clear_death_recorded_pending_respawn() -> void:
	_death_recorded_pending_generation += 1
	_death_recorded_pending_respawn = false


func _expire_death_recorded_pending_respawn(
	pending_generation: int
) -> void:
	if (
		_death_recorded_pending_respawn
		and pending_generation
		== _death_recorded_pending_generation
	):
		_clear_death_recorded_pending_respawn()


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
	pickup.visible = true
	pickup.set_deferred(&"monitoring", true)
	pickup.set_deferred(&"monitorable", true)
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
	_apply_combat_verb(body, CrateLogicType.VERB_SPIN)


func _on_slam_body_entered(body: Node) -> void:
	_apply_combat_verb(body, CrateLogicType.VERB_SLAM)


func _apply_combat_verb(
	candidate: Node,
	verb: StringName
) -> void:
	var now_s := MonotonicClockType.now_s()
	if _is_authored_crate(candidate):
		candidate.call("apply_verb", verb, now_s)
		return
	if not _is_authored_enemy(candidate):
		return
	var result: Dictionary = candidate.call(
		"apply_verb",
		verb,
		now_s
	)
	_apply_enemy_outcome(result, now_s)


func _process_player_crate_collisions(now_s: float) -> void:
	if not _player is CharacterBody3D:
		_active_top_contact_ids.clear()
		_active_enemy_top_contact_ids.clear()
		return
	var player_body := _player as CharacterBody3D
	var top_contacts: Array[int] = []
	var enemy_top_contacts: Array[int] = []
	var bounce_intent_resolved := false
	var high_bounce := false
	var state := (
		StringName(player_body.call("current_state"))
		if player_body.has_method("current_state")
		else &""
	)
	for collision_index: int in range(
		player_body.get_slide_collision_count()
	):
		var collision := player_body.get_slide_collision(
			collision_index
		)
		var collider := collision.get_collider() as Node
		var normal := collision.get_normal()
		if _is_authored_enemy(collider):
			_process_enemy_body_collision(
				collider,
				normal,
				state,
				now_s,
				enemy_top_contacts
			)
			continue
		var crate := collider
		if not _is_authored_crate(crate):
			continue
		crate.call(
			"apply_verb",
			CrateLogicType.VERB_TOUCH,
			now_s
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
				var bounce_info := CrateLogicType.break_result(
					StringName(crate.get("crate_type")),
					CrateLogicType.VERB_BOUNCE,
					_economy
				)
				var bounces_player := bool(
					bounce_info["bounces_player"]
				)
				if bounces_player and not bounce_intent_resolved:
					high_bounce = (
						_consume_bounce_contact_intent(now_s)
					)
					bounce_intent_resolved = true
				var bounce_result: Dictionary = crate.call(
					"apply_bounce",
					high_bounce if bounces_player else false,
					now_s
				)
				if (
					not is_zero_approx(float(
						bounce_result.get(
							"launch_speed_mps",
							0.0
						)
					))
					and _player.has_method(
						"begin_bounce_timing_window"
					)
				):
					_player.call(
						"begin_bounce_timing_window",
						now_s,
						high_bounce
					)
	_active_top_contact_ids = top_contacts
	_active_enemy_top_contact_ids = enemy_top_contacts


func _process_enemy_body_collision(
	enemy: Node,
	normal: Vector3,
	player_state: StringName,
	now_s: float,
	top_contacts: Array[int]
) -> void:
	var verb := CrateLogicType.VERB_TOUCH
	var top_contact := false
	if player_state == PlayerStateMachineType.STATE_SLIDING:
		verb = CrateLogicType.VERB_SLIDE
	elif player_state in [
		PlayerStateMachineType.STATE_BODY_SLAM,
		PlayerStateMachineType.STATE_SLAM_RECOVERY,
	]:
		verb = CrateLogicType.VERB_SLAM
	elif normal.y > 0.0:
		verb = &"jump"
		top_contact = true

	if top_contact:
		var enemy_id := enemy.get_instance_id()
		top_contacts.append(enemy_id)
		if (
			enemy_id in _active_enemy_top_contact_ids
			and not bool(enemy.call("attack_is_active"))
		):
			return
	var result: Dictionary = enemy.call(
		"resolve_contact",
		verb,
		now_s
	)
	_apply_enemy_outcome(result, now_s)


func _apply_enemy_outcome(
	result: Dictionary,
	now_s: float
) -> void:
	if (
		bool(result.get("player_hit", false))
		and _player != null
		and _player.has_method("receive_hit")
	):
		_player.call("receive_hit", now_s)
		return
	if (
		not bool(result.get("player_bounce", false))
		or not _player is CharacterBody3D
		or _move == null
	):
		return
	(_player as CharacterBody3D).velocity.y = (
		JumpKinematicsType.upward_speed_for_height(
			_move.jump_tap_height_m,
			_move
		)
	)
	if _player.has_method("begin_bounce_timing_window"):
		_player.call(
			"begin_bounce_timing_window",
			now_s,
			false
		)


func _on_enemy_attack_contact(
	body: Node,
	enemy: Node
) -> void:
	if body != _player or not _is_authored_enemy(enemy):
		return
	call_deferred(
		&"_resolve_enemy_attack_contact",
		enemy
	)


func _resolve_enemy_attack_contact(enemy: Node) -> void:
	if (
		not _is_authored_enemy(enemy)
		or not bool(enemy.call("attack_is_active"))
	):
		return
	var now_s := MonotonicClockType.now_s()
	var result: Dictionary = enemy.call(
		"resolve_contact",
		CrateLogicType.VERB_TOUCH,
		now_s
	)
	_apply_enemy_outcome(result, now_s)


func _consume_bounce_contact_intent(now_s: float) -> bool:
	if (
		_player != null
		and _player.has_method(
			"consume_bounce_contact_intent"
		)
	):
		return bool(_player.call(
			"consume_bounce_contact_intent",
			now_s
		))
	return false


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


func _is_authored_enemy(candidate: Node) -> bool:
	return (
		candidate != null
		and candidate in _enemies
		and candidate.has_method("apply_verb")
		and candidate.has_method("resolve_contact")
	)


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
	var spawn_transform := _spawn_transform_for_checkpoint(
		target_checkpoint_id
	)
	_player.call(
		"set_spawn_transform",
		spawn_transform
	)


func _spawn_transform_for_checkpoint(
	target_checkpoint_id: int
) -> Transform3D:
	if _checkpoint_transforms.has(target_checkpoint_id):
		return _checkpoint_transforms[target_checkpoint_id]
	# spec §8.2: a boss phase IS the checkpoint. Without this a death in phase
	# 2 or 3 falls back to the level spawn at the bottom of the hut.
	for arena: Node in _papu_arenas:
		if (
			is_instance_valid(arena)
			and arena.has_method("has_phase_spawn")
			and bool(arena.call("has_phase_spawn"))
		):
			return arena.call("phase_spawn_transform")
	return _start_transform


func _reset_chase_hazards_for_checkpoint(
	target_checkpoint_id: int
) -> void:
	var spawn_position := _spawn_transform_for_checkpoint(
		target_checkpoint_id
	).origin
	for hazard: Node in _chase_hazards:
		if (
			is_instance_valid(hazard)
			and hazard.has_method("reset_for_player_position")
		):
			hazard.call(
				"reset_for_player_position",
				spawn_position
			)


func _reset_hog_mounts_for_position(
	player_position: Vector3
) -> void:
	for mount: Node in _hog_mounts:
		if (
			is_instance_valid(mount)
			and mount.has_method(
				"reset_for_player_position"
			)
		):
			mount.call(
				"reset_for_player_position",
				player_position
			)


func _reset_hog_mounts_for_checkpoint(
	target_checkpoint_id: int
) -> void:
	_reset_hog_mounts_for_position(
		_spawn_transform_for_checkpoint(
			target_checkpoint_id
		).origin
	)


func _checkpoint_spawn_transform(crate: Node) -> Transform3D:
	var crate_transform := (crate as Node3D).global_transform
	if _economy == null:
		return crate_transform
	crate_transform.origin += (
		crate_transform.basis
		* _economy.checkpoint_respawn_offset
	)
	return crate_transform


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
	if not crate.has_method("sync_break_state"):
		return
	crate.call(
		"sync_break_state",
		broken,
		run_state.mode == LevelRunState.MODE_RELIC
	)
