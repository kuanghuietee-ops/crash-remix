extends GutTest

const PerfReadoutType := preload("res://src/debug/perf_readout.gd")
const FPS_TOLERANCE := 0.001


func _steady_series(frame_count: int, frame_time_s: float) -> Array[float]:
	var frame_times: Array[float] = []
	for _index in range(frame_count):
		frame_times.append(frame_time_s)
	return frame_times


func test_average_fps_is_the_reciprocal_of_the_mean_frame_time() -> void:
	var frame_times := _steady_series(120, 1.0 / 60.0)

	assert_almost_eq(
		PerfReadoutType.average_fps(frame_times),
		60.0,
		FPS_TOLERANCE,
		"a steady 16.67 ms series must read as 60 fps"
	)


func test_average_fps_is_not_the_mean_of_instantaneous_rates() -> void:
	# E1-04(1): the steady-series test above cannot separate 1/mean(frame_time)
	# from mean(1/frame_time) — they agree when every frame is identical. On a
	# mixed series they do not: 99 frames at 120 fps plus one 100 ms stall is
	# 108.108 fps of real throughput, but averaging instantaneous rates reads
	# 118.9 and flatters the stall away.
	var frame_times := _steady_series(99, 1.0 / 120.0)
	frame_times.append(0.1)

	assert_almost_eq(
		PerfReadoutType.average_fps(frame_times),
		100.0 / (99.0 / 120.0 + 0.1),
		FPS_TOLERANCE,
		"average fps must be frames divided by elapsed time"
	)
	assert_lt(
		PerfReadoutType.average_fps(frame_times),
		110.0,
		"averaging instantaneous rates would read about 118.9"
	)


func test_one_percent_low_reports_the_slowest_frames_not_the_average() -> void:
	# 99 frames at 120 fps plus one 100 ms stall. The average is ~108 fps and
	# the 1% low is 10 fps: any implementation that returns the mean, or that
	# smooths the stall away, cannot pass both assertions.
	var frame_times := _steady_series(99, 1.0 / 120.0)
	frame_times.append(0.1)

	var average := PerfReadoutType.average_fps(frame_times)
	var one_percent_low := PerfReadoutType.one_percent_low_fps(frame_times)

	assert_almost_eq(
		one_percent_low,
		10.0,
		FPS_TOLERANCE,
		"the single slowest frame of 100 is the whole 1% low"
	)
	assert_gt(
		average - one_percent_low,
		90.0,
		"the 1% low must not track the average"
	)


func test_one_percent_low_averages_every_frame_in_the_slowest_one_percent() -> void:
	# 300 frames, so the slowest 1% is three frames: 100 ms, 50 ms and 40 ms.
	# Their mean is 63.3 ms -> 15.79 fps. Reporting only the worst frame would
	# read 10.0 fps, so this separates "average the slowest 1%" from
	# "report the single worst frame".
	var frame_times := _steady_series(297, 1.0 / 120.0)
	frame_times.append(0.1)
	frame_times.append(0.05)
	frame_times.append(0.04)

	var one_percent_low := PerfReadoutType.one_percent_low_fps(frame_times)

	assert_almost_eq(
		one_percent_low,
		3.0 / 0.19,
		FPS_TOLERANCE,
		"three slow frames of 300 must be averaged together"
	)
	assert_gt(
		one_percent_low,
		11.0,
		"reporting only the single worst frame would read 10.0 fps"
	)


func test_an_empty_window_reports_zero_instead_of_dividing_by_zero() -> void:
	var empty: Array[float] = []

	assert_eq(
		PerfReadoutType.average_fps(empty),
		0.0,
		"no samples means no measurement, not NAN"
	)
	assert_eq(
		PerfReadoutType.one_percent_low_fps(empty),
		0.0,
		"no samples means no measurement, not a crash"
	)


func test_the_sample_window_discards_the_oldest_frames() -> void:
	# A 20-minute soak is ~72,000 frames. If the window is unbounded, one
	# early stall pins the 1% low for the rest of the session and the memory
	# grows all soak: the readout has to forget.
	var readout: PerfReadoutType = autofree(PerfReadoutType.new())
	readout.push_frame_time(0.5)
	for _index in range(PerfReadoutType.SAMPLE_WINDOW_FRAMES):
		readout.push_frame_time(1.0 / 60.0)

	assert_eq(
		readout.sample_count(),
		PerfReadoutType.SAMPLE_WINDOW_FRAMES,
		"the window must stay bounded"
	)
	assert_almost_eq(
		readout.sampled_one_percent_low_fps(),
		60.0,
		FPS_TOLERANCE,
		"the 500 ms stall must have rolled out of the window"
	)


func _fake_rendering_info(info_id: int) -> int:
	# Deliberately distinct per metric so a swapped engine id cannot pass.
	match info_id:
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME:
			return 120
		RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME:
			return 150000
		RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME:
			return 37
	return -1


func test_each_rendering_metric_reads_its_own_engine_id() -> void:
	var readout: PerfReadoutType = autofree(PerfReadoutType.new())
	readout.rendering_info_source = _fake_rendering_info

	assert_eq(readout.draw_calls(), 120, "draw calls")
	assert_eq(readout.primitives(), 150000, "primitives")
	assert_eq(readout.objects_in_frame(), 37, "objects in frame")


func test_the_default_rendering_source_is_the_live_engine() -> void:
	var readout: PerfReadoutType = autofree(PerfReadoutType.new())

	assert_false(
		readout.rendering_info_source.is_valid(),
		"production must ship with no injected source"
	)
	assert_eq(
		readout.draw_calls(),
		RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
		),
		"the readout must report what the engine reports"
	)


func test_render_scale_follows_the_viewport_3d_scale() -> void:
	var readout: PerfReadoutType = add_child_autofree(PerfReadoutType.new())
	var viewport := readout.get_viewport()
	assert_not_null(viewport)
	if viewport == null:
		return
	var original_scale := viewport.scaling_3d_scale

	# E1-04(2): two distinct values. Asserting only 0.7 is satisfied by a
	# getter hardcoded to 0.7, which is exactly the value §9.4 cares about.
	viewport.scaling_3d_scale = 0.7
	assert_almost_eq(
		readout.render_scale(),
		0.7,
		FPS_TOLERANCE,
		"§9.4 watches this drop toward 0.7 under load"
	)

	viewport.scaling_3d_scale = 0.85
	assert_almost_eq(
		readout.render_scale(),
		0.85,
		FPS_TOLERANCE,
		"the readout must track the viewport, not report a constant"
	)

	viewport.scaling_3d_scale = original_scale


func test_the_label_displays_every_measured_number() -> void:
	var readout: PerfReadoutType = add_child_autofree(PerfReadoutType.new())
	readout.rendering_info_source = _fake_rendering_info
	for _index in range(120):
		readout.push_frame_time(1.0 / 60.0)

	readout.refresh()

	# E1-04(3): every label and every value. Asserting only three substrings
	# let a readout_text() that silently dropped 1% LOW, OBJ and SCALE pass.
	for expected: String in [
		"FPS",
		"1% LOW",
		"DRAW",
		"PRIM",
		"OBJ",
		"SCALE",
		"60.0",
		"120",
		"150000",
		"37",
	]:
		assert_string_contains(readout.text, expected)


func test_the_display_recompute_is_throttled_but_sampling_is_not() -> void:
	# E1-05: duplicating and sorting 600 samples and rebuilding the whole
	# string every frame adds observer cost to the thermal run it exists to
	# measure. Sampling must stay per-frame -- that IS the measurement -- while
	# the display recompute runs on an interval.
	var readout: PerfReadoutType = autofree(PerfReadoutType.new())
	readout.rendering_info_source = _fake_rendering_info

	readout.tick(1.0 / 60.0)
	var first_text := readout.text
	assert_false(first_text.is_empty(), "the first tick must show something")

	for _index in range(5):
		readout.tick(1.0 / 600.0)

	assert_eq(
		readout.text,
		first_text,
		"the display must not be rebuilt every frame"
	)
	assert_eq(
		readout.sample_count(),
		6,
		"but every frame must still be sampled"
	)

	readout.tick(PerfReadoutType.REFRESH_INTERVAL_S)

	assert_ne(
		readout.text,
		first_text,
		"and the display must catch up once the interval elapses"
	)


func test_the_readout_samples_frames_without_being_driven_by_hand() -> void:
	# The project's predecessor shipped a config system that was never
	# actually called. A readout nobody feeds shows a frozen zero forever,
	# so prove the node samples itself once it is in the tree.
	var readout: PerfReadoutType = add_child_autofree(PerfReadoutType.new())

	# wait_process_frames, not wait_frames: the latter counts physics frames,
	# and this readout deliberately samples in _process.
	await wait_process_frames(3)

	assert_gt(readout.sample_count(), 0, "the node must sample its own frames")
	assert_false(readout.text.is_empty(), "and display what it sampled")


func test_a_hidden_readout_is_not_scheduled_to_process() -> void:
	# E1-02: hiding a CanvasItem does not stop _process being dispatched. The
	# early return made the callback cheap, not absent, so a release build
	# still paid per-frame dispatch for a node it never shows.
	var readout: PerfReadoutType = add_child_autofree(PerfReadoutType.new())

	readout.visible = false
	await wait_process_frames(1)

	assert_false(
		readout.is_processing(),
		"a hidden readout must not be scheduled for _process at all"
	)

	readout.visible = true
	await wait_process_frames(1)

	assert_true(
		readout.is_processing(),
		"and it must resume sampling the moment it is shown"
	)


func test_a_hidden_readout_costs_a_release_build_nothing() -> void:
	# GameRoot hides this node when debug tools are off, which is every
	# release build. Hidden must mean it stops working, not just stops showing.
	var readout: PerfReadoutType = add_child_autofree(PerfReadoutType.new())
	readout.visible = false

	await wait_process_frames(3)

	assert_eq(readout.sample_count(), 0, "a hidden readout must not sample")
	assert_true(readout.text.is_empty(), "and must not build display strings")
