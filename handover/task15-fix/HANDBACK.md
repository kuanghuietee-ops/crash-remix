# Task 15 audit-remediation handback

Phase 0.5 built. GUT: **213 tests passing** with **1,256 assertions**.
Python: **20 tests passing**.

Lints green: gameplay-numbers / content-vocabulary / traversal-authoring.

Correction (2026-07-23): the export tuning command originally returned **127**
because `rg` was absent, so the earlier “passed” claim was vacuous. R1 replaced
that undeclared dependency with `grep -qE`; the repaired verifier now exits
**0** and confirms all nine authored tuning paths, including the four traversal
`.tres` resources, load in the packed build.

On-device drawer implementation: lists `wall_run` / `grind` / `swing` / `phase`
sections. This remains covered by automation; it was not manually rechecked on a
phone during this fix pass.

Built but not judged: wall-run, grind, swing, phase-shift, and three camera
archetypes.

**Gate F2: READY TO RUN — not attempted, not scored, not inferred.**

Gate F is still open. Its latency measurement, 20-minute thermal soak, and
three-separate-days play criteria were not run or changed by this work.

## Finding dispositions

| Finding | Disposition | Evidence |
|---|---|---|
| F1 — phase state survives respawn | **FIXED** | `test_reset_returns_to_the_authored_set_and_clears_the_cooldown` and `test_respawn_restores_a_solid_platform_under_the_player`; commit `4c31cbb` |
| F2 — criterion 3 scoring unit ambiguous | **FIXED** | One attempt now means one required transfer; ten attempts accumulate across runs; threshold remains ≥8/10; commit `5b002e0` |
| F3 — continuity checked only Z | **FIXED** | `test_continuity_check_rejects_lateral_and_vertical_segment_breaks`; real gauntlet also passes full X/Y/Z bounds checks; commit `ba5c4b7` |
| F4 — displaced Phase 0 content | **DEFERRED** | Operator decision required. `Graybox` and camera `Regions` remain at x=100 exactly as instructed. Revisit only when the operator decides what to retain, with Gate F's thermal evidence still open. |
| F5 — stale APK | **FIXED** | Rebuilt from code commit `ba5c4b7` with `scripts/deploy_android.sh --build-only` |
| F6 — missing handback/counts | **FIXED** | This file records the freshly executed verification matrix and finding ledger |

## APK record

- Path: `build/crash-remix-debug.apk`
- Size: `84,010,417` bytes
- SHA-256: `6a0ab9b392206c6414a898132fe93f7379b39973d37cd39c3fdcede5a16e4bf9`
- Built: `2026-07-23 10:18:18 UTC`
- Runtime-code commit: `ba5c4b7` (`2026-07-23 10:17:20 UTC`)
- The APK remains an ignored runtime artifact and was not committed.

## Operator decisions and known limits

- “Authored outward arc” (§4.2) is built as two global constants; the wording
  may instead mean per-strip authoring.
- Wall attach tests velocity heading while §5.3/§4.2 describe input direction.
  Velocity is a proxy, not an equivalent input channel.
- PHASE ships unlocked in this toybox. Phase 1 restores §5.2 progressive
  gating.
- Proposed tuning-number changes from this fix pass: **none**.
- No gauntlet geometry, Phase 0 geometry, camera-region placement, or
  `data/tuning/` value changed.

Not tested or judged here: touch feel, thermal performance, touch latency,
three-separate-days return desire, Gate F2 success rates, or the designated
friend's camera-disorientation response.

No discrepancy was found between the verified audit findings and the ordered
fix plan.
