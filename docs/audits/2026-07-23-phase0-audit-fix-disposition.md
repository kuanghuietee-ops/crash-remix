# Phase 0 static-audit fix disposition

**Source audit:** `2026-07-23-phase0-static-audit.md`
**Rule:** every finding is assigned exactly one disposition. `DEFERRED` does not
mean passed; it identifies the external gate or later-phase scope that prevents
closure.

## Blockers and high findings

| ID | Disposition | Evidence |
|---|---|---|
| B1 | FIXED | Air-action arbitration is exclusive and matches the ratified ground policy. `test_double_jump_wins_same_frame_and_discards_losing_slam` proves DOUBLE JUMP wins and the losing DOWN edge cannot fire next frame. |
| B2 | FIXED | Invalid and unsafe overrides fall back to authored tuning, display `OVERRIDE REJECTED`, and can be removed with `RESET TO AUTHORED`. Covered by tuning-service and debug-UI rejection/reset tests. |
| H1 | FIXED | `TouchControls` rejects new contacts inside either visible debug overlay. Covered by `test_touch_ignores_new_contacts_inside_visible_debug_overlays`. |
| H2 | FIXED | Camera configuration applies `rail_bake_interval_m` even when marker setup already created the curve. Covered with a non-default interval. |
| H3 | FIXED | The camera projects corridor-forward into screen space and updates `InputRouter`. Covered by `test_camera_routes_projected_corridor_axis_to_input_router`. |
| H4 | DEFERRED | Sphere probes are now strided and always include the final trajectory point, materially reducing the worst-case query count. Only a real-phone profile and thermal soak can establish whether the remaining ray workload meets the budget. |
| H5 | FIXED | The debug HUD no longer polls and hashes the catalog every rendered frame. Fingerprints refresh only on configure, edit, save, or reset. |
| H6 | FIXED | Nudge directions are corridor-relative, biased back against travel, hazard-filtered, and rejected by `test_move` when blocked. Covered by pure direction and blocking-geometry tests. |
| H7 | FIXED | Player respawn and edge-nudge teleports reset interpolation. Both top-level depth aids subscribe to `respawned` and reset their interpolation as well. |
| H8 | FIXED | Tokenizer errors now fail the numeric lint closed and name the unscannable file. Covered by a subprocess regression test. |
| H9 | FIXED | The four cancellation-style tests were replaced by partial-frame behavioral assertions. All four were mutation-checked: they failed when `delta_s` was deliberately removed and passed again after restoration. |
| H10 | FIXED | The movement collider remains full visual height; a separate `Hurtbox` carries the 72.5% damage ratio. It is non-monitorable until an external combat system exists, preventing the player's own layer-2 attack masks from self-detecting. Crouch scales both appropriately, so the tunnel requires crouching. |
| H11 | DEFERRED | Desktop round-trip tests pass, but runtime-authored `.tres` resolution inside the signed APK requires acceptance step B on a real device. |
| H12 | FIXED | Non-runtime authoring/measurement fields are excluded from the live drawer, and the HUD explicitly says the hash proves loaded values only. The device procedure separately requires observable jump behavior for liveness. |

## Medium findings

| ID | Disposition | Evidence |
|---|---|---|
| M1 | FIXED | Touch layout listens for viewport size changes and polls safe-rect/DPI inputs at the authored 0.5-second maintenance interval, covering same-size safe-area flips without per-frame platform calls. |
| M2 | FIXED | Overlapping button circles select the nearest normalized hit; JUMP wins exact ambiguity. Covered at a point previously misclassified as SPIN. |
| M3 | FIXED | Blob-shadow rays start at the authored positive offset above the target. Covered by `test_blob_shadow_ray_starts_at_authored_offset_above_target`. |
| M4 | FIXED | Every FSM step prunes expired press and release queues. Covered for unconsumed SPIN and DOWN releases. |
| M5 | FIXED | Prediction now applies gravity before advancing position, matching the controller's semi-implicit integration order. |
| M6 | FIXED | The graybox contains an optional, visibly red `hazard` platform, making hazard filtering and the red landing-ring branch reachable. |
| M7 | FIXED | Tuning HUD/drawer configuration and visibility are gated by `OS.is_debug_build()`. |
| M8 | FIXED | The vacuous group-only assertion was replaced by an explicitly limited Phase 0.5 vocabulary tripwire with identifier and scene-node mutation tests; it runs in pre-commit. It is documented as early warning only, while code/design review establishes structural scope. |
| M9 | FIXED | The landing ring hides once grounded and is asserted visible after a jump, instead of treating the feet-pinned grounded probe as correct. |
| M10 | FIXED | The tuning test now asserts design relationships and safety invariants rather than freezing every initial tuning value. |
| M11 | FIXED | Deployment tests execute build-only and single-device install/stop/launch paths against isolated fake tools and temporary roots. |
| M12 | FIXED | GUT and Python counts remain separate, and the repository pre-commit hook now executes the discovered Python suite. |
| M13 | FIXED | The preset names a project-relative debug keystore restored from repository-pinned non-secret material. The deploy script verifies the exact keystore SHA-256 and explicitly blocks certificate-mismatch recovery from silently endangering `user://tuning/override.tres`. |
| M14 | FIXED | Acceptance B.4 now refers to the fingerprint recorded in B.2. |
| M15 | FIXED | Explicit policy: a simultaneous new ground JUMP+DOWN press produces a normal jump and discards the losing DOWN edge, preventing both a zero-length slide-jump and a next-frame slam. |
| M16 | NOT APPLICABLE | The queue window measures release-event age, not hold length. `velocity_after_release` ignores non-rising motion; every positive Phase 0 impulse is jump-family motion. No Phase 0 non-jump positive impulse can be clipped. |
| M17 | FIXED | Landing assist has its own `landing_assist_probe_depth_m`; changing blob-shadow reach no longer changes assist behavior. |

## Low findings

| ID | Disposition | Evidence |
|---|---|---|
| L1 | FIXED | Universal `HALF`/`DOUBLE` math constants live in `ScalarMath`; gameplay code no longer disguises 2.0 as `1.0 + 1.0`. |
| L2 | FIXED | Catch-all width is now `InputTuning.jump_catchall_width_ratio` and has a differential wiring test. The hard lint scope remains the explicitly required `src/gameplay/**`. |
| L3 | FIXED | README records that GUT 9.7.1 is intentionally vendored for reproducible offline tests. |
| L4 | FIXED | A successful save immediately adds the override path to loaded-path reporting; the reset test verifies it is then removed. |
| L5 | FIXED | The high-jump ledge top is above normal-jump height and at or below high-jump height, enforced by an integration test. |
| L6 | FIXED | Initial camera setup now updates with a zero delta instead of passing a duration as a frame delta. |
| L7 | FIXED | Region transitions track origin, target, and elapsed time, reaching the target at exactly `region_blend_s`; partial and completion behavior are tested. |
| L8 | FIXED | Gamepad D-pad presses emit unified discrete movement intents and retain precedence over analog-stick drift. |
| L9 | DEFERRED | Attack volumes are sized and state-gated, but Phase 0 deliberately prohibits crates and enemies. Damage targets and hit callbacks belong after the human feel gate. |

## Operator decisions applied

- The reduced ratio is a separate damage hurtbox, not the movement collider.
- Simultaneous new JUMP+DOWN gives JUMP priority.
- Debug tuning tools are hidden in non-debug builds.
- Unit conversion and non-runtime authoring/measurement values are not live sliders.
- GUT remains vendored.
- Acceptance B.4 means the fingerprint recorded in B.2.
- Catch-all width lives in `InputTuning`.

The real-device acceptance test and Gate F remain operator-only and are not marked
passed here.

## Final automated verification

- GUT: 95/95 tests passed, 530 assertions.
- Python: 16/16 tests passed.
- Numeric lint, Phase 0.5 vocabulary tripwire, pre-commit hook, and `git diff --check`: passed.
- Headless game boot: 120 frames, exit 0.
- Vulkan rendered-scene smoke test: exit 0; final frame visually inspected.
- Tuning fingerprint:
  `8cc9cc6a011b13d986dc71581a79ce3d9ea1b83359488d7a1cb4cac0d6d0ada7`.
- Android debug APK: package `com.personal.crashremix`, min SDK 29, target SDK
  35, arm64-v8a only, VIBRATE present, v2 signature verified.
- Debug certificate SHA-256:
  `1075362a0a73fe61f610cb501f6e626bcd60a6685e9bf396f027e52c9a9aa0f6`.
- APK SHA-256:
  `14515da05054517a2bbca1e48baf52eac136f6bb2d4696236396e0d6caf03789`.
