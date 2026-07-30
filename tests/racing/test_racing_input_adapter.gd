extends GutTest

# Task 4 (CTR racing input mode): RacingInputAdapter maps InputRouter's
# racing-mode raw stick (x = steer, y = brake pull) and the reused HOP
# button's press/release edges onto KartController's poll surface (steer/
# set_brake/hop_pressed/hop_released/boost_tap). Pure adapter, no Node and
# no physics -- tested here against a small fake controller double so the
# routing logic is provable headless, the same way DriftStateMachine
# (tests/racing/test_drift_state_machine.gd) is tested without a scene.

const ADAPTER_SCRIPT_PATH := "res://src/racing/input/racing_input_adapter.gd"
const TUNING_PATH := "res://data/tuning/gameplay.tres"

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


func test_hop_press_while_sliding_also_fires_boost_tap() -> void:
	# CTR muscle memory: hop and boost share one button. A press that
	# arrives while the kart is already sliding must both re-forward to
	# hop_pressed() (mirrors DriftStateMachine's own hop-held latch) AND
	# attempt a boost tap on the very same press.
	var adapter := _new_adapter()
	if adapter == null:
		return
	var controller := FakeKartController.new()
	controller.sliding = true

	adapter.call("apply_hop_pressed", controller)

	assert_eq(controller.hop_pressed_calls, 1)
	assert_eq(controller.boost_tap_calls, 1)


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
