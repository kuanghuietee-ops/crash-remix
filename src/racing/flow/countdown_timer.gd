class_name CountdownTimer
extends RefCounted

## Pure 3-2-1-GO countdown clock (CTR R5 Task 1). No Node/scene dependency --
## race_session.gd owns the real per-tick drive (calling tick(delta_s) from
## its own _physics_process while process_mode = PROCESS_MODE_PAUSABLE
## already makes that pause-correct for free, the same "just don't get
## ticked while paused" contract elapsed_s()/LevelRunState's own relic timer
## already rely on -- see race_session.gd's class doc TIMER section), the
## same configure()-then-poll shape lap_validator.gd/drift_state_machine.gd
## already establish for this codebase's other pure racing-flow classes.
##
## PHASES. Five, walked in order: &"three" -> &"two" -> &"one" -> &"go" ->
## &"running". The first three each last exactly RaceTuning.countdown_step_s
## of real ticked time; _PRE_GO_PHASES.size() (not a bare literal -- see this
## file's own no-bare-numeric-literal rule, src/racing/** carries the same
## "no gameplay numbers in code" contract as src/gameplay/**) is the number
## of timed phases before GO, so step_index = int(elapsed_s / step_s) directly
## indexes into it: 0 -> "three", 1 -> "two", 2 -> "one", and anything at or
## past that array's own size -> "go". Boundaries are INCLUSIVE of the phase
## they enter (elapsed_s == countdown_step_s reads "two", not "three") --
## the same "the instant AT the boundary already belongs to the new state"
## convention start_boost_judge.gd's own window-edge ruling uses one file
## over, so the two pure classes this task adds agree with each other.
##
## GO IS A ONE-SHOT EDGE. tick() returns &"go" for exactly the one call
## during which elapsed_s first reaches the last phase's own threshold, then
## flips internally to &"running" and reports that on every call after --
## mirroring this codebase's other "was X last tick" edge-detection idioms
## (race_session.gd's own _hop_was_pressed, ai_kart_agent.gd's own
## _was_run_active). A caller that only wants to react ONCE to the countdown
## finishing (race_session.gd's own _tick_countdown(), which unfreezes every
## kart and applies the start-boost verdict on exactly that edge) can simply
## compare tick()'s return value against &"go" every call, with no separate
## "have I already fired this" bookkeeping of its own to maintain.
##
## PRODUCTION NOTE: race_session.gd stops calling tick() at all once it has
## seen &"go" once (the race has started; nothing pre-GO is left to drive),
## so in real play phase() never actually reaches &"running" -- that
## transition exists for this class's own complete, independently-testable
## contract (a caller COULD keep ticking past GO and get a well-defined
## answer), not because production exercises it. RaceSession tracks "has the
## race started" with its own separate flag for exactly this reason, rather
## than leaning on phase() ever reporting &"running" for real.

const _PRE_GO_PHASES: Array[StringName] = [&"three", &"two", &"one"]

var _race_tuning: RaceTuning
var _elapsed_s: float
var _phase: StringName = &"three"


func configure(race_tuning: RaceTuning) -> void:
	_race_tuning = race_tuning
	_elapsed_s = 0.0
	_phase = _PRE_GO_PHASES[0]


## Advances the clock by delta_s and returns the phase AFTER this tick --
## see the class doc's GO IS A ONE-SHOT EDGE section for why a call made
## once phase() is already &"running" is a harmless no-op that keeps
## reporting &"running" forever, never re-deriving it from elapsed_s again.
func tick(delta_s: float) -> StringName:
	if _phase == &"running":
		return _phase
	if _phase == &"go":
		_phase = &"running"
		return _phase
	_elapsed_s += delta_s
	var step_index := int(_elapsed_s / _race_tuning.countdown_step_s)
	if step_index >= _PRE_GO_PHASES.size():
		_phase = &"go"
	else:
		_phase = _PRE_GO_PHASES[step_index]
	return _phase


func phase() -> StringName:
	return _phase


## Real ticked time since configure() -- an accessor for tests/callers that
## want to reason about the countdown's own progress directly rather than
## only its discrete phase (e.g. a future circular-timer HUD affordance).
func elapsed_s() -> float:
	return _elapsed_s


## The full pre-GO duration (_PRE_GO_PHASES.size() timed steps of
## countdown_step_s each) -- exposed so a caller (notably this suite's own
## tests) never has to re-derive "how long is the whole countdown" by
## reaching past this class into its own private phase-count constant.
func total_duration_s() -> float:
	return _race_tuning.countdown_step_s * _PRE_GO_PHASES.size()
