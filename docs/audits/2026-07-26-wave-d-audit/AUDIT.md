# Wave D (Hog Wild) audit — af585f6

Performed 2026-07-26, read-only, against `af585f6a817881e12d54aae7b3e77b2ccf3a8ef8`
on branch `wave-d-task20-21`. Diff audited: `51fdae9..af585f6` (37 files, +2488/-27).
Working tree was clean at start and at end; nothing was edited or committed.

`data/tuning/chase.tres` was **not** changed: blob `92f332ea` is identical at
`51fdae9`, at `af585f6`, and in the working tree.

## P1

**D1 — Ride jump has no coyote time.**
`src/gameplay/player/player_state_machine.gd:139-146` (`enter_ride` sets
`_ground_jump_available = false`), `:174` (`_process_ride_actions` returns early on
`if not grounded:`), versus `:421-433` (`_expire_coyote_if_needed`) and `:315-325`
(`_process_jump`) which give every other state a 0.14 s window.
Executed: identical input 0.02 s past a ledge yields `impulse=jump` on foot and
`impulse=none` on the hog. `coyote_time_s 0.14 x ride_speed_mps 9.0` = **1.26 m** of
lost forgiveness at the game's highest speed. The early-press buffer still works, so
forgiveness is asymmetric. Gaps open at z -304.05 / -678.05 / -717.05; one frame late
is a death. Evidence: `evidence/probe_coyote.log`.

**D2 — The full suite is intermittently red.**
`tests/gameplay/test_wall_run_state.gd:459` attaches with a hardcoded `6.0` against
`data/tuning/wall_run.tres:11 maximum_duration_s = 2.0`, racing engine uptime against
an 8.0 s deadline. Control 3/3 green; with 2 s of uptime burned in a suite sorting
ahead of it, 3/3 fail on exactly that test. Rate at HEAD 2/9 shared runs; at
`51fdae9` 1/20. Pre-existing, but `tests/gameplay/test_ride_state.gd` sorts before
`test_wall_run_state.gd` and adds uptime, so Wave D moved it toward the cliff. The
next test added ahead of it makes the failure permanent.
Evidence: `evidence/flake_experiment.log`.

**D3 — `set -e` hides 71 tests.**
`scripts/run_gut.sh:2`, shared run at `:73`, isolated suites at `:75-76`. Observed
live: exit 1, "460 passing" printed, and `test_main_boot` (40), `test_island_slice`
(17), `test_warp_room` (14) never ran. The only hub-to-Hog-Wild entry test lives in
`test_warp_room.gd`.

**D4 — HogMount is 222 lines of logic behind one existence test.**
`tests/gameplay/test_ride_state.gd:341-358` asserts two method names.
`_ensure_curve_from_markers`, `_connect_triggers`, `_trigger_progress`,
`_path_is_usable`, `_attach_visual`/`_detach_visual` and both signals are untouched.

**D5 — The Area3D wiring is bypassed in tests.**
`tests/integration/test_level_scenes.gd:1231` calls
`mount.call("_on_dismount_trigger_body_entered", player)` directly;
`_on_mount_trigger_body_entered` is never called at all. The real path was verified
working by driving the body into the trigger, so this is regression-blindness rather
than a live defect: a swapped NodePath or bad collision mask ships green.

**D6 — Null hog tuning desyncs mount state.**
`src/gameplay/ride/hog_mount.gd:79-94` checks only `has_method("mount_hog")` and
ignores the outcome, while `src/gameplay/player/player_controller.gd:149-151` returns
early when `_hog_tuning == null`. Result: `HogMount._mounted = true`, `mounted`
emitted, and the hog visual reparented onto a player still in normal walking state.

## P2

**D7 — Plants never trigger on the intended line.** `scenes/segments/hog_plant_chomp.tscn:43-47`;
`src/gameplay/enemies/enemy_base.gd:172-180` is a spherical `distance_to <= 2.5` and
`trigger_lateral_m` is read only by the skink. Plants sit at x = -3.8 / +3.8 while the
crate line at those z values sits at x = +3.8 / -3.8 — **7.6 m** apart. The segment
teaches nothing. Design decision: move the plants onto the line, add a lateral trigger,
or re-tune for 9 m/s.

**D8 — The crescendo is a clone of the weave segment.** Number-normalised diff of
`scenes/segments/hog_crescendo.tscn` against `hog_weave_gates.tscn` differs only in node
names, title text, y 1.8->1.7, block size -0.2, z +2, and colour. `hog_gap_combine`
combines the jump twist with a second copy of itself. No escalation in the back half.
Design decision.

**D9 — Hog mounts reset on plain checkpoint activation.** `src/gameplay/run/level_session.gd:682`
(`_on_checkpoint_reached`) is one of five `_set_player_spawn` callers and does not
teleport. Benign in this level only because mount progress is 0.0 and both checkpoints
(-360, -748) fall inside the ride window; latent for any future ride level whose mount
trigger is not at the start.

**D10 — `hog_tuning` is a null-defaulted parameter on four signatures.**
`player_controller.gd:106` and `:555`, `player_motor.gd:42` and `:131` — in a repo whose
own `test_configure_gating_params_have_no_silent_default` forbids exactly this for
gating params. All five production call sites do pass `catalog.hog`; the default only
protects tests, and it converts three separate failures into silent no-ops.

**D11** controller tests run with `_hog_tuning == null` (`tests/gameplay/test_player_controller.gd:918`).
**D12** `scripts/verify_exported_tuning.sh:66` asserts only `n_sanity_beach` in the LEVEL
META block (low impact — the script was run and `hog_wild.tres` does print).
**D13** `tests/integration/test_level_scenes.gd:1103-1116` can pass with zero assertions.
**D14** `wumpa_total` is never linted (`LevelMetaValues` carries only `crate_count` and
`design_pace_mps`).
**D15** untested branches: 2 of 3 `reset_for_player_position` paths, non-player bodies,
empty curve, airborne mount/dismount, and `exit_ride`'s `grounded` argument (every
dismount assertion is `assert_ne(state, &"ride")`, true either way).

## P3

**D16** misnamed spine markers (`MountLine` 8 m from the trigger, `DismountLine` 11 m
upstream, `FirstRead` marks nothing, no runtime consumer for any of them).
**D17** best-case runtime 1:53, under the design doc's 2-minute floor, and unimprovable.
**D18** required jumps at 16.786 deg against the 15 deg rule — 1.79 deg of headroom.
**D19** `GateLeft`/`GateRight` unhittable from the intended line.
**D20** 8 of 33 crate beats exceed the 2-4 s rule, worst 6.44 s, all at segment seams.

## Checked and cleared — do not "fix" these

- **Gaps are not a softlock.** Exactly three, each 5.00 m, flat on both sides, against
  6.84 m analytic reach. A successful clear was traced: takeoff -716.8, landing -723.7,
  far edge -722.0. A no-jump rider correctly dies at the first gap. `evidence/probe4.log`.
- **Crates cannot block a rider.** All 32 carry `break_on_touch`; the block lasts <= 1
  frame (0.15 m).
- **Trigger collision masks are correct** (layer 0 / mask 1, matching the working Finish
  area) and real `body_entered` detection was proven by moving the body.
- **Segments, seams, checkpoints, camera coverage all pass.** Eight segments on the 2 m
  grid with exact seams; checkpoint intervals 40.0 / 43.1 / 30.1 s, all <= 60 s; camera
  union continuous +2.0 -> -1026.0.
- **Warp-room and level-list entry** are reachable and consistently spelled everywhere.
- **Old tuning overrides backfill correctly** (`tuning_service.gd:519-535` runs at `:131`
  before validation); `catalog_is_usable` cannot null-deref `checked.hog` because the
  generic null sweep at `:197-200` returns first.
- **The tuning loop is provably live** (CLAUDE.md rule 2): `ride_speed_mps` 9.0 ->
  `aeff5511...`, 9.5 -> `08a237ba...`, restored -> `aeff5511...`.
- **The exported runtime loads everything**: `verify_exported_tuning.sh` exit 0, both
  `hog.tres` and `hog_wild.tres` present, source and runtime fingerprints match,
  `EXPORTED HOG WILD SMOKE READY`. `evidence/export_verify.log`.
- **The `configure` arity error in the GUT log is an intentional `[ExpectedError]`**, not
  a bug.

## Missing-test risks, ranked

1. One scene-level test driving the real `Area3D.body_entered` for both triggers —
   asserting `is_mounted()`, `is_hog_mounted()`, `current_state`, the hog visual's
   parent, and that a non-player body changes nothing. Closes D4, D5 and part of D15.
2. A coyote-window assertion for the ride state (closes D1's regression risk).
3. Distinguishing `exit_ride`'s grounded vs airborne outcome.

## Not assessed

Gate F / device feel. The ride-jump press window is roughly 0.30 s before input
latency; that is exactly what the gate exists to judge, and it is the operator's call.
