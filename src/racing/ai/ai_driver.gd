class_name AiDriver
extends RefCounted

## Pure-logic "virtual thumb" for an AI kart (Task 3, CTR R3: AI opponents).
## RefCounted, no Node/scene dependency -- same configure()-then-poll shape
## as drift_state_machine.gd/kart_motor.gd/spine_follower.gd. Task 4's
## AiKartAgent (a Node) owns the real KartController/TrackSpine/
## DriftStateMachine, assembles a per-tick state Dictionary from them, calls
## decide(state) once per physics tick, and routes the returned outputs onto
## the SAME KartController API a human racer drives through (steer(),
## hop_pressed()/hop_released(), boost_tap(), set_brake(), a speed-scale
## setter) -- this class never touches a node, a physics body, or the real
## DriftStateMachine directly.
##
## STATEFUL ACROSS TICKS. decide() is not a pure function of its state
## argument alone: hop and boost_tap are EDGE outputs (true only on the
## single tick the caller should press that button), so this driver has to
## remember, between calls, whether it already fired the edge for the
## slide/window it is currently in the middle of -- otherwise a caller that
## naively translated hop=true into hop_pressed() every tick a corner stays
## sharp would mash the button every physics frame instead of tapping it
## once. See _intending_slide/_was_intending_slide and
## _prev_boost_window_open below. Call reset() to clear this edge memory --
## e.g. Task 4's stuck-kart respawn path (a kart teleported back onto the
## line has no business remembering a slide-intent or boost-window edge
## from wherever it got stuck) or a fresh race retry that reuses driver
## instances. A freshly-constructed AiDriver already starts with this
## memory zeroed, so reset() is only needed to re-arm an existing instance.
##
## INPUT STATE (Dictionary -- read via .get() with safe defaults, since a
## caller may not populate every key every tick; see the plan's Task 3
## interfaces list and
## .superpowers/sdd/2026-07-30-ctr-r3-ai-karts/task-3-brief.md):
##   position: Vector3, forward: Vector3 (unit, kart's current facing),
##   speed_mps: float, is_sliding: bool, boost_window_open: bool,
##   lookahead_point: Vector3, curvature_ahead: float (1/m, an UNSIGNED
##   magnitude -- how tight the corner at the lookahead point is, not which
##   way it turns; turn direction comes entirely from lookahead_point's
##   bearing and lateral_error_m below), lateral_target_m: float (Task 4's
##   own bookkeeping -- not read here, lateral_error_m already carries what
##   this driver needs), lateral_error_m: float (signed, target - actual,
##   along the SAME world-space "positive = kart's right" axis steer uses --
##   see the STEERING section: this is the sign convention Task 4 must
##   produce it with), band_gap_m: float (player_total_progress minus this
##   kart's total_progress; positive = this kart is behind the player).
##
## OUTPUT (Dictionary): steer: float (-1..1), brake: bool, hop: bool (edge),
## boost_tap: bool (edge), speed_scale: float.
##
## STEERING. angle = signed angle (radians, about world +Y) from `forward`
## to (lookahead_point - position), both flattened to the XZ plane --
## positive when the target is to the LEFT of forward (Godot's rotation
## about +Y is CCW-positive and FORWARD.rotated(UP, +angle) sweeps a
## forward-facing vector toward -X, the kart's own left; see
## kart_motor.gd's class doc and its world-space yaw-sign fix note). steer's
## own convention there is the OPPOSITE sign (positive steer = stick right =
## turn right = a NEGATIVE yaw delta, per kart_motor.gd's tick()), so the
## pursuit term negates the angle:
##   pursuit_term = -angle * steer_gain
##
## The lateral correction reuses steer_gain (no new tuning literal, per the
## brief) instead of introducing a second gain field: lateral_error_m,
## divided by the same planar lookahead distance the pursuit angle was just
## computed from, is a small-angle-radians estimate of the extra bearing
## correction the slot offset needs -- the same units the pursuit term's
## angle is already in -- so multiplying by steer_gain applies exactly the
## same angle-to-steer conversion to both terms:
##   lateral_term = steer_gain * (lateral_error_m / lookahead_distance_m)
## raw_steer = pursuit_term + lateral_term, before the slide-floor
## enforcement and final clamp below.
##
## CORNERING / BRAKE. target_speed = kart.top_speed_mps * clamp(1 -
## ai.corner_speed_curvature_gain * curvature_ahead,
## ai.corner_speed_floor_ratio, 1.0); brake = speed_mps > target_speed *
## ai.brake_margin_ratio.
##
## SLIDE (hop) COUPLING. curvature_ahead crossing slide_trigger_curvature
## (from below) while not already sliding arms "intent to slide"; intent
## clears once curvature_ahead drops to/below slide_exit_curvature -- a
## hysteresis band between the two thresholds, the same shape
## DriftStateMachine itself uses for its own start/sustain/end split.
## hop=true fires exactly once, on the tick intent first arms (and only
## while the caller's state still reports it is not already sliding) --
## _was_intending_slide is the edge memory that keeps every later tick of
## the same corner from re-firing it.
##
## DriftStateMachine only STARTS a slide on a tick where hop is held AND
## |steer| >= kart.slide_min_steer (see its class doc), and only SUSTAINS
## an already-active slide while |steer| stays >= that same threshold -- a
## hop fired on a tick where this driver's own steer output is small (e.g.
## pursuit + lateral nearly cancel right as a corner opens up) would
## silently fail to start anything, or silently end an active slide, and
## this driver would have no way to tell from its own state that it
## happened. So for as long as intent stays armed -- from the hop tick
## through every following tick until curvature_ahead drops to/below
## slide_exit_curvature, i.e. "while it intends to hold the slide" --
## _apply_slide_steer_floor bumps |steer| up to kart.slide_min_steer
## whenever the natural pursuit+lateral value falls short, preserving its
## sign (falling back to the last nonzero commanded steer sign if the
## natural value was exactly zero -- see _last_steer_sign). This runs
## BEFORE the final -1..1 clamp. Once intent clears, the floor releases and
## steer follows the natural line again -- which is what lets the real
## FSM's own sustain check end the slide naturally when the corner
## straightens out, rather than this driver trying to detect "the slide
## should end" itself.
##
## BOOST TAP. Fires on the RISING EDGE of state.boost_window_open (false on
## the previous decide() call, true on this one) while state.is_sliding is
## true and ai.boost_tap_enabled is truthy (>= 1.0 -- the tuning field is a
## 0/1 float flag, not a real bool, per the brief). Edge-gated rather than
## "true for as long as the window stays open" for the same reason hop is:
## a caller translating boost_tap=true into a real boost_tap() call every
## tick the window stays open would tap far more often than CTR's
## one-tap-per-window model intends (and if a window's open_s is ever
## authored as 0.0, the real FSM would otherwise re-open the very next
## stage's window before this driver's next tick and get tapped again
## immediately). _prev_boost_window_open is the edge memory.
##
## RUBBER BAND. speed_scale = 1.0 + ai.rubber_band_boost_max_ratio *
## clamp(band_gap_m / ai.rubber_band_full_gap_m, 0.0, 1.0) when
## band_gap_m > 0.0 (behind the player); 1.0 -
## ai.rubber_band_drag_max_ratio * clamp(-band_gap_m /
## ai.rubber_band_full_gap_m, 0.0, 1.0) when band_gap_m < 0.0 (ahead);
## exactly 1.0 at band_gap_m == 0.0 by construction (neither branch runs,
## no separate third case needed).
##
## FAIL-CLOSED. decide() called before a successful configure() (either
## tuning resource still unset) push_errors and returns a neutral, harmless
## output (steer 0.0, brake false, hop false, boost_tap false, speed_scale
## 1.0) instead of crashing on a null tuning dereference -- the same
## fail-closed shape as spine_follower.gd's invalid-configure() path.

var _ai_tuning: AiTuning
var _kart_tuning: KartTuning

var _intending_slide: bool
var _was_intending_slide: bool
var _prev_boost_window_open: bool
var _last_steer_sign: float = 1.0


func configure(ai_tuning: AiTuning, kart_tuning: KartTuning) -> void:
	_ai_tuning = ai_tuning
	_kart_tuning = kart_tuning


## Clears all per-tick edge memory (slide intent + boost-window edge +
## remembered steer sign) without touching the configured tuning
## references. See the class doc's STATEFUL ACROSS TICKS section for when a
## caller needs this.
func reset() -> void:
	_intending_slide = false
	_was_intending_slide = false
	_prev_boost_window_open = false
	_last_steer_sign = 1.0


func decide(state: Dictionary) -> Dictionary:
	if _ai_tuning == null or _kart_tuning == null:
		push_error(
			"AiDriver.decide: called before a successful configure() call "
			+ "-- failing closed to a neutral, harmless output."
		)
		return _neutral_output()

	var position: Vector3 = state.get("position", Vector3.ZERO)
	var forward: Vector3 = state.get("forward", Vector3.FORWARD)
	var speed_mps: float = state.get("speed_mps", 0.0)
	var is_sliding: bool = state.get("is_sliding", false)
	var boost_window_open: bool = state.get("boost_window_open", false)
	var lookahead_point: Vector3 = state.get("lookahead_point", position)
	var curvature_ahead: float = state.get("curvature_ahead", 0.0)
	var lateral_error_m: float = state.get("lateral_error_m", 0.0)
	var band_gap_m: float = state.get("band_gap_m", 0.0)

	var steer := _steer_for(
		position, forward, lookahead_point, lateral_error_m, curvature_ahead
	)

	var hop := _intending_slide and not _was_intending_slide and not is_sliding
	_was_intending_slide = _intending_slide

	if not is_zero_approx(steer):
		_last_steer_sign = signf(steer)

	var target_speed: float = _kart_tuning.top_speed_mps * clampf(
		1.0 - _ai_tuning.corner_speed_curvature_gain * curvature_ahead,
		_ai_tuning.corner_speed_floor_ratio,
		1.0
	)
	var brake := speed_mps > target_speed * _ai_tuning.brake_margin_ratio

	var boost_tap := (
		is_sliding
		and boost_window_open
		and not _prev_boost_window_open
		and _ai_tuning.boost_tap_enabled >= 1.0
	)
	_prev_boost_window_open = boost_window_open

	return {
		"steer": steer,
		"brake": brake,
		"hop": hop,
		"boost_tap": boost_tap,
		"speed_scale": _rubber_band_speed_scale(band_gap_m),
	}


## Computes the clamped steer output and, as a side effect, updates
## _intending_slide from curvature_ahead's hysteresis band (see the class
## doc's SLIDE (hop) COUPLING section) -- steering and slide-intent share
## the same curvature reading each tick, so they are resolved together
## here rather than the caller having to thread curvature_ahead through
## twice.
func _steer_for(
	position: Vector3,
	forward: Vector3,
	lookahead_point: Vector3,
	lateral_error_m: float,
	curvature_ahead: float
) -> float:
	var flat_forward := Vector3(forward.x, 0.0, forward.z)
	var flat_to_target := Vector3(
		lookahead_point.x - position.x, 0.0, lookahead_point.z - position.z
	)
	var lookahead_distance_m := flat_to_target.length()

	var raw_steer := 0.0
	if lookahead_distance_m > 0.0:
		var angle := flat_forward.signed_angle_to(flat_to_target, Vector3.UP)
		var pursuit_term := -angle * _ai_tuning.steer_gain
		var lateral_term := _ai_tuning.steer_gain * (
			lateral_error_m / lookahead_distance_m
		)
		raw_steer = pursuit_term + lateral_term

	if curvature_ahead >= _ai_tuning.slide_trigger_curvature:
		_intending_slide = true
	elif curvature_ahead <= _ai_tuning.slide_exit_curvature:
		_intending_slide = false

	var steer := raw_steer
	if _intending_slide:
		steer = _apply_slide_steer_floor(steer)
	return clampf(steer, -1.0, 1.0)


## Bumps |steer| up to kart.slide_min_steer, preserving whichever sign it
## already had (or the last nonzero commanded sign, if steer is exactly
## zero) -- see the class doc's SLIDE (hop) COUPLING section for why the
## real FSM needs this to actually start or sustain a slide.
func _apply_slide_steer_floor(steer: float) -> float:
	var floor_mag: float = _kart_tuning.slide_min_steer
	if absf(steer) >= floor_mag:
		return steer
	var sign_value := _last_steer_sign
	if not is_zero_approx(steer):
		sign_value = signf(steer)
	return sign_value * floor_mag


func _rubber_band_speed_scale(band_gap_m: float) -> float:
	if band_gap_m > 0.0:
		return 1.0 + _ai_tuning.rubber_band_boost_max_ratio * clampf(
			band_gap_m / _ai_tuning.rubber_band_full_gap_m, 0.0, 1.0
		)
	if band_gap_m < 0.0:
		return 1.0 - _ai_tuning.rubber_band_drag_max_ratio * clampf(
			-band_gap_m / _ai_tuning.rubber_band_full_gap_m, 0.0, 1.0
		)
	return 1.0


func _neutral_output() -> Dictionary:
	return {
		"steer": 0.0,
		"brake": false,
		"hop": false,
		"boost_tap": false,
		"speed_scale": 1.0,
	}
