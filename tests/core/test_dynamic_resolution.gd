extends GutTest

const DynamicResolutionType := preload("res://src/core/dynamic_resolution.gd")
const SCALE_TOLERANCE := 0.0001

# Concrete frame times against the 60 fps budget (16.67 ms), chosen so these
# assertions do not merely restate the production constants:
#   16.0 ms — nearly out of budget, but has NOT dropped a frame yet (§9.4 wants
#             the scale falling before the drop, not after it)
#   13.0 ms — comfortable; neither direction
#    8.0 ms — far inside budget, so the scale can be given back
const NEARLY_OVER_BUDGET_S := 0.016
const COMFORTABLE_S := 0.013
const FAR_INSIDE_BUDGET_S := 0.008


func test_a_frame_nearly_out_of_budget_scales_down_before_it_drops() -> void:
	var next := DynamicResolutionType.next_scale(1.0, NEARLY_OVER_BUDGET_S)

	assert_lt(
		next,
		1.0,
		"§9.4: resolution falls before a frame drops, not after"
	)


func test_a_frame_far_inside_budget_gives_the_resolution_back() -> void:
	var next := DynamicResolutionType.next_scale(0.8, FAR_INSIDE_BUDGET_S)

	assert_gt(next, 0.8, "headroom must be returned to image quality")


func test_a_comfortable_frame_holds_the_current_scale() -> void:
	# Without a hold band the scale oscillates every adjustment, which reads as
	# a shimmering image on a phone.
	assert_almost_eq(
		DynamicResolutionType.next_scale(0.85, COMFORTABLE_S),
		0.85,
		SCALE_TOLERANCE,
		"a frame inside the hold band must not move the scale"
	)


func test_sustained_load_stops_at_the_authored_floor() -> void:
	# §9.4 names 0.7 as the floor: below it the image is worse than the frame
	# drop it is buying.
	var scale := 1.0
	for _index in range(100):
		scale = DynamicResolutionType.next_scale(scale, NEARLY_OVER_BUDGET_S)

	assert_almost_eq(
		scale,
		0.7,
		SCALE_TOLERANCE,
		"sustained load must converge on the floor, not below it"
	)


func test_sustained_headroom_stops_at_full_resolution() -> void:
	var scale := 0.7
	for _index in range(100):
		scale = DynamicResolutionType.next_scale(scale, FAR_INSIDE_BUDGET_S)

	assert_almost_eq(
		scale,
		1.0,
		SCALE_TOLERANCE,
		"the scale must never exceed full resolution"
	)


func test_the_scale_moves_on_an_interval_not_every_frame() -> void:
	# Reacting per frame would chase noise; the controller averages an interval
	# before it moves.
	var controller: DynamicResolutionType = DynamicResolutionType.new()

	var held := controller.tick(NEARLY_OVER_BUDGET_S, 1.0)

	assert_almost_eq(
		held,
		1.0,
		SCALE_TOLERANCE,
		"one slow frame must not move the scale"
	)

	var elapsed_s := NEARLY_OVER_BUDGET_S
	var scale := held
	while elapsed_s < DynamicResolutionType.ADJUST_INTERVAL_S:
		scale = controller.tick(NEARLY_OVER_BUDGET_S, scale)
		elapsed_s += NEARLY_OVER_BUDGET_S

	assert_lt(
		scale,
		1.0,
		"a full interval of slow frames must move it"
	)
