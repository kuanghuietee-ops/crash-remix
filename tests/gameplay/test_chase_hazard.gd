extends GutTest

const CHASE_SCRIPT_PATH := (
	"res://src/gameplay/chase/chase_hazard.gd"
)
const CHASE_TUNING_PATH := "res://data/tuning/chase.tres"
const PROGRESS_TOLERANCE_M := 0.0001


func test_boulder_closes_at_tuned_speed_without_rubber_band() -> void:
	var setup := _new_hazard()
	if setup.is_empty():
		return
	var hazard := setup[&"hazard"] as Node
	var tuning := setup[&"tuning"] as Resource
	var player_start_m := 20.0
	var elapsed_s := 0.5

	hazard.call("start_at_progress", player_start_m)
	var initial_boulder_m := float(
		hazard.call("boulder_progress_m")
	)
	var initial_gap_m := float(
		hazard.call("gap_to_progress_m", player_start_m)
	)
	var equal_speed_player_m := (
		player_start_m
		+ float(tuning.get("boulder_speed_mps")) * elapsed_s
	)
	var outcome: Dictionary = hazard.call(
		"advance_progress",
		elapsed_s,
		equal_speed_player_m
	)

	assert_almost_eq(
		float(hazard.call("boulder_progress_m"))
		- initial_boulder_m,
		float(tuning.get("boulder_speed_mps")) * elapsed_s,
		PROGRESS_TOLERANCE_M,
		"the boulder must advance only by tuned speed × delta"
	)
	assert_almost_eq(
		float(outcome.get(&"gap_m", -1.0)),
		initial_gap_m,
		PROGRESS_TOLERANCE_M,
		"equal player and boulder progress must preserve a constant gap"
	)
	assert_false(
		bool(outcome.get(&"caught", true)),
		"the hazard must not rubber-band into a player matching its speed"
	)


func test_boulder_kills_at_the_tuned_distance_and_not_before() -> void:
	var setup := _new_hazard()
	if setup.is_empty():
		return
	var hazard := setup[&"hazard"] as Node
	var tuning := setup[&"tuning"] as Resource
	var player_start_m := 20.0
	hazard.call("start_at_progress", player_start_m)
	var boulder_m := float(hazard.call("boulder_progress_m"))
	var kill_distance_m := float(
		tuning.get("boulder_kill_distance_m")
	)

	var safe: Dictionary = hazard.call(
		"advance_progress",
		0.0,
		boulder_m + kill_distance_m + PROGRESS_TOLERANCE_M
	)
	assert_false(
		bool(safe.get(&"caught", true)),
		"a player outside the tuned kill distance must remain safe"
	)

	hazard.call("start_at_progress", player_start_m)
	boulder_m = float(hazard.call("boulder_progress_m"))
	var caught: Dictionary = hazard.call(
		"advance_progress",
		0.0,
		boulder_m + kill_distance_m
	)
	assert_true(
		bool(caught.get(&"caught", false)),
		"the tuned kill distance must be the exact catch boundary"
	)


func test_start_and_stop_segment_events_control_the_chase() -> void:
	var setup := _new_hazard()
	if setup.is_empty():
		return
	var hazard := setup[&"hazard"] as Node
	var tuning := setup[&"tuning"] as Resource
	var started: Array[float] = []
	var stopped: Array[bool] = []
	hazard.connect(
		&"chase_started",
		func(gap_m: float) -> void:
			started.append(gap_m)
	)
	hazard.connect(
		&"chase_stopped",
		func() -> void:
			stopped.append(true)
	)

	hazard.call(
		"handle_segment_event",
		&"start",
		30.0
	)
	assert_true(hazard.call("is_active"))
	assert_eq(started.size(), 1)
	if not started.is_empty():
		assert_almost_eq(
			started[0],
			float(tuning.get("boulder_start_gap_m")),
			PROGRESS_TOLERANCE_M
		)

	hazard.call(
		"handle_segment_event",
		&"stop",
		30.0
	)
	assert_false(hazard.call("is_active"))
	assert_eq(stopped.size(), 1)


func _new_hazard() -> Dictionary:
	assert_true(
		ResourceLoader.exists(CHASE_SCRIPT_PATH),
		"Wave C must provide the chase hazard script"
	)
	assert_true(
		ResourceLoader.exists(CHASE_TUNING_PATH),
		"Wave C must provide authored chase tuning"
	)
	if (
		not ResourceLoader.exists(CHASE_SCRIPT_PATH)
		or not ResourceLoader.exists(CHASE_TUNING_PATH)
	):
		return {}
	var script := load(CHASE_SCRIPT_PATH) as Script
	var tuning := load(CHASE_TUNING_PATH) as Resource
	assert_not_null(script)
	assert_not_null(tuning)
	if script == null or tuning == null:
		return {}
	var hazard := script.new() as Node
	assert_not_null(hazard)
	if hazard == null:
		return {}
	add_child_autofree(hazard)
	assert_true(
		hazard.has_method("configure_logic"),
		"the headless chase contract must stay separate from scene glue"
	)
	if not hazard.has_method("configure_logic"):
		return {}
	hazard.call("configure_logic", tuning)
	return {
		&"hazard": hazard,
		&"tuning": tuning,
	}
