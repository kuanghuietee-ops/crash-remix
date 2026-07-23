# Wave 1 follow-up handback

Date: 2026-07-23

Starting revision: `badb6a9`

Implementation revision: `5819ec0`

## Outcome

N1 and N2 are fixed without changing camera behavior, gameplay behavior,
tuning values, tuning migration behavior, geometry, or scenes. N3 remains an
operator decision and was not implemented.

Gate F and Gate F2 are human-only. Neither gate was run, judged, scored, or
recorded during this pass.

## N1 live camera result

The repointed wall-run conformance test **PASSED**. It calls
`wall_run_basis_for_view`, the same function used by the controller, and
derives the settled view direction with the same offset-axis, look-ahead,
look-height, and screen-bias math as `CameraRailController.update_camera`.

With tangent `Vector3.BACK`, the exact unnormalized view directions were:

- right-facing surface normal: `Vector3(0.45, -0.85, 8.0)`;
- left-facing surface normal: `Vector3(-0.45, -0.85, 8.0)`.

Their normalized forms are approximately
`Vector3(0.055848, -0.105490, 0.992851)` and
`Vector3(-0.055848, -0.105490, 0.992851)`.

The live orientation integration test separately instantiates the authored
canyon, attaches at **4.0 m** on both LeftStrip and RightStrip, drives the real
camera controller, and confirms both resulting bases are upright and
right-handed with determinant +1.

The current down-the-slot shot therefore satisfies the existing §5.5
tangent-horizontal assertion. This automated result does not resolve N3's
design ambiguity between the side-on/3/4 wording and the down-the-slot wording.

## Dead basis entry points

The dead `wall_run_basis`, `grind_basis`, and `swing_basis` wrappers were
deleted. After the tests were repointed, no production or test caller remained.
The structural test now fails if any of those duplicate entry points returns,
leaving one shipped and tested basis path per traversal archetype.

## N2 migration-registry protection

`test_every_exported_field_has_override_migration_coverage` reflects every
exported field across every `GameplayTuning` section. It requires an exact
one-to-one match with either the frozen pre-cohort baseline or
`LEGACY_FIELD_GROUPS_BY_SECTION`; it also rejects stale or duplicate entries.
The cohort implementation and its zero-value semantics were not changed.

The red proof used a temporary unregistered exported field named
`input.migration_coverage_probe`. The test failed by naming that exact field as
uncovered. The probe was then removed with no remaining source diff.

## Finding dispositions

| Finding | FIXED | DEFERRED | NOT APPLICABLE |
| --- | --- | --- | --- |
| N1 | Conformance tests now call the live `_for_view` functions with controller-derived view directions. `test_live_wall_run_camera_is_upright_and_right_handed_on_both_walls` covers the real canyon at 4.0 m, and `test_camera_archetypes_expose_only_the_live_basis_entry_points` prevents the dead trio from returning. | — | — |
| N2 | `test_every_exported_field_has_override_migration_coverage` fails when any exported tuning field escapes both the frozen baseline and the cohort registry. | — | — |
| N3 | — | Operator must choose how §5.5's side-on/3/4 rule and down-the-slot canyon shot apply. No behavior or specification decision was made here. | — |

## Test-count accounting

- Baseline: 220 GUT tests.
- N1: two tests added; existing conformance tests were repointed, not removed.
- N2: one test added.
- Final: **223/223 GUT passing**, 1,803 assertions across 20 scripts.
- Python: **22/22 passing**.

No test was deleted, weakened, skipped, or marked pending.

## Final automated verification

- `scripts/lint_gameplay_numbers.py`: passed.
- `scripts/check_content_vocabulary.py`: passed.
- `scripts/lint_traversal_authoring.py`: passed, exit 0.
- `scripts/verify_exported_tuning.sh`: passed, **EXIT=0**.
- No diff in `camera_rail_controller.gd`, `tuning_service.gd`, `data/tuning/`,
  `scenes/`, or `docs/qa/phase05-gate-f2.md`.

These are automated checks only. Device feel and both human gates remain
untested.

## Commits

- `74809ce` — N1: test the live camera basis path and remove the dead trio.
- `5819ec0` — N2: fail when a tuning field escapes migration coverage.

## Audit notes

The audit's N1 and N2 findings were correct. Its warning that the repointed
wall-run assertion might fail was appropriately conditional; with the actual
controller-derived view vectors above, it passed. No audit finding was rejected
as incorrect.
