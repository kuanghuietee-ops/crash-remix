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
## CTR R6 Task 4 REINTRODUCES a raw slot-target key under a new name,
## slot_lateral_target_m: float (default 0.0) -- NOT a revival of the dead
## LOW-9 key: that one was removed because nothing consumed it; this one
## has a real, new consumer (see the APEX LATERAL TARGETING section below).
## The apex blend needs the slot's own RAW target (not just its error from
## the kart's current position) because it interpolates the ABSOLUTE target
## value itself (slot target -> apex target) as curvature rises, which
## lateral_error_m alone cannot reconstruct (lateral_error_m = slot_target -
## actual_lateral -- one equation, two unknowns). Every pre-Task-4 caller
## that never populates this key gets slot_lateral_target_m = 0.0, which
## still degrades gracefully (see APEX LATERAL TARGETING's own doc).
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
##   lateral_term = steer_gain * (apex_adjusted_lateral_error_m / lookahead_distance_m)
## (CTR R6 Task 4: apex_adjusted_lateral_error_m REPLACES the bare
## lateral_error_m input here -- see APEX LATERAL TARGETING immediately
## below for what adjusts it and why it collapses back to the original
## lateral_error_m on a straight.)
## raw_steer = pursuit_term + lateral_term. CTR R6 Task 4 inserts STEER
## DAMPING between this raw_steer and the slide-floor enforcement (see that
## section below for the ordering rationale) before the final clamp.
##
## APEX LATERAL TARGETING (Task 4, CTR R6: circuit polish -- smarter AI).
## Blends the slot's own raw target (state.slot_lateral_target_m) toward a
## curvature-driven "apex" target as the corner ahead tightens, so AI karts
## converge onto a shared racing line through a bend and re-spread to their
## own slots on the following straight, instead of holding a fixed lateral
## offset through every corner regardless of how sharp it is:
##   blend_ratio = clamp(absf(curvature_ahead) * ai.apex_entry_lookahead_m, 0.0, 1.0)
##   apex_target_signed_m = signf(curvature_ahead) * ai.apex_offset_max_m
##   blended_target_m = lerp(slot_lateral_target_m, apex_target_signed_m, blend_ratio)
##   apex_adjusted_lateral_error_m = lateral_error_m + (blended_target_m - slot_lateral_target_m)
## DERIVATION. curvature_ahead's own units are 1/m (see the SIGNED CURVATURE
## CONTRACT below); ai.apex_entry_lookahead_m is a distance in m; their
## product is therefore dimensionless, giving a clean 0..1 engagement ratio
## with no separate literal needed -- blend_ratio reaches 1.0 (full apex
## commitment) once the corner's own local radius (~1/curvature_ahead)
## shrinks to roughly ai.apex_entry_lookahead_m, i.e. that field doubles as
## "how tight a corner has to be before the AI fully commits to the apex
## line," exactly the plan's own "ramped over apex_entry_lookahead" phrasing.
## Multiplying that ratio through ai.apex_offset_max_m (rather than a second,
## separate magnitude field) is the plan's own "no new literals beyond the
## apex fields" constraint -- the SAME blend_ratio the engagement ramp uses
## also scales the magnitude, so "ramp from 0 to apex_offset_max_m scaled by
## |curvature|" and "engaged within apex_entry_lookahead_m" are one formula,
## not two independent ones.
## SIGN -- PIN WORLD-SIDE. apex_target_signed_m takes curvature_ahead's own
## sign, the SAME sign _apply_slide_steer_floor already keys off of one
## section down: positive curvature_ahead = a right-bending corner (per the
## SIGNED CURVATURE CONTRACT below) = apex_target_signed_m positive = a
## target to the kart's world-space right (per lateral_error_m's own "target
## - actual, positive = kart's right" contract at the top of this file).
## Verified against the REAL graybox loop's own East turn, not just the
## algebra: test_ai_kart_agent.gd's own apex-sign test reads the East turn's
## real wall geometry (Walls/SouthInner vs Walls/SouthOuter positions
## relative to the south-straight centerline and its own right vector) and
## proves the INNER wall -- the corner's own geometric inside -- sits on
## that same world-space right side that this formula's positive sign
## points to; the East turn itself is an independently-pinned RIGHT-bending
## (positive-curvature) corner (test_track_spine.gd's own test against this
## exact marker). So "apex side = inside of the corner" and "positive
## curvature = positive apex lateral" are the SAME claim on this real track,
## not two conventions that happen to agree by luck.
## STRAIGHTS. At curvature_ahead == 0.0: blend_ratio == 0.0 unconditionally
## (regardless of apex_target_signed_m's own value, since signf(0.0) is also
## 0.0 -- an edge case that never needs its own fallback here the way
## _apply_slide_steer_floor's sign(0.0) does, because a zero blend_ratio
## already zeroes out whatever sign apex_target_signed_m would have taken),
## so lerp(slot_lateral_target_m, apex_target_signed_m, 0.0) returns
## slot_lateral_target_m exactly and apex_adjusted_lateral_error_m collapses
## to the original lateral_error_m -- "straights -> back to slot offsets,
## karts spread again" falls out of the formula rather than needing a
## separate straight-line special case.
## GRACEFUL DEGRADE. A caller that never populates slot_lateral_target_m
## (default 0.0, see the INPUT STATE section above) still gets a sensibly-
## signed apex pull toward apex_target_signed_m -- the (blended_target_m -
## slot_lateral_target_m) delta just no longer nets out to exactly
## slot_lateral_target_m's own contribution at partial engagement, the same
## "everything still works, just slightly less precisely" degrade this
## file's other optional-input paragraphs already establish as the norm.
##
## STEER DAMPING (Task 4, CTR R6). raw_steer (pursuit + apex-adjusted
## lateral) is low-pass filtered before anything else touches it:
##   steer_after_damping = lerp(_prev_steer_output, raw_steer, 1.0 - ai.steer_damping)
## i.e. an exponential moving average with smoothing factor ai.steer_damping
## (higher = more inertia, more smoothing) -- the R3 final review measured
## this driver's undamped steer regressing (reversing the kart's own net
## spine progress tick-to-tick, see AiKartAgent's STUCK DETECTION doc for
## what "regressing" means here) on 7-28% of ticks through the graybox
## loop's East turn, i.e. real, measurable oscillation against the inner
## wall, not a cosmetic jitter.
## COLD START. _has_prev_steer_output starts false (a fresh driver, or one
## just reset() -- see below) and the FIRST decide() call after either
## returns raw_steer completely unfiltered (no artificial ramp-up from a
## phantom zero prior output) -- this is what keeps every pre-Task-4 single-
## call test in this suite passing unchanged, and it is also the physically
## correct behavior: a kart that just spawned or was just teleported by the
## stuck-respawn safety net has no meaningful "previous tick" to smooth
## against, and blending toward a stale pre-respawn value would be a bug,
## not a feature.
## ORDERING VS. THE SLIDE FLOOR -- THE FLOOR APPLIES AFTER DAMPING, NOT
## BEFORE. _apply_slide_steer_floor's whole job (see FLOOR DIRECTION below)
## is to GUARANTEE |steer| >= kart.slide_min_steer on every tick intent
## stays armed, unconditionally, because DriftStateMachine reads that exact
## per-tick value to decide whether to start/keep sustaining a real slide --
## a guarantee the low-pass filter must never be allowed to soften. Applying
## damping to the RAW value and then flooring the damped result (this
## driver's actual order) preserves that guarantee exactly: whatever the
## damped value came out to, if its magnitude undershoots the floor, the
## floor still unconditionally corrects it to exactly ai.kart_tuning.
## slide_min_steer with curvature_ahead's own sign, every single tick.
## Flooring FIRST and damping SECOND would break the guarantee instead: the
## floor's own output from one tick would immediately get re-blended toward
## whatever raw_steer (potentially near zero, or the wrong sign entirely
## after a corner reversal) the NEXT tick produces, capable of dragging the
## post-floor, post-damping value back UNDER slide_min_steer or even
## flipping its sign -- silently breaking DriftStateMachine's own start/
## sustain contract on exactly the ticks it matters most (see
## test_slide_floor_overrides_damping_even_after_a_large_opposite_prior_tick
## in test_ai_driver.gd for a worked case: a large opposite-signed prior
## output, damped-then-floored still lands exactly on the guarantee;
## floored-then-damped would not). _prev_steer_output is updated to the
## FINAL returned value (post-floor, post-clamp) at the end of every
## decide() call, not the pre-floor raw/damped value -- so damping always
## smooths toward what the kart was ACTUALLY commanded last tick (including
## any floor bump), never a value that was silently overridden before ever
## reaching the caller.
##
## CORNERING / BRAKE. target_speed = kart.top_speed_mps * clamp(1 -
## ai.corner_speed_curvature_gain * absf(curvature_ahead),
## ai.corner_speed_floor_ratio, 1.0); brake = speed_mps > target_speed *
## effective_brake_margin_ratio, where effective_brake_margin_ratio =
## ai.brake_margin_ratio + slot_index * ai.personality_aggression_step (see
## the PERSONALITY section below) -- absf() because how tight a corner is
## (and how hard to brake for it) does not depend on which way it turns.
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
## true, ai.boost_tap_enabled is truthy (>= 1.0 -- the tuning field is a
## 0/1 float flag, not a real bool, per the brief), AND (Task 4, CTR R6)
## this tick's per-(slot, tick) confidence value clears ai.personality_
## skill_jitter -- see PERSONALITY below for exactly how confidence is
## computed and why this is the one output it modulates. Edge-gated rather
## than "true for as long as the window stays open" for the same reason hop
## is: a caller translating boost_tap=true into a real boost_tap() call
## every tick the window stays open would tap far more often than CTR's
## one-tap-per-window model intends (and if a window's open_s is ever
## authored as 0.0, the real FSM would otherwise re-open the very next
## stage's window before this driver's next tick and get tapped again
## immediately). _prev_boost_window_open is the edge memory. A tick whose
## confidence check fails still advances _prev_boost_window_open normally
## (this is a gate on the EDGE firing, not on whether the edge is tracked) --
## so a "missed" window does not somehow re-arm and fire late on a later
## tick of the same still-open window; it is simply skipped, the same "a
## less confident AI misses the window entirely" a real human's own
## mistimed thumb would produce.
##
## PERSONALITY (Task 4, CTR R6: circuit polish -- smarter AI). Two slot-
## indexed, per-driver-lifetime scalars (slot_index is supplied once at
## configure() time, see below -- it never changes tick to tick, the same
## "constant across this driver's life" shape ai_tuning/kart_tuning/item_
## tuning already have):
##   AGGRESSION. effective_brake_margin_ratio = ai.brake_margin_ratio +
##   slot_index * ai.personality_aggression_step (see CORNERING / BRAKE
##   above) -- a higher slot index tolerates a higher speed-over-target
##   multiple before braking, i.e. brakes later and carries more corner
##   speed. Purely a function of slot_index and tuning, so it is IDENTICAL
##   every tick and every run for a given slot -- no separate per-tick state
##   to track.
##   SKILL JITTER. A per-(slot_index, tick) DETERMINISTIC pseudo-noise
##   confidence value gates the boost tap (see BOOST TAP above) -- NO
##   RandomNumberGenerator, NO randf()/randi(), and no seed to manage,
##   because "same slot -> same behavior every run" (the brief's own
##   determinism requirement) rules out anything stateful/seeded:
##     confidence = absf(fmod(float(hash(Vector2i(slot_index, _tick_index))), TAU)) / TAU
##   hash() is Godot's own built-in deterministic Variant hash (used
##   internally for Dictionary/Set keys) -- a pure function of its input,
##   not a random-number source, so the SAME (slot_index, _tick_index) pair
##   always hashes to the SAME int, on every call, every run. fmod(..., TAU)
##   folds that (signed, wide-range) int down to a bounded span using only
##   Godot's own built-in TAU constant (no new tuning literal, no bare
##   numeric-literal gain -- see this file's own no-bare-literal
##   convention), and dividing by TAU normalizes to [0.0, 1.0). The tap
##   fires only when confidence >= ai.personality_skill_jitter -- so
##   personality_skill_jitter reads directly as "the per-tick probability
##   this slot fumbles the tap," despite involving no actual randomness.
##   _tick_index is a plain per-driver counter, incremented once per
##   decide() call (see reset()'s own doc for why it is edge memory too):
##   using it rather than a wall-clock delta_s keeps this driver's own "pure
##   function of state + internal edge memory, no delta_s parameter" shape
##   (see the CALL CONTRACT section above) intact, and keeps confidence
##   reproducible from a fresh configure()/reset() regardless of real frame
##   timing.
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
# Task 4 (CTR R6): this driver's own constant identity for the whole of its
# life -- see the class doc's PERSONALITY section. Defaults to 0 (the
# player's own conventional slot, see ai_kart_agent.gd's LATERAL SLOT
# CENTERING doc) for every pre-Task-4 caller that never passes one, which
# reads as "no aggression offset, slot-0 confidence" -- a harmless neutral,
# not a crash or a fail-closed path.
var _slot_index: int

var _intending_slide: bool
var _was_intending_slide: bool
var _prev_boost_window_open: bool
# Task 5: use_item's own edge memory -- see the class doc's ITEM USE
# HEURISTICS section.
var _intending_item_use: bool
var _was_intending_item_use: bool
# Task 4 (CTR R6): STEER DAMPING's own edge memory -- see that section's
# COLD START paragraph. _prev_steer_output only means something once
# _has_prev_steer_output is true; reading it beforehand would blend toward
# a meaningless zero.
var _prev_steer_output: float
var _has_prev_steer_output: bool
# Task 4 (CTR R6): PERSONALITY's own skill-jitter tick counter -- see that
# section's own doc for why a plain per-decide()-call counter is used
# instead of a wall-clock delta_s.
var _tick_index: int


## item_tuning is OPTIONAL (default null) -- see the class doc's own
## item_tuning paragraph for exactly what degrades (only the missile
## heuristic) versus what does not (everything else, including every
## pre-Task-5 output) when it is left unset. slot_index (Task 4, CTR R6) is
## OPTIONAL too (default 0) -- see the class doc's PERSONALITY section and
## the _slot_index field doc immediately above for what a default of 0
## means for every pre-Task-4 caller.
func configure(
	ai_tuning: AiTuning,
	kart_tuning: KartTuning,
	item_tuning: ItemTuning = null,
	slot_index: int = 0
) -> void:
	_ai_tuning = ai_tuning
	_kart_tuning = kart_tuning
	_item_tuning = item_tuning
	_slot_index = slot_index


## Clears all per-tick edge memory (slide intent + boost-window edge + Task
## 5's own use_item intent + Task 4's own steer-damping/skill-jitter tick
## state) without touching the configured tuning references or slot_index
## (that is this driver's constant identity, not edge memory -- unaffected
## by reset() the same way _ai_tuning/_kart_tuning/_item_tuning already are).
## See the class doc's STATEFUL ACROSS TICKS section for when a caller needs
## this -- Task 4's own STEER DAMPING/COLD START paragraph is why a stuck-
## kart respawn (ai_kart_agent.gd's own _respawn(), which already calls this)
## must also clear _has_prev_steer_output: a kart teleported onto a fresh
## line has no business smoothing its first post-respawn tick toward
## whatever it was doing right before it got stuck.
func reset() -> void:
	_intending_slide = false
	_was_intending_slide = false
	_prev_boost_window_open = false
	_intending_item_use = false
	_was_intending_item_use = false
	_prev_steer_output = 0.0
	_has_prev_steer_output = false
	_tick_index = 0


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
	# Task 4 (CTR R6) -- see the class doc's APEX LATERAL TARGETING section
	# and the INPUT STATE section's own slot_lateral_target_m paragraph.
	var slot_lateral_target_m: float = state.get("slot_lateral_target_m", 0.0)
	# Task 5 (CTR R4 items) -- see the class doc's ITEM USE HEURISTICS
	# section.
	var held_item: StringName = state.get("held_item", &"none")
	var target_gap_ahead_m: float = state.get("target_gap_ahead_m", INF)
	var item_cooldown_ready: bool = state.get("item_cooldown_ready", false)

	# Task 4 (CTR R6): PERSONALITY's own tick counter -- incremented once per
	# decide() call, BEFORE it is read below, so the very first post-
	# configure()/reset() call uses tick 1, never tick 0 (an off-by-one that
	# would otherwise make _tick_index's very first meaningful value
	# indistinguishable from its own zeroed reset() state).
	_tick_index += 1

	var steer := _steer_for(
		position, forward, lookahead_point, lateral_error_m, slot_lateral_target_m, curvature_ahead
	)

	var hop := _intending_slide and not _was_intending_slide and not is_sliding
	_was_intending_slide = _intending_slide

	var target_speed: float = _kart_tuning.top_speed_mps * clampf(
		1.0 - _ai_tuning.corner_speed_curvature_gain * absf(curvature_ahead),
		_ai_tuning.corner_speed_floor_ratio,
		1.0
	)
	# Task 4 (CTR R6): PERSONALITY's own AGGRESSION scalar -- see the class
	# doc's CORNERING / BRAKE and PERSONALITY sections.
	var effective_brake_margin_ratio: float = (
		_ai_tuning.brake_margin_ratio
		+ float(_slot_index) * _ai_tuning.personality_aggression_step
	)
	var brake := speed_mps > target_speed * effective_brake_margin_ratio

	# Task 4 (CTR R6): PERSONALITY's own SKILL JITTER confidence gate -- see
	# the class doc's BOOST TAP and PERSONALITY sections.
	var confident := _skill_confidence(_slot_index, _tick_index) >= _ai_tuning.personality_skill_jitter
	var boost_tap := (
		is_sliding
		and boost_window_open
		and not _prev_boost_window_open
		and _ai_tuning.boost_tap_enabled >= 1.0
		and confident
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
## twice. Task 4 (CTR R6) inserts two more steps between the raw pursuit+
## lateral value and the final clamp -- see the class doc's APEX LATERAL
## TARGETING and STEER DAMPING sections for what each does and, for
## damping, exactly why it runs BEFORE the slide floor rather than after.
func _steer_for(
	position: Vector3,
	forward: Vector3,
	lookahead_point: Vector3,
	lateral_error_m: float,
	slot_lateral_target_m: float,
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
		var apex_adjusted_lateral_error_m := _apex_adjusted_lateral_error_m(
			lateral_error_m, slot_lateral_target_m, curvature_ahead
		)
		var lateral_term := _ai_tuning.steer_gain * (
			apex_adjusted_lateral_error_m / lookahead_distance_m
		)
		raw_steer = pursuit_term + lateral_term

	if absf(curvature_ahead) >= _ai_tuning.slide_trigger_curvature:
		_intending_slide = true
	elif absf(curvature_ahead) <= _ai_tuning.slide_exit_curvature:
		_intending_slide = false

	var damped_steer := _apply_steer_damping(raw_steer)

	var steer := damped_steer
	if _intending_slide:
		steer = _apply_slide_steer_floor(steer, curvature_ahead)
	steer = clampf(steer, -1.0, 1.0)

	# See the class doc's STEER DAMPING section: _prev_steer_output tracks
	# the FINAL (post-floor, post-clamp) value actually returned, never the
	# pre-floor raw/damped intermediate -- damping must always smooth toward
	# what the kart was ACTUALLY commanded last tick.
	_prev_steer_output = steer
	_has_prev_steer_output = true
	return steer


## See the class doc's APEX LATERAL TARGETING section for the full
## derivation (dimensional analysis, the "no snap, straights fall out for
## free" properties, and the world-side sign pin against the real graybox
## loop's East turn).
func _apex_adjusted_lateral_error_m(
	lateral_error_m: float, slot_lateral_target_m: float, curvature_ahead: float
) -> float:
	var blend_ratio := clampf(
		absf(curvature_ahead) * _ai_tuning.apex_entry_lookahead_m, 0.0, 1.0
	)
	var apex_target_signed_m := signf(curvature_ahead) * _ai_tuning.apex_offset_max_m
	var blended_target_m := lerpf(slot_lateral_target_m, apex_target_signed_m, blend_ratio)
	return lateral_error_m + (blended_target_m - slot_lateral_target_m)


## See the class doc's STEER DAMPING section for the cold-start rationale
## (no prior tick to smooth against yet) and why the slide floor is applied
## by the CALLER after this, never before.
func _apply_steer_damping(raw_steer: float) -> float:
	if not _has_prev_steer_output:
		return raw_steer
	return lerpf(_prev_steer_output, raw_steer, 1.0 - _ai_tuning.steer_damping)


## See the class doc's PERSONALITY section's own SKILL JITTER paragraph for
## the full derivation of this NO-RNG, deterministic-per-(slot, tick) hash
## normalization.
func _skill_confidence(slot_index: int, tick_index: int) -> float:
	var raw_hash: int = hash(Vector2i(slot_index, tick_index))
	return absf(fmod(float(raw_hash), TAU)) / TAU


## Bumps |steer| up to kart.slide_min_steer whenever the natural
## pursuit+lateral value falls short of it. The floor's SIGN comes from
## curvature_ahead (the corner's own true, contract-signed direction), not
## from raw_steer and not from any remembered steer history -- see the
## class doc's FLOOR DIRECTION section (fix round 1, [HIGH]) for why
## history was the bug. A raw_steer that already meets or exceeds the
## floor is returned unchanged, sign and all. Task 4 (CTR R6): "raw_steer"
## here is actually the DAMPED value by the time this is called -- see the
## class doc's STEER DAMPING/ORDERING VS. THE SLIDE FLOOR section for why
## that order is load-bearing.
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
