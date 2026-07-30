class_name KartController
extends CharacterBody3D

## CharacterBody3D glue for the CTR kart (Task 3). Thin by design: all the
## actual velocity/yaw/boost/spin-out math lives in KartMotor and all the
## drift/slide-boost timing lives in DriftStateMachine (Task 2); this class
## just owns move_and_slide, ground detection, and wiring the two pure-logic
## systems together each physics tick.
##
## BINDING CONTRACT (orchestrator ruling): every physics tick this
## controller polls DriftStateMachine.consume_boost() and hands whatever
## comes back straight to KartMotor.add_boost(), unconditionally -- most
## ticks that is 0.0 seconds (a cheap no-op in add_boost), but the tick a
## slide-boost tap fires, the accrued seconds are applied the same frame,
## not deferred. Do not gate this call behind "only when sliding" or
## similar -- a valid slide end still leaves boost consumable afterward
## (see drift_state_machine.gd), and it must land on the very next tick
## regardless of whether the slide is still active.
##
## Input is a poll surface, not a live read of Input singleton state: the
## racing input mode (Task 4) is expected to call steer()/set_brake() every
## frame and hop_pressed()/hop_released() on edges, the same way callers
## push into DriftStateMachine directly. hop_pressed() only produces an
## actual vertical impulse when the kart is grounded (mirrors CTR -- mashing
## hop mid-air does not stack extra hops); it still always forwards to the
## drift FSM so an airborne hop-then-land can arm a slide on landing.

const KartMotorType := preload("res://src/racing/kart/kart_motor.gd")
const DriftStateMachineType := preload(
	"res://src/racing/kart/drift_state_machine.gd"
)

var _tuning: KartTuning
var _motor: KartMotorType = KartMotorType.new()
var _drift: DriftStateMachineType = DriftStateMachineType.new()

var _steer_input: float
var _brake_input: bool


func configure(kart_tuning: KartTuning) -> void:
	_tuning = kart_tuning
	_motor.configure(kart_tuning)
	_drift.configure(kart_tuning)


func steer(value: float) -> void:
	_steer_input = value
	_drift.steer(value)


func set_brake(braking: bool) -> void:
	_brake_input = braking


func hop_pressed() -> void:
	_drift.hop_pressed()
	if is_on_floor():
		_motor.hop()


func hop_released() -> void:
	_drift.hop_released()


func boost_tap() -> StringName:
	return _drift.boost_tap()


func apply_boost(seconds: float) -> void:
	_motor.add_boost(seconds)


func apply_spin_out() -> void:
	_motor.apply_spin_out()


func speed_mps() -> float:
	return _motor.speed_mps()


func is_sliding() -> bool:
	return _drift.is_sliding()


func is_invulnerable() -> bool:
	return _motor.is_invulnerable()


func _physics_process(delta_s: float) -> void:
	if _tuning == null:
		return
	var grounded := is_on_floor()
	_drift.tick(delta_s, grounded)
	_motor.add_boost(_drift.consume_boost())
	_motor.tick(
		delta_s,
		_steer_input,
		_brake_input,
		grounded,
		_drift.is_sliding(),
		_drift.slide_direction()
	)
	velocity = _motor.velocity()
	velocity.y = _motor.vertical_speed_mps()
	move_and_slide()
