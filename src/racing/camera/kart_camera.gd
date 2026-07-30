class_name KartCamera
extends Node3D

## CTR-style kart chase camera (Task 5). A Node3D that positions and orients
## a Camera3D child every tick from the kart's own FACING BASIS -- never its
## velocity. A slide's momentary counter-steer or a spin-out's yaw-authority
## zeroing can point velocity somewhere other than where the kart visually
## faces (see kart_motor.gd), and a chase camera that followed velocity
## would swim/jitter through exactly those moments; the facing basis is
## always the stable, visually-correct thing to trail behind.
##
## kart is duck-typed to the same "Node3D-with-KartController-API" surface
## RacingInputAdapter and DriftStateMachine already assume (speed_mps(),
## is_sliding() -- see kart_controller.gd): a plain Node3D type hint plus
## .call() so any fixture exposing those two methods works, real
## KartController or test double alike (see test_kart_camera.gd's FakeKart).
##
## EASED LOOK YAW. camera_yaw_lag_s drives a persistent _camera_forward
## state toward the kart's current facing (plus a drift bias -- see below)
## using the standard exponential-smoothing alpha (1 - exp(-delta/tau), tau
## <= 0 treated as instant/no lag). This eased direction is what the trail/
## height offset is measured along, so BOTH the rig's position and its gaze
## swing smoothly around a sudden kart turn instead of snapping every tick
## -- the classic chase-camera "lags into turns" feel. configure() seeds
## _camera_forward to the kart's facing at that instant so the very first
## frame starts already aligned, never as a snap-from-zero pop.
##
## DRIFT BIAS. While is_sliding() is true, the eased state's TARGET gets an
## additional camera_drift_yaw_degrees rotated into the slide direction
## (CTR's "the camera looks into the turn" flourish) before easing -- so
## enter/exit blends through the same lag instead of snapping. Slide
## direction itself is read off the kart's own recent facing change (the
## sign of the turn between this tick and last), not a dedicated
## DriftStateMachine.slide_direction() call: that method lives on the
## private drift FSM KartController owns internally and is not part of its
## public API (only is_sliding()/speed_mps() are), and deriving the sign
## from the facing basis keeps this class talking to the exact same
## generic surface it already reads kart_forward from.
##
## LOOK TARGET. The camera looks directly at the kart's position raised by
## RaceTuning.camera_look_height_m (added by this task -- see
## race_tuning.gd and tuning_service.gd for the validation + legacy-
## override migration entry) via look_at(), independent of the eased yaw:
## position lags/drifts, but the rig never loses the kart out of frame.
##
## FOV. camera_fov_base + camera_fov_speed_gain * (speed_mps() /
## top_speed_mps), deliberately UNCLAMPED above a ratio of 1: a boost
## pushes speed_mps() past top_speed_mps by kart_tuning.boost_speed_bonus_mps
## (see kart_motor.gd), and letting the ratio follow it past 1 is what
## makes a boost visibly widen the FOV. The natural ceiling is already
## whatever boost_speed_bonus_mps authors into kart.tres -- no extra
## clamp/tuning field needed on top of that.

var _kart: Node3D
var _camera: Camera3D
var _race_tuning: RaceTuning
var _kart_tuning: KartTuning

var _camera_forward := Vector3.FORWARD
var _previous_kart_forward := Vector3.FORWARD
# Mirrors DriftStateMachine's own _slide_direction default (see
# drift_state_machine.gd) so an untouched sign reads the same way.
var _slide_sign := 1


func configure(
	kart: Node3D,
	camera: Camera3D,
	race_tuning: RaceTuning,
	kart_tuning: KartTuning
) -> void:
	_kart = kart
	_camera = camera
	_race_tuning = race_tuning
	_kart_tuning = kart_tuning

	var initial_forward := _kart_forward()
	_camera_forward = initial_forward
	_previous_kart_forward = initial_forward
	_slide_sign = 1
	# Snap fully configured on the very first frame -- _camera_forward is
	# already seeded to the kart's current facing above, so this "tick"
	# produces the at-rest pose, not an eased crawl from a default.
	_apply(0.0)


func tick(delta_s: float) -> void:
	if (
		_kart == null
		or _camera == null
		or _race_tuning == null
		or _kart_tuning == null
	):
		return
	_apply(delta_s)


## The eased look-forward direction (see class doc). Exposed as a getter
## purely for test introspection, the same way kart_motor.gd exposes
## yaw_degrees() -- production code never needs to read this back.
func look_forward() -> Vector3:
	return _camera_forward


func _physics_process(delta_s: float) -> void:
	tick(delta_s)


func _apply(delta_s: float) -> void:
	var kart_forward := _kart_forward()
	_update_slide_sign(kart_forward)

	var target_forward := kart_forward
	if bool(_kart.call("is_sliding")):
		target_forward = kart_forward.rotated(
			Vector3.UP,
			float(_slide_sign) * deg_to_rad(_race_tuning.camera_drift_yaw_degrees)
		)

	var alpha := _ease_alpha(delta_s, _race_tuning.camera_yaw_lag_s)
	if alpha >= 1.0:
		_camera_forward = target_forward
	else:
		_camera_forward = _camera_forward.slerp(target_forward, alpha)
	if not _camera_forward.is_zero_approx():
		_camera_forward = _camera_forward.normalized()

	_camera.global_position = (
		_kart.global_position
		- _camera_forward * _race_tuning.camera_trail_m
		+ Vector3.UP * _race_tuning.camera_height_m
	)
	var look_target := (
		_kart.global_position
		+ Vector3.UP * _race_tuning.camera_look_height_m
	)
	_camera.look_at(look_target, Vector3.UP)

	var speed_ratio := 0.0
	if _kart_tuning.top_speed_mps > 0.0:
		speed_ratio = float(_kart.call("speed_mps")) / _kart_tuning.top_speed_mps
	_camera.fov = (
		_race_tuning.camera_fov_base
		+ _race_tuning.camera_fov_speed_gain * speed_ratio
	)


func _kart_forward() -> Vector3:
	var basis := _kart.global_transform.basis
	return (-basis.z).normalized()


## Slide direction, inferred from which way the kart's own facing basis
## just turned (see class doc) rather than a dedicated FSM getter. Holding
## the previous sign on a tick with no measurable turn (cross_y ~ 0, e.g.
## the very first tick after a slide starts) avoids an artificial flicker
## to a meaningless zero.
func _update_slide_sign(kart_forward: Vector3) -> void:
	var cross_y := _previous_kart_forward.cross(kart_forward).y
	if not is_zero_approx(cross_y):
		_slide_sign = 1 if cross_y > 0.0 else -1
	_previous_kart_forward = kart_forward


## The standard exponential-smoothing blend factor: 1 - exp(-delta/tau).
## tau <= 0 is guarded as instant (alpha = 1, i.e. snap straight to target)
## rather than dividing by zero or a negative time constant.
func _ease_alpha(delta_s: float, tau_s: float) -> float:
	if tau_s <= 0.0:
		return 1.0
	return 1.0 - exp(-delta_s / tau_s)
