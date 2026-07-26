# Wave D CONTENT audit — Hog Wild (wr1_hog_wild), commit af585f6

Repo /tmp/crash-remix-wave-d, branch wave-d-task20-21, diff 51fdae9..af585f6.
Read-only. All three python lints run green (`lint_level_authoring.py`,
`lint_traversal_authoring.py`, `lint_gameplay_numbers.py` — exit 0).

## Baseline geometry (used by every finding below)

Forward axis = **-Z**. No rotations authored anywhere in the level
(verified: every GrayboxPlatform world basis == identity).

Segment instances (`scenes/levels/wr1_hog_wild.tscn:71-92`), each segment's
`Spine/Entry` at local z=0 and `Spine/Exit` at local z=-128:

| # | segment | world offset | spine start → end |
|---|---|---|---|
| 1 | HogMountStart | 0 | 0 → -128 |
| 2 | HogWeaveGates | -128 | -128 → -256 |
| 3 | HogJumpGaps | -256 | -256 → -384 |
| 4 | HogPlantChomp | -384 | -384 → -512 |
| 5 | HogCrateSlalom | -512 | -512 → -640 |
| 6 | HogGapCombine | -640 | -640 → -768 |
| 7 | HogCrescendo | -768 | -768 → -896 |
| 8 | HogDismountFinish | -896 | -896 → -1024 |

Seam arithmetic: 0 + (-128) = -128 = next start; -128 + (-128) = -256; …
-896 + (-128) = -1024. **All eight seams are exact, all offsets are
multiples of 128 (so on the 2 m grid), all eight authored segments are
instanced exactly once, and the spine is contiguous with zero overlap and
zero gap.** Order is intro (mount) → steer twist (weave) → jump twist
(jump gaps) → hazard twist (plant) → slalom → combine (gap+gap) →
crescendo → dismount, which matches §6.1's intro→twist→combine→crescendo
shape at the segment-list level. 8 segments is inside §6.1's "6–10".

Ride jump reach (`src/gameplay/player/jump_kinematics.gd:26-61`,
`data/tuning/move.tres`: gravity 24.0, apex×0.85, fall×1.6, threshold 1.0;
`data/tuning/hog.tres`: hog_jump_height_m 2.0, ride_speed_mps 9.0):

    apex_band = 1.0²/(2·20.4)          = 0.024510 m
    v0        = sqrt(1 + 2·24·1.975490)= 9.78895 m/s
    rise      = (9.78895-1)/24 + 1/20.4= 0.415226 s
    fall      = 1/20.4 + (-1+sqrt(1+2·38.4·1.975490))/38.4 = 0.344798 s
    airtime   = 0.760024 s
    reach @9 m/s = 9.0 × 0.760024 = **6.8402 m**

STATE_RIDE keeps forward speed at 9.0 m/s while airborne
(`src/gameplay/player/player_motor.gd:58-66` returns forward×ride_speed
unconditionally; `player_state_machine.gd:465-470` does not list
STATE_RIDE in `_is_traversal_state`/`_is_ground_state`, so the state
survives the airborne stretch), so the full 6.8402 m is available.

## Q4 answer: crate/wumpa counts and lint coverage — MATCH

`scripts/lint_level_authoring.py:1708-1730` (`_scene_files`) globs
`scenes/levels/**.tscn`; `_level_meta_path` resolves
`metadata/level_meta` from the scene root. Verified by importing the lint
read-only: it scans `wr1_hog_wild.tscn` and resolves it to
`data/tuning/levels/hog_wild.tres`. **The level is covered, not skipped.**

Recursive flatten of the level (429 flat nodes) gives 32 crates:

| segment | standard | checkpoint | total | wumpa pickups |
|---|---|---|---|---|
| HogMountStart | 4 | 0 | 4 | 2 |
| HogWeaveGates | 4 | 0 | 4 | 2 |
| HogJumpGaps | 3 | 1 (id 12) | 4 | 2 |
| HogPlantChomp | 4 | 0 | 4 | 2 |
| HogCrateSlalom | 4 | 0 | 4 | 2 |
| HogGapCombine | 3 | 1 (id 24) | 4 | 2 |
| HogCrescendo | 4 | 0 | 4 | 2 |
| HogDismountFinish | 4 | 0 | 4 | 2 |
| **total** | **30** | **2** | **32** | **16** |

crate_count = 32 ✅ exact match with `data/tuning/levels/hog_wild.tres:9`.

wumpa: 16 pickups × `wumpa_per_pickup=1` + 30 standard crates ×
`wumpa_per_standard_crate=1` + checkpoint crates (0 wumpa,
`crate_logic.gd:64-68`) = **46** ✅ exact match with `hog_wild.tres:10`.
Cross-checked the formula against the two shipped levels: boulders
18+34 = 52 = its `wumpa_total`; n_sanity_beach 6+30+(5 bounce ×5 bounces
×1) = 61 = its `wumpa_total`.

Caveat: `wumpa_total` is **not linted**. `LevelMetaValues`
(`lint_level_authoring.py:167-170`) carries only `crate_count` and
`design_pace_mps`; nothing in the lint reads `wumpa_total`. The 46 is
correct today by hand-check only.

---

# FINDINGS

### `Spine/DismountLine` and the green dismount arch sit 11 m upstream of the actual dismount trigger
- Severity: P3
- File:line: `scenes/segments/hog_dismount_finish.tscn:26-27` (`Spine/DismountLine` local -112 → world -1008) and `:42-50` (`DismountArchLeft/Right`, world z -1006.5..-1009.5); vs `scenes/levels/wr1_hog_wild.tscn:129-135` (DismountTrigger z=-1019) and `:208-214` (Finish z=-1019)
- Claim: The segment names a `DismountLine` marker and parks its two green arch posts at world z=-1008, but the dismount `Area3D` is at z=-1019 — 11 m / 1.22 s downstream — and the level's Finish trigger's leading face is crossed first, so the run completes mounted.
- Evidence: DismountTrigger uses `Shape_ride_trigger` size (18,6,4) at z=-1019 → z span -1017.0 .. -1021.0. Finish uses `Shape_finish` size (18,3,5) at z=-1019 → z span -1016.5 .. -1021.5. Travelling in -Z the player crosses -1016.5 (Finish) about 3-4 physics frames before -1017.0 (dismount) at 9 m/s / 60 Hz (0.15 m per frame); `level_session.gd:1193-1195` then `call_deferred("complete_level")`. Marker→trigger distance: -1008 → -1017 leading face = 9.0 m; -1008 → -1019 centre = 11.0 m.
- **Verified as partly deliberate, so severity is P3 not P2:** `tests/integration/test_level_scenes.gd:1191-1197` explicitly asserts the dismount trigger's x/z coincide with Finish's, with the message "dismount must coincide with finish so manual braking cannot stall the run". Placing the dismount at the finish line is an intended decision, and §6.3 does not require an on-foot beat, so this is *not* a spec violation. What remains wrong is only the authored landmark: a marker literally named `DismountLine` and the arch geometry that reads as the dismount gate are 11 m from where the dismount happens.
- Failure scenario: The next author (or a QA reader) trusts `Spine/DismountLine` as the dismount position and tunes against -1008 instead of -1019 — the same class of marker-vs-logic drift as `Spine/MountLine` below. Also worth stating plainly for the record: no frame of this level is ever played dismounted, so `HogMount.dismounted` / `PlayerController.dismount_hog()` are unreachable here outside a checkpoint reset.

### Ride jump has no coyote time — the only state in the game where the forgiveness window is removed
- Severity: P1
- File:line: `src/gameplay/player/player_state_machine.gd:158-186` (`_process_ride_actions` — `if not grounded: return`) vs `:301-336` (`_process_jump`, which honours `_ground_jump_available` while `state == STATE_AIRBORNE`) and `:421-428` (`_expire_coyote_if_needed`)
- Claim: A ride jump can only be triggered on a frame where the player is actually grounded; `coyote_time_s = 0.14` never applies, so the three 5 m gaps have a hard failure boundary on the late side that no other jump in the game has.
- Evidence: `_process_ride_actions` returns immediately when `not grounded`, so `_pending_impulse = IMPULSE_RIDE_JUMP` is unreachable off the ground. The normal path (`_process_jump`, reached only via the `elif state != STATE_BODY_SLAM…` branch at `:88-100`, which `state == STATE_RIDE` short-circuits) grants `IMPULSE_JUMP` while airborne for up to `coyote_time_s = 0.14 s` (`data/tuning/input.tres:8`). At the ride's 9.0 m/s that lost window is 0.14 × 9.0 = **1.26 m** of ledge overhang. Launch window for gap 1 (RunA lip world z = -304, RunB lip = -309, player `CylinderShape3D` radius 0.32 from `scenes/player/player.tscn:8-10`): grounded until centre z = -304.32; must land with centre z ≤ -308.68; simulated 60 Hz reach = 7.05 m (see below), so earliest viable takeoff = -308.68 + 7.05 = -301.63. **Window = -304.32 … -301.63 = 2.69 m = 0.299 s**, and a press 1 frame late produces no jump at all instead of a coyote jump. `jump_buffer_s = 0.12` does not help: the player is grounded across the whole of RunA, so a buffered early press fires immediately at the press position (landing at press_z - 7.05, inside the pit) rather than being held to the lip.
- Failure scenario: Player thumbs the jump button one or two frames after the hog's front feet pass the lip — the exact input every other surface in the game forgives — gets no jump, falls past `respawn_floor_y_m = -8.0`, and is sent back 304 m (33.8 s of replay for gap 1, since `Checkpoint12` is 56 m *after* the gap; gaps 2 and 3 replay 320 m / 35.6 s from `Checkpoint12`). Spec §6.3 calls rides "the accessibility-friendly 'pure steering' levels"; §5.3's forgiveness table lists coyote time at **140 ms** unconditionally, with no ride/traversal carve-out, and its stated rationale is exactly this case ("3D edges are harder to see, depth ambiguity makes late jumps common").
- Compounding factors: (a) §5.3 budgets **50–90 ms** of Android touch-pipeline latency before the game can react, so the human-facing window is roughly 0.21–0.25 s, not 0.30 s; (b) `enter_ride` (`player_state_machine.gd:139-146`) also sets `_double_jump_available = false` and `_air_spin_available = false`, so §5.4's pillar-4 player-side corrections (double jump, spin-stall) are unavailable too — a missed ride jump has **zero** recovery mechanism; (c) `edge_landing_nudge_m = 0.12` only helps landings, not takeoffs.
- Note on lane: the geometry (5 m gaps) is fine and the fix is not content — it is in `src/gameplay/player/player_state_machine.gd`. Route accordingly.

### Gaps are clearable — arithmetic for Q2 (no P0), but all three are dimensionally identical
- Severity: P3
- File:line: `scenes/segments/hog_jump_gaps.tscn:38-51` (RunA/RunB/RunC), `scenes/segments/hog_gap_combine.tscn:41-54` (RunA/RunB/RunC), `scenes/segments/hog_crescendo.tscn:40` (MainRun — no gap at all)
- Claim: There are exactly three authored gaps in the level, each exactly 5.000 m, all comfortably clearable; `hog_crescendo` contains **zero** gaps.
- Evidence: merged floor coverage over the whole level (18 m-wide platforms, top face y = 0) is continuous from z = +2.00 to z = -1026.00 except:
  - `HogJumpGaps`: RunA ends -304.00, RunB starts -309.00 → **5.000 m** (RunB -309→-346 then RunC -346→-374 are flush; the only gap in the segment)
  - `HogGapCombine` gap A: RunA ends -678.00, RunB starts -683.00 → **5.000 m**
  - `HogGapCombine` gap B: RunB ends -717.00, RunC starts -722.00 → **5.000 m**
  Reach: analytic airtime 0.760024 s × 9.0 = 6.8402 m; 60 Hz semi-implicit simulation of `_apply_vertical_physics` (`player_controller.gd:1344-1359`, gravity from `jump_kinematics.gd:111-122`) gives airtime 0.7833 s, peak 2.082 m, horizontal **7.050 m** (30 Hz: 7.200 m). 7.050 / 5.000 = **1.41× margin**. Not unclearable, not trivial. All three gaps and all three `RequiredJump*` marker pairs are identical (takeoff→landing exactly 7.00 m each: -303→-310, -677→-684, -716→-723), so the jump never escalates across the level.
- Failure scenario: None from the geometry itself. Recorded because the marker-authored span (7.00 m) is 0.15 m *longer* than the analytic reach (6.8402 m) — a reader checking "can the player jump takeoff-marker to landing-marker" gets "no" even though the real lips are 5 m apart. The markers are 1 m inboard of each lip on purpose; nothing enforces or documents that, so the next author has no way to know the 7 m figure is deliberately padded.

### "CHOMP TIMING — READ THE FLASH" never fires on the intended line; the plants are inert scenery at ride speed
- Severity: P2
- File:line: `scenes/segments/hog_plant_chomp.tscn:14-18` (title), `:43-47` (PlantA/PlantB), `:64-86` (Crate13-16); `data/tuning/enemy_plant.tres:10-13`; `src/gameplay/enemies/enemy_base.gd:172-180` (`_player_is_inside_trigger`)
- Claim: `trigger_range_m = 2.5` is a *spherical* distance test, and the segment's own crate line runs 7.6 m laterally away from each plant, so neither plant ever leaves `STATE_DORMANT` on the intended route — no telegraph, no chomp, no threat.
- Evidence: `_player_is_inside_trigger` is `global_position.distance_to(player_position) <= trigger_range_m` — purely spherical, `trigger_lateral_m = 0.0` is not read. World positions: PlantA (-3.8, 0.75, -422), PlantB (+3.8, 0.75, -470). Intended line through PlantA's z is x = +3.8 (Crate13 at z=-412, Crate14 at z=-432, WumpaA at z=-418, all x=+3.8); through PlantB's z it is x = -3.8 (Crate15 -460, Crate16 -482, WumpaB -466). Lateral separation = |3.8 − (−3.8)| = **7.6 m**; closest approach distance = sqrt(7.6² + 0.7²) = **7.632 m ≫ 2.5 m**. Even off-line, the cycle cannot resolve: entering the 2.5 m sphere head-on, `telegraph_s = 0.5` elapses after 0.5 × 9.0 = **4.5 m** of travel, by which point the player is 2.0 m *past* the plant centre and outside the 1.48 m-deep `Shape_attack` box (`scenes/enemies/plant.tscn:69-70`, z span plant_z ± 0.74). The plant tuning was authored for the 4.5 m/s levels (`n_sanity_beach.tres:11`, `boulders.tres:11`), where 2.5 m = 0.556 s of warning; at 9.0 m/s it is 0.278 s.
- Failure scenario: The player rides the whole 128 m segment collecting its four crates and never sees a plant animate. The segment's stated lesson ("read the flash") cannot be learned here, and the two plants function only as decorative solid blocks. Worse, a player who *does* steer into one hits the solid `AnimatableBody3D` (`plant.tscn:72-78`, `collision_layer = 3` includes layer 1, player `collision_mask = 1`) 1.76 m after the trigger — i.e. 0.196 s in, still inside the 0.5 s telegraph — so `resolve_contact(VERB_TOUCH)` returns no-hit (`enemy_plant.gd:80-82`), the forced 9 m/s pins them against the plant's flat +Z face with no lateral slide component, and they die ~0.3 s later when the attack finally goes active. The death is delivered by being stuck, not by a chomp they failed to read.

### `hog_crescendo` is a mechanical copy of `hog_weave_gates` with the obstacles 0.2 m smaller — the level's crescendo does not escalate, and its "combine" combines one mechanic with itself
- Severity: P2
- File:line: `scenes/segments/hog_crescendo.tscn:45-58` vs `scenes/segments/hog_weave_gates.tscn:45-58`; `scenes/segments/hog_gap_combine.tscn:71-85`
- Claim: §6.1 requires an intro→twist→**combine**→**crescendo** cadence. `hog_crescendo` introduces nothing the second segment did not, and `hog_gap_combine` combines the jump twist with a second copy of the jump twist, so the back half of the level has no escalation at all.
- Evidence: normalised diff of the two segment files (side blocks renamed) differs only in: block y 1.8→1.7, block size (6.4,**4.6**,**3.4**)→(6.4,**4.4**,**3.2**), every z shifted +2 (-30/-64/-98 → -28/-62/-96), crate x ±4.5→±4.2, and darker `color` values. Identical in both: three blocks at x = ∓5.8 in the same **Left, Right, Left** order, the same **34 m** spacing, the same 11.4 m of free lane out of an 18 m corridor (blocks span x -9.00..-2.60 / +2.60..+9.00), the same 4-crate/2-wumpa layout, `camera_mode = &"default"`, and **zero gaps** (`hog_crescendo.tscn:40` MainRun is an unbroken 116 m slab; merged floor coverage across the segment is continuous -766.00 → -898.00). Steering demand is unchanged: worst lateral move is x=+6 → x=-6 = 12 m at `steer_lateral_speed_mps = 5.0` = 2.40 s, against 34 m / 9.0 = 3.78 s of available time — the same slack in both segments. Meanwhile `hog_gap_combine` contains only two 5.000 m gaps identical to `hog_jump_gaps`' single 5.000 m gap: no gate, no slalom post, and no plant is combined with the jump anywhere in the level.
- Failure scenario: A player reaching the last third of a ride level that §6.2 bills as "the game's first tempo spike" replays the second segment's exercise with slightly shorter hurdles. Nothing new is asked between z=-256 (first gap taught) and z=-1019 (finish) except doing the same 5 m jump twice in a row. There is no lint rule for cadence, so this passes CI silently.

### Q3 answer — crates on the forced line are solid StaticBody3Ds that self-clear one frame after contact; none can permanently block a rider
- Severity: P3
- File:line: `scenes/props/breakable.tscn:16-24` (`StaticBody3D`, `collision_layer = 3`, 1×1×1 `BoxShape3D`), `scenes/player/player.tscn:51-53` (`collision_mask = 1`), `src/gameplay/run/level_session.gd:926-1020` (`_process_player_crate_collisions`), `src/gameplay/crates/breakable_crate.gd:230-237` (`_finish_break` → `set_deferred("disabled", true)`)
- Claim: Crates are **not** pass-through — every crate is a solid body the rider physically collides with — but all 32 hog crates set `break_on_touch = true`, which converts `VERB_TOUCH` into `VERB_SPIN` and breaks them, so the block lasts at most one physics frame. No crate in the level can trap or kill a rider.
- Evidence: `breakable.tscn` root is `StaticBody3D` with `collision_layer = 3` (bits 1|2 → physics layers 1 and 2) and an enabled 1 m cube `CollisionShape3D`; the player is `collision_mask = 1`, so the collision is real. `break_on_touch = true` is authored on all 32 crates (grep: 4 lines each in all eight `hog_*.tscn`, including `hog_jump_gaps.tscn:98` on the checkpoint crate). `breakable_crate.gd:54-61` resolves `VERB_TOUCH` → `VERB_SPIN` when `break_on_touch`; `crate_logic.gd:56-62` breaks a standard crate on `VERB_SPIN` and pays 1 wumpa; `:64-68` breaks a checkpoint crate. `_armed` is `true` for every non-time crate (`breakable_crate.gd:191-198`), and there are no time or iron crates in this level. Spin is *unavailable* during the ride (`player_state_machine.gd:139-146` `enter_ride` sets `_air_spin_available = false`; `_process_ride_actions` swallows `ACTION_SPIN`), so `break_on_touch` is the only thing making these crates breakable at all — it is correctly set everywhere. Frame cost: at 9.0 m/s / 60 Hz the rider advances 0.15 m per frame, so each crate costs ≲0.15 m of forward progress before its shape is deferred-disabled. `hog_crate_slalom` specifically: Crate17 (-3.8, -540), Crate18 (+3.8, -570), Crate19 (-3.8, -600), Crate20 (0, -624), all on the 18 m-wide MainRun and all `break_on_touch`; its three `Post*` blocks are the actual obstacles and sit at x 3.95..8.45 / -8.45..-3.95, clear of every crate by ≥0.15 m in x and ≥12 m in z.
- Failure scenario: None fatal. Recorded because the mechanism is load-bearing and invisible: delete or forget one `break_on_touch = true` and that crate becomes a solid 1 m wall on a line the player cannot stop on. Nothing in `lint_level_authoring.py` checks `break_on_touch` against ride segments, and the only guard is `tests/integration/test_level_scenes.gd:1239-1256` (`test_hog_wild_crate_lines_break_on_touch`), which I did not run (orchestrator owns Godot).

### Clean best-and-only-case runtime is 1:53, below §6.1's "2–4 min first clear" floor, and the player cannot make it longer
- Severity: P3
- File:line: `data/tuning/levels/hog_wild.tres:11` (`design_pace_mps = 9.0`), `scenes/levels/wr1_hog_wild.tscn:208-209` (Finish z=-1019), `:94-95` (Player spawn z=0)
- Claim: Spawn-to-finish is 1019 m; at the forced 9.0 m/s that is 113.22 s = **1 min 53 s**, and because the ride speed is not player-controlled a deathless clear cannot take any longer.
- Evidence: 1019 / 9.0 = 113.222 s. `player_motor.gd:58-66` returns `forward × ride_speed_mps` unconditionally for `STATE_RIDE`, with no input term on the forward axis, so the player has no way to slow down; the only way to add time is to die. Comparison with the two shipped levels, both of which clear the floor: boulders 570 m / 4.5 = 126.7 s (2:07); n_sanity_beach 666 m / 4.5 = 148.0 s (2:28). Hog Wild is the only level below 2:00. To reach 2:00 the level would need 1080 m — i.e. ~61 m more, roughly half a segment.
- Failure scenario: No in-game failure. It is a stated-spec miss: §6.1's per-level target is "2–4 min first clear" and there is no lint or test for level duration, so this drifted silently. Flagging because §6.2 bills Hog Wild as "the game's first tempo spike" and a sub-2-minute level is the shortest in Warp Room 1 rather than its escalation.

### `Spine/MountLine` is 8 m from the mount trigger and `Spine/FirstRead` marks nothing; no Spine marker has a runtime consumer
- Severity: P3
- File:line: `scenes/segments/hog_mount_start.tscn:23-27` (`MountLine` local -8, `FirstRead` local -62) vs `scenes/levels/wr1_hog_wild.tscn:121-127` (MountTrigger world z=0, `Shape_ride_trigger` span +2.0 .. -2.0)
- Claim: The marker named `MountLine` is 8 m past where mounting actually happens, and `FirstRead` at -62 does not line up with either obstacle in the segment. `Spine/*` markers have no runtime reader at all — they exist only for the authoring lint — so nothing catches this drift.
- Evidence: Mounting happens either at spawn (via `level_session.gd:243-252` → `HogMount.configure` → `reset_for_player_position`, which mounts because spine progress 0.0 ≥ mount progress 0.0) or on `MountTrigger.body_entered` whose box spans z +2.0 .. -2.0 — both at z ≈ 0, never at -8. The segment's two obstacles are `GateLeft` at z -50.5..-53.5 and `GateRight` at z -82.5..-85.5; `FirstRead` at -62 sits 8.5 m past the first and 20.5 m before the second. Grep for `Spine` across `src/` returns **zero** hits; the only consumer is `scripts/lint_level_authoring.py:1651-1655` `_is_spine_marker`, which uses the markers solely as the polyline for checkpoint-spacing distances.
- Failure scenario: An author retunes the mount beat against `MountLine` (-8) and the mount fires 8 m earlier than expected, or moves the trigger to match the marker and breaks `test_hog_wild_mounts_forced_run_and_dismounts_at_finish`'s spawn-mounted assertion. Same drift class as `Spine/DismountLine` above.

### The intro segment's `GateLeft`/`GateRight` cannot be hit from anywhere on the intended line — they are named obstacles that obstruct nothing
- Severity: P3
- File:line: `scenes/segments/hog_mount_start.tscn:42-50`
- Claim: Both intro gates occupy only the outermost 2.5 m of an 18 m corridor, leaving a 12 m free lane, while every crate and wumpa in the segment sits at |x| ≤ 4 — so the segment that is supposed to teach steering never requires any.
- Evidence: `GateLeft` at (-7.25, 1.6, -52) size (2.5, 4.2, 3) → x -8.50 .. -6.00; `GateRight` at (+7.25, 1.6, -84) → x +6.00 .. +8.50. MainRun is 18 m wide (x -9 .. +9), so the clear lane is x -6.00 .. +6.00 = **12.0 m**. Segment crates: Crate1 x=0, Crate2 x=+4, Crate3 x=-4, Crate4 x=0; wumpa x=+4 and x=-4. Minimum lateral clearance between the line and either gate = |6.00 − 4.00| = **2.0 m**, and the player's collision radius is 0.32 m. By contrast `hog_weave_gates`' blocks span x -9.00..-2.60 / +2.60..+9.00 (6.4 m wide), which does force a lane change. So the intro teaches nothing that the second segment does not then teach from scratch.
- Failure scenario: A player rides the first 128 m — 14.2 s, 11% of the level — with the stick untouched and loses nothing. §6.1's intro→twist shape wants the intro to introduce the verb; here the first genuine steering demand is at z=-158, in the *next* segment.

### Crate cadence: 8 of 33 beats exceed §6.1's "every 2–4s", worst 6.44 s — all at segment seams
- Severity: P3
- File:line: seam pairs, e.g. `scenes/segments/hog_mount_start.tscn:85` (Crate4 world -108) → `scenes/segments/hog_weave_gates.tscn:75` (Crate5 world -156); `hog_plant_chomp.tscn:82` (Crate16 world -482) → `hog_crate_slalom.tscn:75` (Crate17 world -540)
- Claim: Every segment ends with its last crate ~14–20 m before the seam and the next starts ~24–28 m after it, so the beat drops out for 4.2–6.4 s at seven of the eight seams.
- Evidence: intervals at 9.0 m/s (spawn → 32 crates → Finish, 33 intervals): over-4 s intervals are 5.33 s (-108→-156), 4.44 s (-292→-332), 5.78 s (-360→-412), **6.44 s (-482→-540)**, 4.22 s (-624→-662), 4.22 s (-698→-736), 5.11 s (-748→-794), 5.33 s (-882→-930). Mean interval 113.2/33 = 3.43 s. Honest caveat: this is **in line with the shipped levels**, not a Hog Wild regression — boulders is 8/37 over 4 s with a 6.22 s worst case, n_sanity_beach 11/47 with a 10.67 s worst case. There is no lint or test for crate cadence anywhere in the repo.
- Failure scenario: The metronome §2.4 relies on goes silent for ~1.5 beats each time the player crosses a seam, which is exactly where a ride most needs a rhythm cue. Low severity because it is a repo-wide pattern, but it is the one §6.1 authoring rule nothing checks.

### `test_hog_wild_has_the_eight_segment_graybox_contract` contains a tautological crate-count assertion
- Severity: P3
- File:line: `tests/integration/test_level_scenes.gd:1085` and `:1482-1488`
- Claim: `assert_eq(meta.crate_count, _hog_wild_authored_crate_count())` compares `hog_wild.tres`'s `crate_count` against itself and can never fail.
- Evidence: `meta` at `:1073` is `level.get_meta(&"level_meta")`, which is `ExtResource("2_meta")` = `res://data/tuning/levels/hog_wild.tres` (`wr1_hog_wild.tscn:4,58`). `_hog_wild_authored_crate_count()` does `load(HOG_WILD_LEVEL_META_PATH) as LevelMeta` and returns `meta.crate_count` — the same resource (same path, and Godot's resource cache returns the same instance). Both sides are the identical field. Same shape exists for the other two levels (`:102`, `:468`), so it is copied convention, not new breakage. Real protection does exist: `:1269-1272` compares the *counted* scene crates against the meta, and `lint_level_authoring.py`'s `_crate_findings` does the same statically.
- Failure scenario: None directly — but the H7 comment block at `:1543-1551` claims this pattern is mutation-proven, and a reader could take line 1085 as the crate-count guard and delete the real one at 1269 as redundant.

---

# CHECKS THAT PASSED (no finding — recorded with numbers so they are not re-audited)

## Q1 — all eight segments instanced, ordered, on-grid, contiguous: PASS
See the baseline table above. Each of the eight authored `hog_*.tscn` files is instanced exactly once, offsets are 0/-128/-256/-384/-512/-640/-768/-896 (all multiples of 128 → on the 2 m grid), and every seam closes exactly because each segment's `Spine/Exit` is at local -128 = the next segment's offset delta. No segment authored-but-not-instanced, no overlap, no gap in the spine. The 4 m coplanar floor overlap at every seam (EntrySurface pokes 2 m behind Entry, ExitSurface 2 m past Exit) is the repo-wide convention — boulders has 26 such overlaps, n_sanity_beach 20 — and is **required** by `tests/integration/test_level_scenes.gd:1103-1152` (`_full_aabbs_overlap` on all three axes). Not a finding.

## Q5 — checkpoints: PASS on every sub-question
Two checkpoint crates (§6.1 wants 2–3):

| checkpoint | crate_id | world z | spine distance | respawn z (`checkpoint_respawn_offset = (0,-0.45,2)`) |
|---|---|---|---|---|
| Checkpoint12 | 12 | **-360.0** | 360.0 m | -358.0 (on `HogJumpGaps/RunC`, -346..-374) |
| Checkpoint24 | 24 | **-748.0** | 748.0 m | -746.0 (on `HogGapCombine/RunC`, -722..-758) |

Trigger positions: **MountTrigger z = 0.0** (box span +2.0 .. -2.0), **DismountTrigger z = -1019.0** (span -1017.0 .. -1021.0), Finish z = -1019.0 (span -1016.5 .. -1021.5).

Intervals at `design_pace_mps = 9.0`, limit 60 s (`economy.tres:20`):
- start (z=0) → CP12: 360.0 m / 9.0 = **40.000 s** ✅
- CP12 → CP24: 388.0 m / 9.0 = **43.111 s** ✅
- CP24 → Finish: 271.0 m / 9.0 = **30.111 s** ✅

The lint's own boundary computation (which uses `-head_gap = -0.05` and `cumulative[-1] + tail_gap = 1029.22` instead of spawn/finish) gives 40.006 / 43.111 / 31.247 s — same conclusion. Monotonic along the level (360 < 748) ✅. Ordering metadata is consistent: `Checkpoint12` carries `metadata/next_checkpoint_id = 24` (`hog_jump_gaps.tscn:99`) and `Checkpoint24` omits it, which is the same convention boulders and n_sanity_beach use for their final checkpoint (only one `next_checkpoint_id` line each) and which `level_session.gd:830-846` `_first_checkpoint_id()` resolves correctly to 12. **Neither checkpoint sits before the mount trigger (0.0) or after the dismount trigger (-1019.0)**; both respawn points are on solid floor and inside a camera region.

## Q6 — camera coverage: PASS, continuous, no uncovered stretch
Eight `camera_region.gd` `Area3D`s, one per segment, each `BoxShape3D` size (22, 12, 132) at local (0, 3, -64) → local z +2 .. -130, `camera_mode = &"default"` on all eight. World z spans: +2.0..-130.0, -126.0..-258.0, -254.0..-386.0, -382.0..-514.0, -510.0..-642.0, -638.0..-770.0, -766.0..-898.0, -894.0..-1026.0. Consecutive regions overlap by **4.0 m** each; the union is continuous from **+2.0 to -1026.0**. Player spawn (z=0), both checkpoints (-360, -748), both respawn points (-358, -746), all three gaps (-304..-309, -678..-683, -717..-722), the dismount trigger (-1019) and the finish (-1019) are all inside. The ride path's last marker is at -1024, still covered. Lateral: regions are 22 m wide (x ±11) against an 18 m floor (x ±9) ✅. **No uncovered stretch along the forward axis.**

≥15° depression on required jumps (§5.4 pillar 1, `minimum_jump_depression_degrees = 15.0` from `data/tuning/camera.tres`): computed with the lint's own `_camera_frame_at` / `_runtime_camera_offset` / `_jump_depression_degrees` against the level's real `CameraRig/Rail` polyline and the `default` offset (3.6, 4.8, 8.5):

| required jump | takeoff z | landing z | depression |
|---|---|---|---|
| HogJumpGaps/RequiredJumpA | -303.0 | -310.0 | **16.786°** ✅ |
| HogGapCombine/RequiredJumpA | -677.0 | -684.0 | **16.786°** ✅ |
| HogGapCombine/RequiredJumpB | -716.0 | -723.0 | **16.786°** ✅ |

Hand-check of the first: camera at (3.6, 4.8, -303 + 8.5 = -294.5), landing (0, 0, -310) → horizontal = sqrt(3.6² + 15.5²) = 15.913, depression = atan(4.8 / 15.913) = 16.79°. Margin over the 15° minimum is only 1.79°, so this is not comfortable headroom — but it passes.

## Q7 — dead/unresolved content: PASS apart from the P3 marker-drift items above
- All four `NodePath` properties on `HogRide` resolve: `ride_path_path` → `HogRide/Path`, `mount_trigger_path` → `HogRide/MountTrigger`, `dismount_trigger_path` → `HogRide/DismountTrigger`, `hog_visual_path` → `HogRide/HogVisual`. No unresolved NodePath anywhere in the level.
- Both `Path3D` nodes (`HogRide/Path`, `CameraRig/Rail`) are authored with **no `curve` property** — this is *not* dead. `HogMount._ensure_curve_from_markers` (`src/gameplay/ride/hog_mount.gd:156-168`) and `CameraRailController._ensure_curve_from_markers` (called from `_ready` at `:30-33` and `configure` at `:57`) both build a `Curve3D` from the `Marker3D` children at runtime. `HogRide/Path` has 5 markers (0, -256, -512, -768, -1024 → baked length 1024); `CameraRig/Rail` has 9 (+8 through -1024). Both non-empty.
- Every crate (32) and every wumpa (16) except the four deliberate mid-gap wumpa is directly over authored 18 m floor and clear of every obstacle box by ≥0.5 m. The four exceptions — `HogJumpGaps/WumpaA` (0, 1.5, -305), `WumpaB` (0, 1.5, -308), `HogGapCombine/WumpaA` (0, 1.5, -680), `WumpaB` (0, 1.5, -719) — are airborne jump rewards inside the gaps, which is intended, and are collectible: the pickup shape is resized to `wumpa_collect_radius_m = 1.0` at runtime (`level_session.gd:720-739`) against a player cylinder of radius 0.32 advancing 0.15 m per frame.
- Rail/spine marker names all match the segment boundaries they claim (`CameraRig/Rail`: MountEnd -128, WeaveEnd -256, JumpEnd -384, PlantEnd -512, CrateEnd -640, CombineEnd -768, CrescendoEnd -896, Finish -1024 — all exact). The only misnamed markers are `Spine/MountLine` and `Spine/DismountLine` (reported above).
- Placeholder text: `HogRide/HogVisual/GrayboxNotice` reads "HOG — GRAYBOX CAPSULE". This is deliberate and asserted by `tests/integration/test_level_scenes.gd:1086-1091` ("the placeholder must identify itself honestly"), and matches the boulders convention (`ChaseHazard/BoulderVisual/Label` = "BOULDER"). Not a finding.

## `data/tuning/chase.tres` / boulder hazards: NOT referenced — clean
Grep for `chase.tres`, `chase_hazard`, `ChaseHazard`, `boulder`, `Boulder` across `scenes/levels/wr1_hog_wild.tscn`, all eight `scenes/segments/hog_*.tscn`, `data/tuning/hog.tres` and `data/tuning/levels/hog_wild.tres` returns **zero matches**. The level has no `chase_hazard`-group node, so `level_session._discover_and_configure_chase_hazards` finds nothing and `catalog.chase` is never touched here. Auto-run is also correctly suppressed: `PlayerController.mount_hog` (`player_controller.gd:149-152`) sets `_chase_auto_run_remaining_s = 0.0` on mount, so the Boulders auto-run path cannot leak into the ride.

## Relic par times (`relic_sapphire_s`/`relic_gold_s`/`relic_platinum_s` = 0.0): consistent, fails closed
All three are 0.0 in `hog_wild.tres:12-14` — identical to `boulders.tres:12-14` and `n_sanity_beach.tres:12-14`. `level_run_state.gd:381-390` requires all three `> 0.0` (and correctly ordered platinum ≤ gold ≤ sapphire) before relic times are considered valid, so 0.0 disables relic tiers rather than awarding platinum for any time. Relic authoring is a project-wide TODO, not a Hog Wild defect. No finding.
