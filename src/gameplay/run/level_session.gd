class_name LevelSession
extends Node

signal respawn_requested(outcome: Dictionary)
signal run_completed(results: Dictionary)
signal run_exited

var run_state := LevelRunState.new()

var _economy: EconomyTuning
var _player: Node
var _crates_by_id: Dictionary = {}
var _checkpoint_transforms: Dictionary = {}
var _start_transform := Transform3D.IDENTITY
var _death_recorded_pending_respawn: bool = false


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


func record_player_death() -> Dictionary:
	var outcome := _record_death()
	_death_recorded_pending_respawn = true
	return outcome


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
	run_state.record_crate_broken(crate_id, wumpa)


func _on_crate_bounced(
	_crate_id: int,
	wumpa: int,
	_launch_speed_mps: float
) -> void:
	run_state.record_wumpa_collected(wumpa)


func _on_checkpoint_reached(crate_id: int) -> void:
	run_state.record_checkpoint(crate_id)
	_set_player_spawn(crate_id)


func _on_mask_granted(amount: int) -> void:
	run_state.record_mask_granted(amount)


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
