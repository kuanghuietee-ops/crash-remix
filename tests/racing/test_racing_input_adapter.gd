extends GutTest

# Task 4 (CTR racing input mode): RacingInputAdapter maps InputRouter's
# racing-mode raw stick (x = steer, y = brake pull) and the reused HOP
# button's press/release edges onto KartController's poll surface (steer/
# set_brake/hop_pressed/hop_released/boost_tap). Pure adapter, no Node and
# no physics -- tested here against a small fake controller double so the
# routing logic is provable headless, the same way DriftStateMachine
# (tests/racing/test_drift_state_machine.gd) is tested without a scene.

const ADAPTER_SCRIPT_PATH := "res://src/racing/input/racing_input_adapter.gd"
const FSM_SCRIPT_PATH := "res://src/racing/kart/drift_state_machine.gd"
const TUNING_PATH := "res://data/tuning/gameplay.tres"
const KART_TUNING_PATH := "res://data/tuning/racing/kart.tres"

var _input_tuning: InputTuning


class FakeKartController:
	extends RefCounted

	var steer_calls: Array[float] = []
	var brake_calls: Array[bool] = []
	var hop_pressed_calls: int
	var hop_released_calls: int
	var boost_tap_calls: int
	var sliding: bool

	func steer(value: float) -> void:
		steer_calls.append(value)

	func set_brake(braking: bool) -> void:
		brake_calls.append(braking)

	func hop_pressed() -> void:
		hop_pressed_calls += 1

	func hop_released() -> void:
		hop_released_calls += 1

	func boost_tap() -> StringName:
		boost_tap_calls += 1
		return &"fired"

	func is_sliding() -> bool:
		return sliding


## Fix round 1: the reviewer's finding was that a fake tracking call counts
## and a hand-set `sliding` flag can't prove the adapter's routing decision
## is actually reachable against the real state machine's real transitions
## (a hand-set flag can silently paper over exactly the "release always
## happens first, and release used to end the slide" bug that made
## boost_tap() unreachable). This fake wraps a REAL DriftStateMachine
## instead of tracking booleans by hand, so is_sliding() here is the FSM's
## own is_sliding(), not a test's assertion of what it should be.
class RealFsmKartController:
	extends RefCounted

	var _drift: RefCounted

	func _init(kart_tuning: Resource) -> void:
		var script: Script = load(FSM_SCRIPT_PATH)
		_drift = script.new()
		_drift.call("configure", kart_tuning)

	func steer(value: float) -> void:
		_drift.call("steer", value)

	func set_brake(_braking: bool) -> void:
		pass

	func hop_pressed() -> void:
		_drift.call("hop_pressed")

	func hop_released() -> void:
		_drift.call("hop_released")

	func boost_tap() -> StringName:
		return _drift.call("boost_tap")

	func is_sliding() -> bool:
		return _drift.call("is_sliding")

	func tick(delta_s: float, grounded: bool) -> void:
		_drift.call("tick", delta_s, grounded)

	func consume_boost() -> float:
		return _drift.call("consume_boost")

	func boost_stage() -> int:
		return _drift.call("boost_stage")


func before_all() -> void:
	var catalog: Resource = load(TUNING_PATH)
	assert_not_null(catalog)
	if catalog != null:
		_input_tuning = catalog.get("input").duplicate()


func test_steer_maps_stick_x_directly_to_controller_steer() -> void:
	var adapter := _new_adapter()
	if adapter == null:
		return
	var controller := FakeKartController.new()

	adapter.call("apply_move", Vector2(0.5, 0.0), controller)
	adapter.call("apply_move", Vector2(-1.0, 0.0), controller)

	assert_eq(controller.steer_calls, [0.5, -1.0])


func test_stick_pull_below_threshold_does_not_brake() -> void:
	var adapter := _new_adapter()
	if adapter == null:
		return
	var controller := FakeKartController.new()
	var below: float = _input_tuning.racing_brake_pull_threshold / 2.0

	adapter.call("apply_move", Vector2(0.0, below), controller)

	assert_eq(controller.brake_calls, [false])


func test_stick_pull_at_or_beyond_threshold_engages_brake() -> void:
	var adapter := _new_adapter()
	if adapter == null:
		return
	var controller := FakeKartController.new()
	var threshold: float = _input_tuning.racing_brake_pull_threshold

	adapter.call("apply_move", Vector2(0.0, threshold), controller)

	assert_eq(controller.brake_calls, [true])


func test_forward_pull_never_reads_as_brake() -> void:
	var adapter := _new_adapter()
	if adapter == null:
		return
	var controller := FakeKartController.new()

	adapter.call("apply_move", Vector2(0.0, -1.0), controller)

	assert_eq(controller.brake_calls, [false])


func test_hop_press_while_not_sliding_only_hops() -> void:
	var adapter := _new_adapter()
	if adapter == null:
		return
	var controller := FakeKartController.new()
	controller.sliding = false

	adapter.call("apply_hop_pressed", controller)

	assert_eq(controller.hop_pressed_calls, 1)
	assert_eq(
		controller.boost_tap_calls,
		0,
		"a hop press while not sliding must not attempt a boost tap"
	)


func test_hop_press_while_sliding_only_boosts_no_hop_impulse() -> void:
	# Fix round 1: CTR muscle memory keeps hop and boost on one button, but a
	# press while already sliding must route to boost_tap() ONLY -- never
	# hop_pressed() -- so there's no mid-slide hop impulse and no re-arm.
	# (An earlier "always hop_pressed() plus boost_tap() when sliding"
	# design was unreachable in practice: see the real-FSM integration test
	# below and the class doc on racing_input_adapter.gd / drift_state_
	# machine.gd for why.)
	var adapter := _new_adapter()
	if adapter == null:
		return
	var controller := FakeKartController.new()
	controller.sliding = true

	adapter.call("apply_hop_pressed", controller)

	assert_eq(
		controller.hop_pressed_calls,
		0,
		"a hop press while sliding must not also forward to hop_pressed()"
	)
	assert_eq(controller.boost_tap_calls, 1)


func test_press_release_press_mid_slide_fires_boost_against_the_real_fsm() -> void:
	# Integration-style proof against the REAL DriftStateMachine (via
	# RealFsmKartController above) of the reviewer's exact scenario: a
	# second hop press is always preceded by a release. Start a slide,
	# release hop (as the one-thumb mobile flow does -- hop is only held
	# long enough to register the initial press), tick into the boost tap
	# window, then press hop again. The adapter must read is_sliding() ==
	# true at that second press (the real FSM's own answer, not a hand-set
	# flag) and route it to boost_tap(), which must actually fire.
	var kart_tuning: Resource = load(KART_TUNING_PATH)
	assert_not_null(kart_tuning, "kart.tres must load")
	var adapter := _new_adapter()
	if kart_tuning == null or adapter == null:
		return
	var controller := RealFsmKartController.new(kart_tuning)

	# Start the slide: grounded + hop press + steer past slide_min_steer.
	adapter.call("apply_move", Vector2(kart_tuning.slide_min_steer, 0.0), controller)
	adapter.call("apply_hop_pressed", controller)
	controller.tick(0.0, true)
	assert_true(
		controller.is_sliding(),
		"fixture setup must land inside a slide"
	)

	adapter.call("apply_hop_released", controller)
	assert_true(
		controller.is_sliding(),
		"releasing hop mid-slide must not end it -- steer sustains now"
	)

	var window_midpoint_s: float = (
		(kart_tuning.boost_window_open_s + kart_tuning.boost_window_close_s) / 2.0
	)
	controller.tick(window_midpoint_s, true)

	adapter.call("apply_hop_pressed", controller)

	assert_eq(controller.boost_stage(), 1, "the second press's boost tap must have fired (stage 1)")
	assert_almost_eq(
		controller.consume_boost(),
		float(kart_tuning.boost_duration_s),
		0.0001,
		"the second press's boost tap must have fired inside the window"
	)


func test_hop_released_forwards_to_controller() -> void:
	var adapter := _new_adapter()
	if adapter == null:
		return
	var controller := FakeKartController.new()

	adapter.call("apply_hop_released", controller)

	assert_eq(controller.hop_released_calls, 1)


func _new_adapter() -> RefCounted:
	var script: Script = load(ADAPTER_SCRIPT_PATH)
	assert_not_null(script, "RacingInputAdapter implementation must exist")
	if script == null:
		return null
	var adapter: RefCounted = script.new()
	adapter.call("configure", _input_tuning)
	return adapter
