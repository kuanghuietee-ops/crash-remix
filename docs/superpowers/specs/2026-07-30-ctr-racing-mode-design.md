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
2. ~~Boost pads / jump pads are listed under "Kart feel" above as a kart verb,
   but no such mechanic exists anywhere in `src/racing/` or `scenes/racing/`
   — Task 8's boost-pad line was deliberately skipped (no track-side trigger,
   no kart-side response). R3+ candidate; needs its own tuning fields and a
   track-authoring rule (author-lint) once built, not just a scene prop.~~
   **RESOLVED, R7 Task 1 (2026-08-01, commit `146e3f8`):** `BoostPad`/
   `JumpPad` (`src/racing/track/boost_pad.gd`/`jump_pad.gd` +
   `scenes/racing/boost_pad.tscn`/`jump_pad.tscn`) are real Area3D track
   props with their own `RaceTuning` fields (`pad_boost_s=1.0`,
   `pad_refire_cooldown_s=1.5`, `jump_pad_velocity_scale=2.2`) and a
   dedicated author-lint rule (on-road + clear of gates/boxes/origin, the
   `track_pads` rule in `scripts/lint_level_authoring.py`) — exactly the
   candidate shape this debt called for. `RaceSession` discovers and wires
   both pad kinds (`_discover_boost_pads`/`_discover_jump_pads`,
   `_on_boost_pad_body_entered`/`_on_jump_pad_body_entered`), per-kart
   refire cooldown included. Temple Twilight (R7 Task 3) authors both a
   boost strip and a jump-pad corner cut as signature features (see this
   doc's own R7 notes below); Sanity Shores and the graybox loop each got
   1-2 boost-strip retrofits (R7 Task 4). See `docs/superpowers/sdd/
   2026-08-01-ctr-r7-second-circuit/task-1-report.md` for the full design.
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
14. **New (R7 Task 5, flagged not fixed): the Cup interstitial/podium's
    Continue/Close buttons are not on `RaceSession`'s own touch-exclusion
    list.** Only the race's own Retry button is added, at `configure()`
    time, before the overlay concept exists — on a real touch device a tap
    on Continue/Close could theoretically also reach the race's own touch
    controls underneath. Debug-menu-gated prototype UI pre-Gate-F; left
    open to keep Task 5's own scope proportionate, worth revisiting once
    the Cup gets real art/UI polish (`task-5-report.md` §8).
15. **New (R7 Task 4, flagged not fixed): the graybox loop's raw `Spine`
    marker polyline has an unlisted ring-closing gap.** `_project_onto_
    polyline` (`scripts/lint_level_authoring.py`) only ever pairs `zip(
    points, points[1:])`, so it never sees an explicit `SouthWest→SouthMid`
    wrap-around segment closing the ring — a point placed near `x∈(-40,0)`
    on the west approach to `SouthStraight` silently clamps onto the wrong,
    curved `WestTurnB→SouthWest` neighbor and reads a misleading tangent
    (measured: `offset_across_m=1.294`, `rotation_degrees.y=-75°` instead of
    the physically correct `-90°`). Not a live bug — Task 4's own pad
    placement avoided the zone entirely — but any future graybox pad/box
    authored near that gap must double-check its own tangent numerically
    rather than trust `offset_across_m` passing (`task-4-report.md` §5).
16. **New (R7 Task 6, confirmed by code read, R7 Task 7): a failed ghost-
    file rename can orphan a `.tmp` file forever.** `GhostRecorder.save_
    to_file()` (`src/racing/flow/ghost_recorder.gd`) mirrors SaveService's
    temp-file-then-rename atomic-write pattern and does clean up the temp
    file if the WRITE itself fails, but if the final `DirAccess.rename_
    absolute()` call fails (permissions, cross-device, disk full mid-
    rename) the function simply returns that error — the already-written
    `<path>.tmp` is left on disk, never removed, never retried. Low
    severity (a ghost is disposable, outside the profile save, and this
    path pushes no error the player would see) but a real, confirmed gap:
    `save_to_file()`'s own doc only ever exercises the write-failure
    cleanup branch, not a rename-failure one.
17. **New (R7 Task 3, corrected diagnosis, R7 Task 7): Temple Twilight's
    tightest corner is NOT where its one measured per-kart wedge cost
    actually lands.** The naive read of the track's own layout names
    `CourtyardHairpin` (R=24, a full 180°, the tightest radius on the whole
    circuit) — and by extension the `CourtyardEntry` straight immediately
    after it — as the likely "start-bunch pinch": six karts still grouped
    off the grid, funneled through the tightest hairpin on the track,
    right at the top of the lap. Task 3's own per-checkpoint diagnostic
    (§5 of its report) already measured the opposite: every AI kart shows
    `respawn_count=0` all the way through t=15s, by which point cumulative
    progress (≈224-229m) has already cleared `CourtyardHairpin` AND
    `CourtyardEntry` and entered `CourtyardBendA`. The one respawn per kart
    that does occur happens later, at t=15-20s (cum≈262-300m), squarely
    inside the direction-reversing courtyard esse
    (`CourtyardBendA→CourtyardMid→CourtyardBendB`) — a steering-transient
    cost from the reversal, not a raw-radius wedge, and not the start-bunch
    hairpin at all. Recorded here so a future pass tuning this track does
    not "fix" `CourtyardHairpin`/`CourtyardEntry` on the strength of how
    the map looks rather than what was actually measured.
18. **New (R7 Task 2 fix round 1, dead-ish since, confirmed R7 Task 7):
    `KartController.commanded_velocity_mps()` has no remaining production
    call site.** Added in Task 2 as the bump-detection relative-speed
    getter, then superseded in fix round 1 by `commanded_velocity_without_
    bump_mps()` (added specifically to exclude an in-flight bump impulse
    from the same calculation, see that round's own same-tick-double-
    detection fix). `commanded_velocity_mps()` (`kart_controller.gd:372`)
    is still defined and still referenced from doc comments explaining why
    the *other* method exists, but nothing calls it anymore — dead code
    left standing rather than removed, safe to delete in a future pass
    once its own doc-comment cross-references are updated alongside it.
19. **New (R7 Task 4, stale by omission, confirmed R7 Task 7): one comment
    still names the `DEBUG_RACING_LEVEL_ID` const Task 4 removed.**
    Task 4's own fix-up reworded the doc comment in `game_root.gd` that
    used to point at it, but missed `tests/racing/test_race_session.gd`'s
    own `test_request_retry_emits_the_retry_requested_signal()` comment
    (line 420: "...game_root.gd's DEBUG_RACING_LEVEL_ID branch"), which
    still names the removed const in the present tense as if it still
    routes retry — the real mechanism is now `_race_scenes_by_level_id`/
    `_on_racing_track_requested()` (`RacingTrackRegistry`). Comment-only,
    no behavior implication; left as a one-line text fix for a future pass
    per this task's own bookkeeping-not-fixing scope.
20. **New (R8 Task 7, confirmed R8 Task 9): the Cortex/Coco gate renders
    read washed-out — fur/skin tones near-white against the authored warm
    reference palette.** Pre-existing trait of the shared render/lighting
    setup each builder's own `create_gate_renders()` function uses
    (`create_cortex.py:660`/`create_coco.py:688`) to produce the
    front/three-quarter/seated-on-kart PNGs under `docs/art/gates/`, not
    something specific to either character's own model or materials —
    confirmed present on both Cortex (Task 6) and Coco (Task 7). The
    operator was told about this before judging either gate, so it should
    not itself sink an otherwise-correct likeness verdict; still worth a
    lighting fix if a future gate gets declined on color/tone grounds
    rather than shape/proportion.
21. **New (R8 Task 8, confirmed R8 Task 9): `coco-likeness-proportions.svg`
    is not well-formed XML.** `xml.dom.minidom.parse()` fails at line 85
    ("not well-formed (invalid token)") — an authored HTML/XML comment in
    the side-view group contains a bare `--` ("...this angle -- two
    tapered..."), which the XML comment grammar forbids anywhere inside a
    comment body, not just at its boundaries. Task 8 found and fixed the
    identical mistake in its own Ripper Roo sheet mid-build but explicitly
    left Coco's pre-existing copy of the same mistake out of scope. Purely
    a documentation-tooling gap today (nothing in the shipped pipeline
    parses these reference SVGs as XML — they are Blender/human visual
    references only) but will bite the first script that ever does.
22. **New (R8 Tasks 6-7, confirmed R8 Task 9): per-driver seat-fit
    constants (`seat_scale`/`seat_offset`) are authored twice, with no
    single source.** The real values live in each `DriverEntry` resource
    (`data/racing/drivers/*.tres`, read by `KartController.mount_
    character()` at runtime) and are duplicated by hand into each
    Blender builder script's own illustrative seated-on-kart render
    (`create_cortex.py`/`create_coco.py`/`create_ripper_roo.py`, editor-
    only preview, never read by the shipped game). A future seat-fit
    tweak to the `.tres` side that forgets its Python twin would silently
    desync the builder's own preview render from what actually ships —
    inherited pattern since Task 6's own Cortex builder, not introduced
    fresh by any one task.
23. **New (R8 Task 4, confirmed by code read R8 Task 9, real behavior
    change, untriaged): picking an ordinary RACE/TIME TRIAL menu entry
    abandons an in-progress Cup up front, even if the player then backs
    out of Driver Select without launching anything.** `_on_racing_track_
    requested()` (`game_root.gd`) calls `_abandon_active_cup()`
    UNCONDITIONALLY before it ever opens `DriverSelectOverlay` — a
    deliberate, correct R7 rule on its own (an ordinary race must never be
    mistaken for cup progress, see that call's own doc). R8 Task 4 then
    inserted the CHOOSE DRIVER screen between that click and the actual
    race launch (`_open_driver_select_overlay()` -> tile tap/SKIP/back-out
    -> `_launch_pending_race()`), so the cup is now abandoned at the FIRST
    click, before the player has confirmed anything. Backing out via
    `_on_driver_select_back_out()` afterward only clears the still-pending
    launch and resumes the pause menu/hub — it does not and cannot restore
    the cup that was already cleared by the click that opened this screen.
    Net effect: tapping RACE, looking at the driver tiles, and backing out
    with no intent to actually race now costs the player their active cup
    silently, whereas pre-Task-4 the abandon and the launch were the same
    atomic click. Flagged at Task 4 time, not fixed; still not triaged as
    of Task 9 whether `_on_racing_track_requested()` should defer its
    `_abandon_active_cup()` call until `_launch_pending_race()` actually
    resolves a pick (restoring the old atomicity) rather than firing on
    the initial click.
24. **New (R8 Task 5, confirmed R8 Task 9): `test_ai_pace_benchmark.gd::
    test_graybox_loop_clean_lap_pace_improves_at_least_eight_percent` is a
    fourth flaky suite, alongside the three already-documented ones
    (`test_island_slice.gd`/camera-archetype suites/`test_main_boot.gd`).**
    First observed failing under full-suite load during R8 Task 5 (2/2
    green when re-run isolated immediately after); the failure mode is
    consistent with the benchmark's own documented East-turn contact-
    physics noise (see that file's own METHOD doc on why it measures
    clean-lap SPEED rather than distance-over-time, precisely to filter
    out this kind of noise) rather than a real regression. Re-run isolated
    whenever it fails inside a full-suite run, the same triage step the
    three pre-existing documented flakes already get; not yet promoted
    into any repo-wide flake list beyond this spec's own record of it.

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

R7 polish-wave notes (2026-08-01, second circuit — see
`2026-08-01-ctr-r7-second-circuit-design.md` for the full per-workstream
spec): boost/jump pads (discharges debt #2, see above), authored kart-to-
kart contact (symmetric, capped, speed-gated lateral bump impulse), a
second full real track (Temple Twilight — night temple circuit, two tight
hairpins bracketing a direction-reversing courtyard esse, a broad cliff
sweep, a boost-strip main straight, and a jump-pad corner cut whose
trajectory clears its gap with a numerically-proven ≥62% margin even at
the AI's own guaranteed floor speed), pad retrofits on both existing
tracks, a track/menu registry replacing four hand-duplicated per-track
signal/const blocks, and the Cup (`CupSession`, a 2-race Sanity Shores →
Temple Twilight championship with tuning-driven placement points, AI
lineup/tint continuity free by construction from the shared grid-slot
scheme, and save v2→v3 for `racing.cups` with the same v1→v2-grade
migration rigor — scratch-verified v1→v3 full chain, v2→v3 with existing
bests preserved, and corrupt-cups fail-closed recovery). **The stretch
time-trial ghost SHIPPED, not deferred**: `GhostRecorder`/`GhostPlayer`
(record/persist/replay, solo-only, best-time-gated, translucent no-
collision visual) landed complete in Task 6 with its own full test roster,
never invoked the plan's own "if it strains, defer" escape hatch. Task 7's
own end-to-end coverage
(`tests/integration/test_cup_flow_e2e.gd::test_full_r7_cup_run_through_a_
real_countdown_fires_a_real_pad_and_exchanges_a_real_bump`) chains a real
3-2-1-GO countdown (not skipped) for race 1, a real boost-pad overlap
reaching the real KartMotor, a real kart-to-kart bump exchange between two
real AI karts (non-zero `bump_count()` on the real post-move_and_slide
contact path), both races teleport-finishing through the real registered
scenes, the between-race interstitial and final podium, and a real save
write verified against a fresh disk load — all in one run with zero
unhandled push_error/engine-error calls. New debts recorded above as
#14-#19.

R8 polish-wave notes (2026-08-02, characters/select/classes — see
`2026-08-02-ctr-r8-characters-design.md` for the full per-workstream spec):
a six-driver roster (`DriverRegistry`, one `DriverEntry` row per driver, a
fixed load-bearing order every AI-fill/select-screen consumer walks
identically) composed onto kart tuning through four `DriverClass`
resources (Balanced/Speed/Acceleration/Turning — the same three
multiplier fields, top_speed/accel/steer_rate, `KartTuning.composed_
with()` already touched); a CHOOSE DRIVER select screen every RACE/TIME
TRIAL/CUP menu entry now routes through first (tap a tile = confirm and
persist, SKIP = keep the last save pick unchanged), with the CUP picking
exactly once at cup start and holding that same pick across both races;
AI fill excludes whichever id the player picked, deterministic registry
order, never a duplicate; save v3→v4 for `racing.selected_driver` and
ghost format v1→v2 for the recorded driver id, both carrying the same
scratch-verified migration rigor as every earlier version bump. Papu's
own seated-pose variant **shipped LIVE** — a pose-only reuse of his
already-operator-accepted platformer mesh, not a new likeness gate — and
now mounts for real in every race instead of falling back.

**Three likeness gates remain PENDING OPERATOR, honestly recorded as
such, never as passed:** Cortex, Coco, and Ripper Roo each got a real,
code-complete, byte-deterministic Blender builder (`create_cortex.py`/
`create_coco.py`/`create_ripper_roo.py`) and real gate renders delivered
to the operator, but all three `DriverEntry` rows still ship an EMPTY
`character_scene_path` — every race featuring any of the three seats the
lab assistant instead (`DriverRegistry`'s own FALLBACK contract), exactly
as the plan required until an explicit operator likeness acceptance
lands. No `.tres` file for any of the three was touched by this task.

Task 9's own end-to-end coverage
(`tests/integration/test_r8_papu_cup_reload_e2e.gd::test_papu_picked_
through_the_real_select_screen_races_a_full_cup_and_survives_a_fresh_
reload`) chains a real Driver Select tile tap (Papu, not SKIP), a real
3-2-1-GO countdown for race 1, both races teleport-finishing through the
real registered scenes with papu's own seated GLB actually mounted
mid-race both times, the between-race interstitial and final podium, a
real save write verified against a fresh disk load — and, new for R8, a
SECOND, brand-new `GameRoot` boot off the same `save_dir` (standing in
for relaunching the app) that reads the persisted pick back off disk and
mounts the same real model again on the very first race it launches, with
no re-pick — all with zero unhandled push_error/engine-error calls (six
expected, bounded `push_warning` fallback calls for the still-gated trio,
one per driver per race, two races). Task 2's own per-class Temple
Twilight health-race battery (three tests: Speed/papu, Acceleration/coco,
Turning/ripper_roo) and Task 3's own ghost v1-compat/v2-round-trip/
corrupt-driver-id suite were both re-run in full on the merged, post-
Papu-flip tree and remain green (see `task-9-report.md` for the exact
counts). New debts recorded above as #20-#24.
