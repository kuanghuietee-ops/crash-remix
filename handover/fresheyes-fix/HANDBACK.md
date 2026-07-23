# Phase 0.5 fresh-eyes Wave 1 handback

Date: 2026-07-23

Starting revision: `c50d992`

Implementation revision: `2675e11`

## Outcome

Wave 1 is complete. A1–A9 are fixed in the required commit groups. No tuning
values or tuning fields were changed, no gauntlet or Phase 0 geometry was
changed, and the wall-run upright-basis fix from `ad5c696` remains intact.

Gate F and Gate F2 are human-only. Neither gate was run, scored, judged, or
recorded during this work.

## Final automated verification

- GUT: **220/220 passing**, 1,331 assertions across 20 scripts.
- Python: **22/22 passing**.
- `scripts/lint_gameplay_numbers.py`: passed.
- `scripts/check_content_vocabulary.py`: passed.
- `scripts/lint_traversal_authoring.py`: passed, exit 0.
- `scripts/verify_exported_tuning.sh`: passed, **EXIT=0**.
- Forbidden-scope diff check for `data/tuning/`, `scenes/game.tscn`,
  `scenes/camera_rig.tscn`, and `docs/qa/phase05-gate-f2.md`: no changes.

These are automated checks only. No claim is made about either human gate or
about device feel.

## Wall-run attachment distances

Every wall-run test added or amended in this batch attaches at **4.0 m** along
the strip, never at distance 0:

- expiry-frame buffered detach: 4.0 m;
- strip-end exit and tuned velocity: 4.0 m;
- timeout exit and tuned velocity: 4.0 m;
- real-physics landing-pad integration: 4.0 m;
- real-canyon camera occlusion on LeftStrip and RightStrip: 4.0 m on each.

## Finding dispositions

| Finding | FIXED | DEFERRED | NOT APPLICABLE |
| --- | --- | --- | --- |
| A1 | Camera now looks down the canyon slot without crossing the opposite wall. Protected by `test_wall_run_camera_is_unoccluded_on_both_real_canyon_walls`. | — | — |
| A2 | Expiry is evaluated after wall-run input dispatch, so a buffered expiry-frame jump emits wall detach, never double jump. Protected by `test_expiry_frame_jump_detaches_from_a_nonzero_strip_distance`. | — | — |
| A3 | Wall-run motion detects the authored strip end and exits there. Protected by `test_strip_end_exits_with_tuned_velocity_from_a_nonzero_attach` and `test_mid_strip_attach_reaches_the_authored_landing_pad`. | — | — |
| A4 | Timeout and strip-end exits both use the existing tuning-sourced wall-detach velocity. Protected by `test_timeout_clears_the_active_strip_and_restores_grounded_motion` and the strip-end test above. | — | — |
| A5 | Phase-0-shaped input overrides backfill the phase-button field cohort while preserving existing operator edits and retaining invalid-current-override rejection. Protected by `test_phase_zero_input_fields_backfill_without_losing_operator_values`. | — | — |
| A6 | `move.run_speed_mps <= 0` is rejected before save or load activation. Protected by `test_zero_run_speed_and_action_buffers_are_rejected`. | — | — |
| A7 | Zero jump and action buffer windows are rejected. Protected by `test_zero_run_speed_and_action_buffers_are_rejected`. | — | — |
| A8 | Native safe-area coordinates and DPI are converted into logical canvas space. Protected at 1440- and 720-tall native resolutions by `test_native_safe_areas_map_into_tall_and_short_logical_viewports`. | — | — |
| A9 | The false swing exemption assertion was removed; the wall-run-only §5.4 exemption and corrected comment remain in `test_wall_run_deliberately_uses_section_5_4_exemption`. No swing value was changed. | — | — |

No Wave 1 finding is deferred or not applicable.

## Commits

- `b7959c7` — A1+A2+A3+A4: wall-run completion and canyon camera.
- `d6ec55f` — A5: legacy override field migration.
- `ce5d78c` — A6+A7: zero-value playability guards.
- `413b173` — A8: native-to-logical touch layout conversion.
- `2675e11` — A9: correct the wall-run-only camera exemption test.

## Audit notes and remaining scope

I found no incorrect Wave 1 finding in the audit. One implementation nuance was
important: Godot's `ResourceSaver` omits fields holding script-default values,
so a generic “replace every zero” migration would also accept deliberately
invalid current overrides. A5 therefore migrates the three phase-button fields
as one version-defining cohort and leaves all other zero-value validation
fail-closed.

The audit's note that `minimum_jump_depression_degrees` has no production
consumer is confirmed. Implementing that rule, plus all other Wave 2 and Wave 3
findings, remains outside this pass exactly as instructed.
