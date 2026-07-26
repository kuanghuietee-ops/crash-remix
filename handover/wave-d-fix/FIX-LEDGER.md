# Ledger — Wave D audit fixes (baseline af585f6)

Terminal fixer statuses: FIXED = verified, regression-tested red then green, and
committed. DEFERRED = verified but requires an operator decision or human gate;
the evidence names the unblocker. REJECTED = the claim did not survive
verification. Non-terminal VERIFIED/REPORTED rows remain audit inputs awaiting
the fixer loop.

| ID | Sev | File:line | Claim | Status | Evidence |
|----|-----|-----------|-------|--------|----------|
| D1 | P1 | player_state_machine.gd:139-146,186-192 | Ride jump has no coyote time; every other state has 0.14 s | VERIFIED | Executed: normal 0.02 s past ledge -> `jump`; ride same input -> `none`. 0.14*9.0 = 1.26 m lost |
| D2 | P1 | tests/gameplay/test_wall_run_state.gd:459 | Suite intermittently red: hardcoded `now_s=6.0` + `maximum_duration_s=2.0` races engine uptime | FIXED | `test_real_physics_holds_the_wall_distance_while_running`: temporary 2 s uptime-burn suite reproduced `airborne` vs `wall_run` and `0.5666667` vs `0.4 +/- 0.0001`; using `MonotonicClock.now_s()` passed under the same burn. Clean verification: shared 461 + isolated 40/17/14 = 532 |
| D3 | P1 | scripts/run_gut.sh:2,73,75-77 | `set -e` aborts before the 3 isolated suites; green count silently omits 71 tests | FIXED | `test_full_runner_attempts_isolated_suites_after_shared_failure`: fake shared failure initially logged 1 invocation instead of 4; runner now aggregates status after attempting shared + all isolated processes. Full verification: shared 461 + isolated 40/17/14 = 532 |
| D4 | P1 | tests/gameplay/test_ride_state.gd:341-358 | HogMount = 222 lines of logic, only an existence test | FIXED | `test_marker_path_mounts_player_and_moves_visual_as_one_contract`: 15 assertions cover marker-built curve, progress, mount/dismount state, calls, signals, and visual ownership/offset. Mutation removing curve points failed 11 assertions. Full verification: shared 462 + isolated 40/17/14 = 533 |
| D5 | P1 | tests/integration/test_level_scenes.gd:1234 | Dismount test hand-calls `_on_dismount_trigger_body_entered`; Area3D path untested; mount handler never called | FIXED | `test_hog_wild_mounts_forced_run_and_dismounts_at_finish`: moves the real player from outside into both real `Area3D`s, asserts overlap, emitted player body, mount/ride state, visual ownership, and dismount. Mutation disconnecting both callbacks failed 8 assertions. Full verification: shared 462 + isolated 40/17/14 = 533 |
| D6 | P1 | hog_mount.gd:83-94 + player_controller.gd:149-151 | With null hog tuning, `mount_hog()` no-ops but HogMount sets `_mounted=true`, emits `mounted`, reparents visual | FIXED | `test_refused_player_mount_keeps_mount_signal_and_visual_inactive`: a refusing player initially left `HogMount` mounted, moved the visual, and emitted `mounted`; `HogMount` now requires and verifies `is_hog_mounted()` before committing its own state. Full verification: shared 463 + isolated 40/17/14 = 534 |
| D7 | P2 | hog_plant_chomp.tscn:43-47,64-86; enemy_base.gd:172-180 | Plants never trigger on the intended line | VERIFIED | Trigger is spherical `distance_to <= 2.5`; `trigger_lateral_m` read only by skink. Plants x=∓3.8, crate line x=±3.8 -> 7.6 m apart |
| D8 | P2 | hog_crescendo.tscn vs hog_weave_gates.tscn | Crescendo is a structural clone of segment 2; gap_combine combines the jump with itself | VERIFIED | Number-normalised diff: only node names, title text, y 1.8->1.7, size -0.2, z+2, colour |
| D9 | P2 | level_session.gd:682 | Hog mounts reset on plain checkpoint activation, not just respawn | FIXED | `test_checkpoint_updates_spawn_without_resetting_hog_until_respawn`: checkpoint activation initially reset the mount once and respawn reset it again; mount restoration now lives beside the four restore/teleport callers, not `_set_player_spawn`, while checkpoint activation only updates the future spawn. Full verification: shared 464 + isolated 40/17/14 = 535 |
| D10 | P2 | player_controller.gd:115; player_motor.gd:48,135; :557 | `hog_tuning` defaulted to null on 4 signatures; contradicts the repo's own no-silent-default test | FIXED | `test_hog_tuning_params_have_no_silent_default`: all four omitted-argument calls initially succeeded and `configure` silently cleared `_hog_tuning`; all four signatures now require `HogTuning`, and every production/test call site was grepped and updated with the real catalog resource. Full verification: shared 466 + isolated 40/17/14 = 537 |
| D11 | P2 | tests/gameplay/test_player_controller.gd:918 | Controller tests run with `_hog_tuning == null` | FIXED | `test_shared_controller_fixture_supplies_hog_tuning`: the new assertion initially saw `<null>` instead of `hog.tres`; the shared controller fixture now passes the real `GameplayTuning.hog` resource. Full verification: shared 465 + isolated 40/17/14 = 536 |
| D12 | P2 | scripts/verify_exported_tuning.sh:66 | LEVEL META grep asserts only n_sanity_beach | FIXED | `test_export_verifier_asserts_every_authored_level_meta_path`: initially found no runtime-log assertion loop; the verifier now checks every authored `data/tuning/levels/*.tres` path. Real exported-pack smoke passed with n_sanity_beach, boulders, and hog_wild paths; full verification: Python 80, shared 466 + isolated 40/17/14 = 537 |
| D13 | P2 | test_level_scenes.gd:1103-1116 | Handoff test can pass with zero assertions | FIXED | `test_hog_wild_handoffs_overlap_on_all_three_axes`: mutating the shared segment lookup to miss the route initially failed with `0` verified handoffs versus `7`; the test now counts every fully checked adjacent pair and requires all seven. Full verification: Python 80, shared 466 + isolated 40/17/14 = 537 |
| D14 | P2 | lint_level_authoring.py | `wumpa_total` is not linted at all | FIXED | `test_wumpa_total_must_match_authored_scene_rewards`: the bad fixture initially returned no findings despite authored rewards of 7 versus `LevelMeta.wumpa_total=6`; the linter now derives standard-crate, full bounce-crate, and pickup rewards from `economy.tres` and checks every authored level. The only `LevelMetaValues`/`AuthoringTuning` constructors are their loaders. Full verification: Python 81, shared 466 + isolated 40/17/14 = 537 |
| D15 | P2 | test_ride_state.gd / hog_mount.gd | Untested: 2 of 3 `reset_for_player_position` branches, non-player body, empty curve, airborne mount/dismount, `exit_ride` grounded arg | REPORTED | Every dismount assertion is `assert_ne(state,&"ride")`, true for both branches |
| D16 | P3 | hog_mount_start/dismount_finish | `Spine/MountLine` 8 m from trigger, `DismountLine` 11 m upstream, `FirstRead` marks nothing | REPORTED | No runtime consumer for any Spine marker |
| D17 | P3 | hog_wild.tres | Best-case runtime 1:53, under §6.1's 2-min floor, unimprovable | REPORTED | 1019 m / 9.0 m/s |
| D18 | P3 | all hog segments | Required jumps at 16.786 deg vs the 15 deg rule — 1.79 deg headroom | REPORTED | Passes the lint today |
| D19 | P3 | hog_weave_gates.tscn | `GateLeft`/`GateRight` unhittable from the intended line | REPORTED | |
| D20 | P3 | 8 of 33 crate beats exceed the 2-4 s rule, worst 6.44 s | REPORTED | In line with shipped levels |

## REJECTED / cleared (checked, not defects)

| Claim | Status | Evidence |
|---|---|---|
| data/tuning/chase.tres changed | REJECTED | Blob `92f332ea` identical at 51fdae9, af585f6 and in the working tree |
| Old overrides break on the new hog section | REJECTED | `_backfill_missing_sections` (tuning_service.gd:519-535) runs at :131 before validation; regression test at test_tuning_service.gd:495-547 |
| Fingerprint might not cover hog (dead-wire) | REJECTED | Executed: 9.0 -> `aeff5511…`, 9.5 -> `08a237ba…`, restored -> `aeff5511…` |
| `catalog_is_usable` null-derefs `checked.hog` | REJECTED | Generic null sweep at :197-200 returns false first |
| Mount/dismount Area3D masks wrong | REJECTED | layer 0 / mask 1, same as the working Finish area; PROBE2 proved real detection |
| An unclearable gap softlocks the ride | REJECTED | 3 gaps, each 5.00 m, flat both sides; reach 6.84 m analytic; traced takeoff -716.8 -> landing -723.7 vs far edge -722.0 |
| Solid crates block the forced run | REJECTED | All 32 carry `break_on_touch`; block <= 1 frame (0.15 m) |
| `configure` arity engine error in the GUT log | REJECTED | Intentional `[ExpectedError]` in test_configure_gating_params_have_no_silent_default |
| Exported runtime misses hog resources | REJECTED | `verify_exported_tuning.sh` exit 0; hog.tres + hog_wild.tres present; source/runtime fingerprints match |
| Segments, seams, checkpoint spacing, camera coverage, warp-room entry | CLEAN | 8 segments on grid, exact seams; checkpoints -360/-748, intervals 40.0/43.1/30.1 s (<=60); camera union +2.0 -> -1026.0 continuous |
