# Turns and a closer camera — design

Date: 2026-07-29. Operator-approved (approach, camera values, pilot scope all
confirmed 2026-07-29). Extends the master design doc
(`2026-07-23-crash-remix-design.md`); nothing here overrides its gates or
pillars. The feel verdict on everything below is a human gate: the agent
builds and reports "ready to test on device", never "feels good".

## Problem

Every shipped level chains 96 m segments in a perfectly straight line down
world −Z, and every camera-rail marker sits at x = 0. The corridor grammar
(§2.1) never *required* straightness — the rail is a spline the rig already
follows — but no level authors a bend, so gameplay reads as a straight march.
Separately, the chase camera sits far and diagonal (offset (3.6, 4.8, 8.5),
FOV 58): Crash is small on screen and the view feels detached compared to the
PS1 games' close, nearly dead-behind framing.

A 2026-07-29 corridor-turn readiness audit established that the runtime is
almost entirely corridor/path-relative already (chase boulders, hog mount
windows, enemies, traversal, respawn, finish detection, and the level author
lint all rotate cleanly) and identified the exact blockers listed below.

## Decision 1 — turns via corner-arc segments + rotated straights

A reusable 90° quarter-arc corner segment (centerline radius ~10–12 m,
corridor width matching the straights, kit-dressed), with spine markers along
the arc. Level assembly after a corner simply instances the existing straight
segments in the rotated frame — segments are fully self-contained (geometry,
crates, enemies, camera regions, spine all local), so rotation carries
everything.

Constraints:

- **≤ 90° per bend, no switchbacks.** The level lint's monotonic-progress
  check measures against the level's endpoint chord; legs turning past 90°
  would false-positive. Acceptable authoring constraint for the pilot;
  revisit only if a level needs a U-turn.
- **Arenas stay axis-aligned.** Papu's shockwave test uses world-Z distance;
  rather than fix it we do not rotate boss arenas. Recorded as NOT APPLICABLE
  unless an arena ever turns.
- **No wall-run / grind / swing segments in rotated frames** for now. The
  traversal lint (`lint_traversal_authoring.py`) composes world positions
  ignoring rotation, so its rules would silently mis-check rotated traversal
  authoring. Instead of porting oriented math now, the lint gains a guard:
  a traversal strip/rail with any rotated ancestor is a lint error. The full
  port is DEFERRED until a turned level wants a traversal segment.

Pilot scope (operator-approved): one–two corners in N. Sanity Beach, two
flowing swerves in Hog Wild. Boulders and boss levels unchanged.

## Decision 2 — runtime turn-readiness fixes (all TDD)

1. **Smooth rail curves.** All five `_ensure_curve_from_markers` copies
   (camera rig, chase hazard, hog mount, traversal rail, wall-run strip)
   build a handle-less polyline, so a bend is a hard kink: corridor forward
   snaps in one frame and `get_closest_offset` goes ambiguous at the inside
   of a corner. Extract one shared helper that also sets Catmull-Rom in/out
   handles (`handle = (next − prev) × factor`). The factor is a new
   `CameraTuning.rail_handle_length_factor` (default ⅙); straight rails are
   unchanged (collinear handles degenerate to the line).
2. **Short-baseline corridor tangent.** `_corridor_forward` is currently the
   chord to a point `look_ahead_m` (2 m) ahead, which cuts corners and
   briefly steers the player into the inside wall. Derive the corridor
   forward from a short-baseline tangent (new
   `CameraTuning.corridor_tangent_baseline_m`, small, e.g. 0.4) and keep
   `look_ahead_m` only for the camera look target.
3. **Live gesture corridor axis.** The touch stick latches its corridor axis
   at gesture start and never updates during a held drag; through a corner
   the magnet steers toward the stale pre-corner heading. Slew the gesture
   axis toward the live corridor axis at a rate-limited
   `InputTuning.gesture_axis_slew_degrees_per_s` (chase screen-relative mode
   keeps its existing behaviour).
4. **Hog visual orientation.** On mount the hog model is pinned to world
   axes (`rotation = Vector3.ZERO`) and nothing yaws it; on a turned Hog
   Wild it would run sideways. Yaw the hog visual from the corridor forward
   the same way the player visual is yawed.

All new numbers are tuning-resource fields (repo rule 1); the fingerprint
must move when they land (rule 2).

## Decision 3 — closer chase camera (tuning only)

`data/tuning/camera.tres`: `default_offset` (3.6, 4.8, 8.5) →
**(1.2, 3.9, 6.8)**, `field_of_view_degrees` 58 → **56**. ~20 % closer,
nearly dead-behind (the on-screen left composition is kept by
`player_screen_left_bias_m`, not by the big lateral rig offset). Depression
stays ≈ 30°, inside the spec's 30–35° band and clear of the ≥ 15° authored
jump rule — re-run the level lint to prove it. Final values are the
operator's, live on device via the tuning panel.

## Decision 4 — difficulty pass (operator-requested 2026-07-29)

The operator asked for the game to be harder. Constraint from the master
design doc, kept absolute: difficulty never comes from
distance-since-checkpoint. The levers are pace and precision, all in tuning
resources so the operator can pull any of them back live on device:

- **Enemies** (`enemy_plant/crab/skink.tres`): shorter telegraph/chomp
  windows, faster patrols — a moderate step (~15–20 % on timing/speed
  values), not a rework.
- **Hog Wild** (`hog.tres`): higher ride speed, so the new swerves demand
  real steering.
- **Boulders** (`chase.tres`): faster boulder / tighter start gap — chase
  pressure is the level's whole point and is currently forgiving.
- **Papu** (`boss_papu.tres`): faster shockwave tempo.
- **Retrofit geometry**: required jumps in the reworked Beach/Hog segments
  authored nearer the movement kit's limits (still lint-green for the ≥ 15°
  rule), and the corner pieces themselves add new reads.

Numbers land as one reviewable tuning commit, separate from the turns work,
so "too hard" reverts by restoring one committed `.tres` (or live on the
device panel) rather than a level re-author.

## Test / verification plan

- TDD each runtime fix: failing GUT test first (curve handle generation,
  tangent baseline vs chord on an L-shaped rail, gesture-axis slew, hog
  visual yaw under a rotated corridor).
- Update the tests the audit flagged as baking straight −Z (checkpoint
  ordering by world z, hog dismount x/z equality, Papu crest world-z travel,
  segment-overlap and footprint z-extent checks) to rail-offset or
  transform-aware equivalents.
- New traversal-lint guard test: rotated ancestor over a wall-run strip or
  rail fails the lint.
- Level lint green on the turned Beach and Hog Wild (jump depression with
  the new camera, checkpoint spacing, crate counts vs `LevelMeta`).
- Full suite before commit, count reported.
- Finish gates yawed with their levels; spawn markers verified in rotated
  frames.

## Out of scope

Turns in Boulders and boss arenas (their difficulty tuning is in scope,
their geometry is not), U-turns/switchbacks, traversal segments in rotated
frames (guarded, deferred), the Papu world-z shockwave math (arenas stay
straight), any art-ladder work, and any feel certification — Gate rules
apply unchanged.
