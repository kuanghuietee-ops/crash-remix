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
	viewport.scaling_3d_scale = 0.7

	assert_almost_eq(
		readout.render_scale(),
		0.7,
		FPS_TOLERANCE,
		"§9.4 watches this drop toward 0.7 under load"
	)

	viewport.scaling_3d_scale = original_scale


func test_the_label_displays_every_measured_number() -> void:
	var readout: PerfReadoutType = add_child_autofree(PerfReadoutType.new())
	readout.rendering_info_source = _fake_rendering_info
	for _index in range(120):
		readout.push_frame_time(1.0 / 60.0)

	readout.refresh()

	for expected: String in ["60.0", "120", "150000"]:
		assert_string_contains(readout.text, expected)


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


func test_a_hidden_readout_costs_a_release_build_nothing() -> void:
	# GameRoot hides this node when debug tools are off, which is every
	# release build. Hidden must mean it stops working, not just stops showing.
	var readout: PerfReadoutType = add_child_autofree(PerfReadoutType.new())
	readout.visible = false

	await wait_process_frames(3)

	assert_eq(readout.sample_count(), 0, "a hidden readout must not sample")
	assert_true(readout.text.is_empty(), "and must not build display strings")
