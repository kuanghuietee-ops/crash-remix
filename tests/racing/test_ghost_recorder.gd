extends GutTest

# CTR R7 Task 6 (stretch, time-trial ghost): GhostRecorder is pure RefCounted
# sampling logic (configure/start/sample/stop poll model, the same shape
# countdown_timer.gd/start_boost_judge.gd already establish) -- see
# ghost_recorder.gd's own class doc and
# .superpowers/sdd/2026-08-01-ctr-r7-second-circuit/task-6-brief.md. File
# persistence (round-trip/corruption) is proved separately in
# test_ghost_file_format.gd; this file only covers sampling cadence + the
# hard keyframe cap.

const GhostRecorderType := preload("res://src/racing/flow/ghost_recorder.gd")


func _new_recorder(interval_s: float, max_keyframes: float) -> GhostRecorderType:
	var tuning := RaceTuning.new()
	tuning.ghost_keyframe_interval_s = interval_s
	tuning.ghost_max_keyframes = max_keyframes
	var recorder := GhostRecorderType.new() as GhostRecorderType
	recorder.configure(tuning)
	return recorder


# ---------------------------------------------------------------------------
# Idle state before start().
# ---------------------------------------------------------------------------


func test_configure_starts_idle_with_no_keyframes() -> void:
	var recorder := _new_recorder(0.1, 3600.0)

	assert_false(recorder.is_recording())
	assert_false(recorder.is_capped())
	assert_false(recorder.has_keyframes())
	assert_eq(recorder.keyframes().size(), 0)


func test_sample_before_start_is_a_no_op() -> void:
	var recorder := _new_recorder(0.1, 3600.0)

	recorder.sample(0.0, Vector3.ZERO, 0.0)

	assert_eq(recorder.keyframes().size(), 0)


# ---------------------------------------------------------------------------
# Cadence: the first post-start sample always records; later ones only
# record once elapsed_s crosses the next interval boundary.
# ---------------------------------------------------------------------------


func test_start_then_first_sample_records_the_go_pose() -> void:
	var recorder := _new_recorder(0.1, 3600.0)
	recorder.start()

	recorder.sample(0.0, Vector3(1.0, 2.0, 3.0), 90.0)

	assert_true(recorder.is_recording())
	var frames := recorder.keyframes()
	assert_eq(frames.size(), 1)
	assert_almost_eq(float(frames[0]["t"]), 0.0, 0.0001)
	assert_eq(frames[0]["position"], Vector3(1.0, 2.0, 3.0))
	assert_almost_eq(float(frames[0]["yaw_degrees"]), 90.0, 0.0001)


func test_samples_between_interval_boundaries_are_dropped() -> void:
	var recorder := _new_recorder(0.1, 3600.0)
	recorder.start()

	recorder.sample(0.0, Vector3.ZERO, 0.0)
	recorder.sample(0.03, Vector3.ZERO, 0.0)
	recorder.sample(0.06, Vector3.ZERO, 0.0)
	recorder.sample(0.09, Vector3.ZERO, 0.0)

	assert_eq(
		recorder.keyframes().size(),
		1,
		"every sample short of the first 0.1s boundary must be dropped"
	)


func test_crossing_an_interval_boundary_records_a_new_keyframe() -> void:
	var recorder := _new_recorder(0.1, 3600.0)
	recorder.start()

	recorder.sample(0.0, Vector3.ZERO, 0.0)
	recorder.sample(0.05, Vector3.ZERO, 0.0)
	recorder.sample(0.1, Vector3(5.0, 0.0, 0.0), 45.0)

	var frames := recorder.keyframes()
	assert_eq(frames.size(), 2)
	assert_almost_eq(float(frames[1]["t"]), 0.1, 0.0001)
	assert_eq(frames[1]["position"], Vector3(5.0, 0.0, 0.0))


func test_cadence_does_not_drift_across_many_boundaries() -> void:
	var recorder := _new_recorder(0.1, 3600.0)
	recorder.start()

	# A real Godot physics tick (~1/60s) is not an exact divisor of the
	# authored 0.1s interval, so individual keyframes land a fraction of a
	# tick either side of their nominal boundary -- exactly the real-world
	# jitter this cadence design must tolerate (see the class doc's CADENCE
	# section: the next-sample threshold always advances by a FIXED
	# interval from the previous THRESHOLD, never from whatever elapsed_s
	# was actually observed, so that per-tick jitter can never accumulate
	# into long-run drift). 720 ticks of 1/60s covers 12.0s of real elapsed
	# time, comfortably enough boundaries to prove the gap between
	# consecutive keyframes stays tightly banded around 0.1s from the very
	# first pair to the very last, rather than growing over time the way a
	# naively-reset ("snap to elapsed_s") threshold would.
	var physics_delta_s := 1.0 / 60.0
	var elapsed_s := 0.0
	for _tick: int in range(720):
		recorder.sample(elapsed_s, Vector3.ZERO, 0.0)
		elapsed_s += physics_delta_s

	var frames := recorder.keyframes()
	# ~12.0s / 0.1s interval -- within one tick's worth of the ideal count.
	assert_between(frames.size(), 118, 122)
	for index: int in range(1, frames.size()):
		var gap := float(frames[index]["t"]) - float(frames[index - 1]["t"])
		assert_between(
			gap,
			0.1 - physics_delta_s,
			0.1 + physics_delta_s,
			"keyframe %d's gap from its predecessor drifted off the authored cadence" % index
		)


# ---------------------------------------------------------------------------
# Hard cap: bounded memory for a long/stuck solo run.
# ---------------------------------------------------------------------------


func test_sampling_stops_once_the_cap_is_reached() -> void:
	var recorder := _new_recorder(0.1, 3.0)
	recorder.start()

	var elapsed_s := 0.0
	for _tick: int in range(10):
		recorder.sample(elapsed_s, Vector3.ZERO, 0.0)
		elapsed_s += 0.1

	assert_eq(
		recorder.keyframes().size(),
		3,
		"recording must never exceed the tuned ghost_max_keyframes ceiling"
	)
	assert_true(recorder.is_capped())
	assert_false(
		recorder.is_recording(),
		"a capped recorder must stop recording, not silently keep discarding"
	)


func test_stop_preserves_already_recorded_keyframes() -> void:
	var recorder := _new_recorder(0.1, 3600.0)
	recorder.start()
	recorder.sample(0.0, Vector3.ZERO, 0.0)
	recorder.sample(0.1, Vector3.ZERO, 0.0)

	recorder.stop()

	assert_false(recorder.is_recording())
	assert_eq(recorder.keyframes().size(), 2)


func test_stop_then_sample_is_a_no_op() -> void:
	var recorder := _new_recorder(0.1, 3600.0)
	recorder.start()
	recorder.sample(0.0, Vector3.ZERO, 0.0)
	recorder.stop()

	recorder.sample(0.1, Vector3(9.0, 9.0, 9.0), 0.0)

	assert_eq(recorder.keyframes().size(), 1)


func test_a_fresh_start_discards_a_previous_recording() -> void:
	var recorder := _new_recorder(0.1, 3600.0)
	recorder.start()
	recorder.sample(0.0, Vector3.ZERO, 0.0)
	recorder.sample(0.1, Vector3.ZERO, 0.0)
	recorder.stop()

	recorder.start()

	assert_eq(
		recorder.keyframes().size(),
		0,
		"a re-start (retry) must never leak a previous run's keyframes"
	)
	assert_false(recorder.is_capped())


func test_keyframes_getter_returns_a_defensive_copy() -> void:
	var recorder := _new_recorder(0.1, 3600.0)
	recorder.start()
	recorder.sample(0.0, Vector3.ZERO, 0.0)

	var frames := recorder.keyframes()
	frames.clear()

	assert_eq(
		recorder.keyframes().size(),
		1,
		"mutating a returned keyframes() array must not corrupt recorder state"
	)
