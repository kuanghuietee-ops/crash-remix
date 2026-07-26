# Wave D wiring audit — af585f6 ("Build Wave D Hog Wild ride")

Scope: integration wiring (tuning migration/fingerprint, configure() arity, warp room /
level list, exported runtime, respawn ordering). Read-only audit; nothing fixed.

---

## Q1 VERIFIED CLEAN — pre-hog override IS migrated (section-level backfill)

Not a finding. Recording the traced path because it was the highest-value question.

Boot path for an old `user://tuning/override.tres` with no `hog`:

- `src/tuning/tuning_service.gd:107-112` loads and clones the authored base catalog
  (`data/tuning/gameplay.tres`, which now has `hog = ExtResource("15_hog")` →
  `data/tuning/hog.tres`).
- `src/tuning/tuning_service.gd:113-123` validates the *base* catalog first and returns
  `ERR_INVALID_DATA` (loud, aborts boot) if it is unusable.
- `src/tuning/tuning_service.gd:127-131` loads the override, then calls
  `_backfill_missing_sections(override_resource, authored)` **before** validation.
- `_backfill_missing_sections` (`:519-535`) iterates `SECTION_NAMES` — which now includes
  `&"hog"` at `:18` — and for any section that is `null` on the loaded override does
  `target.set(section_name, authored_section.duplicate(true))` (`:527-530`).

The old override .tres re-binds `res://src/tuning/gameplay_tuning.gd`, i.e. the *new*
script, at load time. The file simply has no `hog = ...` line, so the exported
`@export var hog: HogTuning` (`src/tuning/gameplay_tuning.gd:17`) initialises to `null`
→ the `target_section == null` branch fires → hog is backfilled from authored. The
player gets 9.0 / 5.0 / 2.0, not a zeroed hog. Existing operator edits in other sections
survive because backfill only touches null sections and legacy field cohorts.

On the version constant: **there is no tuning version constant in this repo.** `grep -rn
"VERSION" src/` finds only `src/core/save_model.gd:4 SCHEMA_VERSION: int = 1` (the *save*
schema, unrelated to tuning). The tuning system's migration is entirely structural:
`LEGACY_FIELD_GROUPS_BY_SECTION` (`src/tuning/tuning_service.gd:22-89`) is a *field-level*
cohort table for new fields added inside *pre-existing* sections (where a saved 0.0 is
ambiguous between "default-omitted" and "operator set it to zero"), and a brand-new whole
section needs no entry because it arrives as `null`, which is unambiguous. The cohort
table is correctly NOT extended for `hog`, and the test suite states that intent
explicitly at `tests/tuning/test_tuning_service.gd:225-243` ("Tasks 17, 19, and 20 add
whole enemy, chase, and hog sections, which _backfill_missing_sections migrates
atomically ... Their initial fields therefore join this baseline"), with the frozen
baseline sha256 recomputed to `4943bdf3...`. Direct regression test:
`tests/tuning/test_tuning_service.gd:495-547`
(`test_pre_hog_override_backfills_hog_and_preserves_existing_edits`), which saves a
`hog = null` override plus an unrelated `chase` edit and asserts both migration and
preservation. NOT RUN by me (GUT is the orchestrator's; see caveats).

## Q2 VERIFIED CLEAN — hog is inside the fingerprint

Not a finding.

`fingerprint()` (`src/tuning/tuning_service.gd:154-166`) loops `SECTION_NAMES` and calls
`_append_fingerprint_lines(..., catalog.get(section_name))`; `&"hog"` is in
`SECTION_NAMES` at `:18`. `_append_fingerprint_lines` (`:576-591`) emits one
`section.property=value` line per entry of `_exported_property_names(resource)`, which
(`:594-600`) accepts every `property_info` whose usage has `PROPERTY_USAGE_SCRIPT_VARIABLE`
— i.e. all three `@export` floats on `HogTuning` (`src/tuning/hog_tuning.gd:5-7`). So
editing `data/tuning/hog.tres` moves the sha256. Covered by
`tests/tuning/test_tuning_service.gd:456-476`
(`test_fingerprint_moves_when_a_hog_value_changes`) and the loaded-paths assertion at
`:952` (`hog.tres`). Rule 2 satisfied on the static evidence.

## Q3 VERIFIED CLEAN — null `hog` cannot reach the field dereference

Not a finding, and the answer differs from the question's premise.

`catalog_is_usable` opens with a generic null+finiteness sweep over *every* section
(`src/tuning/tuning_service.gd:197-200`):

```gdscript
for section_name: StringName in SECTION_NAMES:
    var section := checked.get(section_name) as Resource
    if section == null or not _resource_values_are_finite(section):
        return false
```

Because `&"hog"` is in `SECTION_NAMES`, a null hog returns `false` at `:200`, long before
`var hog := checked.hog` at `:436`. That is the same protection every other section relies
on — none of the per-section blocks (`move` `:202`, `input` `:228`, `chase` `:426`, …)
null-check individually either, and they don't need to. Failure mode for a hand-edited or
ext_resource-missing override is therefore the loud-ish rejection path at
`:132-134`: `override_rejected = true`, override discarded, authored catalog kept, boot
continues. For a broken *base* catalog it is `:113-123` → `ERR_INVALID_DATA` →
`GameRoot._ready()` push_error + aborted boot. No crash on either path. Regression test:
`tests/tuning/test_tuning_service.gd:1009-1021`
(`test_catalog_is_unusable_without_hog`).

## Q6 VERIFIED CLEAN (partially) — hog.tres is included in the APK by the generic filter

`export_presets.cfg:8` is `export_filter="all_resources"` with
`exclude_filter="addons/gut/**,tests/**,docs/**,prompts/**,scripts/**"` and an empty
`include_filter`. `data/tuning/hog.tres` is not excluded, so it ships by exactly the same
mechanism as the other 13 section .tres files — there is no per-file include list that
could have been forgotten. `scripts/verify_exported_tuning.sh:34-36` additionally asserts
every `data/tuning/levels/*.tres` (glob, so `hog_wild.tres` is covered automatically) has
a `.remap` entry in the exported pack, and `:62-64` now includes `hog` in the runtime
tuning-path list. Remaining gaps in that script are filed separately below.

---

# FINDINGS

### hog_tuning is a silently-defaulted param that gates a whole level's core verb, contradicting the repo's own "no silent default" invariant
- Severity: P2 (latent P1 — no shipped call site hits it today)
- File:line: `src/gameplay/player/player_controller.gd:106-117` (`hog_tuning: HogTuning = null` at `:116`); `src/gameplay/player/player_motor.gd:42-50` and `:56-64`; `src/gameplay/player/player_motor.gd:129-137` and `:171-176`; `src/gameplay/player/player_controller.gd:554-566`; guard at `src/gameplay/player/player_controller.gd:147-149`
- Claim: `configure()`'s new 10th parameter (the prompt calls it the 9th; positionally it is #10 after `phase_enabled`) defaults to `null`, and every consumer of a null `_hog_tuning` degrades *silently* — the exact shape `test_configure_gating_params_have_no_silent_default` exists to forbid.
- Evidence: three independent silent-degradation paths:

```gdscript
# player_controller.gd:147-149  — mount request evaporates
func mount_hog() -> void:
    if _hog_tuning == null:
        return
```
```gdscript
# player_motor.gd:56-58  — ride freezes solid
if state == STATE_RIDE:
    if hog_tuning == null:
        return Vector3.ZERO
```
```gdscript
# player_motor.gd:171-176 / player_controller.gd:562-564 — ride jump becomes a no-op
IMPULSE_RIDE_JUMP:
    if hog_tuning != null:
        result.y = JumpKinematicsType.upward_speed_for_height(...)
```
  None of the three pushes an error or warning. Compare `tests/gameplay/test_player_controller.gd:623-664`
  (`test_configure_gating_params_have_no_silent_default`), which deliberately calls the
  7-arg shape and asserts `"Method expected"` fires, with the comment "omitting configure's
  gating params must be a real call error, not a silent false/null default".
  That test still passes with the new default (min-arg count is 9, so a 7-arg call still
  errors), so the *existing* invariant is not broken — but `hog_tuning` was added on the
  wrong side of it. The four analogous statics also gained silent defaults:
  `PlayerMotor.horizontal_velocity(..., hog_tuning: HogTuning = null)` (`:49`),
  `PlayerMotor.impulse_velocity(..., hog_tuning: HogTuning = null)` (`:136`),
  `PlayerController.tap_height_for_impulse(..., hog_tuning: HogTuning = null)` (`:557`).
- Failure scenario: a future level (or a refactor of `_refresh_active_level_tuning`) adds a
  player-configure call site and forgets `catalog.hog`. Hog Wild then loads, the player
  walks into the mount trigger, `HogMount._set_mounted(true)` calls `mount_hog()`,
  `mount_hog()` returns immediately, `_ride_mounted` stays `false`, the hog visual is
  reparented onto the player anyway (`hog_mount.gd:90` runs after the `mount_hog()` call at
  `:89`, unconditionally), and the player walks the whole ride corridor on foot carrying a
  hog capsule, with no error in the log. That is precisely the dead-wire class CLAUDE.md's
  preamble was written about.

### All five production `player.configure()` call sites DO pass `catalog.hog` (verified)
- Severity: P3 (record only — no defect)
- File:line: `src/core/game_root.gd:915-927` (level load), `src/core/game_root.gd:1027-1039`
  (`_refresh_active_level_tuning`, the on-device re-tune path),
  `src/core/phase0_game.gd:75-87` (`_ready`), `src/core/phase0_game.gd:137-149`
  (`refresh_tuning`), `src/gameplay/hub/warp_room.gd:100-112`
- Claim: the tuning refresh path is complete, so an on-device hog edit reaches the live player.
- Evidence: each of the five blocks ends `_phase_available()` / `true` / `_phase_available`
  followed by `catalog.hog` / `_catalog.hog`. Both *refresh* sites (`game_root.gd:1039`,
  `phase0_game.gd:148`) are included, which is what makes rule 2's "change it on device and
  see it move" true for hog rather than load-time only.
- Failure scenario: n/a.

### Test suite runs almost all PlayerController tests with `_hog_tuning == null`
- Severity: P2 (missing coverage)
- File:line: `tests/gameplay/test_player_controller.gd:908-928` (`_new_controller` helper,
  10-arg call ending `false` with no hog); also `tests/integration/test_level_scenes.gd:1400-1411`,
  `tests/integration/test_phase_state_integration.gd:116-127`,
  `tests/gameplay/test_mercy_and_masks.gd:626-637`, `tests/gameplay/test_player_controller.gd:515-526`
- Claim: the shared controller fixture never supplies hog tuning, so no existing controller
  test would notice if a *non*-ride code path started depending on `_hog_tuning`.
- Evidence: `_new_controller()` at `:918-928` passes `[_move,_input,_depth,_wall_run,_grind,_swing,buffer,_economy,false]`
  — 9 args. Every test built on that helper therefore exercises the null-hog configuration.
  The two call sites that DO pass hog are `tests/gameplay/test_ride_state.gd:228-240` and
  `tests/integration/test_level_scenes.gd:1446-1459` (the new Wave D tests) and
  `tests/gameplay/test_player_controller.gd:815-834`
  (`test_controller_receives_every_movement_tuning_resource`, renamed from
  `..._traversal_...` in this commit).
- Failure scenario: not a live defect; it means the null-hog degradation above is *only*
  exercised implicitly, and no test asserts what SHOULD happen (loud failure) when a ride
  level is configured without hog tuning.

### `HogMount._set_mounted(true)` cannot tell that `mount_hog()` refused, so HogMount and the player can disagree about being mounted
- Severity: P2 (latent P1 — the mechanism behind the finding above)
- File:line: `src/gameplay/ride/hog_mount.gd:83-94`
- Claim: `mount_hog()` is fire-and-forget; the mount bookkeeping proceeds regardless.
- Evidence:

```gdscript
# hog_mount.gd:83-94
if next_mounted:
    if (
        _player == null
        or not _player.has_method("mount_hog")
    ):
        return
    _player.call("mount_hog")   # :89 — return value is void; refusal is invisible
    _attach_visual()            # :90 — runs even if the player declined
    if not _mounted:
        mounted.emit()
    _mounted = true
    return
```
  `mount_hog()` (`player_controller.gd:146-149`) can decline (`_hog_tuning == null`) but has
  no return value, and `_set_mounted` has no post-check such as
  `_player.call("is_hog_mounted")` — even though that getter exists at
  `player_controller.gd:181-182`. So `HogMount.is_mounted()` can return `true` while
  `PlayerController.is_hog_mounted()` returns `false`.
- Failure scenario: with a null-hog player (see previous finding), `HogMount.is_mounted()`
  reports `true`, the `mounted` signal fires, the hog capsule reparents onto the player,
  but the player is in `grounded`/`airborne` with normal walk speed. Any future consumer of
  `HogMount.mounted` (HUD prompt, camera mode, audio) would act on a ride that isn't
  happening. Also means `test_hog_wild_mounts_forced_run_and_dismounts_at_finish` would
  still pass its `mount.is_mounted()` half in a dead-wired build; only the
  `player.is_hog_mounted()` assertion catches it.

### `_set_player_spawn()` now resets hog mount state on plain checkpoint activation, unlike every neighbouring runtime reset
- Severity: P2 (inconsistency; benign only because of this level's specific geometry)
- File:line: reset added at `src/gameplay/run/level_session.gd:1227-1239`; call sites
  `:405`, `:532`, `:593`, `:627`, `:682`
- Claim: four of the five `_set_player_spawn` callers are respawn/teleport paths; the
  fifth (`_on_checkpoint_reached`, `:678-682`) is *not*, and the surrounding design
  deliberately keeps runtime-state resets out of it — the new hog reset ignores that split.
- Evidence: the chase-hazard reset added in Wave C is paired with `_set_player_spawn` at
  every respawn call site and *only* there:

| line | caller | teleports player? | `_reset_chase_hazards_for_checkpoint` | hog reset (new) |
|---|---|---|---|---|
| `:405` | `restore_snapshot` | yes (`:413-415` `player.respawn()`) | yes `:406-408` | yes (inside `_set_player_spawn`) |
| `:532` | `accept_mercy_skip` | yes (`:541-543`) | yes `:533-535` | yes |
| `:593` | `_record_death` | yes (deferred, after `respawn_delay_s`) | yes `:594-596` | yes |
| `:627` | `_on_player_respawn_started` | yes (caller is `respawn()` itself) | yes `:628` | yes |
| `:682` | `_on_checkpoint_reached` | **no** | **no** | **yes** |

  `_on_checkpoint_reached` is the "player just ran over a checkpoint crate" handler:

```gdscript
# level_session.gd:678-682
func _on_checkpoint_reached(crate_id: int) -> void:
    run_state.record_checkpoint(crate_id)
    _offered_skip_checkpoint_id = LevelRunState.START_CHECKPOINT
    _offered_skip_completes_level = false
    _set_player_spawn(crate_id)   # → _reset_hog_mounts_for_position(...)
```
  Note also that the reset is fed the **checkpoint's** spawn origin
  (`level_session.gd:1230-1238`), not the player's live position, so at checkpoint
  activation it re-derives mount state from a point the player is merely *near*.
  In `wr1_hog_wild` as authored this is harmless, and the reason is worth recording
  because it is fragile: `HogMount._trigger_progress(_mount_trigger, 0.0)` resolves the
  MountTrigger at `scenes/levels/wr1_hog_wild.tscn:121-124` (`position = Vector3(0, 2, 0)`)
  against a curve whose first marker is `MountStart` at the origin
  (`:107`), so `mount_progress_m == 0.0`. Since `Curve3D.get_closest_offset()` never
  returns a negative offset, the guard at `hog_mount.gd:56-64`

```gdscript
if (
    player_progress_m >= mount_progress_m       # >= 0.0 — ALWAYS true
    and player_progress_m < dismount_progress_m # < 1019.0
):
    _set_mounted(true)
elif player_progress_m < mount_progress_m:      # DEAD BRANCH in this level
    _set_mounted(false, true)
else:
    _set_mounted(false)
```
  can only ever answer "mounted" for any point before the DismountTrigger
  (`:129-130`, `position = Vector3(0, 2, -1019)`). Both authored checkpoints sit inside
  that span: Checkpoint12 at `scenes/segments/hog_jump_gaps.tscn:94-95` (`z = -104`) under
  segment offset `wr1_hog_wild.tscn:76-77` (`z = -256`) → world `z = -360`, and
  Checkpoint24 at `scenes/segments/hog_gap_combine.tscn:105-106` (`z = -108`) under offset
  `:85-86` (`z = -640`) → world `z = -748`; with
  `checkpoint_respawn_offset = Vector3(0, -0.45, 2)` (`data/tuning/economy.tres:19`) their
  spawn progresses are ≈358 and ≈746. So the recompute agrees with the player's actual
  state and `mount_hog()` is re-entered while already mounted, which is inert:
  `_set_state` early-returns on an unchanged state (`player_state_machine.gd:473-475`, so
  `_state_entered_s` survives) and the flags `enter_ride` clears
  (`_ground_jump_available`, `_double_jump_available`, `_air_spin_available`, `is_spinning`)
  are all unread while `state == STATE_RIDE` (`player_state_machine.gd:70-76` routes to
  `_process_ride_actions`, which consults none of them).
- Failure scenario: the moment any Hog Wild revision moves the mount trigger off progress
  0 (an on-foot approach segment before the mount — the obvious next authoring step), or
  places a checkpoint crate whose spawn maps past the DismountTrigger, a player crossing
  that checkpoint **while mounted** is force-dismounted mid-ride at full ride speed:
  `_set_mounted(false, ...)` → `dismount_hog()` → `exit_ride(now, is_on_floor())`
  (`player_controller.gd:171-178`) plus `_detach_visual()`, which reparents the hog capsule
  back to `HogRide` (`hog_mount.gd:118-127`). No respawn, no teleport — the player is
  simply thrown off the hog by touching a checkpoint. Nothing in the suite would catch it:
  `test_hog_wild_checkpoint_death_respawns_mounted`
  (`tests/integration/test_level_scenes.gd:1275-1305`) touches the checkpoint and *then*
  respawns, so it never observes the mid-ride checkpoint-only case.

### Q7 ORDERING — verified correct and load-bearing (record, not a defect)
- Severity: P3 (record only)
- File:line: `src/gameplay/player/player_controller.gd:645-671`;
  `src/gameplay/run/level_session.gd:615-628`, `:1227-1239`
- Claim: the hog reset runs early enough inside `respawn()` that `respawn()`'s own ride
  re-entry sees the corrected flag. This is subtle and easy to break.
- Evidence: exact order for a fall-death respawn (no `record_player_death` armed):
  1. `respawn()` `:646` — `respawn_started.emit()` **before** the teleport at `:647`.
  2. `LevelSession._on_player_respawn_started()` `:615` → not armed → `:627`
     `_set_player_spawn(respawn_checkpoint)`.
  3. `_set_player_spawn` `:1231` sets the player's spawn transform, then `:1237`
     `_reset_hog_mounts_for_position(spawn_transform.origin)` →
     `HogMount.reset_for_player_position` → `mount_hog()` / `dismount_hog()`, which is what
     writes `_ride_mounted`.
  4. control returns to `respawn()`: `:647` `global_transform = _spawn_transform` (the
     transform step 3 just installed), `:655` `_state_machine = PlayerStateMachineType.new()`
     (wipes to `STATE_AIRBORNE`), then `:656-659`
     `if _ride_mounted and _hog_tuning != null: _state_machine.enter_ride(...)`.
  If the reset in step 3 ran *after* step 4 — e.g. if someone "tidied" the emit at `:646`
  to fire after the teleport, or moved the hog reset out of `_set_player_spawn` into the
  respawn call sites the way the chase reset is done — the player would respawn inside the
  ride corridor in `STATE_AIRBORNE` with `_ride_mounted` true, i.e. standing still on a hog
  that never moves. For the death path the reset happens earlier still (at `_record_death`
  `:593`, i.e. at the instant of death, then `_on_player_respawn_started` early-returns at
  `:619-620` because `_death_recorded_pending_respawn` is armed); nothing integrates during
  the delay because `_physics_process` bails at `player_controller.gd:743`
  (`if advance_respawn(now_s) or is_respawning(): return`), so the corpse does not slide
  forward at `ride_speed_mps`. RELIC mode sends the reset to `START_CHECKPOINT`
  (`level_session.gd:621-626`) → `_start_transform` → progress 0 → mounted, which matches
  the level's start-mounted design.
- Failure scenario: n/a today; documented so a future refactor doesn't silently invert it.

### Q5 VERIFIED CLEAN — `wr1_hog_wild` is reachable and consistently spelled everywhere
- Severity: P3 (record only)
- File:line: see list below
- Claim: every level-enumerating site is updated; no hardcoded pair-of-two survived.
- Evidence: `grep -rn "wr1_boulders\|BOULDERS"` and the matching `hog_wild` grep across
  `*.gd/*.tscn/*.tres/*.cfg/*.sh/*.py` produce a 1:1 correspondence:
  scene path + id consts `src/core/game_root.gd:60-62`; scene-path dictionary `:64-68`;
  meta preload `:42-43`; hub meta dictionary `:717-722`; `_level_meta()` chain `:879-880`;
  unlock feed `_available_level_ids()` `:725-729` derives from `_LEVEL_SCENE_PATHS`, so the
  portal unlocks automatically; `PortalRules.LEVEL_IDS` `src/gameplay/hub/portal_rules.gd:9-13`;
  warp-room portal node `scenes/levels/warp_room_1.tscn:154-158`
  (`metadata/level_id = &"wr1_hog_wild"`, `display_name = "HOG WILD"`, mirrored at
  `x = +9.7` opposite Boulders at `x = -9.7`); level-list button
  `scenes/ui/level_list_overlay.tscn:84-88` and handler `src/ui/level_list_overlay.gd:18-21`;
  export smoke case `src/debug/export_level_meta_smoke.gd:16-20`. `portal_rules.gd` and
  `warp_room_1.tscn` are *not* in this commit's diff — `git log` shows they were populated
  in `3e6a9bc` ("Lock portals without playable level scenes"), which is why af585f6 only
  needed the `_LEVEL_SCENE_PATHS` entry to flip the portal from locked to unlocked.
  Naming is consistent with the Boulders precedent: meta `display_name = "Hog Wild"`
  (`data/tuning/levels/hog_wild.tres:8`), portal `"HOG WILD"`, list `"HOG WILD  [WAVE D]"`.
  No hardcoded level count found; `scripts/lint_level_authoring.py` and
  `scripts/lint_traversal_authoring.py` walk `scenes/levels/` and `scenes/segments/`
  generically. Level-list panel min height 610 px
  (`scenes/ui/level_list_overlay.tscn:51`) still exceeds the 4-button content
  (≈546 px with the debug Toybox row shown), so the new row does not overflow, and
  `PanelContainer` would grow anyway.
  RAN: `python3 scripts/lint_gameplay_numbers.py` → pass;
  `python3 scripts/lint_level_authoring.py` → exit 0;
  `python3 scripts/lint_traversal_authoring.py` → exit 0;
  `python3 scripts/check_content_vocabulary.py` → pass;
  `python3 -m unittest discover -s tests -p 'test_*.py'` → **78 tests, OK**.
- Failure scenario: n/a.

### Exported-runtime check never asserts the hog_wild (or boulders) LevelMeta path in the runtime log
- Severity: P2 (missing coverage)
- File:line: `scripts/verify_exported_tuning.sh:65-70`
- Claim: the `LEVEL META` block still only pins N. Sanity Beach, so two of the three levels'
  metas are unverified in the exported pack.
- Evidence:

```bash
grep -qE '^LEVEL META$' "$runtime_log"
grep -qE '^res://data/tuning/levels/n_sanity_beach\.tres$' "$runtime_log"
grep -qE '^FINGERPRINT [0-9a-f]{12}$' "$runtime_log"
grep -qE '^EXPORTED LEVEL META SMOKE READY$' "$runtime_log"
grep -qE '^EXPORTED BOULDERS SMOKE READY$' "$runtime_log"
grep -qE '^EXPORTED HOG WILD SMOKE READY$' "$runtime_log"
```
  The smoke does enter all three levels (`src/debug/export_level_meta_smoke.gd:5-21`) and
  `TuningDebugUI._refresh_summary` prints `LEVEL META` + `_level_meta_path` per level
  (`src/debug/tuning_debug_ui.gd:499-502`, fed by `report_level_meta` at `:61-68`), so the
  runtime log *contains* `res://data/tuning/levels/hog_wild.tres` — nothing greps for it.
  The gap is inherited (boulders has the same hole), not introduced here, but Wave D was the
  chance to close it. Mitigation that already exists: `:34-36` globs
  `data/tuning/levels/*.tres` and requires a `.remap` in the pack, so hog_wild's meta is
  proven *shipped*; and the ready marker only prints after `_configure_authored_level`
  succeeds (`game_root.gd:856-862` aborts and `_clear_content()`s if `_level_meta()`
  returns null, which would make the node disappear and the smoke time out), so it is
  proven *loaded* indirectly.
- Failure scenario: a future edit that points `HOG_WILD_META` at a path stripped from the
  export, or a `.tres` that loads in-editor but resolves to a different resource in the
  pack, would not be caught by an explicit path assertion — only by the weaker
  node-exists timeout. NOT RUN: the script invokes Godot/export, which the orchestrator owns.

### The NEXT field added to `HogTuning` will silently reject the operator's whole override unless a cohort entry lands with it
- Severity: P3 (forward-looking; af585f6 itself is correct)
- File:line: `src/tuning/tuning_service.gd:22-89` (no `&"hog"` key),
  `src/tuning/hog_tuning.gd:5-7` (no sentinel defaults),
  `src/tuning/tuning_service.gd:436-442`
- Claim: whole-section backfill covers *this* commit, but the field-level trap the cohort
  table exists for is now armed for `hog`.
- Evidence: an override written by af585f6 has `hog` non-null, so
  `_backfill_missing_sections` takes the `_backfill_legacy_field_groups` branch
  (`:531-535`), which returns immediately at `:543-544` because
  `LEGACY_FIELD_GROUPS_BY_SECTION` has no `&"hog"` key. A newly added 4th `HogTuning` field
  would therefore stay at its script default of `0.0` (there is no `-1.0` sentinel the way
  `ChaseTuning.opening_auto_run_duration_s` has one at `src/tuning/chase_tuning.gd:8`), and
  `catalog_is_usable`'s `hog.<new_field> <= 0.0` guard would reject the entire override:
  `load_from_paths:132-134` sets `override_rejected = true` and keeps the authored catalog.
  The only surface signal is the "OVERRIDE REJECTED" watermark
  (`src/debug/tuning_debug_ui.gd:505-513`). The test file already states the required
  discipline (`tests/tuning/test_tuning_service.gd:231-234`: "later fields inside those
  sections still belong in a legacy cohort").
- Failure scenario: Wave E adds `hog_lean_degrees`; the operator's phone-tuned hog values
  from Wave D vanish on the next boot with no error, only a watermark.

### `_collect_hog_mount_descendants` duck-types on one method where the chase equivalent requires two
- Severity: P3 (nit)
- File:line: `src/gameplay/run/level_session.gd:255-264` vs `:229-237`
- Claim: a node in group `hog_mount` that has `reset_for_player_position` but no `configure`
  is collected and reset forever without ever learning who the player is.
- Evidence: `_collect_chase_hazard_descendants` requires both `advance_runtime` and
  `reset_for_player_position` (`:233-234`); the hog collector requires only
  `reset_for_player_position` (`:259-261`), and `configure` is checked at call time
  (`:246`) rather than at collection time. Such a node's `reset_for_player_position` hits
  `hog_mount.gd:42-44` (`_player == null` → `_set_mounted(false, true)`) on every
  checkpoint and respawn, permanently un-mountable, with no error.
  Note the missing `_gameplay_tuning == null` guard (present at `:210-211` for chase) is
  *correct* here — `HogMount` takes no tuning resource.
- Failure scenario: only reachable via a mis-authored scene; recorded for symmetry.

---

## WHAT I RAN vs WHAT I DID NOT (CLAUDE.md rule 4)

RAN, green:
- `python3 scripts/lint_gameplay_numbers.py` → "Gameplay numeric-literal lint passed.", exit 0
- `python3 -m unittest discover -s tests -p 'test_*.py'` → **Ran 78 tests, OK**
- `python3 scripts/lint_level_authoring.py` → exit 0
- `python3 scripts/lint_traversal_authoring.py` → exit 0
- `python3 scripts/check_content_vocabulary.py` → "Phase 2+ content vocabulary tripwire passed.", exit 0

NOT RUN (orchestrator owns Godot / the shared import cache) — needs a run to settle:
1. **The GUT suite.** Every claim about the new GDScript tests passing is unverified:
   `tests/gameplay/test_ride_state.gd` (new, 358 lines),
   `tests/tuning/test_tuning_service.gd:440-1021` (hog fingerprint / migration / rejection),
   `tests/integration/test_level_scenes.gd:1062-1337` (hog level contract),
   `tests/integration/test_warp_room.gd:374-414` (level-list → hog scene).
   In particular the frozen baseline constant was recomputed to
   `4943bdf335e6432df4440e9830a581447083ce318ad2af82b6260ff15fe8f5c8` — only
   `test_phase_zero_baseline_field_set_is_frozen` proves that value is right.
2. `scripts/verify_exported_tuning.sh` — exported-pack `.remap` presence for
   `data/tuning/hog.tres`, and source-vs-runtime fingerprint parity.
3. **Rule 2 end-to-end**: edit `data/tuning/hog.tres`, confirm the boot fingerprint sha256
   moves on device, edit it again in the on-device drawer (the drawer derives its section
   list from `TuningServiceType.SECTION_NAMES` at `src/debug/tuning_debug_ui.gd:7`, so a
   HOG section with 3 sliders should appear automatically — unverified), restart, confirm
   persistence. Static reading says all three legs are wired; none of them is *run*.
4. Whether `@export_category("Ride")` (`src/tuning/hog_tuning.gd:4`) contributes a
   `property_info` carrying `PROPERTY_USAGE_SCRIPT_VARIABLE`. If it did,
   `_exported_property_names` (`tuning_service.gd:594-600`) would emit a spurious
   `hog.Ride=null` fingerprint line. Thirteen existing sections use `@export_category` with
   a frozen baseline hash, so this is almost certainly fine — but it is an assumption.
5. Whether `HogRide/Path` (`scenes/levels/wr1_hog_wild.tscn:105`, declared with **no**
   `curve =` line) arrives at runtime with `curve == null` or an empty `Curve3D`. Either
   way `_ensure_curve_from_markers` (`hog_mount.gd:156-168`) builds it from the five
   Marker3D children — but if a non-empty curve ever showed up, the early return at `:159-163`
   would silently ignore the markers and **all** mount/dismount progress math would be wrong.
   Everything in this audit's Q7 geometry reasoning depends on that curve being the
   marker-built one, length 1024.
6. Whether mutating `CylinderShape3D.height/radius` and `CollisionShape3D.position`
   (`player_controller.gd:1398-1420`, reached from `mount_hog()` → `_apply_character_dimensions`)
   and calling `Node3D.reparent()` (`hog_mount.gd:113`) from **inside** an `Area3D.body_entered`
   handler (`hog_mount.gd:196-198`) produces Godot's physics-flush errors
   ("Can't change this state while flushing queries"). `STATE_RIDE` is not crouched so the
   *values* are unchanged, but the setters still fire. Only a device/headless run shows the log.
7. The mid-ride checkpoint scenarios from the `_set_player_spawn` finding: (a) mounted player
   crosses Checkpoint12/Checkpoint24 — predicted inert re-mount; (b) the same with the
   MountTrigger moved off progress 0 — predicted force-dismount mid-ride; (c) respawn at a
   checkpoint positioned after the DismountTrigger — predicted `_set_mounted(false)` with the
   hog capsule left at the death position rather than restored to authored.
