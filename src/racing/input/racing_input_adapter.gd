class_name RacingInputAdapter
extends RefCounted

## Task 4 (CTR racing input mode): translates InputRouter's racing-mode raw
## stick and the reused HOP button's press/release edges into KartController
## calls. Pure adapter -- no Node, no physics -- so it is unit-testable
## headless the same way DriftStateMachine (Task 2) is.
##
## Stick x maps straight to steer(-1..1). Stick y pulled DOWN past
## InputTuning.racing_brake_pull_threshold is read as a brake/reverse hold
## (see InputRouter's racing mode: the raw filtered stick arrives with no
## corridor remap, so y keeps its screen-space "down is positive" sense).
##
## A HOP press always forwards to hop_pressed(). If the kart is already
## sliding, the SAME press is also routed to boost_tap() -- CTR muscle
## memory keeps hop and boost on one button on a single mobile thumb.
## DriftStateMachine.boost_tap() ignores taps while not sliding (returns
## &"ignored"), so this stays safe even if the sliding read here is stale by
## a frame relative to the controller's own tick().
##
## The controller parameter is duck-typed (steer/set_brake/hop_pressed/
## hop_released/boost_tap/is_sliding) rather than typed against
## KartController directly, so this adapter is testable against a plain
## RefCounted fake with no scene tree or physics involved.

var _tuning: InputTuning


func configure(input_tuning: InputTuning) -> void:
	_tuning = input_tuning


func apply_move(value: Vector2, controller: Object) -> void:
	controller.steer(value.x)
	controller.set_brake(_is_brake_pull(value))


func apply_hop_pressed(controller: Object) -> void:
	controller.hop_pressed()
	if controller.is_sliding():
		controller.boost_tap()


func apply_hop_released(controller: Object) -> void:
	controller.hop_released()


func _is_brake_pull(value: Vector2) -> bool:
	if _tuning == null:
		return false
	return value.y >= _tuning.racing_brake_pull_threshold
