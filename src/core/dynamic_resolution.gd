class_name DynamicResolution
extends RefCounted

## Drives Viewport.scaling_3d_scale between full resolution and the §9.4 floor.
##
## Design doc §9.4 asks for "dynamic resolution 1.0->0.7 before any frame drop".
## Before, not after: the trigger is a frame approaching the 60 fps budget, not
## one that already missed it, so the scale is already falling by the time load
## would have cost a frame.
##
## The numbers below are renderer policy, not gameplay tuning: nothing here
## changes what the game does, only how many pixels it does it at. They are
## deliberately NOT a tuning section -- adding one would put render policy on
## the on-device gameplay drawer and in the gameplay fingerprint, which is an
## operator decision, not a side effect of this fix.

const TARGET_FRAME_TIME_S := 1.0 / 60.0
## Frames slower than 90% of the budget are treated as load. The margin is the
## whole point: waiting for a real overrun means reacting one dropped frame late.
const DOWNSCALE_TRIGGER_RATIO := 0.9
## Only give resolution back when there is real headroom, so the scale does not
## sit on the boundary flipping up and down.
const UPSCALE_TRIGGER_RATIO := 0.7
const DOWNSCALE_FRAME_TIME_S := TARGET_FRAME_TIME_S * DOWNSCALE_TRIGGER_RATIO
const UPSCALE_FRAME_TIME_S := TARGET_FRAME_TIME_S * UPSCALE_TRIGGER_RATIO
## §9.4's floor. Below this the image costs more than the frame it buys.
const MINIMUM_SCALE := 0.7
const MAXIMUM_SCALE := 1.0
const SCALE_STEP := 0.05
## Average over an interval before moving, so the scale tracks load rather than
## chasing single-frame noise.
const ADJUST_INTERVAL_S := 0.5

var _elapsed_s := 0.0
var _frame_count := 0


## Pure: the whole policy, with no clock and no viewport.
static func next_scale(current_scale: float, frame_time_s: float) -> float:
	if frame_time_s > DOWNSCALE_FRAME_TIME_S:
		return maxf(current_scale - SCALE_STEP, MINIMUM_SCALE)
	if frame_time_s < UPSCALE_FRAME_TIME_S:
		return minf(current_scale + SCALE_STEP, MAXIMUM_SCALE)
	return current_scale


## Accumulates frames and returns the scale to use. Returns current_scale
## unchanged until a full interval has been averaged.
func tick(delta_s: float, current_scale: float) -> float:
	_elapsed_s += delta_s
	_frame_count += 1
	if _elapsed_s < ADJUST_INTERVAL_S:
		return current_scale
	var average_frame_time_s := _elapsed_s / float(_frame_count)
	_elapsed_s = 0.0
	_frame_count = 0
	return next_scale(current_scale, average_frame_time_s)
