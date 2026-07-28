class_name PerfReadout
extends Label

## Frame budgets come from data/tuning/art_budget.tres (design doc 9.4), not from
## literals here -- the same rule the gameplay code follows. Loaded once: this
## runs inside the per-frame readout and must not touch the disk on a refresh.
const ART_BUDGET_PATH := "res://data/tuning/art_budget.tres"
const BYTES_PER_MEGABYTE := 1024 * 1024
const STATUS_OK := "OK"
const STATUS_OVER_TYPICAL := "OVER-TYPICAL"
const STATUS_OVER_PEAK := "OVER-PEAK"

# The share of frames the "1% low" figure is measured over. This is the
# definition of the metric in design doc §9.4 ("1% low >= 50"), not a
# gameplay value: the readout reports the average frame rate across the
# slowest 1% of the sample window, which is the standard benchmarking
# meaning and the one a 20-minute soak needs -- a single stall must not
# be smoothed away by 3,600 good frames.
const ONE_PERCENT := 0.01
# Ten seconds at 60 fps. Bounded on purpose: a 20-minute soak is roughly
# 72,000 frames, so an unbounded window would grow all session and pin the
# 1% low to the first stall of the run forever.
const SAMPLE_WINDOW_FRAMES := 600

## Test seam, in the same spirit as game_root's `_threaded_load_status_override`:
## production leaves this unset and reads the live `RenderingServer`. A test can
## substitute a source that answers each metric id differently, so wiring a
## metric to the wrong engine id fails instead of shipping green -- headless
## rendering counters are all zero and would agree with any mistake.
var rendering_info_source: Callable = Callable()

# The display recompute sorts the whole window and rebuilds the string, which
# is measurable observer cost on the very thermal run this readout exists to
# measure (E1-05). Sampling stays per-frame -- that is the measurement -- while
# the numbers on screen refresh four times a second, which is as fast as anyone
# can read them anyway.
const REFRESH_INTERVAL_S := 0.25

var _art_budget: ArtBudgetTuning = load(ART_BUDGET_PATH)
var _frame_times_s: Array[float] = []
var _since_refresh_s := REFRESH_INTERVAL_S


static func average_fps(frame_times_s: Array[float]) -> float:
	if frame_times_s.is_empty():
		return 0.0
	var total_s := 0.0
	for frame_time_s: float in frame_times_s:
		total_s += frame_time_s
	if total_s <= 0.0:
		return 0.0
	return float(frame_times_s.size()) / total_s


static func one_percent_low_fps(frame_times_s: Array[float]) -> float:
	if frame_times_s.is_empty():
		return 0.0
	var slowest_first := frame_times_s.duplicate()
	slowest_first.sort()
	slowest_first.reverse()
	var sample_count := int(ceil(float(slowest_first.size()) * ONE_PERCENT))
	if sample_count < 1:
		sample_count = 1
	var total_s := 0.0
	for index in range(sample_count):
		total_s += slowest_first[index]
	if total_s <= 0.0:
		return 0.0
	return float(sample_count) / total_s


func push_frame_time(frame_time_s: float) -> void:
	_frame_times_s.append(frame_time_s)
	while _frame_times_s.size() > SAMPLE_WINDOW_FRAMES:
		_frame_times_s.pop_front()


func sample_count() -> int:
	return _frame_times_s.size()


func sampled_average_fps() -> float:
	return average_fps(_frame_times_s)


func sampled_one_percent_low_fps() -> float:
	return one_percent_low_fps(_frame_times_s)


func _rendering_info(info_id: int) -> int:
	if rendering_info_source.is_valid():
		return int(rendering_info_source.call(info_id))
	return int(RenderingServer.get_rendering_info(info_id))


func draw_calls() -> int:
	return _rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
	)


func primitives() -> int:
	return _rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME
	)


func objects_in_frame() -> int:
	return _rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME
	)


func texture_memory_mb() -> float:
	return float(
		_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)
	) / float(BYTES_PER_MEGABYTE)


## The worst of the two whole-frame metrics wins: draw calls over peak must not
## be hidden by a triangle count that happens to be fine.
func budget_status() -> String:
	if _art_budget == null:
		return STATUS_OK
	var calls := draw_calls()
	var triangles := primitives()
	if (
		calls > _art_budget.frame_draw_calls_peak
		or triangles > _art_budget.frame_triangles_peak
	):
		return STATUS_OVER_PEAK
	if (
		calls > _art_budget.frame_draw_calls_typical
		or triangles > _art_budget.frame_triangles_typical
	):
		return STATUS_OVER_TYPICAL
	return STATUS_OK


## The 3D render scale §9.4 watches fall toward 0.7 under load. The readout
## only observes it; nothing in this project drives it yet.
func render_scale() -> float:
	var viewport := get_viewport()
	if viewport == null:
		return 0.0
	return viewport.scaling_3d_scale


func readout_text() -> String:
	return (
		(
			"FPS %.1f  1%% LOW %.1f  DRAW %d  PRIM %d  OBJ %d  "
			+ "SCALE %.2f  TEX %.1fMB  %s"
		)
		% [
			sampled_average_fps(),
			sampled_one_percent_low_fps(),
			draw_calls(),
			primitives(),
			objects_in_frame(),
			render_scale(),
			texture_memory_mb(),
			budget_status(),
		]
	)


func refresh() -> void:
	text = readout_text()


func _ready() -> void:
	visibility_changed.connect(_sync_processing)
	_sync_processing()


## A hidden readout is a release build's readout. Hiding a CanvasItem does not
## stop _process being dispatched, so unschedule it outright rather than paying
## a per-frame callback to return early (E1-02).
func _sync_processing() -> void:
	set_process(visible)


## Sample every frame, rebuild the display on REFRESH_INTERVAL_S. Public so the
## throttle is provable without depending on engine frame pacing.
func tick(delta_s: float) -> void:
	push_frame_time(delta_s)
	_since_refresh_s += delta_s
	if _since_refresh_s < REFRESH_INTERVAL_S:
		return
	_since_refresh_s = 0.0
	refresh()


func _process(delta: float) -> void:
	tick(delta)
