class_name StartBoostJudge
extends RefCounted

## Pure CTR-style "hold HOP for a launch boost" judge (CTR R5 Task 1). No
## Node/scene dependency -- race_session.gd is the one real caller, feeding
## it the player's own real HOP-held state once per pre-GO physics tick (see
## its own _tick_countdown()) and reading verdict() exactly once, on the
## tick CountdownTimer.tick() reports &"go".
##
## HOLD-SAMPLING MODEL. This judge does not know where "now" sits relative
## to GO -- it only ever sees pre-GO ticks (the caller stops sampling once
## the countdown reaches &"go", the same one-shot-edge contract countdown_
## timer.gd's own class doc documents), so it tracks exactly one thing: how
## long, in real ticked seconds, the CURRENT continuous HOP hold has lasted.
## sample(delta_s, hop_held) accumulates that duration while hop_held is
## true and resets it to 0.0 on every false sample (a release always starts
## a fresh hold the next time HOP goes down, mirroring this codebase's other
## "reset on release" edge trackers, e.g. drift_state_machine.gd's own hop-
## held latch). Because the caller only ever samples PRE-GO ticks and
## verdict() is only ever read on the very last of them (the GO tick
## itself), held_duration_s AT THAT INSTANT already equals exactly "how long
## before GO did the currently-held press begin" -- there is no separate
## "time remaining until GO" this class needs to be told; the caller's own
## sampling window boundary (pre-GO, ending exactly at GO) supplies it for
## free.
##
## VERDICT, read once at GO:
## - &"none": HOP is not held at GO (never pressed, or pressed and released
##   before GO). No start-boost mechanic applies either way.
## - &"boost": HOP IS held at GO, and the current hold began within the
##   last RaceTuning.start_boost_window_s of the countdown -- i.e.
##   held_duration_s <= start_boost_window_s. INCLUSIVE of the window's own
##   opening instant (a hold that began EXACTLY start_boost_window_s before
##   GO reads as inside the window, not outside it) -- the same "the instant
##   AT a boundary already belongs to the phase/window it enters" convention
##   countdown_timer.gd's own phase boundaries use one file over, so both of
##   this task's pure classes agree on which side of an edge wins.
## - &"bog": HOP IS held at GO, but the current hold began EARLIER than the
##   window (held_duration_s > start_boost_window_s) -- mashing/holding HOP
##   too early and riding it all the way to GO is punished, not rewarded.
##
## This is the real CTR mechanic: tap-and-hold HOP right at the very end of
## the countdown for a launch boost; jam it down early and keep holding and
## the start bogs down instead; leave it alone and nothing special happens
## either way.

var _race_tuning: RaceTuning
var _is_held: bool
var _held_duration_s: float


func configure(race_tuning: RaceTuning) -> void:
	_race_tuning = race_tuning
	_is_held = false
	_held_duration_s = 0.0


## Called once per pre-GO physics tick (see the class doc's HOLD-SAMPLING
## MODEL section) with the player's real HOP-held state that tick.
func sample(delta_s: float, hop_held: bool) -> void:
	if hop_held:
		_held_duration_s += delta_s
	else:
		_held_duration_s = 0.0
	_is_held = hop_held


## Read once at GO -- see the class doc's VERDICT section for the three
## possible answers and exactly where the window edges fall.
func verdict() -> StringName:
	if not _is_held:
		return &"none"
	if _held_duration_s <= _race_tuning.start_boost_window_s:
		return &"boost"
	return &"bog"
