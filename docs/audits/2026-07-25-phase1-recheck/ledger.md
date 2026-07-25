# Phase 1 Wave A — RECHECK ledger

Frozen at `8ddaf37`. Eight fresh-eyes agents over both fix lanes (Codex `5e49d77..975df4e`,
this session `975df4e..8ddaf37`). Raw per-agent notes in `raw/`.

**Every row below was produced by EXECUTING the scenario, not by reading a diff.**

## Headline

The two P0s that nearly shipped are genuinely fixed, and both were re-broken and re-caught:
`P0-1` (unreachable level exit) and `P0-2` (spawn over a hole).

`P1-11`'s twelve cells — a table of tests the original audit had already *proven vacuous* —
were re-mutated to their literal original shape. **All twelve are now genuinely caught.**

All 3 `REJECTED` rows hold up when re-read at `5e49d77`. All 5 `DEFERRED` rows are genuinely
deferred, not quietly broken. Across all 155 exported tuning fields, exactly one has no runtime
consumer and it is legitimately lint-only.

No P0 was found. Nothing found here makes the level unplayable.

## New findings

| ID | Sev | File | Claim | Status |
|----|-----|------|-------|--------|
| R1 | P1 | `src/tuning/tuning_service.gd:295` | **N1's fix closes one axis of three.** `catalog_is_usable` bounds only `checkpoint_respawn_offset.y`; `.x`/`.z` are unbounded and reachable from the on-device drawer (SpinBox range ±1,000,000). Proved: `Vector3(1000000, -7.99, 1000000)` passes as usable, reproducing P0-2's death-loop shape sideways. The guard-the-guard test cannot catch it — it requires only *a* bad value per field *name*. **Found independently by two agents.** | FIXED — `catalog_is_usable` now bounds `.x`/`.y`/`.z` of `checkpoint_respawn_offset` against `absf(move.respawn_floor_y_m)` (the catalog's only existing "how far is definitely too far" distance scale), closing the sideways/upward death-loop shape. `test_every_exported_economy_field_has_a_rejection_case` (the guard-the-guard) now demands, for every Vector3-typed field, a rejection case that isolates each axis (every other component held at its authored value) — proven to fail on the pre-fix arrangement first (the old single `Vector3(0, floor, 0)` case incidentally moved `.z` too, so it isolated zero axes). New behavioral test: `test_checkpoint_respawn_offset_x_and_z_axes_are_bounded_like_y`. GUT 455/455 (4,312 asserts), Python 70/70, all lints EXIT=0. |
| R2 | P1 | `scripts/lint_traversal_authoring.py` | **A duplicated parser that never got either fix.** This lint carries its own copy of the scene parser, separate from `lint_level_authoring.py`, and received neither P1-1 (`transform =` blindness) nor G13 (silent drop of unclassifiable sections). Reproduced: two `transform =` markers both flatten to `(0,0,0)`; a `[connection]` section parses with no error. Dormant only because wall-run/grind content is `position =`-only today; one editor re-save silently degrades the camera-comfort and rail-linkage checks. Zero fixtures cover either case. | OPEN |
| R3 | P2 | `src/core/game_root.gd:324` | App-pause while idling in the hub pauses nothing. `_pause_and_snapshot_active_run()` dispatches `EVENT_PAUSE` only when `flow.state == LEVEL`, so `get_tree().paused` is never set and the FSM stays in `WARP_ROOM` — defeating I15's `PROCESS_MODE_PAUSABLE` guard for the commonest real-device trigger. | OPEN |
| R4 | P2 | `tests/tuning/test_tuning_service.gd` | **A8's fix is a speed bump, not a barrier.** Executed: built a real old override, added a real new field, watched its authored value silently fall back to the script default with `override_active=true` and no error. Then mis-registered the field in the baseline list and pasted the hash the failing test itself prints — both guard tests go green, the silent discard unchanged. Correct fix is structural: derive the Phase 0 baseline from a committed Phase 0 artifact, not a hand-typed list that can be edited to agree with itself. | OPEN |
| R5 | P2 | `src/core/game_root.gd` `_ready()` | C5's boot-error overlay covers only the Q9 future-save refusal. The earlier base-tuning-load failure `return`s before the UI is installed — a total black screen with no text, worse than the case that was fixed. | OPEN |
| R6 | P2 | `scenes/ui/hud.tscn` | I8's "HUD never overlaps the touch zones" holds only at 1920×1080. `MercyPanel` is pixel-anchored, the stick region ratio-anchored; below ~920px safe height they genuinely overlap. Third instance of the "two independently-tuned numbers drift apart" pattern (with R1 and I17). | OPEN |
| R7 | P2 | `src/ui/safe_area_control.gd`, `touch_controls.gd` | The poll uses `fmod(x, interval_s)`; a non-positive interval yields `NaN`, making it run every frame forever instead of throttling. The polling code has no self-defense, and the **authored base `.tres` is never passed through `catalog_is_usable` at boot** — only overrides are. | OPEN |
| R8 | P2 | `src/gameplay/run/level_session.gd` | Mercy-skip *offer* state does not survive a process-kill/relaunch restore, though the model's death count does. | OPEN |
| R9 | P2 | `scenes/levels/wr1_n_sanity_beach.tscn` | P0-2's fix is a single coordinate correction with no generalised guard: nothing asserts that floor exists under the authored spawn, so the next level can reintroduce it. | OPEN |
| R10 | P2 | `src/gameplay/run/level_session.gd` | F8 froze gameplay timers across pause correctly, but the same wall-clock-deadline pattern is left uncompensated in a sibling field. | OPEN |
| R11 | P2 | `scripts/lint_level_authoring.py` | P1-10 is half-fixed: the recursion half is genuinely test-proven, but the scan-root *path string* half is unproven — sabotaging `"levels"`→`"levelz"` leaves all 36 tests green. The real CLI fails today only incidentally. | OPEN |
| R12 | P3 | `src/core/game_root.gd:170` | The resume-snapshot `dispatch()` is the only one in `_ready()` whose error is unchecked. The failure case does not currently reproduce — safe by coincidence, not by structure. | OPEN |
| R13 | P3 | `src/core/game_root.gd` | `set_threaded_load_status_override` (C19's test seam) is a public, ungated method on the shipped node, against the codebase's underscore-prefix convention. | OPEN |
| R14 | P3 | `tests/integration/test_island_slice.gd:40-105` | The only test citing D9/N1 reads `player._spawn_transform` and compares hand-computed math; it never drives a real death and confirms the player lands there, on real floor, without a second fall. Same shape as P1-0. | OPEN |
| R15 | P3 | `src/gameplay/crates/crate_logic.gd` | D11's removal of the out-of-range guards holds today, but the invariant now rests purely on convention with no runtime assertion; the removed code was a harmless fallback. | OPEN |
| R16 | P3 | `scripts/lint_level_authoring.py` | G13/N3's "every real scene parses" is false as stated — 16 real `.tscn` files under `addons/gut/` fail, harmless only because they sit outside the scan root. | OPEN |
| R17 | P3 | `tests/` | Three tests written during the recheck cover real gaps and exist only in discarded worktrees: early-boundary bounce timing, X/Y blast occlusion, mid-progress bounce re-arm. Worth porting. | OPEN |

## Verified sound — re-broken and re-caught

`P0-1` · `P0-2` · `P1-1` (`transform =`, by real `pack()` re-save, 0/42 geometry mismatches) ·
`P1-5` `P1-9` `P1-17` (dead-wired values — consumer deleted, real end-to-end test fails) ·
`P1-7` (migration chain, single- and double-hop) · `P1-8` (export smoke proves LevelMeta LOADS) ·
`P1-12` (catalog isolation; underlying Godot bug confirmed still real for the old idiom) ·
`P1-13` (TNT blast — verified on all three axes, beyond the shipped test's Z-only wall) ·
`P1-11` **all twelve cells** · `A4` · `A9` · `A13` · `B1` `B2` `B8` `B9` · `Q9` · `D8` ·
`D10` · `J3` · `J4` · `F20` · `F5`/`F6` · `G12` (lint math vs real engine: 7.306° vs 7.3058°) ·
Task 16 PHASE gating · `I7` `I11` `I12` `I16` `I17` `I18` `I19` · both halves of `I8`/`I15` ·
`P1-6` (one real touch through both `TouchControls` and `HUD._input()` at the real rendered
rect → exactly one effect) · all 8 authoring-lint rules · all 3 traversal-lint rules ·
the pre-commit hook.
</content>
