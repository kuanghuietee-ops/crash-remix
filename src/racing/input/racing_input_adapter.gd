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
## Fix round 1: a HOP press routes to EITHER hop_pressed() OR boost_tap(),
## never both -- while the kart is already sliding, every press is a boost
## tap instead of a hop (no hop impulse mid-slide, no re-arm). This
## replaces an earlier "always hop_pressed(), plus boost_tap() when
## sliding" design that a reviewer found unreachable: DriftStateMachine
## used to sustain a slide on the hop button being held, so a second press
## is always preceded by a release, and that release ended the slide
## synchronously -- is_sliding() was already false by the time the boost
## branch ran, and no touch/gamepad sequence could ever fire boost_tap().
## DriftStateMachine now sustains slides on steer instead (see its class
## doc), so hop_released() mid-slide is a no-op and is_sliding() correctly
## reads true at a second press. See tests/racing/test_racing_input_adapter.gd
## for an integration-style test driving the real FSM through this exact
## press-release-press sequence.
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
	if controller.is_sliding():
		controller.boost_tap()
	else:
		controller.hop_pressed()


func apply_hop_released(controller: Object) -> void:
	controller.hop_released()


## R4 Task 2 (CTR item loop): routes an ITEM press edge straight to the
## controller's own use_item() -- a fire-once action, not press-and-hold,
## so unlike hop there is no matching apply_item_released(). See
## race_session.gd's _route_input() for the edge-sampling that guarantees
## this is only ever called once per real press.
func apply_item_pressed(controller: Object) -> void:
	controller.use_item()


func _is_brake_pull(value: Vector2) -> bool:
	if _tuning == null:
		return false
	return value.y >= _tuning.racing_brake_pull_threshold
