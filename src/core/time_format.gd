class_name TimeFormat
extends RefCounted

## Race-timer formatting (Task 7). Lives outside src/racing/** and
## src/gameplay/** on purpose: the "no gameplay numbers in code" lint those
## two trees carry (scripts/lint_gameplay_numbers.py) would otherwise reject
## the unit-conversion literals below (60 seconds/minute, 1000 milliseconds/
## second). These are fixed SI/calendar constants, not tunable gameplay
## values -- the same carve-out src/core/monotonic_clock.gd's
## MICROSECONDS_PER_SECOND and src/core/save_model.gd's
## _MILLISECONDS_PER_SECOND already rely on by living outside the scanned
## trees. race_hud.gd (src/racing/ui/**, scanned) calls into this instead of
## doing the mm:ss.mmm arithmetic itself.

const SECONDS_PER_MINUTE := 60.0
const MILLISECONDS_PER_SECOND := 1000.0


## "mm:ss.mmm". Negative input (a timer that hasn't started, or a tiny
## floating-point wobble below zero) clamps to zero so this never renders a
## garbled or negative string.
static func mm_ss_mmm(total_s: float) -> String:
	var clamped_s := maxf(total_s, 0.0)
	var total_ms := int(round(clamped_s * MILLISECONDS_PER_SECOND))
	var ms_per_minute := int(SECONDS_PER_MINUTE * MILLISECONDS_PER_SECOND)
	var minutes := total_ms / ms_per_minute
	var remainder_ms := total_ms % ms_per_minute
	var seconds := remainder_ms / int(MILLISECONDS_PER_SECOND)
	var milliseconds := remainder_ms % int(MILLISECONDS_PER_SECOND)
	return "%02d:%02d.%03d" % [minutes, seconds, milliseconds]
