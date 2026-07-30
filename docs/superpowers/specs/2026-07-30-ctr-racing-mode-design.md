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
- **Start boost** — countdown "3-2-1": throttle timed into the green window
  at "GO" fires a launch boost, early = bog.
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

1. **R4-BINDING**: `apply_spin_out()` (kart_controller.gd) only calls
   `KartMotor.apply_spin_out()` — it never cancels `DriftStateMachine`. A hit
   landing mid-slide zeroes the motor's yaw authority but leaves the drift FSM
   still reporting `is_sliding()` true and still boostable, since nothing
   about a spin-out tells it the slide is over (parked Task-3 review finding).
   The R4 (items/hazards) plan MUST add a drift cancel alongside the spin-out,
   plus gate `boost_tap()` so a hit can't be "rewarded" with a boost stacked
   the instant before or during it.
2. Boost pads / jump pads are listed under "Kart feel" above as a kart verb,
   but no such mechanic exists anywhere in `src/racing/` or `scenes/racing/`
   — Task 8's boost-pad line was deliberately skipped (no track-side trigger,
   no kart-side response). R3+ candidate; needs its own tuning fields and a
   track-authoring rule (author-lint) once built, not just a scene prop.
3. Four `RaceTuning` fields are authored and validated (registered,
   fingerprinted, panel-editable, rejected if non-positive) but read by
   nothing in `src/racing/`: `countdown_step_s`, `start_boost_window_s`,
   `start_bog_penalty_s`, `checkpoint_tolerance_m`. They exist for R5's
   countdown/start-boost systems, which haven't been built yet — expected,
   not a bug, but worth naming so a future pass doesn't assume they're
   already wired because they validate cleanly. (`respawn_drop_height_m` was
   the fifth field on this list; Task 4 (R3: AI opponents) consumed it —
   `AiKartAgent`'s stuck-kart respawn teleport raises the kart this many
   meters above the centerline point it drops onto — so it is struck from
   this unread-fields debt as of 2026-07-30.)
4. **Known feel-gate note**: `RaceSession._route_input()` samples
   `is_action_pressed(InputIntent.ACTION_JUMP)` once per physics tick and only
   reacts to a change from the previous tick's sampled state (the same
   inherited input-polling architecture the platformer uses). A HOP press and
   release that both land inside the same physics tick's polling window —
   plausible on a touch button under a fast tap — produces no edge at all and
   is silently swallowed. If a human tester reports dropped boost taps or
   missed hops on device, this poll-vs-edge gap is the mechanism to check
   first, not the drift FSM's own timing.
5. **R3 ships AI opponents WITHOUT item use, by design.** The "AI (phase R3)"
   line above ("...item use with cooldowns. 5 karts.") reads as if item use
   ships in this phase, but items themselves do not exist anywhere in the
   codebase until R4 (see "Items (phase R4)" above and Recorded-debt #2 on
   boost pads) — there is nothing for an AI driver to use yet.
   `AiDriver`/`AiKartAgent` (R3, Tasks 3-4) only ever call
   `steer()`/`set_brake()`/`hop_pressed()`/`hop_released()`/`boost_tap()`/
   `set_speed_scale()`, the same kart-only verbs a human racer has in R1-R3.
   This is an intentional scope split, not a missed line item — the R4 plan
   must add AI item-use once item boxes/roulette actually exist.
6. **Stuck detector fires on any 3s net-stationary-or-non-progressing AI
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
   countdown reaches GO.
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

Final-review residual minors (follow-ups, none gate R2): GameRoot's
same-frame content swap briefly leaves two children so a tuning edit in that
exact frame refreshes the retiring session (self-heals next edit); racing
INPUT tuning is not live-refreshed mid-race (kart/race/camera are — input
applies on retry); the shadow-distance policy lint only walks
scenes/levels so the racing tracks' values (90 / 120) are unguarded and
inconsistent with each other.
