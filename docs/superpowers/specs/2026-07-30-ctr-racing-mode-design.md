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
one-tap retry. Time trial ships earlier (R2) as race-minus-AI with best-time
save via the existing save system.

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

Final-review residual minors (follow-ups, none gate R2): GameRoot's
same-frame content swap briefly leaves two children so a tuning edit in that
exact frame refreshes the retiring session (self-heals next edit); racing
INPUT tuning is not live-refreshed mid-race (kart/race/camera are — input
applies on retry); the shadow-distance policy lint only walks
scenes/levels so the racing tracks' values (90 / 120) are unguarded and
inconsistent with each other.
