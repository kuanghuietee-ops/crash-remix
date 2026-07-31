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
##   lookahead_point: Vector3, curvature_ahead: float (1/m, SIGNED -- fix
##   round 1: positive = the corner bends toward the kart's world-space
##   RIGHT, the same "+right" sense steer's own convention uses; negative =
##   bends left. Magnitude alone drives the trigger/exit/corner-speed math
##   below (always read through absf()); the SIGN is what tells the slide
##   floor which way to lock a drift at corner entry, when the natural
##   pursuit+lateral steer is too small to trust on its own -- see SLIDE
##   (hop) COUPLING and the SIGNED CURVATURE CONTRACT section, which is
##   binding on Task 4's producer of this value), lateral_error_m: float
##   (signed, target - actual, along the SAME world-space "positive =
##   kart's right" axis steer uses -- see the STEERING section: this is the
##   sign convention Task 4 must produce it with), band_gap_m: float
##   (player_total_progress minus this kart's total_progress; positive =
##   this kart is behind the player). Fix-wave LOW-9: an earlier revision of
##   Task 4's own producer also included a standalone lateral_target_m key
##   (the slot's raw target, pre-error-subtraction) -- this driver never
##   read it (lateral_error_m already carries everything the steering math
##   below needs), so it was a dead key with no consumer and has been
##   removed at the source rather than kept as unused bookkeeping.
##
## Task 5 (CTR R4 items) adds three more keys: held_item: StringName (
## &"missile"/&"shield"/&"turbo"/&"beaker" while an item is held, &"none"
## otherwise -- see item_slot.gd's own held_item() doc), target_gap_ahead_m:
## float (the nearest OTHER kart's strictly-positive progress margin ahead
## of this one, by SpineFollower totals -- the exact "nearest kart truly
## AHEAD" quantity missile.gd's own LAUNCH-TIME TARGET LOCK computes at
## launch time, except AiKartAgent re-evaluates it fresh every tick rather
## than locking it once; INF when no kart is ahead, e.g. this kart is
## already in the lead), item_cooldown_ready: bool (see the class doc's
## ITEM USE COOLDOWN section below for why this is an INPUT, not something
## decide() times itself).
##
## OUTPUT (Dictionary): steer: float (-1..1), brake: bool, hop: bool (edge),
## boost_tap: bool (edge), speed_scale: float, use_item: bool (edge, Task 5).
##
## CALL CONTRACT. decide() must be called exactly once per physics tick,
## and the caller must consume/apply its outputs before the next call --
## hop and boost_tap are edge outputs whose memory (_was_intending_slide,
## _prev_boost_window_open) advances every time decide() runs, not only on
## ticks where the caller acts on the result. Calling decide() twice for
## the same logical tick (e.g. once to preview, once for real) silently
## suppresses the second call's edges by design; it is not a bug to work
## around from the caller's side, and there is no separate "peek" method.
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
## ai.corner_speed_curvature_gain * absf(curvature_ahead),
## ai.corner_speed_floor_ratio, 1.0); brake = speed_mps > target_speed *
## ai.brake_margin_ratio. absf() because how tight a corner is (and how
## hard to brake for it) does not depend on which way it turns.
##
## SLIDE (hop) COUPLING. absf(curvature_ahead) crossing
## slide_trigger_curvature (from below) while not already sliding arms
## "intent to slide"; intent clears once absf(curvature_ahead) drops
## to/below slide_exit_curvature -- a hysteresis band between the two
## thresholds, the same shape DriftStateMachine itself uses for its own
## start/sustain/end split. hop=true fires exactly once, on the tick intent
## first arms (and only while the caller's state still reports it is not
## already sliding) -- _was_intending_slide is the edge memory that keeps
## every later tick of the same corner from re-firing it.
##
## DriftStateMachine only STARTS a slide on a tick where hop is held AND
## |steer| >= kart.slide_min_steer (see its class doc), and only SUSTAINS
## an already-active slide while |steer| stays >= that same threshold -- a
## hop fired on a tick where this driver's own steer output is small (e.g.
## pursuit + lateral nearly cancel right as a corner opens up) would
## silently fail to start anything, or silently end an active slide, and
## this driver would have no way to tell from its own state that it
## happened. So for as long as intent stays armed -- from the hop tick
## through every following tick until absf(curvature_ahead) drops to/below
## slide_exit_curvature, i.e. "while it intends to hold the slide" --
## _apply_slide_steer_floor bumps |steer| up to kart.slide_min_steer
## whenever the natural pursuit+lateral value falls short of it. This runs
## BEFORE the final -1..1 clamp. Once intent clears, the floor releases and
## steer follows the natural line again -- which is what lets the real
## FSM's own sustain check end the slide naturally when the corner
## straightens out, rather than this driver trying to detect "the slide
## should end" itself.
##
## FLOOR DIRECTION (fix round 1, [HIGH]). The floor's SIGN comes from
## sign(curvature_ahead), never from the pursuit+lateral steer it is
## replacing and never from steer history. Reviewer-caught bug: at a
## typical corner entry (fixed lookahead, the corner just now crossing
## slide_trigger_curvature) pursuit+lateral steer is often still ~0 -- the
## lookahead point hasn't swung off-axis yet even though the road is about
## to turn hard -- so falling back to "whatever steer sign happened to be
## commanded last" (the previous implementation's _last_steer_sign) could
## lock DriftStateMachine's slide_direction the WRONG way through the
## corner, since that direction is LOCKED for the slide's entire life.
## curvature_ahead's sign, by contract (see SIGNED CURVATURE CONTRACT
## below), IS the corner's true direction -- it is always the right answer
## when the driver doesn't yet have a trustworthy pursuit signal, so the
## floor uses it unconditionally whenever flooring is needed:
##   if absf(raw_steer) >= slide_min_steer: use raw_steer unchanged
##   else: use sign(curvature_ahead) * slide_min_steer
## (sign(0.0) falls back to +1.0 -- an unreachable case in practice, since
## slide_exit_curvature is validated strictly positive, so absf(
## curvature_ahead) crosses out of "intending" before curvature_ahead can
## ever reach exactly 0.0, but the fallback keeps the function total).
## There is no more steer-history state to carry between ticks for this --
## _last_steer_sign is gone.
##
## SIGNED CURVATURE CONTRACT (binding on Task 4's TrackSpine.
## curvature_at_progress()). Let tangent_now be the spine tangent at the
## kart's current progress and tangent_ahead be the spine tangent at the
## lookahead sample point (in that order -- cross() is anti-commutative,
## so the order is part of the contract). Then:
##   magnitude = tangent_now.angle_to(tangent_ahead) / sample_span_m   (>= 0)
##   sign      = -signf(tangent_now.cross(tangent_ahead).y)
##   curvature_ahead = sign * magnitude
## Derivation (verified against a running Godot 4.7.1 instance, matching
## kart_motor.gd's already-verified world-space convention: positive steer
## = stick right = turn right = a NEGATIVE yaw delta, and
## FORWARD.rotated(UP, +angle) sweeps toward -X/left, since rotation about
## +Y is CCW-positive): a path bending RIGHT is one whose tangent rotates
## toward the kart's world-space right as you sample further ahead, e.g.
## tangent_now = (0,0,-1), tangent_ahead = (1,0,-1).normalized(); measured
## directly, tangent_now.cross(tangent_ahead) = (0, -0.707, 0) -- cross.y
## NEGATIVE for a RIGHTWARD bend (and, symmetrically, cross.y POSITIVE for
## a LEFTWARD bend, e.g. tangent_ahead = (-1,0,-1).normalized() gives
## cross.y = +0.707). Negating that sign is what turns it into this
## contract's "positive = bends right" convention -- so Task 4 must
## multiply the raw angle-over-span magnitude by
## -signf(tangent_now.cross(tangent_ahead).y), not by the bare cross.y sign.
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
## ITEM USE COOLDOWN (Task 5, CTR R4 items). decide()'s own signature takes
## no delta_s -- see the CALL CONTRACT section above, unchanged since Task
## 3 -- so this driver has no way to time a real ai_item_use_cooldown_s
## window itself the way AiKartAgent's own stuck-detector/box-respawn-alike
## timers do (both accumulate real delta_s in a Node's _physics_process).
## Consistent with that existing split (this class is pure logic with no
## notion of wall-clock time; the Node glue owns every real timer),
## AiKartAgent owns the actual cooldown timer and hands this driver the
## single bit it needs as the item_cooldown_ready input key -- the same
## shape band_gap_m already uses ("AiKartAgent computes it from real
## session/session-adjacent state, this driver only ever consumes the
## already-computed number/flag").
##
## ITEM USE HEURISTICS (Task 5). Exactly one heuristic is consulted, keyed
## by whichever item is currently held (state.held_item) -- holding nothing
## (&"none") never satisfies any of them:
##   &"shield": always true. R4 keeps it simple -- a held shield is used the
##     instant it is held, no other condition gates it (the task brief's own
##     "shield used immediately on pickup" ruling).
##   &"turbo": absf(curvature_ahead) < ai.slide_exit_curvature -- reuses the
##     EXISTING "this counts as straight enough" threshold the slide-intent
##     hysteresis band already defines (see the class doc's SLIDE (hop)
##     COUPLING section) rather than a new tuning literal; a turbo punched
##     into a real corner just adds speed the kart can't use through the
##     bend, so "straight" is the right gate.
##   &"missile": target_gap_ahead_m <= item.ai_missile_max_target_gap_m --
##     the brief's own "a target within X ahead"; note the <=, not <.
##   &"beaker": band_gap_m < 0.0 -- band_gap_m's own documented sign
##     ("positive = this kart is behind the player") means negative is AHEAD
##     of the player, i.e. leading; the brief's own "beaker when leading".
##     Strict <, not <=: exactly tied (band_gap_m == 0.0) is not leading.
## The satisfied-heuristic result is further gated on item_cooldown_ready
## and combined into a single armed/not-armed "intent" exactly like SLIDE
## (hop) COUPLING's own _intending_slide -- use_item is the RISING EDGE of
## that intent (_was_intending_item_use is the edge memory, cleared by
## reset() alongside every other edge field), for the identical reason hop/
## boost_tap are edge-gated rather than level outputs: a condition that
## stays true for many ticks (a long straight while holding turbo, a
## leading kart still holding a beaker) must fire use_item exactly ONCE per
## arming, not every tick it stays true -- "once per decision, not
## machine-gun" per the task brief. In the real AiKartAgent -> RaceSession.
## use_item_for() flow this is largely self-clearing anyway (using an item
## empties item_slot.gd's own &"held" state back to &"empty" the same tick,
## which flips held_item back to &"none" and drops intent on its own), but
## the edge memory is still the primary, ROBUST guard -- it does not depend
## on that same-tick clearing actually happening, the same defensive
## posture hop's own edge memory already takes against a caller that
## doesn't consume every tick's output (see the CALL CONTRACT section
## above). It is also the ONLY guard against a DIFFERENT case same-tick
## clearing cannot cover at all: a fresh item picked up while still inside
## a previous item's cooldown window would otherwise satisfy its own
## heuristic immediately (a brand new held_item, never used before) with no
## clearing event to have suppressed it -- item_cooldown_ready is what
## stops that back-to-back item spam.
##
## item_tuning: ItemTuning is an OPTIONAL third configure() parameter
## (default null) -- unlike ai_tuning/kart_tuning, which stay hard-required
## (decide() still fails closed to a fully neutral output, use_item
## included, if EITHER of those is missing; see FAIL-CLOSED below,
## unchanged by this task). Missing item_tuning degrades gracefully
## instead: every non-missile heuristic (shield/turbo/beaker) needs nothing
## from it and keeps working normally, and only the missile heuristic --
## the one that reads item.ai_missile_max_target_gap_m -- fails closed to
## "never fires" rather than crashing on a null dereference. This mirrors
## ai_kart_agent.gd's own established "optional Callable, defaults to a
## safe no-op when not wired" shape (see its other_kart_positions_getter)
## rather than AiDriver's OWN existing all-or-nothing FAIL-CLOSED shape one
## section down -- deliberately, so every one of the ~20 existing
## AiKartAgent test fixtures that configure() a kart WITHOUT wiring any
## item support keeps steering/braking/sliding/boosting exactly as before
## this task, instead of silently going neutral the moment item_tuning is
## absent.
##
## FAIL-CLOSED. decide() called before a successful configure() (either
## tuning resource still unset) push_errors and returns a neutral, harmless
## output (steer 0.0, brake false, hop false, boost_tap false, speed_scale
## 1.0) instead of crashing on a null tuning dereference -- the same
## fail-closed shape as spine_follower.gd's invalid-configure() path.

var _ai_tuning: AiTuning
var _kart_tuning: KartTuning
# Task 5 (CTR R4 items): OPTIONAL -- see configure()'s own doc and the class
# doc's item_tuning paragraph for the graceful-degrade contract this enables.
var _item_tuning: ItemTuning

var _intending_slide: bool
var _was_intending_slide: bool
var _prev_boost_window_open: bool
# Task 5: use_item's own edge memory -- see the class doc's ITEM USE
# HEURISTICS section.
var _intending_item_use: bool
var _was_intending_item_use: bool


## item_tuning is OPTIONAL (default null) -- see the class doc's own
## item_tuning paragraph for exactly what degrades (only the missile
## heuristic) versus what does not (everything else, including every
## pre-Task-5 output) when it is left unset.
func configure(
	ai_tuning: AiTuning, kart_tuning: KartTuning, item_tuning: ItemTuning = null
) -> void:
	_ai_tuning = ai_tuning
	_kart_tuning = kart_tuning
	_item_tuning = item_tuning


## Clears all per-tick edge memory (slide intent + boost-window edge + Task
## 5's own use_item intent) without touching the configured tuning
## references. See the class doc's STATEFUL ACROSS TICKS section for when a
## caller needs this.
func reset() -> void:
	_intending_slide = false
	_was_intending_slide = false
	_prev_boost_window_open = false
	_intending_item_use = false
	_was_intending_item_use = false


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
	# Task 5 (CTR R4 items) -- see the class doc's ITEM USE HEURISTICS
	# section.
	var held_item: StringName = state.get("held_item", &"none")
	var target_gap_ahead_m: float = state.get("target_gap_ahead_m", INF)
	var item_cooldown_ready: bool = state.get("item_cooldown_ready", false)

	var steer := _steer_for(
		position, forward, lookahead_point, lateral_error_m, curvature_ahead
	)

	var hop := _intending_slide and not _was_intending_slide and not is_sliding
	_was_intending_slide = _intending_slide

	var target_speed: float = _kart_tuning.top_speed_mps * clampf(
		1.0 - _ai_tuning.corner_speed_curvature_gain * absf(curvature_ahead),
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

	# Task 5 (CTR R4 items) -- see the class doc's ITEM USE HEURISTICS
	# section for the full rationale; mirrors SLIDE (hop) COUPLING's own
	# "compute intent, edge-fire on the rising transition" shape one section
	# up.
	_intending_item_use = (
		held_item != &"none"
		and item_cooldown_ready
		and _item_heuristic_satisfied(held_item, curvature_ahead, target_gap_ahead_m, band_gap_m)
	)
	var use_item := _intending_item_use and not _was_intending_item_use
	_was_intending_item_use = _intending_item_use

	return {
		"steer": steer,
		"brake": brake,
		"hop": hop,
		"boost_tap": boost_tap,
		"speed_scale": _rubber_band_speed_scale(band_gap_m),
		"use_item": use_item,
	}


## See the class doc's ITEM USE HEURISTICS section for the exact condition
## (and its rationale) per held item. held_item values outside the four
## real item names (should never happen -- item_slot.gd's own ITEM_NAMES is
## the only producer) fall through to false rather than erroring, matching
## this file's own "stay total, fail closed" posture elsewhere (e.g.
## _apply_slide_steer_floor's sign(0.0) fallback).
func _item_heuristic_satisfied(
	held_item: StringName,
	curvature_ahead: float,
	target_gap_ahead_m: float,
	band_gap_m: float
) -> bool:
	match held_item:
		&"shield":
			return true
		&"turbo":
			return absf(curvature_ahead) < _ai_tuning.slide_exit_curvature
		&"missile":
			if _item_tuning == null:
				return false
			return target_gap_ahead_m <= _item_tuning.ai_missile_max_target_gap_m
		&"beaker":
			return band_gap_m < 0.0
		_:
			return false


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

	if absf(curvature_ahead) >= _ai_tuning.slide_trigger_curvature:
		_intending_slide = true
	elif absf(curvature_ahead) <= _ai_tuning.slide_exit_curvature:
		_intending_slide = false

	var steer := raw_steer
	if _intending_slide:
		steer = _apply_slide_steer_floor(steer, curvature_ahead)
	return clampf(steer, -1.0, 1.0)


## Bumps |steer| up to kart.slide_min_steer whenever the natural
## pursuit+lateral value falls short of it. The floor's SIGN comes from
## curvature_ahead (the corner's own true, contract-signed direction), not
## from raw_steer and not from any remembered steer history -- see the
## class doc's FLOOR DIRECTION section (fix round 1, [HIGH]) for why
## history was the bug. A raw_steer that already meets or exceeds the
## floor is returned unchanged, sign and all.
func _apply_slide_steer_floor(steer: float, curvature_ahead: float) -> float:
	var floor_mag: float = _kart_tuning.slide_min_steer
	if absf(steer) >= floor_mag:
		return steer
	var sign_value := signf(curvature_ahead)
	if is_zero_approx(sign_value):
		sign_value = 1.0
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
		"use_item": false,
	}
