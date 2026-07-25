# Phase 1 Wave A — audit-fix ledger

Source audit: `docs/audits/2026-07-24-phase1-wave-a-audit.md`
Started from: `975df4e` (D8 complete). P0/P1 and 30 P2 findings already landed in
commits `7172115..975df4e` (70 commits).

**This file is the source of truth for what remains.** Update the row the moment a
finding reaches a terminal status. Statuses: `OPEN` · `VERIFIED` (read the code, it is
real) · `REJECTED` (read the code, it is not) · `FIXED` (evidence = test name) ·
`DEFERRED` (evidence = why + unblocker) · `NOT APPLICABLE` (evidence).

Rules in force: one finding at a time, failing test first, never weaken a test or lint,
no gameplay numbers in `src/gameplay/**`, explicit-path staging only, stop at
Checkpoint A (do not start Task 17 / Wave B), never touch `docs/qa/phase05-gate-f2.md`.

---

## P2 — 9 remaining (D9 FIXED)

| ID | File | Claim | Status | Evidence |
|----|------|-------|--------|----------|
| D9 | `scenes/props/crate_checkpoint.tscn` | respawn offset `Vector3(0,-0.45,2)` authored in the scene — invisible to the numeric lint, untunable on device | FIXED | `test_checkpoint_respawn_transform_follows_tuned_offset` (`tests/integration/test_island_slice.gd`) — real level, real checkpoint crate 14; mutates `EconomyTuning.checkpoint_respawn_offset` and proves the actual respawn transform tracks it (and would NOT match the old scene-authored value). Added `EconomyTuning.checkpoint_respawn_offset` (consumed in `LevelSession._checkpoint_spawn_transform`), removed the dead `Spawn` marker from the scene, registered the field in `TuningService`'s legacy-migration cohorts, fixed 2 pre-existing tests that were circularly asserting against the same scene marker the runtime read (`test_level_run_state.gd`, `test_mercy_and_masks.gd`), and fixed the debug-drawer field-count test's expectation logic which assumed every economy field renders as one row (Vector3 renders as 3 component rows). Full suite green: GUT 416/416 (4,053 asserts), Python 47/47, all 4 lints EXIT=0.|
| N1 | `src/tuning/tuning_service.gd` (`catalog_is_usable`) | **Raised by the Opus audit of the D9 fix.** D9 added `EconomyTuning.checkpoint_respawn_offset` with a sentinel default of `Vector3(-999999,-999999,-999999)` and did **not** add it to `catalog_is_usable`. It is now the only 1 of 20 exported economy fields with no bound, undoing A6's guarantee for the one field whose failure mode is worst: a leaked sentinel (or an operator dragging the drawer's y slider low) respawns the player 999 km under the world on every checkpoint — an unrecoverable death loop, i.e. P0-2's exact shape reintroduced through tuning. `_resource_values_are_finite` passes it. | FIXED | `catalog_is_usable` now rejects `economy.checkpoint_respawn_offset.y <= move.respawn_floor_y_m` — a cross-field invariant reusing the already-tuned, already-validated fall floor instead of a new magic number; catches both the raw sentinel and any non-sentinel value an operator drags below the floor. Proved via `test_playability_critical_soft_brick_values_are_rejected` (in-memory, both the sentinel and an at-floor value rejected, authored catalog still accepted) and `test_every_invalid_economy_field_is_rejected_from_disk` (a real override file, at-floor value, rejected end-to-end through `load_from_paths`; the literal sentinel is deliberately excluded from this one since it's this field's own script default and its legacy cohort is a lone field, so the real backfill path heals it before `catalog_is_usable` ever runs — asserting rejection there would be a false expectation). Added guard-the-guard `test_every_exported_economy_field_has_a_rejection_case`, which asserts every exported `EconomyTuning` field has a bad-value case in the new shared `_economy_invalid_values` helper; proved mutation-sensitive by temporarily deleting the new entry and observing it fail, then restoring it. Full suite green: GUT 417/417 (4,081 asserts, +1 test over the 416/4,053 baseline), Python 47/47, all 4 lints EXIT=0. Call sites of `catalog_is_usable` grepped (`tuning_service.gd:80,120`, `tuning_debug_ui.gd:128`) — only the return value is consumed, so tightening it cannot break a caller; it can only correctly reject a state that was wrongly accepted before. |
| I7 | `src/ui/safe_area_control.gd` | does not poll; a sensor-landscape 180° flip leaves it stale (A8 pattern in `touch_controls.gd` already polls) | OPEN | |
| I8 | `scenes/ui/hud.tscn` | §5.2 occlusion rule holds but is unasserted; `_hud` missing from `_level_touch_exclusions` | OPEN | |
| I9 | `src/ui/results_screen.gd` | `present()` is `pass` | OPEN | |
| I10 | `src/ui/results_screen.gd` | HUD/results counters unasserted | OPEN | |
| I11 | `src/ui/pause_overlay.gd` | no test emits any pause-overlay signal; deleting quit-to-hub stays green | OPEN | |
| I12 | `src/ui/pause_overlay.gd` | retry-without-hub unasserted | OPEN | |
| I14 | `tests/integration/test_warp_room.gd` | Task 15's own poll assertion races `GameRoot`'s `load_threaded_get`, red ~1 run in 3 | OPEN | |
| A8 | `src/tuning/tuning_service.gd` | N2 migration-coverage guard accepts baseline registration as a cohort → new economy field silently discarded from an older override, guard stays green | FIXED | Verified real by reading `test_every_exported_field_has_override_migration_coverage`: it treats "listed in `PHASE0_BASELINE_FIELDS_BY_SECTION`" (a hand-typed, test-local constant) and "listed in a `LEGACY_FIELD_GROUPS_BY_SECTION` cohort" (the runtime script's constant) as equally valid coverage, but only the latter is ever actually backfilled by `_backfill_legacy_field_groups`. Added `test_phase_zero_baseline_field_set_is_frozen` in `tests/tuning/test_tuning_service.gd`, which hashes the sorted `(section, field)` set of `PHASE0_BASELINE_FIELDS_BY_SECTION` (sha256) against a hardcoded, deliberately-recomputed signature — so a field can no longer be silently added to baseline; growing it now requires consciously recomputing the frozen hash, and a genuinely new field belongs in a legacy cohort instead. Proved by mutation: temporarily moved `checkpoint_respawn_offset` from `tuning_service.gd`'s legacy cohort into the test's baseline list (the exact A8 shape) — the pre-existing `test_every_exported_field_has_override_migration_coverage` stayed green (1/1 passed, confirming the guard really is satisfiable without real migration coverage), while the new `test_phase_zero_baseline_field_set_is_frozen` went red (hash mismatch); reverted both files and confirmed 418/418 green again. Full suite green: GUT 418/418 (4,083 asserts, +1 over the 417/4,081 post-N1 baseline), Python 47/47, all 4 lints EXIT=0. Test-only change — no production signature touched, so no call sites to grep. |
| A9 | `scripts/verify_exported_tuning.sh:43` | greps for "Phase 0 tuning failed to load"; Phase 1 boot emits "Phase 1", so the failure string can never match | FIXED | Verified real by reading the actual emitters: `src/core/game_root.gd:105` (the real `scenes/main.tscn` boot path the exported build and the smoke harness both use) prints `"Phase 1 tuning failed to load: ..."`; only the retired toybox `src/core/phase0_game.gd:38` still prints the literal `"Phase 0 tuning failed to load"` the script grepped for. Changed the grep on `verify_exported_tuning.sh:42` from the literal `Phase 0 tuning failed to load` to `Phase [0-9]+ tuning failed to load`, so it matches the current emitter and any future phase-numbered one without needing another fix later. Added a permanent, static regression test (`test_export_verifier_detects_game_root_s_real_boot_failure_message` in `tests/deploy/test_exported_tuning_contract.py`) that extracts the real `push_error` message from `game_root.gd`'s source and the grep pattern from the shell script's source, and asserts the pattern matches the message — this fails again immediately if either string ever drifts. Proved by mutation two ways: (1) ran the new test against the unfixed script first and captured the literal RED (`Regex didn't match: 'No loader found|Phase 0 tuning failed to load' not found in 'Phase 1 tuning failed to load'`); (2) ran the real, unmodified `verify_exported_tuning.sh` end-to-end (real Godot export + smoke boot) against a genuinely broken base tuning path and directly grep-tested the real captured runtime log with both patterns — the old pattern did not match (`OLD: NO MATCH`), the new one did (`NEW: MATCHED`); reverted the boot-path mutation immediately after (`game_root.gd` confirmed byte-identical to its committed state via `git diff --stat`). Full suite green: GUT 418/418 (4,083 asserts, unchanged), Python 48/48 (+1 over the 47 baseline), all 4 lints EXIT=0. Grepped every reference to the old literal string across `*.gd`/`*.sh`/`*.py`/`*.md`; the only other emitter (`phase0_game.gd`) is also matched by the broadened pattern, and the remaining hits are historical audit/handover prose left untouched. |

## P3 — 47 remaining

| ID | File | Claim | Status | Evidence |
|----|------|-------|--------|----------|
| E6 | `src/gameplay/run/level_run_state.gd` | `accept_mercy_skip()` has no precondition and voids a run never offered a skip; its test exercises that illegal path | OPEN | |
| E7 | `src/gameplay/run/level_run_state.gd` | relic completion reports `wumpa_banked` that is never banked | OPEN | |
| E8 | `src/gameplay/run/level_run_state.gd` | `restore()` silently drops broken crates when `authored_crate_ids` is `[]` | OPEN | |
| E9 | `src/gameplay/run/level_run_state.gd` | the pure model's invariants are enforced by the Node glue, not the model | OPEN | |
| E10 | `src/gameplay/run/level_run_state.gd` | `record_death(economy)` dereferences `economy` with no null guard | OPEN | |
| E11 | `src/gameplay/run/level_run_state.gd` | `relic_tier` can go stale against `best_relic_time_ms` | OPEN | |
| B11 | `src/core/game_root.gd` | design §4.4 lists app-pause as a profile write trigger; `store_profile` is never called on app pause | OPEN | |
| B12 | `src/core/save_service.gd` | `recovered_from_backup` is set and read by nothing — a rollback is invisible | OPEN | |
| J3 | `src/gameplay/player/player_controller.gd` | a locked `ACTION_PHASE` press is not consumed and can fire on the frame the gate opens | OPEN | |
| J4 | `src/gameplay/player/player_controller.gd` | new gating params default to `false`/`null`, defeating the compiler backstop behind "grep every call site" | OPEN | |
| J5 | git history | all 16 commits authored by generic `root` | OPEN | |
| J6 | `src/ui/safe_area_control.gd` | unplanned file — not in 02-PLAN's file list | OPEN | |
| J9 | `build/` | a stale `.idsig` sits beside the APK | OPEN | |
| J10 | `android/` | a debug keystore is committed (predates this range) | OPEN | |
| J14 | `handover/phase1/` | the entire Phase 1 authorisation package is untracked | OPEN | |
| G8 | `scripts/lint_level_authoring.py` | spine ≠ playable extent | OPEN | |
| G9 | `scripts/lint_level_authoring.py` | spine ordered by document order | OPEN | |
| G10 | `scripts/lint_level_authoring.py` | no off-spine projection check | OPEN | |
| G11 | `scripts/lint_level_authoring.py` | region bounds ignore rotation/scale | OPEN | |
| G12 | `scripts/lint_level_authoring.py` | overlap resolution differs from runtime | OPEN | |
| G13 | `scripts/lint_level_authoring.py` | parser drops unclassifiable lines silently | OPEN | |
| G14 | `tests/lint/test_level_authoring_lint.py` | rule-edge test gaps | OPEN | |
| C11 | `src/core/game_root.gd` | `NOTIFICATION_WM_CLOSE_REQUEST` is untested — removing it costs nothing | OPEN | |
| C16 | `src/core/game_root.gd` | §4.4's several write triggers collapse to one `store_profile` call site | OPEN | |
| C17 | `src/gameplay/player/player_controller.gd` | `configure`'s new params default, blunting Task 16's own discipline | OPEN | |
| C18 | `src/ui/hud.gd`, `src/core/game_root.gd` | stale mercy banner across runs; hub touch exclusions omit the drawer; retry-from-pause round-trips a full hub instantiate | OPEN | |
| C19 | `src/core/game_root.gd` | the load poll is unbounded with no timeout and no loading affordance | OPEN | |
| F16 | `src/gameplay/run/level_session.gd` | `respawn_requested` is emitted and never consumed | OPEN | |
| F17 | `tests/gameplay/*` | a test launders `tnt_blast_radius_m`/`mask_stack_maximum` and can go vacuous | OPEN | |
| F18 | `tests/gameplay/*` | no `after_each`; fixture early-returns leak nodes | OPEN | |
| F20 | `src/gameplay/player/player_controller.gd` | `receive_hit()` keeps consuming masks while already dying | OPEN | |
| H7 | `tests/integration/test_level_scenes.gd` | re-declares crate counts as the literal `40` in three places instead of reading `LevelMeta` | OPEN | |
| H8 | `tests/integration/test_level_scenes.gd` | the enemy-free assertion is vacuous — nothing joins the `enemy` group (re-introduces Phase 0 M8) | OPEN | |
| H9 | `scenes/segments/*` | only 1 of 3 enemy-bearing segments carries the "ENEMIES IN TASK 17" disclosure | OPEN | |
| H10 | `scenes/levels/wr1_n_sanity_beach.tscn` | §5's "TNT beside a stack" authored as a flat row → 2.0 m blast reaches 1 of 2 neighbours; test written to geometry not the design beat | OPEN | |
| A12 | `README.md:66` | still advertises the retired "Phase 1 content vocabulary tripwire" | OPEN | |
| A13 | `src/core/scalar_math.gd` | open numeric-laundering channel into `src/gameplay/**` the lint's default scope cannot see (no instance yet) | OPEN | |
| D10 | `src/gameplay/crates/crate_logic.gd` | `_finish_break`'s guard untested; `_set_crate_visual` re-arms crates by poking private fields | OPEN | |
| D11 | `src/gameplay/crates/crate_logic.gd` | bounce `> max` and `<= 0` branches unreachable and untested | OPEN | |
| D13 | design vs canon | landing on a standard crate does nothing — code matches plan; plan may not match canon (operator call) | OPEN | |
| I15 | hub/UI | minor | OPEN | |
| I16 | hub/UI | minor | OPEN | |
| I17 | hub/UI | minor | OPEN | |
| I18 | hub/UI | minor | OPEN | |
| I19 | hub/UI | minor | OPEN | |
| I20 | hub/UI | minor | OPEN | |
| I21 | hub/UI | minor | OPEN | |

## Final

| ID | Item | Status | Evidence |
|----|------|--------|----------|
| CKA | Checkpoint A verification + handback (full suite green count, APK SHA-256, handback doc) | OPEN | |

---

## Notes

- `I15`–`I21` and `G8`–`G14` are collapsed ranges in the audit's P3 prose. Their
  individual claims must be recovered from the raw auditor notes or re-derived by
  reading the code before they can leave `OPEN`.
- Anything a fix round raises that is new goes in as a new row, not a footnote.
</content>
</invoke>
