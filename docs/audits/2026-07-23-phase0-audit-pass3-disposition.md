# Phase 0 audit pass-three fix disposition

**Source audit:** `2026-07-23-phase0-audit-pass3-verification.md`
**Date fixed and verified:** 2026-07-23
**Baseline:** 95 GUT tests and 16 Python tests before this batch.

The pass-three auditor confirmed all twelve pass-two dispositions. They remain
closed and were not rewritten in this batch.

## Findings checklist

| Finding | Disposition | Evidence |
|---|---|---|
| A — airborne ground braking dead-wires slide-jump distance | **FIXED** | This was a pre-existing motor defect, not a regression from either fix batch. `PlayerMotor.horizontal_velocity` now has an explicit momentum-preserving airborne branch. Zero input returns the existing horizontal velocity unchanged. Directional input can steer and accelerate up to `run_speed_mps`, using the existing run responsiveness, but never reduces an already larger slide-jump boost. No new gameplay constant was required. Before the fix, `test_slide_jump_travels_authored_distance_across_full_airtime` failed at **4.484751 m versus 5.5 m**, and `test_releasing_stick_in_air_preserves_slide_jump_momentum` failed at **5.672149 m/s versus 8.588816 m/s after one frame**. Both now pass, and `test_air_input_steers_without_spending_slide_jump_boost` guards the chosen steering model. The four existing H9 partial-frame ground/crouch/slide tests remain green. |
| B — high/slide jump share the 0.9 m variable-release clamp | **FIXED — OPERATOR SELECTED OPTION 1** | The operator explicitly selected fixed-height high-jump and slide-jump behavior. `tap_height_for_impulse` now reserves variable release for normal and double jumps; high/slide jumps return the `0.0` disabled sentinel. `advance_logic` stores that sentinel for jump impulses while preserving body-slam handling, and `velocity_after_release` now explicitly returns unchanged velocity for non-positive tap heights. Before the fix, immediate release clipped both moves to **6.559232 m/s**, instead of the authored high-jump **11.790824 m/s** and slide-jump **8.186790 m/s** launch speeds. Both full-controller regressions now pass. Existing normal-jump and independent double-jump release tests remain green. The device checklist now calls out both fixed-height sanity checks. No tuning value or tuning field changed. |

## Audit notes acknowledged

- `respawn_floor_y_m >= 0.0` remains intentionally a bounded sign check, not a
  scene-geometry proof. No code change was requested.
- The vocabulary tripwire's tokenizer fallback remains intentionally
  conservative. It is early warning rather than structural scope proof, so no
  fail-closed tokenizer change was requested.

## Remaining external gates

- **H4:** landing-ring query cost still requires real-phone profiling and the
  20-minute thermal soak.
- **H11:** runtime-authored `.tres` loading in the signed APK still requires
  device acceptance step B.
- **L9:** combat targets and callbacks remain blocked until after Gate F.
- **Pass-two finding 10:** ledge-nudge stickiness remains a Gate F feel
  observation.
- Device acceptance A–C and Gate F were not run or marked passed.

## Independent verification

- Red phase reproduced the audit: 95/97 GUT tests passed, with only the two new
  displacement/momentum regressions failing at the values recorded above.
- Finding B's red phase then ran from the Finding A-green baseline: **98/100**
  GUT tests passed. Only the two new full-controller early-release regressions
  failed, both at **6.559232 m/s**. The first mapping-only attempt drove both to
  zero and exposed that `velocity_after_release` lacked the audit's assumed
  non-positive-height no-op; the final sentinel guard closed that path.
- Final GUT 9.7.1 run: **100/100 tests passed, 544 assertions**.
- Python `unittest`: **16/16 tests passed**.
- Gameplay numeric-literal lint, Phase 0.5 vocabulary tripwire, repository
  pre-commit hook, Bash syntax, and changed-function call-site scans: passed.
- `git diff --check`: passed.
- Headless game boot: 120 frames, exit 0.
- Vulkan Forward Mobile movie smoke: 120 frames at 1920×1080 on llvmpipe, exit
  0; final frame visually inspected.
- Authored tuning fingerprint remains
  `8cc9cc6a011b13d986dc71581a79ce3d9ea1b83359488d7a1cb4cac0d6d0ada7`,
  as expected because this batch repairs runtime wiring without changing an
  authored value.
- Rebuilt Android debug APK: package `com.personal.crashremix`, version
  `0.1.0-phase0`, min SDK 29, target SDK 35, arm64-v8a only, VIBRATE present.
- APK Signature Scheme v2 verified with one signer. Certificate SHA-256 remains
  `1075362a0a73fe61f610cb501f6e626bcd60a6685e9bf396f027e52c9a9aa0f6`.
- APK SHA-256:
  `b5d069945be0237853ac55a85f19213611388fccb07fff91c7a775d856fbc8e5`.

No device installation, device acceptance, Gate F, commit, remote, or push was
performed.
