class_name PapuPapuArena
extends Node3D

## Scene glue for the Papu Papu gauntlet. All fight rules live in the pure
## BossFightFlow (01-DESIGN §4.14, spec §8.2); this node only turns real
## Area3D overlaps into strikes and reports the result back.

const BossFightFlowType := preload(
	"res://src/gameplay/boss/boss_fight_flow.gd"
)

## Emitted when the last phase is cleared. LevelSession turns this into the
## level's completion, so victory follows the same path as any other finish.
signal boss_defeated

@export var strike_trigger_paths: Array[NodePath] = []
## spec §8.2's checkpoint per phase. The arena authors no checkpoint crates,
## so the phase itself carries the respawn point.
@export var phase_spawn_paths: Array[NodePath] = []

var _flow: BossFightFlowType = BossFightFlowType.new()
var _player: Node3D
var _depth: DepthTuning
var _triggers_connected := false
var _phase_elapsed_s := 0.0
var _slams_emitted := 0
var _wave_ages_s: Array[float] = []


func _ready() -> void:
	add_to_group(&"papu_arena")


func configure(
	player: Node3D,
	tuning: BossTuning,
	depth: DepthTuning
) -> void:
	_player = player
	_depth = depth
	_flow.configure(tuning)
	reset_phase_hazards()
	_connect_strike_triggers()


## A phase restart clears its ripples: the player must not inherit waves
## emitted before they died, which would make the retry unfair on entry.
func reset_phase_hazards() -> void:
	_phase_elapsed_s = 0.0
	_slams_emitted = 0
	_wave_ages_s.clear()


## §4.14: debris is blob-shadow telegraphed for debris_telegraph_s before it
## can kill, so a death is always something the player could read coming.
func debris_is_lethal_now() -> bool:
	return _flow.debris_is_lethal(_phase_elapsed_s)


## Height above the player's OWN supporting surface, probed downward the same
## way the blob shadow finds its floor. World Y cannot answer this: each phase
## floor sits 2 m higher than the last, so standing safely on tier 3 is a world
## Y that would read as airborne on tier 1.
func player_height_above_surface_m() -> float:
	if _player == null or _depth == null:
		return 0.0
	var space_state := get_world_3d().direct_space_state
	var from := _player.global_position
	var to := from + Vector3.DOWN * _depth.shadow_ray_length_m
	var query := PhysicsRayQueryParameters3D.create(from, to)
	if _player is CollisionObject3D:
		query.exclude = [(_player as CollisionObject3D).get_rid()]
	query.collide_with_areas = false
	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		# Nothing under them within the probe: they are over a gap, which is
		# not something a floor-hugging ripple can reach.
		return _depth.shadow_ray_length_m
	var surface_position: Vector3 = hit["position"]
	return maxf(from.y - surface_position.y, 0.0)


## Emits one ripple per slam that has landed this phase, advances every live
## ripple, and reports whether one reached a player who was too low to clear it.
func advance_runtime(delta_s: float) -> Dictionary:
	if _player == null or _flow.is_defeated():
		return {&"caught": false}
	var step := maxf(delta_s, 0.0)
	_phase_elapsed_s += step
	var landed_slams := _flow.slam_count_by(_phase_elapsed_s)
	while _slams_emitted < landed_slams:
		_wave_ages_s.append(0.0)
		_slams_emitted += 1
	var origin := _current_strike_origin()
	var player_gap_m := absf(_player.global_position.z - origin.z)
	var clears := _flow.shockwave_clears_player(
		player_height_above_surface_m()
	)
	var caught := false
	var live_waves: Array[float] = []
	for age_s: float in _wave_ages_s:
		var next_age_s := age_s + step
		var travelled_m := _flow.shockwave_distance_m(next_age_s)
		if travelled_m < player_gap_m:
			live_waves.append(next_age_s)
			continue
		# The ripple has reached them; a jumped player lets it pass under.
		if not clears:
			caught = true
	_wave_ages_s = live_waves
	return {
		&"caught": caught,
		&"live_waves": _wave_ages_s.size(),
	}


## Whether this arena has an authored respawn point for the current phase.
func has_phase_spawn() -> bool:
	return _phase_spawn_marker() != null


## Where a death in the current phase should put the player back.
func phase_spawn_transform() -> Transform3D:
	var marker := _phase_spawn_marker()
	if marker == null:
		return Transform3D.IDENTITY
	return marker.global_transform


func _phase_spawn_marker() -> Node3D:
	var index := _flow.checkpoint_phase() - 1
	if index < 0 or index >= phase_spawn_paths.size():
		return null
	return get_node_or_null(phase_spawn_paths[index]) as Node3D


func _current_strike_origin() -> Vector3:
	var index := _flow.current_phase() - 1
	if index < 0 or index >= strike_trigger_paths.size():
		return global_position
	var trigger := get_node_or_null(
		strike_trigger_paths[index]
	) as Node3D
	return trigger.global_position if trigger != null else global_position


func current_phase() -> int:
	return _flow.current_phase()


func checkpoint_phase() -> int:
	return _flow.checkpoint_phase()


func strikes_this_phase() -> int:
	return _flow.strikes_this_phase()


func is_defeated() -> bool:
	return _flow.is_defeated()


func on_player_death() -> void:
	_flow.on_player_death()
	reset_phase_hazards()


func _connect_strike_triggers() -> void:
	if _triggers_connected:
		return
	for trigger_path: NodePath in strike_trigger_paths:
		var trigger := get_node_or_null(trigger_path) as Area3D
		if trigger == null:
			continue
		if not trigger.body_entered.is_connected(
			_on_strike_trigger_body_entered
		):
			trigger.body_entered.connect(
				_on_strike_trigger_body_entered
			)
	_triggers_connected = true


func _on_strike_trigger_body_entered(body: Node3D) -> void:
	# A non-player body must change nothing, and a won fight must not keep
	# accumulating strikes.
	if body != _player or _flow.is_defeated():
		return
	_flow.register_strike()
	reset_phase_hazards()
	if _flow.is_defeated():
		boss_defeated.emit()
