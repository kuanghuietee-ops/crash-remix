class_name EnemyBase
extends AnimatableBody3D

signal attack_contact(body: Node, enemy: Node)

const ScalarMathType := preload(
	"res://src/core/scalar_math.gd"
)

const VERB_TOUCH := &"touch"
const VERB_SPIN := &"spin"
const VERB_JUMP := &"jump"
const VERB_SLIDE := &"slide"
const VERB_SLAM := &"slam"

const STATE_DORMANT := &"dormant"
const STATE_TELEGRAPH := &"telegraph"
const STATE_ACTIVE := &"active"
const STATE_COOLDOWN := &"cooldown"
const STATE_PATROL := &"patrol"
const STATE_TURN_PAUSE := &"turn_pause"

var _enemy_tuning: EnemyTuning
var _move_tuning: MoveTuning
var _authored_transform := Transform3D.IDENTITY
var _authored_global_transform := Transform3D.IDENTITY
var _authored_spawn_captured: bool = false
var _defeated: bool = false
var _attack_active: bool = false
var _behavior_state: StringName = STATE_DORMANT


func _ready() -> void:
	sync_to_physics = false
	add_to_group(&"enemy")
	_capture_authored_spawn()
	var attack_area := get_node_or_null("AttackArea") as Area3D
	if (
		attack_area != null
		and not attack_area.body_entered.is_connected(
			_on_attack_area_body_entered
		)
	):
		attack_area.body_entered.connect(
			_on_attack_area_body_entered
		)
	_sync_state_cues()


func configure(
	enemy_tuning: EnemyTuning,
	move_tuning: MoveTuning
) -> void:
	_enemy_tuning = enemy_tuning
	_move_tuning = move_tuning
	if not _authored_spawn_captured:
		_capture_authored_spawn()
	_apply_visual_shape_ratios()
	reset_to_authored_spawn()


func refresh_tuning(
	enemy_tuning: EnemyTuning,
	move_tuning: MoveTuning
) -> void:
	_enemy_tuning = enemy_tuning
	_move_tuning = move_tuning
	_apply_visual_shape_ratios()


func enemy_kind() -> StringName:
	return &""


func tuning_section() -> StringName:
	return &""


func accepted_verbs() -> Array[StringName]:
	return []


func advance_logic(
	_now_s: float,
	_player_position: Vector3
) -> void:
	pass


func delay_timers(_duration_s: float) -> void:
	pass


func behavior_state() -> StringName:
	return _behavior_state


func attack_is_active() -> bool:
	return _attack_active and not _defeated


func is_defeated() -> bool:
	return _defeated


func authored_spawn_transform() -> Transform3D:
	return _authored_global_transform


func apply_verb(
	verb: StringName,
	_now_s: float = 0.0
) -> Dictionary:
	if (
		_defeated
		or _enemy_tuning == null
		or verb not in accepted_verbs()
	):
		return _outcome()
	_set_defeated(true)
	return _outcome(true)


func resolve_contact(
	verb: StringName,
	now_s: float
) -> Dictionary:
	if _defeated:
		return _outcome()
	if verb in accepted_verbs():
		return apply_verb(verb, now_s)
	return _outcome(false, true)


func reset_to_authored_spawn() -> void:
	if not _authored_spawn_captured:
		_capture_authored_spawn()
	transform = _authored_transform
	reset_physics_interpolation()
	_set_defeated(false)
	_set_attack_active(false)
	_reset_behavior_state()


func _reset_behavior_state() -> void:
	_set_behavior_state(STATE_DORMANT)


func _set_behavior_state(state: StringName) -> void:
	_behavior_state = state
	_sync_state_cues()


func _set_attack_active(active: bool) -> void:
	_attack_active = active and not _defeated
	var attack_area := get_node_or_null("AttackArea") as Area3D
	if attack_area != null:
		attack_area.set_deferred(
			&"monitoring",
			_attack_active
		)
	_sync_state_cues()


func _set_authored_lateral_offset(offset_m: float) -> void:
	var shifted := _authored_transform
	var lateral_axis := shifted.basis.x.normalized()
	shifted.origin += lateral_axis * offset_m
	transform = shifted


func _player_is_inside_trigger(
	player_position: Vector3
) -> bool:
	if _enemy_tuning == null:
		return false
	return (
		global_position.distance_to(player_position)
		<= _enemy_tuning.trigger_range_m
	)


func _player_lateral_direction(
	player_position: Vector3
) -> float:
	var lateral_axis := _authored_global_transform.basis.x.normalized()
	var lateral_distance := (
		player_position - _authored_global_transform.origin
	).dot(lateral_axis)
	if lateral_distance < 0.0:
		return -1.0
	return 1.0


func _capture_authored_spawn() -> void:
	_authored_transform = transform
	_authored_global_transform = (
		global_transform if is_inside_tree() else transform
	)
	_authored_spawn_captured = true


func _set_defeated(defeated: bool) -> void:
	_defeated = defeated
	visible = not defeated
	var hurt_shape := (
		get_node_or_null("CollisionShape3D")
		as CollisionShape3D
	)
	if hurt_shape != null:
		hurt_shape.set_deferred(&"disabled", defeated)
	if defeated:
		_set_attack_active(false)


func _apply_visual_shape_ratios() -> void:
	if _move_tuning == null:
		return
	var visual := get_node_or_null("Visual") as MeshInstance3D
	if visual == null or visual.mesh == null:
		return
	var visual_bounds := visual.transform * visual.mesh.get_aabb()
	_apply_box_shape_ratio(
		get_node_or_null("CollisionShape3D") as CollisionShape3D,
		visual_bounds,
		_move_tuning.hurtbox_visual_ratio,
		false
	)
	_apply_box_shape_ratio(
		get_node_or_null(
			"AttackArea/CollisionShape3D"
		) as CollisionShape3D,
		visual_bounds,
		_move_tuning.attack_visual_ratio,
		true
	)


func _apply_box_shape_ratio(
	collision: CollisionShape3D,
	visual_bounds: AABB,
	ratio: float,
	align_to_hurt_top: bool
) -> void:
	if collision == null or not collision.shape is BoxShape3D:
		return
	var shape := collision.shape.duplicate() as BoxShape3D
	shape.size = visual_bounds.size * ratio
	collision.shape = shape
	var center := visual_bounds.get_center()
	var bottom := visual_bounds.position.y
	var hurt_height := (
		visual_bounds.size.y
		* _move_tuning.hurtbox_visual_ratio
	)
	var target_top := bottom + hurt_height
	center.y = (
		target_top - shape.size.y * ScalarMathType.HALF
		if align_to_hurt_top
		else bottom + shape.size.y * ScalarMathType.HALF
	)
	collision.position = center


func _sync_state_cues() -> void:
	var telegraph_cue := (
		get_node_or_null("TelegraphCue") as Node3D
	)
	var active_cue := get_node_or_null("ActiveCue") as Node3D
	if telegraph_cue != null:
		telegraph_cue.visible = (
			not _defeated
			and _behavior_state == STATE_TELEGRAPH
		)
	if active_cue != null:
		active_cue.visible = (
			not _defeated
			and _behavior_state == STATE_ACTIVE
		)


func _on_attack_area_body_entered(body: Node) -> void:
	if attack_is_active():
		attack_contact.emit(body, self)


func _outcome(
	enemy_defeated: bool = false,
	player_hit: bool = false,
	player_bounce: bool = false
) -> Dictionary:
	return {
		"enemy_defeated": enemy_defeated,
		"player_hit": player_hit,
		"player_bounce": player_bounce,
	}
