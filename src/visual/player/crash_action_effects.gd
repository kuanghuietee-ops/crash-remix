class_name CrashActionEffects
extends Node3D

const SPIN_ROTATION_SPEED_RADIANS_PER_SECOND := TAU * 2.5
const SPIN_PULSE_SPEED_RADIANS_PER_SECOND := TAU * 3.0
const SPIN_PULSE_AMPLITUDE := 0.08
const STOMP_DURATION_S := 0.42
const STOMP_START_SCALE := 0.35
const STOMP_END_SCALE := 2.4
const STOMP_FLOOR_OFFSET_M := 0.025

@export var controller_path: NodePath

@onready var _spin: Node3D = $Spin
@onready var _stomp: Node3D = $Stomp
@onready var _impact_ring: MeshInstance3D = $Stomp/ImpactRing
@onready var _dust: GPUParticles3D = $Stomp/Dust

var _controller: CharacterBody3D
var _spin_active: bool
var _spin_phase: float
var _stomp_elapsed_s := STOMP_DURATION_S
var _impact_material: BaseMaterial3D
var _impact_color := Color.WHITE


func _ready() -> void:
	_controller = get_node_or_null(controller_path) as CharacterBody3D
	if _controller == null:
		push_error("Crash action effects controller path must resolve")
		set_process(false)
		return
	_controller.connect(
		&"spin_changed",
		Callable(self, "_on_spin_changed")
	)
	_controller.connect(
		&"body_slam_impacted",
		Callable(self, "_on_body_slam_impacted")
	)
	_stomp.top_level = true
	_impact_material = (
		_impact_ring.get_active_material(0) as BaseMaterial3D
	)
	if _impact_material != null:
		_impact_material = _impact_material.duplicate() as BaseMaterial3D
		_impact_ring.material_override = _impact_material
		_impact_color = _impact_material.albedo_color
	_reset_spin()
	_reset_stomp()


func _process(delta_s: float) -> void:
	if _spin_active:
		_advance_spin(delta_s)
	if _stomp.visible:
		_advance_stomp(delta_s)


func is_spin_effect_active() -> bool:
	return _spin_active and _spin.visible


func is_stomp_effect_active() -> bool:
	return _stomp.visible and _stomp_elapsed_s < STOMP_DURATION_S


func _on_spin_changed(active: bool) -> void:
	_spin_active = active
	_spin.visible = active
	if active:
		_spin_phase = 0.0
		_spin.scale = Vector3.ONE
	else:
		_reset_spin()


func _on_body_slam_impacted() -> void:
	_stomp_elapsed_s = 0.0
	_stomp.visible = true
	_stomp.global_transform = Transform3D(
		Basis.IDENTITY,
		_controller.global_position
		+ Vector3.UP * STOMP_FLOOR_OFFSET_M
	)
	_impact_ring.scale = Vector3(
		STOMP_START_SCALE,
		1.0,
		STOMP_START_SCALE
	)
	_set_impact_alpha(_impact_color.a)
	_dust.emitting = true
	_dust.restart()


func _advance_spin(delta_s: float) -> void:
	var safe_delta := maxf(delta_s, 0.0)
	_spin.rotate_y(
		SPIN_ROTATION_SPEED_RADIANS_PER_SECOND * safe_delta
	)
	_spin_phase = fmod(
		_spin_phase
		+ SPIN_PULSE_SPEED_RADIANS_PER_SECOND * safe_delta,
		TAU
	)
	var pulse := 1.0 + sin(_spin_phase) * SPIN_PULSE_AMPLITUDE
	_spin.scale = Vector3.ONE * pulse


func _advance_stomp(delta_s: float) -> void:
	_stomp_elapsed_s = minf(
		_stomp_elapsed_s + maxf(delta_s, 0.0),
		STOMP_DURATION_S
	)
	var progress := _stomp_elapsed_s / STOMP_DURATION_S
	var eased_progress := 1.0 - pow(1.0 - progress, 3.0)
	var ring_scale := lerpf(
		STOMP_START_SCALE,
		STOMP_END_SCALE,
		eased_progress
	)
	_impact_ring.scale = Vector3(ring_scale, 1.0, ring_scale)
	_set_impact_alpha(_impact_color.a * (1.0 - progress))
	if progress >= 1.0:
		_stomp.visible = false


func _set_impact_alpha(alpha: float) -> void:
	if _impact_material == null:
		return
	_impact_material.albedo_color = Color(
		_impact_color.r,
		_impact_color.g,
		_impact_color.b,
		clampf(alpha, 0.0, 1.0)
	)


func _reset_spin() -> void:
	_spin_active = false
	_spin.visible = false
	_spin.rotation = Vector3.ZERO
	_spin.scale = Vector3.ONE


func _reset_stomp() -> void:
	_stomp_elapsed_s = STOMP_DURATION_S
	_stomp.visible = false
	_dust.emitting = false
