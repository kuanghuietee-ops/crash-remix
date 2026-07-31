# CTR-style racing mode — design

Date: 2026-07-30. Operator-approved same day (structure: same repo new mode;
scope: full CTR loop; first track from the island kit). Extends the master
design doc; all its hard rules apply unchanged — no gameplay numbers in code,
tuning provably live, human-only feel gates, every byte original. "CTR-style"
means the PS1 kart-racing *grammar*; no assets, names, tracks or audio from
any shipped game.

## What this is

A kart-racing mode living beside the corridor platformer: `src/racing/`,
`scenes/racing/`, `data/tuning/racing/`, selectable from the existing level
list UI. The platformer is untouched and stays playable. The racer reuses the
proven infrastructure: touch input plumbing, TuningService (new sections),
RailCurveBuilder (looped), blob shadows, HUD/save/deploy pipelines, the
island art kit and palette.

## Kart feel (the product)

Authored arcade physics on CharacterBody3D — no rigid-body simulation. Verbs:

- **Auto-accelerate** (mobile default; stick-down = brake/reverse).
- **Steer** — left floating stick, direct lateral mapping (NO corridor
  magnet; racing input mode bypasses it).
- **Hop** (one right-thumb button); **power-slide** = press hop while
  steering past a threshold to start, then **steer magnitude alone sustains
  it** — drift direction locks at slide start, and the slide keeps going for
  as long as steer stays past the threshold **in either direction**;
  straightening the stick back below the threshold is what ends it. One-thumb
  mobile rationale: original CTR holds a shoulder button (sustain) while
  tapping a face button (boost), which needs two inputs held/tapped at once;
  this game puts hop and boost on the *same* single touch button (CTR
  muscle memory), so that button can no longer be what sustains the slide —
  sustain moves to the steer stick instead, freeing the button for pure taps.
  Because direction stays locked but sustain doesn't care which way the
  stick is pointing, full deflection *against* the locked direction —
  **counter-steering** — keeps the slide alive too, at a smaller yaw rate,
  letting a player widen the drift arc mid-slide (CTR's signature move).
- **Slide-boost** — the CTR signature: while sliding, a boost window meter
  charges; a well-timed BOOST tap (the SAME hop button, re-pressed) fires a
  speed burst instead of a hop; up to **three stacking taps** per slide,
  each window tighter, a mistimed tap ends the slide with no boost, and
  straightening the stick ends the slide (with any earned boost kept if
  that happens at or after the minimum slide duration, forfeited if
  earlier).
- **Start boost** — countdown "3-2-1": throttle already auto-accelerates (see
  Auto-accelerate above), so this is timed on HOP instead — a hold that
  begins in the window right before "GO" fires a launch boost; holding HOP
  continuously from earlier in the countdown and riding it to "GO" bogs
  instead. [Polish-wave correction, R5 (2026-07-31): this bullet originally
  said "throttle timed into the green window", which doesn't match the
  shipped mechanic — see `start_boost_judge.gd`'s own class doc.]
- **Spin-out** on hazard/item hit: control cut, speed dump, brief
  invulnerability after.
- Jump pads / boost pads on track.

Every number lives in `data/tuning/racing/kart.tres` (`KartTuning`) +
`race.tres` (`RaceTuning`) etc., registered in TuningService (fingerprint +
on-device panel + override migration), so kart feel is tuned by thumb.

## Track system

A track is a **closed loop**: a looped Path3D spine built by RailCurveBuilder
(gains closed-curve support), road geometry from kit pieces, walls, ordered
checkpoint gates (Area3D) crossing the full road width, a start/finish line.
Lap counts only when every gate is crossed in order; wrong-way detection from
movement dot spine tangent. Position (R3+) = spine progress + lap.

First track: **Sanity Shores Circuit** — beach/jungle loop from the existing
kit and real-life palette, target 60–90 s/lap, 3 laps.

Author-lint gains track rules: gates ordered and monotonic along the spine,
gate boxes span the road width, a start line exists, spine is closed.

## Camera

New kart chase camera: low and close behind the kart, yaw-follows with lag,
FOV widens with speed (all tuning). Drift angles the view slightly into the
slide. No rail — the kart is the authority.

## AI (phase R3)

Path-following opponents: authored racing line = spine + lateral offset
profile, per-curvature target speeds, CTR-strength rubber-banding
(tuning-capped), hop/slide on tight corners, item use with cooldowns. 5 karts.

## Items (phase R4)

Item boxes → roulette → four items to start: homing missile, shield mask
(blocks one hit), turbo canister, dropped beaker hazard. Hit = spin-out.
Wumpa-juiced variants deferred.

## Race flow (phase R5)

Countdown + start boost, live positions, lap/position HUD, results screen,
one-tap retry. Time trial ships as race-minus-AI with best-time save via the
existing save system -- authored in R2 as the two race scenes' own default
shape (no AI existed yet), then reintroduced in the R3 fix-wave as an
explicit `RaceSession.spawn_opponents` flag (default `true`) once R3 gave
those same two scenes an AI-populated default: four level-list entries now
exist (RACE/TIME TRIAL × Graybox/Sanity Shores), not two AI-only ones -- see
Recorded debts #8.

## Phases and gates

R1 kart physics + racing input + kart camera on a graybox loop (APK).
R2 Sanity Shores Circuit + laps/checkpoints + time trial + HUD (APK).
R3 AI karts. R4 items. R5 race flow/results/positions (APK each).
Kart-feel verdicts are the operator's, on device, by thumb — the agent ships
"ready to test", never "feels right". Pure logic (drift FSM, boost windows,
lap validator, roulette, AI line) is headless-tested; scene wiring is
integration-tested like the platformer.

## Out of scope

Adventure map, multiplayer, more tracks/characters/kart art (graybox kart
until the art ladder gets there), juiced items, weather. The platformer's
roadmap is unchanged.

## Recorded debts (R3+)

Findings from the R1/R2 final fix wave (2026-07-30) that are correctly out of
scope for this pass but must not be forgotten when the phases that touch them
start.

1. ~~**R4-BINDING**: `apply_spin_out()` (kart_controller.gd) only calls
   `KartMotor.apply_spin_out()` — it never cancels `DriftStateMachine`. A hit
   landing mid-slide zeroes the motor's yaw authority but leaves the drift FSM
   still reporting `is_sliding()` true and still boostable, since nothing
   about a spin-out tells it the slide is over (parked Task-3 review finding).
   The R4 (items/hazards) plan MUST add a drift cancel alongside the spin-out,
   plus gate `boost_tap()` so a hit can't be "rewarded" with a boost stacked
   the instant before or during it.~~ **FIXED, R4 Task 1 (2026-07-30):**
   `apply_spin_out()` now also calls `DriftStateMachine.cancel_slide()` (ends
   the slide, zeroes accrued boost/stage/window) plus `hop_released()`
   (clears a hop latched-but-not-yet-sliding right before the hit, which
   `cancel_slide()` alone leaves standing since it is a no-op when nothing is
   sliding); `boost_tap()` and `hop_pressed()` are now gated on the new
   `KartMotor.is_spinning_out()` for the whole `spin_out_duration_s` stun, at
   the controller (`kart_controller.gd`), not the drift FSM. See
   `tests/racing/test_kart_controller.gd`'s R4 Task 1 section.
2. Boost pads / jump pads are listed under "Kart feel" above as a kart verb,
   but no such mechanic exists anywhere in `src/racing/` or `scenes/racing/`
   — Task 8's boost-pad line was deliberately skipped (no track-side trigger,
   no kart-side response). R3+ candidate; needs its own tuning fields and a
   track-authoring rule (author-lint) once built, not just a scene prop.
3. One `RaceTuning` field is authored and validated (registered,
   fingerprinted, panel-editable, rejected if non-positive) but read by
   nothing in `src/racing/`: `checkpoint_tolerance_m`. It exists for a
   checkpoint-crossing tolerance mechanic that hasn't been built yet —
   expected, not a bug, but worth naming so a future pass doesn't assume
   it's already wired because it validates cleanly. (`respawn_drop_height_m`
   was originally the fifth field on this list; Task 4 (R3: AI opponents)
   consumed it — `AiKartAgent`'s stuck-kart respawn teleport raises the kart
   this many meters above the centerline point it drops onto — struck from
   this unread-fields debt as of 2026-07-30. `countdown_step_s`,
   `start_boost_window_s`, and `start_bog_penalty_s` were the other three
   originally named here; all three were consumed by R5 Task 1
   (2026-07-31) — `CountdownTimer`/`StartBoostJudge`
   (`src/racing/flow/countdown_timer.gd`/`start_boost_judge.gd`) read them
   for the real 3-2-1 countdown timing and the start-boost verdict window,
   see `race_session.gd`'s own COUNTDOWN + START BOOST class-doc section —
   struck likewise, leaving `checkpoint_tolerance_m` as the sole remaining
   unread field as of 2026-07-31.)
4. **Known feel-gate note**: `RaceSession._route_input()` samples
   `is_action_pressed(InputIntent.ACTION_JUMP)` once per physics tick and only
   reacts to a change from the previous tick's sampled state (the same
   inherited input-polling architecture the platformer uses). A HOP press and
   release that both land inside the same physics tick's polling window —
   plausible on a touch button under a fast tap — produces no edge at all and
   is silently swallowed. If a human tester reports dropped boost taps or
   missed hops on device, this poll-vs-edge gap is the mechanism to check
   first, not the drift FSM's own timing. (R4: the ITEM button shares the same
   once-per-tick edge sampling and the same swallow window. R5, polish-wave
   addition: the countdown's own pre-GO sampler — `_tick_countdown()`
   feeding `StartBoostJudge.sample()`, race_session.gd — reads the identical
   once-per-tick `is_action_pressed()` level state and shares the same
   swallow window: a HOP press-and-release that both land inside one
   physics tick's polling window is invisible to the start-boost judge too,
   not just to `_route_input()`.)
5. ~~**R3 ships AI opponents WITHOUT item use, by design.** The "AI (phase R3)"
   line above ("...item use with cooldowns. 5 karts.") reads as if item use
   ships in this phase, but items themselves do not exist anywhere in the
   codebase until R4 (see "Items (phase R4)" above and Recorded-debt #2 on
   boost pads) — there is nothing for an AI driver to use yet.
   `AiDriver`/`AiKartAgent` (R3, Tasks 3-4) only ever call
   `steer()`/`set_brake()`/`hop_pressed()`/`hop_released()`/`boost_tap()`/
   `set_speed_scale()`, the same kart-only verbs a human racer has in R1-R3.
   This is an intentional scope split, not a missed line item — the R4 plan
   must add AI item-use once item boxes/roulette actually exist.~~
   **RESOLVED, R4 Task 5 (2026-07-30):** items now exist, and `AiDriver`/
   `AiKartAgent` decide whether/when to use a held one — shield used
   immediately on pickup, missile/turbo/beaker gated by heuristics keyed off
   `held_item`/`target_gap_ahead_m`/`item_cooldown_ready` (see `ai_driver.
   gd`'s own ITEM USE HEURISTICS doc) — and route that decision through the
   SAME `RaceSession.use_item_for()` -> `dispatch_item_use()` entry point
   the player's own ITEM press uses, no privileged AI-only path. Both real
   tracks also now author 6 `ItemBox` instances each (see debt #10 below).
   See `tests/racing/test_race_session.gd`'s `test_seeded_ai_kart_picks_up_
   a_box_rolls_and_uses_a_shield_through_real_dispatch`.
6. ~~**Stuck detector fires on any 3s net-stationary-or-non-progressing AI
   kart — fine in R3, binding on R5.** `AiKartAgent._check_stuck_and_
   respawn()` (ai_kart_agent.gd) respawns any AI kart whose NET SPINE
   PROGRESS (fix-wave HIGH-1: `follower.total_progress_m()`, not raw
   position) gains less than `respawn_stuck_speed_mps * respawn_stuck_
   after_s` (ai.tres: 1.5 m/s × 3.0s) over a rolling window — correct in
   R3, where every AI kart drives itself from tick 1 of `configure()`
   onward, so "not progressing" always means "actually stuck." R5's
   countdown/grid-hold (race flow, not yet built) will legitimately hold
   every kart still at the start line for several seconds before GO fires;
   without an explicit gate, that hold alone would cross the stuck
   threshold and force-respawn the entire AI grid before the race even
   starts. The R5 plan MUST gate `AiKartAgent` (equivalent to Task 5's own
   `is_run_active()` binding contract 1 freeze gate, see race_session.gd's
   `_finish_race()` and ai_kart_agent.gd's RUN-ACTIVE GATE doc) so agents
   do not accumulate stuck-window time — or drive at all — until the
   countdown reaches GO.~~ **RESOLVED, R5 Task 1 (2026-07-31):** the gate
   this debt called for already existed — Task 5's own `is_run_active()`
   binding contract 1 (`ai_kart_agent.gd`'s RUN-ACTIVE GATE section) makes
   the whole of `_physics_process()` a no-op, stuck-window accumulation
   included, whenever a kart is frozen. R5 Task 1 makes every kart —
   AI included — spawn frozen (`set_run_active(false)`, see
   `race_session.gd`'s own COUNTDOWN + START BOOST class-doc section) and
   stay frozen for the whole pre-GO countdown, so this R3-built gate covers
   the R5 hold *by construction*, with zero new AI-side code required. Not
   taken on faith: `tests/racing/test_race_start_flow.gd`'s own
   `test_one_second_of_physics_during_the_countdown_produces_zero_
   displacement_and_zero_respawns` drives a real, sustained countdown
   through real physics and asserts every AI kart's own `respawn_count()`
   stays exactly `0` throughout, and this task's own
   `tests/integration/test_race_flow_e2e.gd` exercises the same gate again
   end to end on both real tracks.
7. **Graybox loop East-turn wedge recovers via respawn, not by never
   happening.** The graybox loop's East turn can trap an AI kart oscillating
   against the inner wall for several real seconds (Task 4's own reviewer
   repro) before `_check_stuck_and_respawn()`'s tumbling window closes and
   teleports it clear — worst case up to roughly 2× `respawn_stuck_after_s`
   (≈6s at ai.tres's current 3.0s) if the kart's own bounce pattern keeps
   re-anchoring the window just short of firing. This is accepted, tested
   (`test_east_turn_never_permanently_wedges_over_twenty_real_seconds`), and
   working as designed — the safety net is respawn, not corner geometry that
   prevents the wedge outright. Fix-wave HIGH-1 replaced the detector's own
   net-DISPLACEMENT window (fix round 1) with net SPINE PROGRESS instead
   (a kart can rack up real straight-line displacement without ever
   advancing along the racing line -- see ai_kart_agent.gd's STUCK
   DETECTION doc for the full "moving without progressing" finding and
   `test_lateral_oscillation_with_flat_spine_progress_triggers_respawn_
   within_two_windows`'s own regression lock) -- the East turn's own worst-
   case recovery-window bound above is unchanged by that swap, since both
   detector generations share the same tumbling-window shape and the same
   two tuning fields, only the "is this kart actually progressing" signal
   itself changed. AI line tuning (`lateral_slot_spacing_m`, `steer_gain`,
   `corner_speed_curvature_gain`/`corner_speed_floor_ratio`, `slide_
   trigger_curvature`/`slide_exit_curvature` — all in ai.tres) could in
   principle be retuned to avoid the wedge entirely rather than recover
   from it; this is an operator-tunable, on-device follow-up, not a code
   change.

   **R6 Task 4 addendum (2026-07-31): a genuinely tighter bound is now
   ALSO asserted, but zero respawns remains unreached and is ACCEPTED, not
   further pursued.** Apex-line steering (curvature-derived lateral offset)
   plus `steer_damping` (the low-pass filter on steer output, both new this
   task) were tuned against the East turn specifically, with explicit
   permission to report BLOCKED rather than lower the bar if a genuine
   zero-respawn result proved unreachable. It did: a sweep isolating each
   variable (apex driven to ~0, only `steer_damping` varied at 0.1 and 0.35)
   reproducibly costs exactly one respawn either way, and driving damping
   ALSO to ~0 alongside apex reproducibly clears to zero — proving
   `steer_damping`'s own approach-phase lag, on its own, is sufficient to
   cost that one respawn, independent of apex tuning. This is the textbook
   responsiveness/smoothness trade-off of a low-pass filter on a fast-moving
   target, not an implementation bug, and `steer_damping` is a required
   feature of this same task (it is what closes the oscillation baseline
   below) — so it cannot simply be tuned away to chase this one corner.
   Ruling: the original "healthy progress OR demonstrably recovers" bound
   stays UNCHANGED (never weakened); a new, honestly-earned tightened bound
   is ADDED alongside it in the same test —
   `test_east_turn_never_permanently_wedges_over_twenty_real_seconds` now
   also asserts `respawn_count <= 1` (was unbounded) at the shipped
   defaults (`apex_offset_max_m=4.0`, `apex_entry_lookahead_m=18.0`,
   `steer_damping=0.35`). A real fix to reach true zero would need a
   different mechanism (damping the apex TARGET rather than the steer
   OUTPUT, so the target itself doesn't sweep as fast during approach) —
   out of this task's own scope, left for a future pass if the operator
   wants it. The same root cause also costs a measured 10% regressing-tick
   rate over a 10s solo run at this one corner (`test_regressing_tick_
   fraction_stays_under_twenty_percent_over_a_ten_second_solo_run`,
   `test_ai_kart_agent.gd`), against a 0% baseline with apex/damping driven
   to ~0 — not a second independent finding, the same event.

   **R6 stabilization fix addendum (post-Task-6): the tightened bound above
   relaxed from `respawn_count <= 1` to `respawn_count <= 2`.** The
   `respawn_count == 1` bound sat on a physics-timing-marginal edge:
   independent review runs measured `respawn_count == 2` at the shipped
   defaults on 2 of 3 cold runs, and Task 4's own sweep table already
   recorded three rows landing on 2 for configs neighboring the shipped
   defaults (5.0/24.0/0.35, 6.0/10.0/0.35, 4.0/18.0/0.2). A flaky suite gate
   is worse than an honest bound, so the assertion was widened rather than
   chasing determinism that isn't there at these tuning values. The
   pre-Task-4 state was unbounded, so `<= 2` still guards the wedge-forever
   regression class; it no longer claims a tighter number than the shipped
   config can reliably hit.
8. **Solo time trial is a scene-level flag, not a tuning override (fix-wave
   MEDIUM-5).** `RaceSession.spawn_opponents` (default `true`) owns whether
   a race spawns `AiTuning.opponent_count` AI karts at all;
   `opponent_count` itself keeps validating strictly positive regardless
   (see tuning_service.gd, unchanged). Two thin scene variants
   (`race_time_trial_solo.tscn`/`race_sanity_shores_solo.tscn`) instance
   the ordinary `race_time_trial.tscn`/`race_sanity_shores.tscn` scenes and
   override only this one value; the level list now shows four racing
   entries (RACE/TIME TRIAL × Graybox/Sanity Shores) instead of the two
   AI-populated-only entries R3 shipped with. See race_session.gd's own
   `spawn_opponents` doc and game_root.gd's `_RACE_SCENES_BY_LEVEL_ID`.
9. ~~**New (R4 Task 1): RACE and TIME TRIAL share one best-times record per
   `track_id`, which R4/R5 will make incoherent.** Debt #8's solo variants
   (`race_time_trial_solo.tscn`/`race_sanity_shores_solo.tscn`) instance the
   AI-populated base scene and override only `spawn_opponents` — `track_id`
   itself is inherited, so `race_time_trial.tscn` (AI, `track_id =
   "graybox_loop"`) and `race_time_trial_solo.tscn` (solo, same
   `"graybox_loop"`) write into the exact same `SaveModel.racing[track_id]`
   slot (`game_root.gd`'s `_present_race_results`-equivalent handler around
   `SaveModel.racing_record()`/`improved_racing_record()`, `save_model.gd`'s
   `racing_record()`). This is coherent through R3: nothing about AI
   opponents on the track changes what a lap-time *means* for the player's
   own kart, so a RACE personal-best and a TIME TRIAL personal-best on the
   same track are genuinely comparable. It stops being coherent once either
   R4 (items — a race lap can be shortened by a boost item or lengthened by
   getting hit, neither of which time trial has) or R5 (countdown/
   start-boost — a race start and a time-trial start won't take the same
   fixed time before the clock effectively "starts" racing) lands: a RACE
   time will no longer measure the same thing a TIME TRIAL time does, but
   both will keep overwriting the same best-times slot as if they still did.
   Revisit at R5 (once both R4 items and R5's start systems exist to
   actually diverge the two): either split the save key by mode (e.g.
   `track_id` + a mode suffix) or stop writing best times from AI races
   (RACE) entirely and keep the personal-best record TIME-TRIAL-only.~~
   **RESOLVED, R5 Task 3 (2026-07-31):** took the second option — a race
   (`RaceSession.spawn_opponents == true`) never calls `SaveModel.
   improved_racing_record()` and never writes to `SaveModel.racing[track_id]`
   at all, no matter how fast its own result reads; only a solo session
   (`spawn_opponents == false`) compares against and, if better, persists the
   record. No save-key/schema change — `game_root.gd`'s `_on_racing_finished`
   branches on `spawn_opponents` at the existing single `SaveModel.racing
   [track_id]` slot rather than splitting it. A race still reads the existing
   record and hands it down to `RaceHUD` unmodified, relabeled "TT BEST
   mm:ss.mmm" (blank if none exists yet) — a reference only, never a claim
   about that race's own result, and never accompanied by the NEW BEST marker
   (`new_best_total`/`new_best_lap` are hardcoded false for a race). See
   `race_session.gd`'s own `spawn_opponents` doc, `game_root.gd`'s
   `_on_racing_finished` doc, and `race_hud.gd`'s own TT BEST class-doc
   section.
10. **New (R4 Task 4 fix round 1 [LOW-b]): the PLAYER kart has the same
    one-frame spawn-transform flash the AI-kart fix (Task 4 item 6) closed
    for `_spawn_ai_karts()`, and it is still open.** `race_time_trial.tscn`/
    `race_sanity_shores.tscn` (and their solo variants, which instance
    these) author their `Kart` node with NO explicit transform, so it sits
    at `Transform3D.IDENTITY` (this scene's own local/world origin) from
    the instant the whole packed scene enters the tree until `configure()`'s
    own `_seed_kart_transform(_kart, spawn)` call moves it a few lines
    later — same mechanism, same risk, as the AI-kart bug: a
    CharacterBody3D's first entry into a live SceneTree registers a real
    physics-server broadphase snapshot at whatever transform it has at that
    instant, deliverable as a queued `body_entered` on a later physics tick
    regardless of the same-script-tick reposition that follows. VERIFIED
    empirically (not just reasoned): a synthetic `ItemBox` placed at the
    race scene's own local origin and added as a child of the race root
    BEFORE `add_child_autofree(race)` (so both `Kart` and the box enter the
    tree together, the same relationship a track-authored box would have)
    reads `is_active() == false` after `configure()` runs — a real false
    pickup, not a false alarm. UNLIKE the AI-kart case, there is no clean
    "instantiate → position → add_child" reorder available here: `Kart` is
    a scene-authored child of the packed race scene, not something this
    codebase's own script instantiates and parents at runtime, so the fix
    shape from `_spawn_ai_karts()` does not transplant directly (candidate
    approaches — hand-authoring `Kart`'s scene transform to already sit
    near its real spawn marker, or a session-level "arm collision only
    after the transform is seeded" step — both need real design work, not
    a same-round patch). CURRENTLY LATENT: `test_neither_real_race_scene_
    authors_any_item_boxes_yet` (test_race_session.gd) confirms neither
    shipped track authors any `ItemBox` yet, so nothing on either real
    track can trigger this today. [Polish-wave correction, R5
    (2026-07-31): that test no longer exists — Task 5's box authoring below
    superseded it. The current mitigation is enforced by the
    `track_item_boxes` authoring-lint rule's own
    `TRACK_ITEM_BOX_ORIGIN_CLEARANCE_M` (10.0m) check
    (`scripts/lint_level_authoring.py`), proven by
    `tests/lint/test_level_authoring_lint.py::
    test_item_box_near_origin_fires_the_item_box_rule`.] Task 5 (item box placement on both
    tracks) is what turns this from latent to live — that task MUST either
    keep every authored box's `box_pickup_radius_m` clear of wherever each
    track's own `KartSpawn` marker sits (the practical near-term mitigation,
    since `Kart`'s flash position is this scene's local origin, not
    necessarily `KartSpawn`'s own position — check both), or this debt must
    be picked up and actually fixed before boxes ship.

    **RESOLVED (R4 Task 5): the mitigation, not the structural fix, was
    taken.** Both tracks now author 6 `ItemBox` instances each (two on-road
    lines of three — `track_graybox_loop.tscn`/`track_sanity_shores.tscn`,
    each under its own `ItemBoxes` container), and every authored box sits
    comfortably clear of both this scene's own local origin AND its
    `KartSpawn` marker. **Correction (R4 Task 6 doc-integrity fix,
    2026-07-31): the two clearance figures originally recorded here — ~19.75m
    graybox / ~424m sanity shores — were wrong, quoted from the wrong
    source, and the "verified numerically" claim they sat under overstated
    what had actually been checked.** Recomputed directly from each box's
    authored `position` against `Vector3.ZERO` (the real minimum over all 12
    boxes, not an estimate): the closest box is `ItemBoxSouth1`
    (`track_graybox_loop.tscn`, position `(20, 1, -17)`) at **~26.27m** on
    the graybox loop, and `ItemBoxBack1` (`track_sanity_shores.tscn`,
    position `(300, 1, 380.5037)`) at **~484.5m** on sanity shores — both
    still comfortably clear of the 10.0m floor below. The racing-track
    lint's own new `track_item_boxes` rule pins
    this so it cannot regress: every authored box must sit at least
    `TRACK_ITEM_BOX_ORIGIN_CLEARANCE_M` (10.0m) from `Vector3.ZERO` in the
    track scene's own coordinate frame — see `scripts/lint_level_
    authoring.py`'s own `TRACK_ITEM_BOX_ORIGIN_CLEARANCE_M` doc for why
    that one check covers both "world origin" and "this scene's own
    origin" under the current wiring (`Track` sits at identity in both real
    race scenes). The underlying player-kart origin-flash mechanism itself
    is UNTOUCHED and still real — this only keeps every currently-authored
    box out of its blast radius, the same shape the AI-kart fix's own
    grid-slot lint precedent already established. A future box authored
    without running the lint, or a future hazard placed origin-adjacent by
    hand, remains exposed; the structural fix (seed the player `Kart`'s
    transform before it ever enters the tree, or arm collision only after
    that seeding) is still not done.

11. **New (R6 Task 5, design decision, accepted): an AI kart shakes off an
    attached TNT stick only incidentally, never by deliberate intent.**
    `tnt_stick.gd`'s shake-off counter decrements on either of a victim's
    real `hop_pressed_edge`/`boost_tap_edge` signals (see `KartController`'s
    own signal docs) — for the PLAYER this is a deliberate mashed response
    to being hit; for an AI kart, `AiDriver`/`AiKartAgent` have no "I am
    currently a TNT victim, start mashing hop" state or heuristic at all
    (see `ai_driver.gd`'s own ITEM USE HEURISTICS doc — bomb/tnt_stick/
    triple_turbo intent all describe when to USE an item, never how to
    react to being hit by one). An AI kart only shakes a stick off if its
    own ordinary cornering/sliding behavior happens to fire a hop or
    boost-tap edge before the fuse (`tnt_fuse_s`) expires — CTR-authentic
    in spirit (the original game's own CPU racers show no special item-
    reaction behavior either) and not a bug: a human victim's own escape
    path is unaffected and reliable (`test_shake_off_through_the_real_
    adapter_works_while_the_victim_is_sliding`/`..._is_not_sliding`,
    `tests/racing/test_tnt_stick.gd`). Revisit only if on-device play
    reveals AI karts eating TNT hits far more often than feels right —
    would need new per-agent "was I just hit" state, a genuinely new
    feature, not a tuning knob.
12. **New (R6 Tasks 2/3, standing gap, unresolved): the whole-frame draw-
    call/triangle budget stays unverifiable from this headless worktree,
    and R6 measurably raised the number of draw calls in play.** Task 2's
    own dressing-density pass roughly doubled the racing-line kit-piece
    count on Sanity Shores; Task 3 added one draw call per kart for the
    new stylized mesh (replacing the graybox box, itself already one draw
    call, so roughly a wash there) plus each mounted character's own draw
    call(s) (the already-budgeted Crash/lab-assistant hero/enemy assets).
    Every individual asset passes the per-asset art-budget lint
    (`scripts/lint_art_budgets.py`, green — see Task 6's own sweep), but
    that lint has never modeled a whole-FRAME total the way a real device's
    GPU experiences it, on this track or any other in this repo — a
    standing gap since before R6, not introduced by it, but worth flagging
    now that the number of pieces in frame at once went up materially.
    Operator on-device pass (real phone, real frame-time readout) is the
    only way to close this; no further headless work can.
13. **New (R6 Task 3, operator-pending): Crash's own seat height on the
    kart is an estimate, not a verified fit.** `KartController.mount_
    character()` positions the mounted character at `SeatMount` (a
    Marker3D authored at an eyeballed seat-height position on `kart.tscn`
    — see that file's own SEAT/MOUNT DESIGN doc), never rendered or
    screenshotted in this headless worktree, so whether Crash's own model
    actually sits ON the seat (rather than floating above it or clipping
    into the kart body) is unverified. Flagged for the operator's own
    on-device look pass, same as the kart mesh's own stand-in-tier note
    above; may need a small `SeatMount` height nudge once seen riding for
    real. The lab-assistant AI karts share the same `SeatMount` node and
    the same open question, though R6 Task 3 also separately notes they
    ride a rest/bind pose rather than an authored seated one (acceptable
    per the task brief, a different and already-recorded gap from this
    one).

Final-review residual minors (follow-ups, none gate R2): GameRoot's
same-frame content swap briefly leaves two children so a tuning edit in that
exact frame refreshes the retiring session (self-heals next edit); racing
INPUT tuning is not live-refreshed mid-race (kart/race/camera are — input
applies on retry); the shadow-distance policy lint only walks
scenes/levels so the racing tracks' values (90 / 120) are unguarded and
inconsistent with each other.

R4 final-review notes: one item box can feed two karts entering in the same
physics step (deferred monitoring-off; generous, by design for now); a
leaderless missile flies straight through geometry until lifetime expiry
(no collision node — graybox-appropriate); fresh checkouts need one
`godot --headless --editor --quit` before building (class-name cache).

R5 polish-wave notes: `RaceSession.placement()` removed as dead code
(superseded by `standings()`, whose finished-before-unfinished ranking it
disagreed with — see race_session.gd's own `standings()` doc).

R6 polish-wave notes (2026-07-31, circuit polish — see
`2026-07-31-ctr-r6-circuit-polish-design.md` for the full per-workstream
spec): stage-colored drift-spark/boost-flame FX and a spinning/bobbing item-
box visual, both tuning-driven (`&"fx"` section, `data/tuning/racing/
fx.tres`); Sanity Shores dressed to racing density with a start/finish arch
and per-gate flags; an original stylized kart mesh seating the existing
Crash model (player) and lab-assistant models (AI, tinted per slot);
curvature-derived apex racing lines plus steer damping and per-slot
personality scalars on `AiDriver`/`AiKartAgent`; three new items (bomb,
TNT stick, triple-turbo charges) and position-weighted roulette
(`weight_front_<item>`/`weight_back_<item>` pairs, `ItemTuning`) replacing
the old uniform N-way roll, with AI intent extended to all three. Task 6's
own end-to-end coverage (`tests/integration/test_race_flow_r6_e2e.gd`)
chains a real seeded countdown-to-GO, a real weighted box pickup firing a
new item through the real dispatch path, live FX on a real AI slide, both
character sources actually mounted, and a real finish/standings split, all
in one bounded run with zero unhandled push_error/engine-error calls. New
debts recorded above as #11-#13; #7 (East-turn wedge) gained an R6
addendum tightening its own bound to `respawn_count <= 1`, since relaxed to
`respawn_count <= 2` by a post-Task-6 stabilization fix (physics-timing
marginal, see #7's own addendum; zero remains accepted-unreached, not
further pursued this pass).
