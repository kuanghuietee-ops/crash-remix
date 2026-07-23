class_name MonotonicClock
extends RefCounted

const MICROSECONDS_PER_SECOND := 1_000_000.0


static func now_s() -> float:
	return float(Time.get_ticks_usec()) / MICROSECONDS_PER_SECOND
