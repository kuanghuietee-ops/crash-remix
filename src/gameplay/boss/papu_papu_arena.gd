class_name PapuPapuArena
extends Node3D

## Scene glue for the Papu Papu gauntlet. All fight rules live in the pure
## BossFightFlow (01-DESIGN §4.14, spec §8.2); this node only turns real
## Area3D overlaps into strikes and reports the result back.

const BossFightFlowType := preload(
	"res://src/gameplay/boss/boss_fight_flow.gd"
)
## Authored, not built in code: the crest's dimensions belong in a scene where
## the numeric lint can see them and an author can change them.
const RIPPLE_VISUAL_SCENE := preload(
	"res://scenes/props/shockwave_ripple.tscn"
)
## §4.14's falling debris. Its drop height, hit volume and blob-shadow
## telegraph are all authored in the scene rather than computed in code.
const DEBRIS_SCENE := preload("res://scenes/props/papu_debris.tscn")

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
var _ripple_visuals: Array[Node3D] = []
var _debris: Array[Node3D] = []
var _debris_ages_s: Array[float] = []


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
	_configure_boss_blob_shadow()


## Papu gets the same ground contact as every other dynamic object (spec
## §5.4.2). His visual pivot is what the visual driver moves, so the blob
## targets that rather than this arena node, which never moves.
func _configure_boss_blob_shadow() -> void:
	if _depth == null:
		return
	var pivot := get_node_or_null("PapuVisual") as Node3D
	if pivot == null:
		return
	var blob := pivot.get_node_or_null("BlobShadow")
	if blob == null or not blob.has_method("configure"):
		return
	blob.call("configure", pivot, _depth)


## A phase restart clears its ripples: the player must not inherit waves
## emitted before they died, which would make the retry unfair on entry.
func reset_phase_hazards() -> void:
	_phase_elapsed_s = 0.0
	_slams_emitted = 0
	_wave_ages_s.clear()
	_sync_ripple_visuals()
	for piece: Node3D in _debris:
		if is_instance_valid(piece):
			piece.queue_free()
	_debris.clear()
	_debris_ages_s.clear()


## P-008: one visible crest per live ripple. A lethal thing the player cannot
## see is Pillar 1 inverted.
func ripple_visuals() -> Array:
	var live: Array = []
	for visual: Node3D in _ripple_visuals:
		if is_instance_valid(visual):
			live.append(visual)
	return live


func _sync_ripple_visuals() -> void:
	while _ripple_visuals.size() < _wave_ages_s.size():
		var crest := RIPPLE_VISUAL_SCENE.instantiate() as Node3D
		add_child(crest)
		_ripple_visuals.append(crest)
	while _ripple_visuals.size() > _wave_ages_s.size():
		var spent: Node3D = _ripple_visuals.pop_back()
		if is_instance_valid(spent):
			spent.queue_free()
	var origin := _current_strike_origin()
	var floor_y := origin.y - _strike_height_offset_m()
	for index in range(_wave_ages_s.size()):
		var crest: Node3D = _ripple_visuals[index]
		if not is_instance_valid(crest):
			continue
		# Travels back down the corridor toward the player, standing exactly as
		# tall as the arc the player has to clear.
		crest.global_position = Vector3(
			origin.x,
			floor_y,
			origin.z + _flow.shockwave_distance_m(_wave_ages_s[index])
		)
		crest.scale.y = _flow.shockwave_height_m()


## §4.14: the slam brings debris down with it. Each piece marks its landing
## spot first, falls through its telegraph, and only then can kill.
func debris_pieces() -> Array:
	var live: Array = []
	for piece: Node3D in _debris:
		if is_instance_valid(piece):
			live.append(piece)
	return live


func _spawn_debris_over_player() -> void:
	var piece := DEBRIS_SCENE.instantiate() as Node3D
	add_child(piece)
	piece.global_position = Vector3(
		_player.global_position.x,
		_player.global_position.y - player_height_above_surface_m(),
		_player.global_position.z
	)
	_debris.append(piece)
	_debris_ages_s.append(0.0)


## Returns whether landed debris is currently on top of the player.
func _advance_debris(step_s: float) -> bool:
	var caught := false
	var live_pieces: Array[Node3D] = []
	var live_ages: Array[float] = []
	for index in range(_debris.size()):
		var piece: Node3D = _debris[index]
		if not is_instance_valid(piece):
			continue
		var age_s: float = _debris_ages_s[index] + step_s
		var rock := piece.get_node_or_null("Rock") as Node3D
		var lethal := _flow.debris_is_lethal(age_s)
		if rock != null and not lethal:
			# Fall through the telegraph, so it lands exactly as it arms.
			var fall_ratio := 1.0 - _flow.debris_fall_ratio(age_s)
			rock.position.y = _debris_drop_height_m(piece) * fall_ratio
		elif rock != null:
			rock.position.y = 0.0
		if lethal and _debris_covers_player(piece):
			caught = true
		if lethal and _flow.debris_is_spent(age_s):
			piece.queue_free()
			continue
		live_pieces.append(piece)
		live_ages.append(age_s)
	_debris = live_pieces
	_debris_ages_s = live_ages
	return caught


func _debris_drop_height_m(piece: Node3D) -> float:
	if not piece.has_meta(&"drop_height_m"):
		var rock := piece.get_node_or_null("Rock") as Node3D
		piece.set_meta(
			&"drop_height_m",
			rock.position.y if rock != null else 0.0
		)
	return float(piece.get_meta(&"drop_height_m"))


func _debris_covers_player(piece: Node3D) -> bool:
	var impact := piece.get_node_or_null("Impact") as Area3D
	if impact == null:
		return false
	return impact.get_overlapping_bodies().has(_player)


## The strike volume sits above its floor; the crest must ride the floor.
func _strike_height_offset_m() -> float:
	var marker := _phase_spawn_marker()
	if marker == null:
		return 0.0
	return maxf(_current_strike_origin().y - marker.global_position.y, 0.0)


## §4.14: debris is blob-shadow telegraphed for debris_telegraph_s before it
## can kill, so a death is always something the player could read coming.
func debris_is_lethal_now() -> bool:
	return _flow.debris_is_lethal(_phase_elapsed_s)


## Height above the player's OWN supporting surface, probed downward the same
## way the blob shadow finds its floor. World Y cannot answer this: each phase
## floor sits 2 m higher than the last, so standing safely on tier 3 is a world
## Y that would read as airborne on tier 1.
## P-006: only what the player can actually stand on. Without this the probe
## saw layer-3 crates and enemies as floor.
func height_probe_mask() -> int:
	if _player is CollisionObject3D:
		return (_player as CollisionObject3D).collision_mask
	return 0


func player_height_above_surface_m() -> float:
	if _player == null or _depth == null:
		return 0.0
	# P-005: the engine's own grounded state is the authority. A downward ray
	# from the body centre misses at an authored floor edge, which read as
	# airborne and handed the player an immunity spot on solid ground.
	if _player is CharacterBody3D and (_player as CharacterBody3D).is_on_floor():
		return 0.0
	var space_state := get_world_3d().direct_space_state
	var from := _player.global_position
	var to := from + Vector3.DOWN * _depth.shadow_ray_length_m
	var query := PhysicsRayQueryParameters3D.create(from, to)
	if _player is CollisionObject3D:
		query.exclude = [(_player as CollisionObject3D).get_rid()]
	query.collide_with_areas = false
	query.collision_mask = height_probe_mask()
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
	# Advance the waves already in flight by the whole step, then emit any that
	# landed DURING this step aged from their own landing moment (P-009): a
	# hitch must not backdate a new ripple to the start of the frame.
	var advanced: Array[float] = []
	for age_s: float in _wave_ages_s:
		advanced.append(age_s + step)
	_wave_ages_s = advanced
	var landed_slams := _flow.slam_count_by(_phase_elapsed_s)
	while _slams_emitted < landed_slams:
		_slams_emitted += 1
		_spawn_debris_over_player()
		_wave_ages_s.append(
			maxf(
				_phase_elapsed_s - _flow.slam_landing_time_s(_slams_emitted),
				0.0
			)
		)
	var debris_caught := _advance_debris(step)
	var origin := _current_strike_origin()
	var player_gap_m := absf(_player.global_position.z - origin.z)
	var clears := _flow.shockwave_clears_player(
		player_height_above_surface_m()
	)
	var caught := false
	var live_waves: Array[float] = []
	for age_s: float in _wave_ages_s:
		var travelled_m := _flow.shockwave_distance_m(age_s)
		if travelled_m < player_gap_m:
			live_waves.append(age_s)
			continue
		# The ripple has reached them; a jumped player lets it pass under.
		if not clears:
			caught = true
	_wave_ages_s = live_waves
	_sync_ripple_visuals()
	return {
		&"caught": caught or debris_caught,
		&"live_waves": _wave_ages_s.size(),
		&"live_debris": _debris.size(),
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


## Read-only visual seam: Papu stands on the active phase floor while the
## gameplay strike volume remains centred above it.
func visual_anchor_position() -> Vector3:
	var origin := _current_strike_origin()
	return Vector3(
		origin.x,
		origin.y - _strike_height_offset_m(),
		origin.z
	)


## Read-only visual seam used to fire one authored slam for each real ripple.
func slams_emitted() -> int:
	return _slams_emitted


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
