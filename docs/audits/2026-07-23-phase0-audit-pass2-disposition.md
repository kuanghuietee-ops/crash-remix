# Phase 0 audit pass-two fix disposition

**Source audit:** `2026-07-23-phase0-audit-pass2-verification.md`
**Date fixed and verified:** 2026-07-23
**Rule:** every numbered finding has exactly one disposition. `DEFERRED` is not
a pass; it names the external human gate that prevents a responsible code change.

## Numbered findings

| Finding | Severity | Disposition | Evidence |
|---|---|---|---|
| 1 | HIGH | FIXED | Air JUMP+DOWN now applies the ratified ground policy: DOUBLE JUMP wins and the losing DOWN edge is consumed. `test_double_jump_wins_same_frame_and_discards_losing_slam` proves no next-frame slam occurs. |
| 2 | MEDIUM | FIXED | `Hurtbox` remains on collision layer 2 but is explicitly non-monitorable until an external combat system exists. The player scene test asserts this, preventing the layer-2 Spin/Slam masks from self-detecting it. |
| 3 | MEDIUM | FIXED | D-pad input takes precedence whenever non-zero, including during analog motion events. A regression injects sub-dead-zone stick drift after D-pad RIGHT and still observes `Vector2.RIGHT`. |
| 4 | MEDIUM | FIXED | Viewport size changes remain signal-driven; safe-area/DPI maintenance polling is accumulator-gated to the authored 0.5-second interval. A count-based regression proves sub-interval frames do not poll. The platform interval is validator-protected and excluded from the live drawer. |
| 5 | MEDIUM | FIXED | The exact non-secret debug keystore is restored from repository-owned base64 material and verified against SHA-256 `3926b1f9d7403e4067f3e062801c4d90ac5490132819893cc18075462d1a8aa9` before signing. Deployment tests prove clean regeneration is byte-stable. `INSTALL_FAILED_UPDATE_INCOMPATIBLE` now stops before launch and explicitly warns that uninstalling destroys `user://tuning/override.tres`. |
| 6 | MEDIUM | FIXED | `catalog_is_usable` now explicitly guarantees Phase 0 playability, recoverable controls, and finite runtime math. It rejects non-positive maximum fall speed, a non-negative respawn floor, negative jump/action/coyote windows, invalid jump tap/full relationships, and a non-positive layout poll interval. Differential regressions cover every audited soft-brick value. |
| 7 | MEDIUM | FIXED | The script and hook are renamed to `check_phase0_vocabulary.py` and their output says “Phase 0.5 vocabulary tripwire.” It scans paths, identifiers, and scene structural names while ignoring comments and prose strings. README and the first disposition state plainly that it is early warning, while code/design review establishes structural scope. Synthetic identifier, scene-node, comment, and prose tests cover the contract. |
| 8 | LOW | FIXED | Drawer rebuild removes every old row from its parent before queueing deletion. An immediate child-count regression proves RESET does not render duplicate rows for a frame. |
| 9 | LOW | FIXED | Landing-ring probe selection is now an O(1) modulus/final-index predicate. The per-physics-frame `PackedInt32Array` allocation and repeated linear `.has()` scan are gone; stride/final-point behavior remains tested. |
| 10 | LOW | DEFERRED — GATE F | No blind movement change was made, as the audit required. The device procedure now calls out deliberate short hops off ledges so the operator can judge whether recovery-direction nudge priority feels sticky. |
| 11 | LOW | FIXED | Touch exclusion now accepts multiple controls, and Phase 0 registers both the HUD and Drawer. A regression presses through each overlay and proves neither contact creates a floating stick or movement intent. |
| 12 | LOW | FIXED | `double_jump_tap_height_m` is independently authored, live-tunable, validated against the double-jump full height, and carried by the controller as the active release profile. A controller-level regression proves a tapped double jump uses this value rather than the ground-jump tap height. |

## Operator decisions applied

- Air arbitration discards the losing DOWN edge, matching the ratified ground
  policy.
- Scope automation is an honestly limited vocabulary tripwire; structural scope
  remains a review responsibility.
- `catalog_is_usable` guarantees playability, not merely recoverability.
- Debug signing material is repository-pinned so clean builds and other machines
  retain the certificate.
- Double jump receives its own tap-height tuning field.

## Remaining external gates

- **H4:** the landing-ring query budget still requires profiling and the
  20-minute thermal soak on a real target phone. Finding 9 removes avoidable
  selection overhead but does not substitute for device evidence.
- **H11:** signed-APK loading of a runtime-authored `.tres` override still requires
  device acceptance step B.
- **L9:** combat targets and callbacks remain correctly blocked until after Gate F.
- **Finding 10:** ledge-nudge stickiness is an explicit Gate F feel observation.
- Device acceptance A–C and Gate F were not run or marked passed.

## Independent automated verification

- GUT 9.7.1: **95/95 tests passed, 530 assertions**.
- Python `unittest`: **16/16 tests passed**.
- Repository pre-commit hook, gameplay numeric-literal lint, Phase 0.5
  vocabulary tripwire, Bash syntax check, stale-name/call-site scans, and
  `git diff --check`: passed.
- Headless game boot: 120 frames, exit 0.
- Vulkan Forward Mobile movie smoke: 120 frames at 1920×1080 on llvmpipe, exit
  0; final frame visually inspected for the player, course, HUD, touch buttons,
  and depth presentation.
- Authored tuning fingerprint:
  `8cc9cc6a011b13d986dc71581a79ce3d9ea1b83359488d7a1cb4cac0d6d0ada7`.
- Android debug APK: package `com.personal.crashremix`, version
  `0.1.0-phase0`, min SDK 29, target SDK 35, arm64-v8a only, VIBRATE present.
- APK Signature Scheme v2 verified with one signer. Certificate SHA-256:
  `1075362a0a73fe61f610cb501f6e626bcd60a6685e9bf396f027e52c9a9aa0f6`.
- APK SHA-256:
  `14515da05054517a2bbca1e48baf52eac136f6bb2d4696236396e0d6caf03789`.
