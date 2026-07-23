# Phase 0 audit pass-four disposition

**Source audit:** `2026-07-23-phase0-audit-pass4-verification.md`
**Date reviewed:** 2026-07-23
**Baseline:** 100 GUT tests and 16 Python tests.

Claude's pass-four audit independently confirms that pass-three Findings A and
B are genuinely fixed. Those findings remain closed.

## Findings checklist

| Finding | Disposition | Evidence |
|---|---|---|
| 1 — body slam receives ground braking | **FIXED — OPERATOR SELECTED OPTION 1** | The operator explicitly selected committed-descent braking. `PlayerMotor.uses_airborne_momentum_model` now classifies normal airborne movement as momentum-preserving and explicitly excludes `STATE_BODY_SLAM`, with the landing intent documented beside the policy. Runtime braking is unchanged. `test_body_slam_explicitly_uses_committed_ground_braking` locks both the state classification and the authored first-frame deceleration from a slide-jump boost. |
| 2 — respawn does not reset the release profile | **FIXED** | `PlayerController.respawn` now restores `_active_jump_tap_height_m` from the authored `jump_tap_height_m` whenever tuning is configured. `test_respawn_restores_default_jump_release_profile` first drives the controller through a fixed high-jump, proves the active sentinel is `0.0`, respawns, and asserts the authored normal-jump profile is restored. Before the fix, the test failed at **0.0 versus 0.9**. |

## Audit notes

- The airborne steering arc-length model is unchanged. A code comment now
  records that higher momentum intentionally turns through a smaller angle for
  the same acceleration budget.
- The no-input landing prediction and runtime motor now agree on preserved
  horizontal momentum. This was an incidental improvement from Finding A and
  requires no additional code change.

## Verification

- Red phase: **100/101 GUT tests passed**, with only
  `test_respawn_restores_default_jump_release_profile` failing at the values
  recorded above.
- Option 1 policy red phase: **101/102 GUT tests passed**. Only
  `test_body_slam_explicitly_uses_committed_ground_braking` failed because the
  explicit state-policy method did not yet exist; established slam braking was
  intentionally left unchanged.
- Final GUT 9.7.1 run: **102/102 tests passed, 554 assertions**.
- Python `unittest`: **16/16 tests passed**.
- Gameplay numeric-literal lint, Phase 0.5 vocabulary tripwire, repository
  pre-commit hook, Bash syntax, and `git diff --check`: passed.
- Headless game boot: 120 frames, exit 0.
- Vulkan Forward Mobile movie smoke: 120 frames at 1920x1080 on llvmpipe, exit
  0; final frame visually inspected.
- Authored tuning fingerprint remains
  `8cc9cc6a011b13d986dc71581a79ce3d9ea1b83359488d7a1cb4cac0d6d0ada7`.
- Rebuilt Android debug APK: package `com.personal.crashremix`, version
  `0.1.0-phase0`, min SDK 29, target SDK 35, arm64-v8a only, VIBRATE present.
- APK Signature Scheme v2 verified with one signer. Certificate SHA-256:
  `1075362a0a73fe61f610cb501f6e626bcd60a6685e9bf396f027e52c9a9aa0f6`.
- APK SHA-256:
  `cb2b4b279a976602650542c3e93f49e9a731b253649ea1a786252f21d3463c0d`.

No device installation, device acceptance, Gate F, commit, remote, or push was
performed. H4, H11, L9, pass-two finding 10, device acceptance A-C, and Gate F
remain open and operator-only.
