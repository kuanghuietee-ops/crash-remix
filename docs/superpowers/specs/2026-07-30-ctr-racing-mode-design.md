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
