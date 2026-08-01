class_name AiKartAgent
extends Node

## Node glue that drives one AI kart every physics tick (Task 4, CTR R3: AI
## opponents). Owns a real SpineFollower + AiDriver and feeds a real,
## already-configured KartController through the EXACT SAME public API a
## human racer drives through (steer()/set_brake()/hop_pressed()/
## hop_released()/boost_tap()/set_speed_scale()) -- see kart_controller.gd's
## own class doc: "Input is a poll surface... the racing input mode is
## expected to call steer()/set_brake() every frame and hop_pressed()/
## hop_released() on edges". This class is that "racing input mode", just
## driven by AiDriver.decide() instead of a human thumb. It never reaches
## past the controller into KartMotor/DriftStateMachine directly, and it
## never touches the kart's CharacterBody3D physics except during the
## stuck-respawn teleport below.
##
## PROCESS MODE. Set to PROCESS_MODE_PAUSABLE in configure(), the same
## "physics-driven per-tick accumulation must actually stop while the tree
## is paused" contract race_session.gd's own configure() establishes for
## itself (see its class doc's TIMER section) -- an AI kart has no business
## still driving itself while the game is paused.
##
## KART TYPE. The plan text describes configure()'s first parameter loosely
## as "kart: Node", but this class reads kart.global_position,
## kart.global_transform, and kart.velocity every tick (Node3D/
## CharacterBody3D built-in properties, not something a bare Node has) and
## writes kart.global_position directly during a stuck-respawn teleport --
## so, like race_session.gd's own _kart field, it is typed CharacterBody3D.
## Every KartController-specific method (steer(), configure(), etc.) still
## goes through .call() rather than a static KartController type, the same
## duck-typed shape racing_input_adapter.gd's own controller parameter uses.
##
## STATE ASSEMBLY, per ai_driver.gd's documented INPUT STATE contract:
## - position/forward: the kart's own current world-space position/facing.
## - speed_mps: KartController.speed_mps() (the MOTOR's own commanded
##   speed) -- deliberately NOT the same signal stuck-detection uses below
##   (see STUCK DETECTION). This is the right signal for lookahead-distance
##   scaling and AiDriver's own corner-speed/brake formula: both want to
##   know how fast the kart is COMMANDED to be going, independent of a
##   momentary collision.
## - lookahead_m = ai_tuning.lookahead_min_m + speed_mps *
##   ai_tuning.lookahead_speed_gain_s (the brief's own formula, no new
##   literal).
## - lookahead_point = spine.point_at_progress(progress + lookahead_m) --
##   wraps past the seam internally (see track_spine.gd's point_at_progress()
##   doc).
## - curvature_ahead = spine.curvature_at_progress(progress, lookahead_m).
##   RESOLVED AMBIGUITY (the brief flagged "decide cleanly, document"):
##   ai_driver.gd's own SIGNED CURVATURE CONTRACT defines tangent_now as
##   "the spine tangent at the KART'S CURRENT PROGRESS" and tangent_ahead as
##   "the spine tangent at the LOOKAHEAD SAMPLE POINT" -- i.e. progress_m =
##   the kart's own current progress (not the lookahead point itself), and
##   sample_span_m = lookahead_m (the along-spine distance from the kart to
##   that lookahead point). That is EXACTLY curvature_at_progress(progress,
##   lookahead_m)'s own signature, so this is not a free choice -- it is
##   what the already-shipped, binding AiDriver contract requires. The
##   plan's alternate phrasing ("sample tangents at +/-lookahead") would
##   center the sample AROUND the lookahead point instead, which does not
##   match tangent_now's own definition ("the kart's current progress") and
##   was not used.
## - lateral_error_m = _lateral_target_m - actual_lateral_m, where
##   _lateral_target_m is this slot's own centered offset from the pursuit
##   line, computed once in configure() (see _compute_lateral_target_m())
##   since slot_index/ai_tuning never change per tick -- fix-wave LOW-9: this
##   private field was NOT itself included as a separate "lateral_target_m"
##   key in the assembled state Dictionary below at the time (ai_driver.gd's
##   own INPUT STATE doc said that key was "not read here, lateral_error_m
##   already carries what this driver needs" -- a dead key with no
##   consumer, removed rather than kept as unused bookkeeping). Task 4 (CTR
##   R6) REINTRODUCES it under a new name and a real consumer -- see the
##   slot_lateral_target_m paragraph below. actual_lateral_m is the
##   perpendicular projection of (kart_pos - centerline_point) onto the
##   CURRENT tangent's own "right" vector (tangent.cross(Vector3.UP) -- the
##   same right-hand identity kart_motor.gd's own velocity() uses: for the
##   default facing (0,0,-1), forward.cross(UP) = (1,0,0) = world +X =
##   Godot's own basis.x for an identity transform, i.e. "right" by the same
##   convention steer's own +right sign already uses). Positive
##   lateral_error_m therefore means the target slot sits to the kart's
##   world-space right, satisfying ai_driver.gd's own documented sign
##   requirement for this value.
## - slot_lateral_target_m (Task 4, CTR R6) = _lateral_target_m itself, RAW
##   (pre-error-subtraction) -- see ai_driver.gd's own INPUT STATE and APEX
##   LATERAL TARGETING sections for why the apex blend needs the raw slot
##   target in addition to lateral_error_m (one equation, two unknowns:
##   lateral_error_m alone cannot reconstruct both the target and the
##   kart's actual position from a single subtraction).
## - band_gap_m = player_progress_getter.call() - follower.total_progress_m()
##   (positive = this kart is behind the player) -- SEAM-SAFE by
##   construction since both sides of the subtraction are continuous
##   SpineFollower totals, never a raw seam-ambiguous spine offset (see the
##   plan's own "Seam ruling").
## - held_item, target_gap_ahead_m, item_cooldown_ready (Task 5, CTR R4
##   items): see the ITEM WIRING section below.
##
## ITEM WIRING (Task 5, CTR R4 items). Three new configure() parameters,
## ALL OPTIONAL (default null/Callable()) -- mirrors other_kart_positions_
## getter's own established "every existing caller that never passes one
## keeps the exact pre-fix behavior" shape one section up, so every one of
## this suite's own pre-Task-5 fixtures that never wires item support keeps
## driving exactly as before:
## - item_tuning: ItemTuning, forwarded straight through to AiDriver.
##   configure() (see its own class doc for what that unlocks/degrades).
## - item_targets_getter: Callable -> Array[Dictionary], each entry shaped
##   {"kart": CharacterBody3D, "progress": float} -- the EXACT SAME Callable
##   shape (and, in production, the exact same bound method,
##   RaceSession._item_targets()) missile.gd's own configure() already
##   consumes for its LAUNCH-TIME TARGET LOCK. The difference: a missile
##   calls it ONCE and locks the result for its whole life; this agent calls
##   it fresh every tick (see _target_gap_ahead_m()) since an AI's item
##   decision is a live, every-tick read, not a one-shot launch commitment.
## - use_item_dispatcher: Callable, called as use_item_dispatcher.call(kart)
##   -- in production, Callable(self, "use_item_for") bound to nothing (the
##   kart argument is supplied at call time, not bound in), the EXACT SAME
##   session method racing_input_adapter.gd's own player ITEM-press path
##   routes through (see race_session.gd's own use_item_for() doc: "Task
##   5's AI item-use decision is documented to call kart.use_item() itself
##   the SAME way and route its own result through THIS method"). Neither
##   this agent nor AiDriver re-implements any part of the missile/beaker/
##   turbo/shield switch themselves -- that switch lives in exactly one
##   place, RaceSession.dispatch_item_use().
##
## STATE ASSEMBLY (item keys): held_item reads _kart.call("item_slot") ->
## .call("held_item") every tick, unconditionally -- this needs no item
## wiring at all (item_slot() is a base KartController capability RaceSession
## already configure()s onto every kart, player and AI alike, independent of
## whether THIS agent was given any item Callables), so it is guarded only by
## _kart.has_method("item_slot") (false for a bare test-fixture CharacterBody3D
## with no controller script at all, matching this file's own _read_kart_
## extents() precedent for a missing capability), never by whether item
## wiring is present. target_gap_ahead_m re-scans item_targets_getter's
## snapshot every tick for the nearest OTHER kart with a strictly-positive
## progress margin ahead of this one -- the identical "nearest kart truly
## ahead" search missile.gd's own configure() already performs, just
## re-evaluated fresh each tick instead of locked once; INF when the getter
## is unset/invalid (mirrors player_progress_getter's own "invalid Callable
## -> 0.0" graceful-default shape one section up) or no kart is strictly
## ahead. item_cooldown_ready reads a real timer THIS agent owns (_item_
## cooldown_elapsed_s, accumulated every tick in _physics_process exactly
## like the stuck-window/hop-release timers already are) against item_
## tuning.ai_item_use_cooldown_s -- see AiDriver's own ITEM USE COOLDOWN doc
## for why the timer lives here and not in the driver. Starts already-ready
## at configure() time (elapsed seeded to the cooldown duration itself, not
## a new literal) so the very first item this kart ever picks up can be used
## the instant its own heuristic is satisfied, with no artificial race-start
## delay; resets to 0.0 the instant an item is actually dispatched (see
## OUTPUT ROUTING's own use_item paragraph below), independent of the
## stuck-respawn timers (an item-use cooldown is real wall-clock pacing,
## unrelated to track position, so _respawn() does not touch it).
##
## LATERAL SLOT CENTERING. lateral_slot_spacing_m's own doc says "slot_i *
## spacing, centered across the field" -- centered across ALL
## ai_tuning.opponent_count + 1 karts (every AI opponent PLUS the player,
## who conventionally takes slot 0 -- see the plan's Task 5), not just the
## opponents: centered_slot = slot_index - HALF of (opponent_count + 1 - 1),
## lateral_target_m = centered_slot * lateral_slot_spacing_m (HALF via
## src/core/scalar_math.gd, per this file's own no-bare-literal rule -- see
## spine_follower.gd's identical use of ScalarMathType.HALF for its own
## half-length wrap). This spreads every kart (player included) to a
## distinct lateral offset around the pursuit line rather than only
## centering the AI pack and leaving the player's own slot 0 off to one
## side.
##
## OUTPUT ROUTING:
## - steer, set_brake: called every tick unconditionally, mirroring
##   racing_input_adapter.gd's apply_move() (a level, not an edge).
## - hop: AiDriver's own hop output is ALREADY an edge (true only once per
##   armed intent, see ai_driver.gd's class doc), but KartController wants a
##   PRESS-then-RELEASE pair, not a press held forever -- holding it forever
##   would leave DriftStateMachine's own _hop_held latch armed indefinitely,
##   which is harmless to slide-START (that already only fires once) but is
##   needless stale state with no benefit. So: hop=true this tick calls
##   hop_pressed() THIS tick and arms _hop_release_pending; the NEXT tick
##   (before assembling any new state) calls hop_released() and clears it --
##   a clean one-tick "tap" simulation, decided once here rather than
##   re-litigated per corner.
## - boost_tap: AiDriver's own output is already a one-shot edge; routed
##   straight through with no press/release pairing needed (boost_tap() is
##   itself a single discrete call on the controller, same as
##   racing_input_adapter.gd's own hop-while-sliding branch).
## - speed_scale: set_speed_scale() every tick, unconditionally (KartMotor's
##   own default of 1.0 covers "no scaling" for the ticks before the first
##   decide() call ever runs, so there is no missing-call gap to guard).
## - use_item (Task 5): AiDriver's own output is already a one-shot edge
##   (see its class doc's ITEM USE HEURISTICS section), routed straight
##   through with no press/release pairing needed -- when true AND use_
##   item_dispatcher.is_valid() (the graceful "never wired" no-op every
##   other optional Callable here already uses), this calls use_item_
##   dispatcher.call(_kart) and immediately resets _item_cooldown_elapsed_s
##   to 0.0, re-arming the cooldown window from this exact tick rather than
##   whenever the next _physics_process tick would have naturally sampled
##   it. An invalid dispatcher still lets the edge fire (harmlessly, since
##   nothing consumes it) rather than suppressing use_item at the source --
##   AiDriver's own output stays a pure function of the state it was given,
##   never reaching back into this agent's own wiring to decide what to
##   report.
##
## STUCK DETECTION (fix-wave HIGH-1 -- REPLACES the fix-round-1 net-
## DISPLACEMENT design below with NET SPINE PROGRESS). Still a TUMBLING
## window, not a continuously-reset instantaneous-speed check:
## _stuck_window_anchor_total_progress_m/_stuck_window_elapsed_s anchor the
## kart's own follower.total_progress_m() once and accumulate real elapsed
## time; once _stuck_window_elapsed_s reaches respawn_stuck_after_s, this
## compares (follower.total_progress_m() - anchor) against
## respawn_stuck_speed_mps * respawn_stuck_after_s (the same natural product
## of the two existing tuning fields the fix-round-1 design already used --
## no new literal). Below that: stuck, respawn. At or above it: NOT stuck --
## re-anchor to the current total and start a fresh window, so a genuinely
## progressing kart always gets a fair, un-poisoned window rather than one
## contaminated by an earlier slow patch. total_progress_m() can decrease
## (SpineFollower.update()'s own "reverse driving decreases" semantics), so
## a kart making real net BACKWARD progress reads as stuck too, correctly --
## a comparison against 0.0 alone would not, but this compares against the
## tuned crawl-speed threshold instead, which a negative delta always fails.
##
## WHY NOT NET DISPLACEMENT (the fix-round-1 design this replaces): a kart
## can rack up real straight-line displacement every tick -- oscillating
## across the road width, spinning against a wall, ricocheting between two
## obstacles -- without ever advancing a single meter along the actual
## racing line. Net displacement compares the window's start/end WORLD
## positions, so it reads that oscillation as "moved N meters, not stuck"
## purely because the two sampled instants happened to land on different
## sides of it, even though the kart's own progress around the lap never
## went anywhere (measured: a kart oscillating at 8.7 m/s stayed confined to
## a 14m spine span for a full 30 real seconds with zero respawns -- moving
## without progressing). Net spine progress does not have this blind spot:
## it compares the SAME continuous, seam-safe SpineFollower total every
## other cross-kart comparison in this codebase already trusts (see the
## class doc's own STATE ASSEMBLY section), so a kart that is genuinely
## moving but never actually advancing reads as exactly what it is.
## Decided to REPLACE rather than keep both checks: an AND of the two would
## suppress the fix (a moving-without-progressing kart usually still clears
## the old displacement threshold, which is the whole bug), and an OR would
## make the displacement check purely redundant -- fix-round-1's own
## motivating case (a kart bouncing in place against a wall, sharp velocity
## spikes and all) already reads as flat net progress too, since none of
## that bouncing is net forward motion along the spine either. Vertical
## motion has no bearing on spine progress at all (a 2D projection onto the
## track's own polyline), so the fix-round-1 design's separate "flatten to
## XZ" step has no equivalent need here -- a kart mid-hop-arc making real
## forward progress advances its own total_progress_m() exactly as it
## should, hop or no hop.
##
## WRONG-WAY RECOVERY (Task 2b, CTR R7 -- OPERATOR PRIORITY: device report on
## R6, "the AI got bug, keep driving back the wrong way and stuck at the
## side. Make the AI smarter and harder."). This agent owns a real
## wall-clock timer (_recovery_heading_error_elapsed_s) and a persisted
## armed/cleared bit (_recovery_active), updated once per tick in
## _update_recovery_state() -- BEFORE the stuck-window check below, so a
## closing window always reads THIS tick's own current recovery state, never
## a one-tick-stale value. AiDriver has no delta_s and no notion of
## wall-clock time (see its own ITEM USE COOLDOWN doc for the established
## precedent this mirrors), so the SUSTAINED-trigger timing lives here, the
## same way the item-use cooldown timer does; AiDriver only ever consumes
## the resulting bit via the state Dictionary's own recovery_active key.
##
## HEADING ERROR is the unsigned angle (degrees, flattened to XZ -- vertical
## pitch from a hop arc has no bearing on which way along the track the kart
## is pointed) between the kart's own current forward and TrackSpine.
## tangent_at_progress() at the kart's own current (raw, unwrapped-follower)
## progress -- see _heading_error_degrees(). A degenerate zero-length
## flattened forward or tangent (e.g. a kart pitched dead vertical mid-hop)
## reads as 0.0 error rather than crashing on Vector3.angle_to's own
## undefined-for-zero-vectors case -- "cannot tell, don't arm on a guess".
##
## SUSTAINED TRIGGER + HYSTERESIS. Heading error above ai.recovery_heading_
## error_degrees accumulates _recovery_heading_error_elapsed_s every tick;
## once that reaches ai.recovery_trigger_s, _recovery_active arms. Once
## armed, it stays armed regardless of momentary fluctuation until heading
## error drops BELOW HALF ai.recovery_heading_error_degrees (ScalarMathType.
## HALF, per this file's own no-bare-literal derivation one section up) --
## the same hysteresis-band shape ai_driver.gd's own SLIDE (hop) COUPLING
## uses (a lower exit threshold than the arm threshold, so a kart hovering
## right at the boundary cannot chatter the bit on and off every tick).
## Clearing also resets the elapsed ARM timer (_recovery_heading_error_
## elapsed_s) to zero, so re-arming from a fresh clear always needs its own
## full recovery_trigger_s of sustained heading error again.
##
## Fix round 1 (reviewer MEDIUM, SAFETY-NET STARVATION) -- clearing does
## NOT touch the stuck window or _recovery_attempts. An earlier version of
## this design DID unconditionally re-anchor the window and zero attempts
## on every clear (to stop a recovery episode's own necessary backward
## dip -- see BRAKE, FORCED TRUE WHILE RECOVERING in ai_driver.gd's own
## class doc -- from poisoning a window that closed moments after a
## genuine realignment); that in turn let a kart whose yaw oscillates
## across the hysteresis band faster than the stuck window's own period
## re-anchor the window on every spurious clear, so it could never
## naturally close at all -- the safety net starved indefinitely. See
## _update_recovery_state()'s own doc for the actual fix: this agent marks
## _recovery_was_active_this_window true every tick recovery is active and
## leaves the window's own reset cadence COMPLETELY UNTOUCHED by arm/clear
## events, so it always closes on schedule regardless of oscillation --
## still granting a genuinely-recovering kart the SAME retry-leniency
## (see BOUNDED RECOVERY RETRIES below), just decided by "was recovery
## active at any point in this window", not "did clearing itself happen
## recently enough to still be sitting in this exact tick's memory".
##
## STEERING WHILE ACTIVE. This agent's own _assemble_state() substitutes a
## much NEARER lookahead_point while _recovery_active is true -- own progress
## + ai.lookahead_min_m (reused as "a short forward distance", no new
## literal -- see _assemble_state()'s own comment) instead of the normal
## speed-scaled lookahead -- and sets state.recovery_active true so AiDriver
## takes its own dedicated full-authority steering path (see ai_driver.gd's
## class doc WRONG-WAY RECOVERY section for exactly what that suppresses:
## lateral/apex targeting, steer damping, the slide floor, and slide intent
## itself).
##
## FASTER UNSTICK (Task 2b point 2). The OLD tumbling stuck window's
## worst-case detection latency was ALMOST 2x respawn_stuck_after_s: a kart
## that becomes wedged the instant AFTER a window's own anchor reset has to
## wait through nearly one full window before the anchor even reflects the
## wedge, then a SECOND full window before the next close checks it. Fixed
## here by HALVING THE ANCHOR PERIOD rather than adding a sliding ring
## buffer -- _check_stuck_and_respawn checks every `respawn_stuck_after_s *
## ScalarMathType.HALF` seconds instead of every full respawn_stuck_after_s,
## against a stuck-speed threshold scaled down by the SAME half-period (
## respawn_stuck_speed_mps * half_period_s) -- SAME PRODUCT BOUND, just
## evaluated twice as often: the implied minimum average speed
## (threshold_m / period_s = respawn_stuck_speed_mps) is IDENTICAL to
## before, only the CHECK FREQUENCY doubles. This halves the worst-case
## detection latency from ~2x respawn_stuck_after_s down to ~1x it, with no
## new tuning field and no ring-buffer bookkeeping -- the simpler of the two
## designs the task brief offered ("halved anchor with same product bound"),
## chosen over a sliding window of progress samples because it reuses the
## EXACT SAME tumbling-window mechanism (anchor + elapsed, re-anchor on
## close) fix-wave HIGH-1 already established, just retuned, rather than
## introducing a second, structurally different detection mechanism
## alongside it.
##
## BOUNDED RECOVERY RETRIES. A window that closes stuck (net progress below
## the half-period threshold) no longer respawns UNCONDITIONALLY: if
## _recovery_was_active_this_window is ALSO true (recovery was actively
## steering to fix a wrong-facing kart at SOME point during the window now
## closing -- see the fix-round-1 doc above for why this, not the
## instantaneous _recovery_active, is the correct signal) AND _recovery_
## attempts is still below ai.recovery_max_attempts, this window's closure
## is treated as ONE recovery attempt -- incremented, the window re-
## anchored and given another half-period to work, and the flag cleared
## (so the NEXT window starts with a clean slate, not carrying forward
## "recovery was active" from an episode already accounted for), rather
## than teleporting the kart away mid-recovery. Once _recovery_attempts
## reaches ai.recovery_max_attempts, the NEXT closing-while-stuck-and-
## recovery-touched window respawns like any other -- so a kart that stays
## both stuck AND wrong-facing for more than (recovery_max_attempts + 1)
## half-periods still gets the safety net, never an infinite retry loop.
## A window that closes stuck WITHOUT recovery ever having been active
## during it (the ORIGINAL "wall-stuck, correctly facing" case fix-wave
## HIGH-1 already handled) is completely UNCHANGED: it respawns on its
## very first closing window, exactly as before this task -- the retry
## leniency applies ONLY to windows recovery actually touched.
##
## is_recovering() exposes _recovery_active for the identical "observe the
## safety net precisely, don't infer it from noisy progress deltas" reason
## respawn_count()/total_progress_m() are already exposed.
##
## STUCK RESPAWN, once a window closes below the stuck threshold: teleport
## to spine.point_at_progress(follower.total_progress_m() -
## respawn_drop_gap_m), Y raised by RaceTuning.respawn_drop_height_m (the
## first real consumer of this previously-unread field -- see the spec's
## Recorded-debts #3), facing spine.tangent_at_progress() there via
## KartController.set_yaw_degrees() (the SAME seeding path race_session.gd's
## own spawn placement uses: place the transform, then seed yaw as an
## independent step). reset_speed() clears the motor's stale forward/
## vertical speed; follower.reset() and driver.reset() are called with the
## SAME target total (preserving lap count -- see SpineFollower.reset()'s
## own "resume mid-race" semantics) so cross-kart standings never see a
## fabricated near-full-lap regression, and clear AiDriver's edge memory per
## its own class doc ("e.g. Task 4's stuck-kart respawn path").
##
## FORCE-CLEARING AN ACTIVE SLIDE (fix round 1, reviewer follow-up on the
## same finding): the East-turn repro that motivated the displacement fix
## above gets stuck WHILE mid-slide (is_sliding() stays true for many
## seconds straight, bouncing against the inner wall) -- the original
## respawn path only reset motor speed/yaw and left the real
## DriftStateMachine's _sliding/_hop_held state completely untouched, so a
## freshly-teleported kart would still report is_sliding() true and keep
## adding slide_yaw_bonus_degrees_per_s of extra yaw every tick, right after
## being dropped onto a clean line. KartController has no direct public
## "cancel the slide" proxy, but set_run_active(false) already calls
## DriftStateMachine.cancel_slide() as one of its side effects (see
## kart_controller.gd's own doc) -- bouncing false then immediately back to
## true (both calls synchronous, no tick runs in between, so nothing ever
## observes the kart in "race finished" mode) reuses that existing public
## surface to force-clear the slide/hop-held latch without adding a new
## method whose only caller would be this one teleport path.
## respawn_count() (a plain running counter, incremented here) is exposed so
## a caller -- notably this suite's own East-turn regression-lock test --
## can observe "did the safety net actually fire" precisely, instead of
## inferring it from noisy progress deltas.
##
## RESPAWN-ONTO-PLAYER AVOIDANCE (fix-wave MEDIUM-4). Before committing to
## the centerline drop point above, _clear_of_other_karts() checks it
## against every OTHER kart's CURRENT position (horizontal-only, same
## flatten-to-XZ shape the stuck detector's own fix-round-1 displacement
## check used) -- a stuck-respawn must never teleport this kart on top of
## the player or another AI kart that happens to be sitting right there.
## ACCESS: this agent has no reach into RaceSession's own kart roster, so
## the session hands it a Callable at configure() (other_kart_positions_
## getter, optional, defaults to an invalid Callable -- every existing
## caller that never passes one keeps the exact pre-fix behavior, no
## avoidance step at all) returning every OTHER kart's global_position; see
## race_session.gd's own _spawn_ai_karts() for how it is built and bound per
## kart. This mirrors player_progress_getter's own established shape
## (binding contract 3) rather than reaching past the agent into physics
## overlap queries or a new controller-level proxy -- the session already
## owns the one place that knows about every kart, the same reason it
## already owns player_progress_getter.
## BLOCKING RADIUS / STEP SIZE: "within about one kart-length" (the brief's
## own phrasing) reads as this kart's own collision box's Z extent (see
## _read_kart_extents(), kart.tscn's BoxShape3D size = (width, height,
## length)); the lateral nudge steps in increments of that SAME box's X
## extent (kart-WIDTH steps) -- both read from the real scene once at
## configure() time rather than a literal, per this file's own no-bare-
## literal rule. A kart with no readable CollisionShape3D (bare test
## fixtures that construct a plain CharacterBody3D.new()) reads both as
## 0.0, which safely disables this whole step rather than guessing.
## SEARCH: tries the centerline point first (the common case: nothing is
## there), then steps outward in kart-width increments alternating right/
## left, capped at the widest lateral offset any already-authored AI slot
## legitimately sits at (opponent_count/2 slots * lateral_slot_spacing_m --
## see MEDIUM-3's grid-slot fix, which proved that whole range fits both
## real tracks' own road width) so this can never push a kart somewhere
## MEDIUM-3 didn't already verify is on the road. If every step in that
## bounded range is still blocked (pathological -- would need the full AI
## grid plus the player all crowded onto the exact same short stretch), it
## falls back to the plain centerline point rather than searching forever
## or picking something outside the proven-safe range.

const AiDriverType := preload("res://src/racing/ai/ai_driver.gd")
const SpineFollowerType := preload("res://src/racing/track/spine_follower.gd")
const ScalarMathType := preload("res://src/core/scalar_math.gd")

var _kart: CharacterBody3D
var _spine: TrackSpine
var _ai_tuning: AiTuning
var _kart_tuning: KartTuning
var _race_tuning: RaceTuning
var _slot_index: int
var _player_progress_getter: Callable
# Fix-wave MEDIUM-4: optional -- see configure()'s own doc and the class
# doc's RESPAWN-ONTO-PLAYER AVOIDANCE section below.
var _other_kart_positions_getter: Callable
# Task 5 (CTR R4 items): all three optional -- see configure()'s own doc and
# the class doc's ITEM WIRING section.
var _item_tuning: ItemTuning
var _item_targets_getter: Callable
var _use_item_dispatcher: Callable

var _driver: RefCounted
var _follower: RefCounted
var _lateral_target_m: float
# Fix-wave MEDIUM-4: this kart's own collision extents, read once at
# configure() (see _read_kart_extents()) -- 0.0 when unreadable (a test
# fixture with no CollisionShape3D child), which safely disables the
# respawn-onto-player avoidance below rather than guessing a literal.
var _kart_length_m: float
var _kart_width_m: float

var _stuck_window_anchor_total_progress_m: float
var _stuck_window_elapsed_s: float
var _respawn_count: int
var _hop_release_pending: bool
# Task 2b (CTR R7, OPERATOR PRIORITY) -- see the class doc's own WRONG-WAY
# RECOVERY/FASTER UNSTICK sections.
var _recovery_active: bool
var _recovery_heading_error_elapsed_s: float
var _recovery_attempts: int
# Fix round 1 (reviewer MEDIUM, SAFETY-NET STARVATION) -- true whenever
# recovery was active at ANY point during the stuck window currently
# accumulating (set every tick _recovery_active is true, cleared only
# where the stuck window itself resets -- see _check_stuck_and_respawn's
# own doc for why this, not the instantaneous _recovery_active, is what
# gates a window's retry-leniency).
var _recovery_was_active_this_window: bool
# Task 5: real wall-clock timer this agent owns for AiDriver's own
# item_cooldown_ready input -- see the class doc's ITEM WIRING section for
# why the timer lives here and not in the (delta_s-less) driver.
var _item_cooldown_elapsed_s: float
var _configured: bool
# See the class doc's RUN-ACTIVE GATE section. Starts true so a kart that is
# active from its very first tick (the normal case) never misreads tick 1 as
# a "reactivation".
var _was_run_active: bool = true


## RUN-ACTIVE GATE (Task 5, CTR R3 integration, BINDING CONTRACT 1). Every
## _physics_process tick first checks kart.is_run_active() -- when false
## (RaceSession freezes every kart at the finish line via set_run_active(
## false), see race_session.gd's own finish handling) this entire method is a
## no-op: no steer/hop/speed_scale calls, and critically, NO stuck-window
## accumulation either. Without the second half of that, a frozen kart whose
## position legitimately stops changing (it is deliberately parked) would
## read EXACTLY like a wedged one once _stuck_window_elapsed_s crosses
## respawn_stuck_after_s, and _respawn()'s own set_run_active(false) ->
## set_run_active(true) bounce (see FORCE-CLEARING AN ACTIVE SLIDE below)
## would silently reactivate it seconds after the race was supposed to have
## frozen it solid -- a real, reviewer-probe-confirmed resurrection bug.
##
## _was_run_active tracks the PREVIOUS tick's active state so a
## false -> true transition (reactivation) can be caught as an edge: the
## stuck window is re-anchored fresh right then (anchor = current follower.
## total_progress_m(), elapsed = 0.0) rather than either (a) carrying
## forward however much time accumulated while frozen (which would
## immediately misread the frozen gap itself as "hasn't moved in ages" and
## fire a false-positive respawn on the very next qualifying tick) or (b)
## comparing against a stale pre-freeze anchor total. This mirrors _check_
## stuck_and_respawn's own "genuinely progressing kart always gets a fair,
## un-poisoned window" rationale one
## level up: a kart coming OFF a freeze deserves the same fresh start a kart
## that just cleared its own stuck threshold gets.
##
## Fix round 1 (reviewer [MEDIUM]): configure() now verifies the SpineFollower
## it just built is actually usable (spine.length_m() > 0, mirrored by
## SpineFollower.is_valid() -- see spine_follower.gd's own configure() doc)
## before committing to _configured = true. A TrackSpine with no markers (or
## any other zero/negative-length degenerate) previously left this agent
## "configured" but silently driving off of a follower that fails closed to
## 0.0 forever -- steer/lookahead/curvature would all be computed from a
## permanently-wrong progress=0.0 instead of anything real. Failing closed
## here instead (push_error, _configured stays false, every _physics_process
## tick after is a no-op) matches AiDriver's/SpineFollower's own fail-closed
## shape one layer up, and is loud about it immediately at configure() time
## rather than silently misbehaving forever.
func configure(
	kart: CharacterBody3D,
	spine: TrackSpine,
	ai_tuning: AiTuning,
	kart_tuning: KartTuning,
	race_tuning: RaceTuning,
	slot_index: int,
	player_progress_getter: Callable,
	other_kart_positions_getter: Callable = Callable(),
	# Task 5 (CTR R4 items): see the class doc's ITEM WIRING section.
	item_tuning: ItemTuning = null,
	item_targets_getter: Callable = Callable(),
	use_item_dispatcher: Callable = Callable()
) -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_kart = kart
	_spine = spine
	_ai_tuning = ai_tuning
	_kart_tuning = kart_tuning
	_race_tuning = race_tuning
	_slot_index = slot_index
	_player_progress_getter = player_progress_getter
	_other_kart_positions_getter = other_kart_positions_getter
	_item_tuning = item_tuning
	_item_targets_getter = item_targets_getter
	_use_item_dispatcher = use_item_dispatcher

	var extents := _read_kart_extents()
	_kart_width_m = extents.x
	_kart_length_m = extents.z

	_driver = AiDriverType.new()
	# Task 4 (CTR R6): slot_index forwarded straight through -- see ai_
	# driver.gd's own class doc PERSONALITY section for what it unlocks
	# (aggression/skill-jitter, both deterministic functions of this value).
	_driver.configure(ai_tuning, kart_tuning, item_tuning, slot_index)

	_follower = SpineFollowerType.new()
	_follower.configure(spine.length_m())
	if not _follower.is_valid():
		push_error(
			(
				"AiKartAgent.configure: TrackSpine.length_m() was not "
				+ "positive (got %s) -- failing closed: this agent will not "
				+ "process until reconfigured with a valid spine."
			) % spine.length_m()
		)
		_configured = false
		return
	_follower.reset(spine.progress_for_position(kart.global_position))

	_lateral_target_m = _compute_lateral_target_m()
	_stuck_window_anchor_total_progress_m = _follower.total_progress_m()
	_stuck_window_elapsed_s = 0.0
	_respawn_count = 0
	_hop_release_pending = false
	# Task 2b (CTR R7, OPERATOR PRIORITY) -- a fresh driver starts with no
	# recovery state armed, same as every other edge/timer field here.
	_recovery_active = false
	_recovery_heading_error_elapsed_s = 0.0
	_recovery_attempts = 0
	_recovery_was_active_this_window = false
	# Task 5: already-ready at configure() time -- see the class doc's ITEM
	# WIRING section for why this seeds from the cooldown duration itself
	# (no new literal) rather than starting the very first pickup out on an
	# artificial delay. Harmless when _item_tuning is null (item_cooldown_
	# ready() below reads _item_tuning != null first).
	_item_cooldown_elapsed_s = _item_tuning.ai_item_use_cooldown_s if _item_tuning != null else 0.0
	_was_run_active = true
	_configured = true


## This kart's own continuous, never-wrapping progress -- exposed so a
## caller (Task 5's standings/placement, or this suite's own tests) never
## has to reach past this agent into its private SpineFollower. 0.0 before a
## successful configure(), matching SpineFollower's own fail-closed shape.
func total_progress_m() -> float:
	return _follower.total_progress_m() if _configured else 0.0


## How many times the stuck-detector has force-teleported this kart --
## exposed for the same "observe the safety net precisely, don't infer it
## from noisy progress deltas" reason total_progress_m() is. 0 before a
## successful configure() (nothing has run yet) and 0 after one that never
## needed to respawn -- both indistinguishable from "never got stuck",
## which is the correct reading either way.
func respawn_count() -> int:
	return _respawn_count


## Whether wrong-way recovery is currently armed -- exposed for the same
## "observe the safety net precisely" reason respawn_count()/total_
## progress_m() are already exposed. See the class doc's own WRONG-WAY
## RECOVERY section. false before a successful configure().
func is_recovering() -> bool:
	return _recovery_active if _configured else false


func _physics_process(delta_s: float) -> void:
	if not _configured:
		return

	# See the class doc's RUN-ACTIVE GATE section (Task 5 binding contract).
	if not bool(_kart.call("is_run_active")):
		_was_run_active = false
		return
	if not _was_run_active:
		_stuck_window_anchor_total_progress_m = _follower.total_progress_m()
		_stuck_window_elapsed_s = 0.0
		# Task 2b (CTR R7, OPERATOR PRIORITY): a kart coming off a freeze
		# deserves the same fresh start the stuck window itself gets one line
		# up -- no stale pre-freeze recovery arming/attempt count carried
		# forward.
		_recovery_active = false
		_recovery_heading_error_elapsed_s = 0.0
		_recovery_attempts = 0
		_recovery_was_active_this_window = false
		_was_run_active = true

	if _hop_release_pending:
		_kart.call("hop_released")
		_hop_release_pending = false

	# Task 5: real wall-clock accumulation for item_cooldown_ready -- see the
	# class doc's ITEM WIRING section. Gated behind the same RUN-ACTIVE GATE
	# early-returns above (a frozen kart's cooldown must not keep ticking
	# either, matching the stuck-window's own "no accumulation while frozen"
	# contract one section up), though nothing currently reads this while
	# frozen anyway since decide() never runs past this point.
	_item_cooldown_elapsed_s += delta_s

	var kart_pos: Vector3 = _kart.global_position
	var raw_progress := _spine.progress_for_position(kart_pos)
	# Task 2b (CTR R7, OPERATOR PRIORITY): updates _recovery_active from THIS
	# tick's own live heading error -- must run BEFORE the stuck-window check
	# below, so a closing window always reads the current, not one-tick-
	# stale, recovery state. See the class doc's own WRONG-WAY RECOVERY
	# section.
	_update_recovery_state(delta_s, raw_progress)

	if _check_stuck_and_respawn(delta_s):
		return

	_follower.update(raw_progress, _max_follower_step_m(delta_s))
	var progress: float = _follower.lap_progress_m()

	var decision: Dictionary = _driver.decide(_assemble_state(kart_pos, progress))
	_route_decision(decision)


func _assemble_state(kart_pos: Vector3, progress: float) -> Dictionary:
	var speed_mps: float = _kart.call("speed_mps")
	var lookahead_m := _ai_tuning.lookahead_min_m + speed_mps * _ai_tuning.lookahead_speed_gain_s

	var forward: Vector3 = -_kart.global_transform.basis.z
	# Task 2b (CTR R7, OPERATOR PRIORITY): while recovering, aim at a much
	# NEARER point on the spine -- own progress + ai.lookahead_min_m itself
	# (no new literal; reuses the existing lookahead floor as "a short
	# forward distance", per the class doc's own WRONG-WAY RECOVERY section)
	# instead of the normal speed-scaled lookahead, which for a kart facing
	# backward can sit many meters behind the kart's own nose and produce a
	# near-180-degree pursuit angle that is numerically valid but a poor
	# target to spin the kart around toward. curvature_ahead below keeps
	# using the NORMAL lookahead_m regardless -- AiDriver's own recovery path
	# never reads it (see its class doc's WRONG-WAY RECOVERY section), so
	# there is no reason to distort the cornering/brake formula's own input
	# while recovering.
	var lookahead_point := _spine.point_at_progress(
		progress + (_ai_tuning.lookahead_min_m if _recovery_active else lookahead_m)
	)
	var curvature_ahead := _spine.curvature_at_progress(progress, lookahead_m)

	var tangent_now := _spine.tangent_at_progress(progress)
	var right := tangent_now.cross(Vector3.UP)
	var centerline_point := _spine.point_at_progress(progress)
	var actual_lateral_m := (kart_pos - centerline_point).dot(right)
	var lateral_error_m := _lateral_target_m - actual_lateral_m

	var player_progress := 0.0
	if _player_progress_getter.is_valid():
		player_progress = float(_player_progress_getter.call())
	var band_gap_m: float = player_progress - _follower.total_progress_m()

	return {
		"position": kart_pos,
		"forward": forward,
		"speed_mps": speed_mps,
		"is_sliding": bool(_kart.call("is_sliding")),
		"boost_window_open": bool(_kart.call("boost_window_open")),
		"lookahead_point": lookahead_point,
		"curvature_ahead": curvature_ahead,
		"lateral_error_m": lateral_error_m,
		# Task 4 (CTR R6): the RAW slot target (not the error) -- see ai_
		# driver.gd's own INPUT STATE section (slot_lateral_target_m
		# paragraph) and APEX LATERAL TARGETING section for why the apex
		# blend needs this in addition to lateral_error_m.
		"slot_lateral_target_m": _lateral_target_m,
		"band_gap_m": band_gap_m,
		# Task 5 (CTR R4 items) -- see the class doc's ITEM WIRING section.
		"held_item": _held_item(),
		"target_gap_ahead_m": _target_gap_ahead_m(),
		"item_cooldown_ready": _item_cooldown_ready(),
		# Task 2b (CTR R7, OPERATOR PRIORITY) -- see ai_driver.gd's own class
		# doc WRONG-WAY RECOVERY section for what this switches on.
		"recovery_active": _recovery_active,
	}


## See the class doc's ITEM WIRING/STATE ASSEMBLY section: needs no item
## wiring at all, only item_slot() itself -- guarded by has_method() rather
## than any of this agent's own optional item fields.
func _held_item() -> StringName:
	if not _kart.has_method("item_slot"):
		return &"none"
	var slot: Object = _kart.call("item_slot")
	if slot == null:
		return &"none"
	return StringName(slot.call("held_item"))


## See the class doc's ITEM WIRING/STATE ASSEMBLY section. Re-scans item_
## targets_getter's own snapshot fresh every tick (unlike missile.gd's own
## ONE-TIME launch lock) for the nearest OTHER kart with a strictly-positive
## progress margin ahead of this one -- the identical search missile.gd's
## own configure() already performs against the exact same snapshot shape.
## INF when the getter is unset/invalid or nothing is strictly ahead.
func _target_gap_ahead_m() -> float:
	if not _item_targets_getter.is_valid():
		return INF
	var snapshot: Array = _item_targets_getter.call()
	var self_progress: float = _follower.total_progress_m()
	var best_gap_m := INF
	for entry: Variant in snapshot:
		var other_kart: CharacterBody3D = entry.get("kart")
		if other_kart == null or other_kart == _kart:
			continue
		var margin_m: float = float(entry.get("progress", 0.0)) - self_progress
		if margin_m > 0.0 and margin_m < best_gap_m:
			best_gap_m = margin_m
	return best_gap_m


## See the class doc's ITEM WIRING section for why this timer lives on this
## agent rather than on the (delta_s-less) AiDriver. false whenever _item_
## tuning was never wired -- there is no cooldown DURATION to measure
## _item_cooldown_elapsed_s against, so this fails closed rather than
## reading an unconfigured/zero threshold as "always ready".
func _item_cooldown_ready() -> bool:
	return _item_tuning != null and _item_cooldown_elapsed_s >= _item_tuning.ai_item_use_cooldown_s


func _route_decision(decision: Dictionary) -> void:
	_kart.call("steer", float(decision.get("steer", 0.0)))
	_kart.call("set_brake", bool(decision.get("brake", false)))
	if bool(decision.get("hop", false)):
		_kart.call("hop_pressed")
		_hop_release_pending = true
	if bool(decision.get("boost_tap", false)):
		_kart.call("boost_tap")
	_kart.call("set_speed_scale", float(decision.get("speed_scale", 1.0)))
	# Task 5: see the class doc's OUTPUT ROUTING/use_item paragraph.
	if bool(decision.get("use_item", false)) and _use_item_dispatcher.is_valid():
		_use_item_dispatcher.call(_kart)
		_item_cooldown_elapsed_s = 0.0


## Per-tick clamp for this kart's own SpineFollower.update() -- the true
## physical ceiling on how far a kart can travel in one tick, derived
## entirely from tuning (no literal): (top_speed_mps + boost_speed_bonus_mps)
## is KartMotor's own maximum possible forward-speed TARGET (see
## kart_motor.gd's tick()), and (1.0 + rubber_band_boost_max_ratio) is the
## most that target can then be scaled up by (see kart_motor.gd's own
## set_speed_scale() doc and ai_driver.gd's RUBBER BAND section for the cap).
## Multiplying both in is the actual worst-case top speed this specific kart
## can ever be commanded to -- using only top_speed_mps (as the brief's own
## looser phrasing, "kart top speed x delta x a safety factor", might
## suggest) would UNDERESTIMATE it during a boosted, rubber-banding tick and
## risk clamping away real forward movement into a false seam-ambiguity
## read.
func _max_follower_step_m(delta_s: float) -> float:
	var max_target_speed_mps := (
		(_kart_tuning.top_speed_mps + _kart_tuning.boost_speed_bonus_mps)
		* (1.0 + _ai_tuning.rubber_band_boost_max_ratio)
	)
	return max_target_speed_mps * delta_s


## See the class doc's STUCK DETECTION section for why this is a tumbling
## NET SPINE PROGRESS window rather than a net-displacement or instantaneous-
## velocity check, and its FASTER UNSTICK section (Task 2b, CTR R7 --
## OPERATOR PRIORITY) for why the anchor PERIOD below is respawn_stuck_
## after_s HALVED (ScalarMathType.HALF, no new tuning field) rather than the
## full duration -- same product bound (stuck_threshold_m / period_s is
## still exactly respawn_stuck_speed_mps), checked twice as often, halving
## the old worst-case ~2x-window detection latency. Reads follower.total_
## progress_m() as it stood at the END of the PREVIOUS tick's update (this
## tick's own follower.update() has not run yet -- see _physics_process's
## own ordering) -- a one-tick staleness that is immaterial against a
## multi-second window. Returns true (and has already respawned) exactly on
## the tick a closing window reads as stuck AND recovery has exhausted its
## own bounded retries (or was never armed); the caller must skip the rest
## of that tick's normal drive logic, since _respawn() has just invalidated
## the kart's position/the follower's own total out from under it.
func _check_stuck_and_respawn(delta_s: float) -> bool:
	_stuck_window_elapsed_s += delta_s
	var window_period_s := _stuck_window_period_s()
	if _stuck_window_elapsed_s < window_period_s:
		return false

	var net_progress_m: float = (
		float(_follower.total_progress_m()) - _stuck_window_anchor_total_progress_m
	)
	var stuck_threshold_m := _stuck_progress_threshold_m(window_period_s)
	if net_progress_m < stuck_threshold_m:
		# Task 2b (CTR R7, OPERATOR PRIORITY): BOUNDED RECOVERY RETRIES -- see
		# the class doc's own section by that name. A window closing stuck
		# WHILE recovery was active AT ANY POINT during it gets up to
		# recovery_max_attempts retries (re-anchored, not respawned) before
		# falling through to the unconditional respawn below; a window
		# closing stuck WITHOUT recovery ever having been active during it
		# (the original "wall-stuck, correctly facing" case) is completely
		# unchanged -- it respawns on this very first check, exactly as
		# before this task.
		#
		# Fix round 1 (reviewer MEDIUM, SAFETY-NET STARVATION):
		# _recovery_was_active_this_window, NOT the instantaneous _recovery_
		# active, is what gates this -- see that field's own doc and _update_
		# recovery_state()'s doc for why checking only "is recovery active
		# RIGHT NOW" was exploitable (recovery can clear moments before this
		# exact tick even after being active for most of the window) and why
		# resetting the window on every heading-clear (the original,
		# replaced design) was ALSO exploitable the other way (a kart whose
		# yaw oscillates across the hysteresis band faster than window_
		# period_s never lets the window close at all). This flag is set
		# once per tick recovery is active (see _update_recovery_state) and
		# cleared only here and in the "not stuck" branch below -- i.e.
		# exactly when the window itself resets -- so it accurately answers
		# "was this window's own dip touched by a recovery episode" without
		# depending on exact arm/clear timing relative to this tick.
		if _recovery_was_active_this_window and _recovery_attempts < int(_ai_tuning.recovery_max_attempts):
			_recovery_attempts += 1
			_stuck_window_anchor_total_progress_m = _follower.total_progress_m()
			_stuck_window_elapsed_s = 0.0
			_recovery_was_active_this_window = false
			return false
		_respawn()
		return true

	_recovery_attempts = 0
	_stuck_window_anchor_total_progress_m = _follower.total_progress_m()
	_stuck_window_elapsed_s = 0.0
	_recovery_was_active_this_window = false
	return false


## The stuck-window's own halved anchor period -- see the class doc's
## FASTER UNSTICK section. Factored out so _check_stuck_and_respawn's own
## two call sites (period and the threshold derived from it) never risk
## drifting apart.
func _stuck_window_period_s() -> float:
	return _ai_tuning.respawn_stuck_after_s * ScalarMathType.HALF


## The minimum net progress (m) that period_s seconds at ai.respawn_stuck_
## speed_mps represents -- the "stuck" bar _check_stuck_and_respawn checks
## net progress against.
func _stuck_progress_threshold_m(period_s: float) -> float:
	return _ai_tuning.respawn_stuck_speed_mps * period_s


## See the class doc's WRONG-WAY RECOVERY section for the full sustained-
## trigger/hysteresis contract this implements. Must run every tick (not
## only while already armed) so the elapsed-time accumulation itself is
## real wall-clock time, matching every other timer this agent owns (item
## cooldown, the stuck window).
##
## Fix round 1 (reviewer MEDIUM, SAFETY-NET STARVATION). The original
## version of this function unconditionally re-anchored the stuck window
## and zeroed _recovery_attempts on EVERY heading-based clear -- correct
## for a kart that genuinely realigned, but exploitable by a kart whose own
## yaw oscillates across the 60/120-degree hysteresis band FASTER than the
## stuck window's own halved period (_stuck_window_period_s()): every
## spurious clear re-anchored the window before it could ever naturally
## close, so _check_stuck_and_respawn's own stuck-check never even ran --
## the safety net was starved indefinitely (reviewer's own scripted repro:
## an 0.85s arm/clear cycle, 20.4s, 0 respawns, progress pinned; see
## test_ai_kart_agent.gd's own test_yaw_oscillation_faster_than_the_stuck_
## window_period_still_respawns_within_a_bounded_time, which pins this
## exact scenario). A first attempted fix (gating the reset on "real
## progress made since recovery armed") turned out to be WRONG in a
## different way: the hysteresis EXIT is a pure heading check, so a
## genuine recovery typically clears within a fraction of a second of
## arming, long before enough real distance has accumulated to clear any
## meaningful progress bar measured AT the clear instant -- that gate
## reintroduced the ORIGINAL false-positive bug for the very case it most
## needed to protect (see git history / this task's own report for the
## measured trace).
##
## THE ACTUAL FIX: this function no longer touches the stuck window OR
## _recovery_attempts AT ALL, on either arm or clear -- it owns ONLY the
## heading-based arm/clear state machine (_recovery_active) and, while
## active, marks _recovery_was_active_this_window true. The stuck window's
## own reset cadence is therefore COMPLETELY DECOUPLED from recovery arm/
## clear events: it always closes on its own unmodified schedule (see
## _check_stuck_and_respawn), which both (a) bounds the starvation case (an
## oscillating kart can no longer prevent the window from ever closing) and
## (b) still correctly grants a genuinely-recovering kart leniency (the
## window that happens to close WHILE OR SHORTLY AFTER a recovery episode
## ran sees _recovery_was_active_this_window true and gets a retry rather
## than an immediate respawn, giving the kart a full additional window
## period to build up real, unambiguous progress before being judged again).
func _update_recovery_state(delta_s: float, raw_progress: float) -> void:
	var heading_error_degrees := _heading_error_degrees(raw_progress)
	if _recovery_active:
		_recovery_was_active_this_window = true
		if heading_error_degrees < _ai_tuning.recovery_heading_error_degrees * ScalarMathType.HALF:
			_recovery_active = false
			_recovery_heading_error_elapsed_s = 0.0
		return

	if heading_error_degrees > _ai_tuning.recovery_heading_error_degrees:
		_recovery_heading_error_elapsed_s += delta_s
		if _recovery_heading_error_elapsed_s >= _ai_tuning.recovery_trigger_s:
			_recovery_active = true
			_recovery_was_active_this_window = true
	else:
		_recovery_heading_error_elapsed_s = 0.0


## Unsigned heading error (degrees, flattened to XZ) between the kart's own
## current facing and the spine's tangent at its current (raw, unwrapped)
## progress -- see the class doc's own WRONG-WAY RECOVERY section for why
## this is unsigned (recovery only cares HOW wrong the facing is, not which
## way, the same way ai_driver.gd's own CORNERING/BRAKE formula reads
## curvature_ahead through absf()) and why a degenerate zero-length
## flattened vector reads as 0.0 rather than crashing on Vector3.angle_to's
## own undefined-for-zero-vectors case.
func _heading_error_degrees(raw_progress: float) -> float:
	var tangent := _spine.tangent_at_progress(raw_progress)
	var forward: Vector3 = -_kart.global_transform.basis.z
	var flat_tangent := Vector3(tangent.x, 0.0, tangent.z)
	var flat_forward := Vector3(forward.x, 0.0, forward.z)
	if flat_tangent.is_zero_approx() or flat_forward.is_zero_approx():
		return 0.0
	return rad_to_deg(flat_forward.angle_to(flat_tangent))


## See the class doc's LATERAL SLOT CENTERING section.
func _compute_lateral_target_m() -> float:
	var total_karts := _ai_tuning.opponent_count + 1.0
	var centered_slot := float(_slot_index) - (total_karts - 1.0) * ScalarMathType.HALF
	return centered_slot * _ai_tuning.lateral_slot_spacing_m


## See the class doc's STUCK RESPAWN and FORCE-CLEARING AN ACTIVE SLIDE
## sections.
func _respawn() -> void:
	_respawn_count += 1

	var target_total: float = _follower.total_progress_m() - _ai_tuning.respawn_drop_gap_m
	var length := _spine.length_m()
	var wrapped_target := fposmod(target_total, length) if length > 0.0 else 0.0

	var point := _spine.point_at_progress(wrapped_target)
	var tangent := _spine.tangent_at_progress(wrapped_target)
	# See the class doc's RESPAWN-ONTO-PLAYER AVOIDANCE section.
	point = _clear_of_other_karts(point, tangent)

	_kart.global_position = point + Vector3.UP * _race_tuning.respawn_drop_height_m
	if not tangent.is_zero_approx():
		var facing_degrees := rad_to_deg(Vector3.FORWARD.signed_angle_to(tangent, Vector3.UP))
		_kart.call("set_yaw_degrees", facing_degrees)
	_kart.call("reset_speed")
	# Fix round 1 (reviewer follow-up): force-clears DriftStateMachine's own
	# _sliding/_hop_held state through the only public surface that reaches
	# it (see the class doc's FORCE-CLEARING AN ACTIVE SLIDE section) -- a
	# kart teleported off a wedge it was still actively sliding against must
	# not keep adding slide yaw on its fresh, clean line.
	_kart.call("set_run_active", false)
	_kart.call("set_run_active", true)

	_follower.reset(target_total)
	_driver.reset()
	_stuck_window_anchor_total_progress_m = _follower.total_progress_m()
	_stuck_window_elapsed_s = 0.0
	_hop_release_pending = false
	# Task 2b (CTR R7, OPERATOR PRIORITY): a kart just dropped onto a fresh
	# line, facing the tangent, has no business remembering an armed
	# recovery/attempt count from wherever it got stuck -- same "fresh slate"
	# reset every other per-episode field on this line already gets.
	_recovery_active = false
	_recovery_heading_error_elapsed_s = 0.0
	_recovery_attempts = 0
	_recovery_was_active_this_window = false


## See the class doc's RESPAWN-ONTO-PLAYER AVOIDANCE section. Returns the
## centerline point unchanged when there is nothing to check against (no
## getter wired -- the default for every caller that never passes one, see
## configure()'s own doc -- or no readable kart extents, or a degenerate
## zero tangent with no sensible lateral direction to offset along).
func _clear_of_other_karts(point: Vector3, tangent: Vector3) -> Vector3:
	if not _other_kart_positions_getter.is_valid():
		return point
	if tangent.is_zero_approx() or _kart_length_m <= 0.0 or _kart_width_m <= 0.0:
		return point
	var other_positions: Array = _other_kart_positions_getter.call()
	if _point_is_clear_of(point, other_positions):
		return point

	var right := tangent.cross(Vector3.UP)
	# The widest lateral offset any legitimately-placed AI kart already sits
	# at (slot_index = opponent_count, the far end of _compute_lateral_
	# target_m()'s own centered range) -- a tuning-derived bound on how far
	# this nudge may push the drop point, so it can only ever land somewhere
	# already proven to fit the road (see MEDIUM-3's grid-slot fix), never
	# off it. No new literal: HALF via ScalarMathType, same as _compute_
	# lateral_target_m()'s own derivation one function up.
	var max_offset_m := _ai_tuning.opponent_count * ScalarMathType.HALF * _ai_tuning.lateral_slot_spacing_m
	var step_index := 1
	while float(step_index) * _kart_width_m <= max_offset_m:
		var offset_m := float(step_index) * _kart_width_m
		var candidate_right := point + right * offset_m
		if _point_is_clear_of(candidate_right, other_positions):
			return candidate_right
		var candidate_left := point - right * offset_m
		if _point_is_clear_of(candidate_left, other_positions):
			return candidate_left
		step_index += 1
	# No clear step found within the tuning-derived bound -- best effort:
	# drop at the original centerline point rather than searching forever or
	# picking something outside the proven-safe range.
	return point


## Horizontal-only (flattened to XZ, same rationale as the stuck-detector's
## own fix-round-1 displacement check) proximity test against every OTHER
## kart's current position -- "within about one kart-length" per this fix's
## own brief, using the real collision extents read at configure() rather
## than a literal.
func _point_is_clear_of(point: Vector3, other_positions: Array) -> bool:
	for other_position: Variant in other_positions:
		var other: Vector3 = other_position
		var horizontal := Vector3(
			point.x - other.x,
			0.0,
			point.z - other.z
		).length()
		if horizontal < _kart_length_m:
			return false
	return true


## Reads this kart's own collision extents once at configure() time -- see
## the class doc's RESPAWN-ONTO-PLAYER AVOIDANCE section. Vector3.ZERO (x/z
## both 0.0) when the kart has no BoxShape3D CollisionShape3D child to read
## (a bare test fixture, e.g. a plain CharacterBody3D.new()) -- the caller
## treats a non-positive extent as "cannot compute a meaningful kart-length/
## kart-width, skip the avoidance step entirely" rather than guessing.
func _read_kart_extents() -> Vector3:
	var collision := _kart.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null:
		return Vector3.ZERO
	var box := collision.shape as BoxShape3D
	if box == null:
		return Vector3.ZERO
	return box.size
