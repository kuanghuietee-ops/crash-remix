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
## actual vertical impulse when the kart is grounded AND not already
## sliding (mirrors CTR -- mashing hop mid-air does not stack extra hops,
## and a hop press mid-drift is a boost tap, not a jump); it still always
## forwards to the drift FSM so an airborne hop-then-land can arm a slide on
## landing. Fix round 1: RacingInputAdapter now routes every hop press that
## arrives while already sliding to boost_tap() instead of calling
## hop_pressed() at all (see racing_input_adapter.gd and drift_state_
## machine.gd's class docs for why), so this guard is defense in depth
## against any other caller reaching hop_pressed() mid-slide, not something
## the adapter's own call pattern currently exercises.

const KartMotorType := preload("res://src/racing/kart/kart_motor.gd")
const DriftStateMachineType := preload(
	"res://src/racing/kart/drift_state_machine.gd"
)

var _tuning: KartTuning
var _motor: KartMotorType = KartMotorType.new()
var _drift: DriftStateMachineType = DriftStateMachineType.new()

var _steer_input: float
var _brake_input: bool
var _run_active: bool = true


func configure(kart_tuning: KartTuning) -> void:
	_tuning = kart_tuning
	_motor.configure(kart_tuning)
	_drift.configure(kart_tuning)
	set_run_active(true)


## Live tuning refresh (M2 fix-wave): re-applies a new KartTuning to the
## motor and drift FSM this controller already owns, the same "the tuning
## loop must be provably live" contract every other live tuning consumer in
## this repo honors (see camera_rail_controller.gd's own refresh_tuning()).
## Unlike configure(), this deliberately does NOT call set_run_active(true)
## -- a mid-race tuning edit must never reactivate a kart a race has
## already frozen at the finish line (see set_run_active()'s own doc); it
## also never touches any live motor/drift STATE (speed, yaw, boost, slide
## progress), only which tuning values that state is computed against next
## tick, exactly like KartMotor.configure()/DriftStateMachine.configure()
## already do on their own.
func refresh_tuning(kart_tuning: KartTuning) -> void:
	_tuning = kart_tuning
	_motor.configure(kart_tuning)
	_drift.configure(kart_tuning)


func steer(value: float) -> void:
	_steer_input = value
	_drift.steer(value)


func set_brake(braking: bool) -> void:
	_brake_input = braking


## Seeds the motor's yaw so a kart placed on an authored spawn transform
## (see race_session.gd's configure(), which calls this AFTER copying the
## spawn's global_transform onto this body) actually keeps facing the way
## it was authored, instead of _physics_process's own unconditional
## rotation.y write below snapping it back to KartMotor's default 0.0
## heading on the very first tick -- the HIGH-1 fix-wave bug: a kart placed
## on a spawn authored facing anything other than -Z (yaw 0) would wedge
## into scenery before a single real gate could validate. Also writes
## rotation.y immediately so the body's own facing basis is correct even
## before the next physics tick runs (matches the invariant
## _physics_process already maintains every tick thereafter).
func set_yaw_degrees(degrees: float) -> void:
	_motor.set_yaw_degrees(degrees)
	rotation.y = deg_to_rad(degrees)


func hop_pressed() -> void:
	_drift.hop_pressed()
	if is_on_floor() and not _drift.is_sliding():
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


## Fix round 1 (KartCamera review): -1/1, locked for the life of a slide --
## see drift_state_machine.gd. Exposed alongside is_sliding()/speed_mps() so
## a camera rig can bias its look yaw into the slide without reaching past
## this controller into the private drift FSM it owns.
func slide_direction() -> int:
	return _drift.slide_direction()


func is_invulnerable() -> bool:
	return _motor.is_invulnerable()


## Fix round (H2 review): a race that just finished must stop the kart
## driving into walls behind the finish line under its own auto-throttle,
## and must not leave a mid-finish slide latched forever accumulating yaw.
## false zeroes the routed steer, releases the held hop latch, and
## force-ends any active slide (DriftStateMachine.cancel_slide()) as a
## one-time transition -- _physics_process then branches every following
## tick to KartMotor.decelerate_to_stop() instead of the normal drift+motor
## tick, so the kart visually rolls to a stop (brake_mps2) and stays there
## rather than snapping to zero or creeping back up to speed once it
## arrives. true is the default and is re-applied by configure(), so a
## fresh kart (the normal case: race retry reinstantiates the whole scene)
## always starts active; it also lets a caller that reuses a KartController
## instance across races reactivate it explicitly.
func set_run_active(active: bool) -> void:
	if active == _run_active:
		return
	_run_active = active
	if not active:
		_steer_input = 0.0
		_brake_input = false
		_drift.steer(0.0)
		_drift.hop_released()
		_drift.cancel_slide()


func is_run_active() -> bool:
	return _run_active


func _physics_process(delta_s: float) -> void:
	if _tuning == null:
		return
	var grounded := is_on_floor()
	if _run_active:
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
	else:
		_motor.decelerate_to_stop(delta_s, grounded)
	velocity = _motor.velocity()
	velocity.y = _motor.vertical_speed_mps()
	# Fix round 1 (KartCamera review): the body's own basis never turned --
	# KartMotor already computes velocity FROM its internal yaw (see
	# kart_motor.gd's velocity()), but nothing wrote that yaw back onto this
	# CharacterBody3D's transform, so -global_transform.basis.z (the
	# "facing" a chase camera or any other Node3D-level reader needs) stayed
	# stuck at whatever it spawned with regardless of steering. Writing
	# rotation.y from the same yaw_degrees() the motor already used for
	# velocity() this tick keeps the two consistent by construction.
	rotation.y = deg_to_rad(_motor.yaw_degrees())
	move_and_slide()
