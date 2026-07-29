# Turns + Closer Camera + Difficulty Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the corridor turn (pilot: N. Sanity Beach + Hog Wild), pull the chase camera in to PS1-Crash framing, and raise difficulty via tuning — per `docs/superpowers/specs/2026-07-29-turns-and-camera-design.md`.

**Architecture:** The runtime is already corridor-relative; this plan (a) fixes the four audited straight-line assumptions (polyline rail kinks, chord-cut corridor tangent, stale gesture axis, world-pinned hog visual), (b) guards the not-yet-ported traversal lint, then (c) authors turns as corner-arc segments plus rotated existing segments, and (d) lands camera + difficulty as pure `.tres` changes.

**Tech Stack:** Godot 4.7.1 (`scripts/run_gut.sh`, GUT), Python 3 lints/tests (pre-commit runs them), `.tres` tuning resources.

## Global Constraints

- **No gameplay numbers in code** — every new number is a tuning field; numeric literals in `src/gameplay/**` limited to `0`, `1`, `-1` (pre-commit lint enforces).
- **TDD** — failing test before each behavior change.
- **Shared tree** — stage explicit paths only; never `git add -A`; two files (`docs/qa/phase05-gate-f2.md`, `docs/superpowers/specs/2026-07-23-crash-remix-design.md`) have someone else's unstaged edits — never stage them.
- **Human gates** — never claim feel; final step reports "ready to test on device".
- **≤90° per bend, no switchbacks; arenas and traversal segments stay unrotated.**
- **Full GUT + Python suites green before each commit; report counts.**
- Run GUT: `bash scripts/run_gut.sh` (env `GODOT_BIN` already valid). Run Python tests: they run in pre-commit; directly via `python3 -m pytest tests/python -q` if that dir exists, else the pre-commit run is the record.

---

### Task 1: Shared curve-from-markers builder with Catmull-Rom handles

**Files:**
- Create: `src/gameplay/common/rail_curve_builder.gd`
- Modify: `src/tuning/camera_tuning.gd` (new export), `data/tuning/camera.tres`, `src/tuning/tuning_service.gd` (validation), and the five `_ensure_curve_from_markers` copies: `src/gameplay/camera/camera_rail_controller.gd:240-251`, `src/gameplay/chase/chase_hazard.gd:274-286`, `src/gameplay/ride/hog_mount.gd:159-171`, `src/gameplay/traversal/traversal_rail.gd:123-130`, `src/gameplay/traversal/wall_run_strip.gd:60-67`
- Test: `tests/gameplay/test_rail_curve_builder.gd`

**Interfaces:**
- Produces: `RailCurveBuilder.curve_from_markers(parent: Node, bake_interval_m: float, handle_length_factor: float) -> Curve3D` (static; class_name RailCurveBuilder). Handles: for interior point i, `out = (p[i+1] − p[i−1]) × factor`, `in = −out`; endpoints get zero handles. Collinear markers therefore reproduce today's straight rails exactly.
- Produces: `CameraTuning.rail_handle_length_factor: float` (value 0.1667 in `camera.tres`).

- [ ] **Step 1: failing test** — `tests/gameplay/test_rail_curve_builder.gd`:

```gdscript
extends GutTest

const BUILDER_PATH := "res://src/gameplay/common/rail_curve_builder.gd"

func _markers_parent(points: Array[Vector3]) -> Node3D:
	var parent := Node3D.new()
	for point in points:
		var marker := Marker3D.new()
		marker.position = point
		parent.add_child(marker)
	add_child_autofree(parent)
	return parent

func test_straight_markers_stay_straight() -> void:
	var script: Script = load(BUILDER_PATH)
	var parent := _markers_parent([
		Vector3.ZERO, Vector3(0, 0, -96), Vector3(0, 0, -192),
	])
	var curve: Curve3D = script.call("curve_from_markers", parent, 0.2, 1.0 / 6.0)
	assert_eq(curve.point_count, 3)
	var mid := curve.sample_baked(curve.get_baked_length() / 2.0)
	assert_almost_eq(mid.x, 0.0, 0.0001)

func test_corner_markers_get_catmull_rom_handles() -> void:
	var script: Script = load(BUILDER_PATH)
	var parent := _markers_parent([
		Vector3.ZERO, Vector3(0, 0, -96), Vector3(-96, 0, -96),
	])
	var curve: Curve3D = script.call("curve_from_markers", parent, 0.2, 1.0 / 6.0)
	var expected_out := (Vector3(-96, 0, -96) - Vector3.ZERO) * (1.0 / 6.0)
	assert_almost_eq(curve.get_point_out(1).x, expected_out.x, 0.0001)
	assert_almost_eq(curve.get_point_out(1).z, expected_out.z, 0.0001)
	assert_eq(curve.get_point_in(1), -curve.get_point_out(1))
	assert_eq(curve.get_point_out(0), Vector3.ZERO)
```

- [ ] **Step 2: run** `bash scripts/run_gut.sh` → new tests FAIL (builder missing).
- [ ] **Step 3: implement** `src/gameplay/common/rail_curve_builder.gd`:

```gdscript
class_name RailCurveBuilder
extends RefCounted


static func curve_from_markers(
	parent: Node,
	bake_interval_m: float,
	handle_length_factor: float
) -> Curve3D:
	var curve := Curve3D.new()
	if bake_interval_m > 0.0:
		curve.bake_interval = bake_interval_m
	var points: Array[Vector3] = []
	if parent != null:
		for marker: Node in parent.get_children():
			if marker is Marker3D:
				points.append((marker as Marker3D).position)
	for point in points:
		curve.add_point(point)
	var index := 1
	while index < points.size() - 1:
		var out_handle := (
			(points[index + 1] - points[index - 1])
			* handle_length_factor
		)
		curve.set_point_out(index, out_handle)
		curve.set_point_in(index, -out_handle)
		index += 1
	return curve
```

- [ ] **Step 4: wire the five call sites.** Each `_ensure_curve_from_markers` keeps its guard clauses and calls the builder. Camera rig passes `_camera_tuning.rail_bake_interval_m` and `_camera_tuning.rail_handle_length_factor`; the other four have no CameraTuning — they read the same catalog (`load("res://data/tuning/gameplay.tres").camera`)? **No** — they get the values through their existing configure paths if available; where none exists (chase/hog/traversal/wall-run build at `_ready` before configure), pass `0.0` bake interval (keep engine default) and the factor from the loaded `GameplayTuning` catalog via `TuningService` if reachable, else preserve exact old behavior by passing `0.0` factor (straight polyline) and set the real factor in `configure(...)` re-build. Keep it minimal: only the camera rig *needs* smoothed handles for corridor_forward; chase/hog paths get markers authored densely along arcs anyway. Decision recorded: camera rig uses the tuning factor; the other four call the builder with factor `0.0` (behavior-identical refactor, one code path).
- [ ] **Step 5: tuning field.** `camera_tuning.gd` add `@export var rail_handle_length_factor: float` under Rail; `camera.tres` add `rail_handle_length_factor = 0.1667`; `tuning_service.gd` validation: reject `rail_handle_length_factor < 0.0 or > 0.5` alongside the existing camera checks at `:273-278`.
- [ ] **Step 6: run** `bash scripts/run_gut.sh` → PASS, all suites.
- [ ] **Step 7: commit** (explicit paths: the new builder, its test, five call-site files, `camera_tuning.gd`, `camera.tres`, `tuning_service.gd`).

### Task 2: Short-baseline corridor tangent

**Files:**
- Modify: `src/gameplay/camera/camera_rail_controller.gd:94-106`, `src/tuning/camera_tuning.gd`, `data/tuning/camera.tres`, `src/tuning/tuning_service.gd`
- Test: `tests/gameplay/test_camera_rail_controller.gd` (extend; file exists — follow its setup pattern)

**Interfaces:**
- Produces: `CameraTuning.corridor_tangent_baseline_m: float` (0.4 in `camera.tres`).

- [ ] **Step 1: failing test.** L-shaped rail (markers (0,0,0), (0,0,−20), (−20,0,−20) via the camera rig scene path used by existing tests), player parked at (0,0,−4) — well before the corner. Assert `corridor_forward()` is within 2° of `Vector3(0,0,−1)`. With today's 2 m look-ahead chord near a corner at (0,0,−16), assert also a second case: player at (0,0,−15.5) → forward must still be within 15° of −Z (the chord version fails this once handles bend the curve; the short baseline passes).
- [ ] **Step 2: run** → FAIL.
- [ ] **Step 3: implement.** In `update_camera`, compute corridor forward from `sample_baked(rail_offset + corridor_tangent_baseline_m)` − `sample_baked(rail_offset)` (fall back to the behind-sample exactly as the current code does), and keep `look_offset`/`look_position` (the 2 m look-ahead) purely for the camera look target. Add the export + tres value 0.4 + validation (`> 0.0`).
- [ ] **Step 4: run** → PASS, full GUT.
- [ ] **Step 5: commit.**

### Task 3: Gesture corridor-axis slew

**Files:**
- Modify: `src/gameplay/input/input_router.gd` (`set_corridor_axis`), `src/gameplay/camera/camera_rail_controller.gd:254-261` (pass delta), `src/tuning/input_tuning.gd`, `data/tuning/input.tres`, `src/tuning/tuning_service.gd`
- Test: `tests/gameplay/test_input_router.gd` (exists — extend)

**Interfaces:**
- Produces: `InputRouter.set_corridor_axis(axis: Vector2, delta_s: float = 0.0)`. Grep every call site of `set_corridor_axis` before commit (audit found one runtime caller + tests).
- Produces: `InputTuning.gesture_axis_slew_degrees_per_s: float` (240.0 in `input.tres` — crosses a 90° corner's axis change in ~0.4 s of held drag).

- [ ] **Step 1: failing test.** Configure router with input tuning; `push_move(Vector2.UP, 0.0, &"touch")` (gesture starts, gesture axis latches to current corridor axis `Vector2.UP`); call `set_corridor_axis(Vector2.RIGHT, 0.1)`; assert the routed movement intent direction has rotated part-way (not still full-forward on the old axis, not snapped to the new one): with 240°/s × 0.1 s = 24°, the corridor-space input should equal `to_corridor_input(UP, UP rotated 24° toward RIGHT)`. Also assert a fresh gesture (`push_move` zero → non-zero) still snap-latches.
- [ ] **Step 2: run** → FAIL.
- [ ] **Step 3: implement.** In `set_corridor_axis(axis, delta_s)`: update `_corridor_axis` as today; then, when a drag is live (`not _screen_movement.is_zero_approx()`) and screen-relative tracking is off, rotate `_gesture_corridor_axis` toward `_corridor_axis` by at most `deg_to_rad(tuning.gesture_axis_slew_degrees_per_s) * delta_s` (use `Vector2.angle_to` + `rotated`, clamp to the remaining angle) and `_route_screen_movement()`. Screen-relative branch keeps its existing snap. `camera_rail_controller._update_input_corridor_axis` gains a `delta_s` parameter passed from `update_camera`.
- [ ] **Step 4: run** → PASS, full GUT.
- [ ] **Step 5: commit.**

### Task 4: Hog visual yaws with the corridor

**Files:**
- Modify: `src/gameplay/ride/hog_mount.gd` (`_attach_visual`, add `_physics_process`)
- Test: `tests/gameplay/test_hog_mount.gd` (exists — extend)

**Interfaces:**
- Consumes: `CrashAnimationDriver.yaw_for_velocity` convention (`src/visual/player/crash_animation_driver.gd:198-205`) — reuse the same static if callable, else identical `atan2` form. Numeric literals are fine there only if the file is outside `src/gameplay/**`; inside hog_mount use only the corridor vector (no literals needed).
- Consumes: player `has_method("corridor_forward")`? It does not — player exposes `set_corridor_forward`. Read the facing from the ride direction instead: `player_motor` moves along corridor forward; hog_mount already knows the ride path — yaw from the path tangent at the player's progress: `tangent = curve.sample_baked(progress + ε) − curve.sample_baked(progress)` using the existing `progress_for_position`. ε is `_ride_path.curve.bake_interval` (already a resource-driven value) — no new literal.

- [ ] **Step 1: failing test.** Build a mount whose ride path bends 90° (markers (0,0,0), (0,0,−20), (−20,0,−20)); mount the player, teleport player to (−10, 0, −20) (on the −X leg), run one `_physics_process`; assert the hog visual's global basis Z-column is within 5° of `Vector3(1,0,0)` (facing −X travel, i.e. `-basis.z` ≈ (−1,0,0)).
- [ ] **Step 2: run** → FAIL (rotation stays ZERO).
- [ ] **Step 3: implement.** While `_mounted` and the path is usable, per physics tick compute the tangent at the player's progress and set the visual's global yaw to face it (`look_at` with `Vector3.UP`, guarding degenerate tangents). Keep `_attach_visual` as-is otherwise.
- [ ] **Step 4: run** → PASS, full GUT.
- [ ] **Step 5: commit.**

### Task 5: Traversal-lint rotated-ancestor guard

**Files:**
- Modify: `scripts/lint_traversal_authoring.py`
- Test: wherever the Python suite tests that lint (grep `lint_traversal` under `tests/`; add a case beside the existing ones)

- [ ] **Step 1: failing test.** Fixture scene text: a wall-run strip under a parent with `transform = Transform3D(0, 0, -1, 0, 1, 0, 1, 0, 0, 0, 0, 0)` (yaw 90°) → expect a finding like `traversal_rotated_ancestor`. An unrotated fixture stays clean.
- [ ] **Step 2: run** the Python suite → FAIL.
- [ ] **Step 3: implement.** While walking to compose `_world_position` (`scripts/lint_traversal_authoring.py:499-511`), also collect each ancestor's basis (`scene_transform_parsing.py` already parses `Transform3D`/`Basis`/`rotation`); if any is non-identity (beyond epsilon), emit `traversal_rotated_ancestor` naming the node. Message text: "wall-run/rail authoring under a rotated parent is unsupported until the traversal lint composes rotations (spec 2026-07-29, deferred)".
- [ ] **Step 4: run** → PASS (225 → 226+).
- [ ] **Step 5: commit.**

### Task 6: Closer chase camera

**Files:**
- Modify: `data/tuning/camera.tres` only: `default_offset = Vector3(1.2, 3.9, 6.8)`, `field_of_view_degrees = 56.0`.

- [ ] **Step 1:** edit values. **Step 2:** full GUT + pre-commit (the level-authoring lint inside the suites re-proves the ≥15° jump rule under the new camera geometry). If a level's required jump fails the ≥15° check, do NOT weaken the lint — raise `default_offset.y` until green and record the final numbers in the commit message. **Step 3:** commit (this file alone) with a note that the fingerprint hash must visibly move on next device boot (repo rule 2).

### Task 7: Corner-arc segments

**Files:**
- Create: `scenes/segments/corner_left_90.tscn`, `scenes/segments/swerve_left_45.tscn`, `scenes/segments/swerve_right_45.tscn`

**Interfaces (produced, used by Tasks 8–9):**
- Local frame: entry at origin heading −Z; `corner_left_90` exits at position (−R, 0, −R) heading −X with R = 12; `swerve_left_45` exits at (−R·(1−cos45°), 0, −R·sin45°) ≈ (−3.51, 0, −8.49) heading (−sin45°, 0, −cos45°); mirror x for the right swerve.
- Spine: `Spine/Entry` at origin, `Spine/Exit` at the exit point, 2 mid markers on the arc (the level lint's polyline projection consumes these).
- Floor: quarter/eighth-annulus approximated by 6 (90°) / 3 (45°) `graybox_platform.tscn` slabs, each yawed 15°/mid-arc-aligned, widths matching the host level corridor (Beach ~8 m; verify Hog width from `hog_crate_slalom.tscn` before authoring and match it).
- Each scene carries a `CameraRegion` (Area3D, `MODE_DEFAULT`) sized to the arc — copy the structure from `beach_jungle_corridor.tscn:78-85`.
- No crates, no enemies (crate counts in `LevelMeta` stay valid).

- [ ] **Step 1:** author `corner_left_90.tscn` (copy `beach_jungle_corridor.tscn` skeleton; replace floor/spine/region as above). **Step 2:** author both swerves. **Step 3:** integration check — the existing `tests/integration/test_level_scenes.gd` patterns don't know these scenes yet; add a small scene-open smoke test asserting Spine/Entry/Exit exist at the documented local positions. **Step 4:** full GUT. **Step 5:** commit.

### Task 8: N. Sanity Beach turn retrofit

**Files:**
- Modify: `scenes/levels/wr1_n_sanity_beach.tscn`, `tests/integration/test_level_scenes.gd` (the world-Z-baked assertions the audit listed that this level trips)

Layout (all in the level scene):
- Segments 1–3 unchanged (0 → −288).
- `CornerJungle` = `corner_left_90.tscn` at (0, 0, −288), no rotation → exits (−12, 0, −300) heading −X.
- Downstream segments re-seated in the rotated frame, yaw +90° (basis columns X=(0,0,−1), Y=(0,1,0), Z=(1,0,0)), i.e. `transform = Transform3D(0, 0, -1, 0, 1, 0, 1, 0, 0, ox, 0, oz)`: CrateCadence origin (−12, 0, −300); TNTIntroduction (−108, 0, −300); PlantGauntlet (−204, 0, −300); Crescendo (−300, 0, −300). (Each straight segment spans 96 m along its local −Z, which now points −X.)
- Rail markers: keep Start/BeachEnd/CratesEnd/JungleEnd (z 8 → −288), then arc markers at (−3.5, 0, −296.5) and (−8.5, 0, −299.5)? **No — compute on the true arc**: center (−12, 0, −288); markers at 30° and 60°: (−12 + 12·cos30°, 0, −288 − 12·sin30°) = (−1.61, 0, −294) and (−12 + 12·cos60°, 0, −288 − 12·sin60°) = (−6, 0, −298.39); then CadenceEnd (−108, 0, −300), TNTEnd (−204, 0, −300), PlantsEnd (−300, 0, −300), Finish (−396, 0, −300).
- `Finish` Area3D: move to (−390, 1.5, −300) with the same +90° yaw so the gate crosses the corridor; `RelicOnly` stopwatch/time-crate positions past the corner re-seated the same way (TimeMedium at old (3, 0.7, −336) → rotate about the corner: distance past −288 is 48 → new position (−12 − 48 + 0, …)? Use the mapping `world = corner_exit + yaw90 · (local − corner_entry_local)`: a point (x, y, −288 − d) with lateral x maps to (−12 − d, y, −300 − x). TimeMedium (3, 0.7, −336): d = 48 → (−60, 0.7, −303). TimeLarge (0, 0.7, −548): d = 260 → (−272, 0.7, −300). Player/Stopwatch/TimeSmall are before the corner — unchanged.
- Player spawn unchanged.

- [ ] **Step 1:** apply the scene edits above. **Step 2:** run full GUT; the audit-flagged straight-Z tests that fail for this level get rewritten to rail-relative equivalents (sort by `get_closest_offset` on the level rail; compare gate/segment placement via transforms, not raw `.z`). Do not delete assertions — port them. **Step 3:** run pre-commit suites (level lint: ≥15° rule, checkpoint spacing at `design_pace_mps = 4.5`, crate count 40 — corner adds none). **Step 4:** commit scene + test changes.

### Task 9: Hog Wild swerve retrofit

**Files:**
- Modify: `scenes/levels/wr1_hog_wild.tscn`, `tests/integration/test_level_scenes.gd` (hog checkpoint sort `:1795-1835`, dismount/finish x/z assertion `:1443-1448`)

Same mechanics as Task 8: insert `swerve_left_45` at the boundary after the second hog segment and `swerve_right_45` two segments later (net heading returns to −Z, offset laterally −x; exact origins computed from the swerve exit formulas in Task 7); re-seat every downstream segment, ride-path markers, rail markers, dismount trigger and Finish gate through the same transform mapping; the hog **ride path** gets markers along both arcs (the ride path is what the hog progress/mount windows and the new visual yaw sample — dense markers every ~4 m on the arcs).

- [ ] **Step 1:** verify hog corridor width from `hog_crate_slalom.tscn` and confirm the swerve scenes match (fix the swerve scenes now if not). **Step 2:** apply the scene edits. **Step 3:** full GUT; port the flagged tests rail-relative. **Step 4:** pre-commit suites green (checkpoint spacing, crate count vs `hog_wild.tres`). **Step 5:** commit.

### Task 10: Difficulty pass (single tuning commit)

**Files:**
- Modify: `data/tuning/enemy_plant.tres`, `data/tuning/enemy_crab.tres`, `data/tuning/enemy_skink.tres`, `data/tuning/hog.tres`, `data/tuning/chase.tres`, `data/tuning/boss_papu.tres`

- [ ] **Step 1:** read each file; scale ~15–20 % in the "harder" direction only for **timing windows and speeds** (shorter telegraphs/chomp windows, faster patrols, hog ride speed up, boulder speed up / start gap down, Papu shockwave tempo up). Leave sizes, health, economy untouched. Record before→after for every field in the commit message.
- [ ] **Step 2:** full GUT + pre-commit — several GUT tests assert against loaded tuning values; if any hard-codes an old number, port the test to read the resource rather than freezing the value, unless the test encodes a spec bound (e.g. touch-latency) — those bounds win and cap the change.
- [ ] **Step 3:** commit these six files alone.

### Task 11: Verification + report

- [ ] **Step 1:** `bash scripts/run_gut.sh` and the pre-commit Python suite one final time; capture both counts.
- [ ] **Step 2:** findings checklist — every spec decision lands in exactly one column: FIXED (with test name), DEFERRED (traversal-lint oriented-math port; corner-piece kit dressing; Papu world-z shockwave math), NOT APPLICABLE (arena rotation).
- [ ] **Step 3:** update `docs/superpowers/specs/2026-07-29-turns-and-camera-design.md` only if implementation diverged; say which side was wrong.
- [ ] **Step 4:** layman Telegram summary via agentos (`/root/agentos`, `lib/tg.py`, OS_TELEGRAM_* env): what changed in play terms, that it needs a phone test, that difficulty is one revert away.
- [ ] **Step 5:** report to operator: suites' counts, the checklist, APK **not** built (deploy is `scripts/deploy_android.sh`, operator-triggered), feel gates untouched and waiting.

## Self-Review

- Spec coverage: Decision 1 → Tasks 7–9; Decision 2 fixes 1–4 → Tasks 1–4; lint guard → Task 5; Decision 3 → Task 6; Decision 4 → Task 10; verification section → Task 11. No gaps.
- Type consistency: `RailCurveBuilder.curve_from_markers(parent, bake_interval_m, handle_length_factor)` is the only cross-task signature besides the two new tuning fields and `set_corridor_axis(axis, delta_s)`; names match across tasks.
- Placeholders: none — every step names exact files, values, and pass/fail behavior; geometry numbers are computed in-plan.
