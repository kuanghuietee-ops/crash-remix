# Wave D test-quality audit — raw findings

Repo `/tmp/crash-remix-wave-d`, branch `wave-d-task20-21`, HEAD `af585f6`, diff `51fdae9..af585f6`.
Static reading only; no Godot/GUT runs by this agent.

**Scope correction:** the task brief calls `tests/integration/test_level_scenes.gd` "new, 391 lines".
It is **not new** — it is a 1623-line pre-existing suite that this commit grew by +391 (no deletions).
`git diff --stat -M 51fdae9..af585f6 -- tests/` confirms only `tests/gameplay/test_ride_state.gd`
is a new file. All judgements below are against the +391 hunk only.

---

### HogMount has 222 lines of production logic and one existence-only test
- Severity: **P1**
- File:line: `tests/gameplay/test_ride_state.gd:341-358` (whole test); production `src/gameplay/ride/hog_mount.gd:1-222`
- Claim: The only test that names `HogMount` asserts nothing about its behaviour — it instantiates the script and asserts two method names exist, giving zero coverage of trigger wiring, path progress, mount/dismount signalling, visual reparenting or the unusable-path guard.
- Evidence:
```gdscript
func test_hog_mount_glue_exists_as_a_real_runtime_node() -> void:
	assert_true(
		ResourceLoader.exists(HOG_MOUNT_SCRIPT_PATH),
		"Task 20 requires the runtime mount/dismount node"
	)
	...
	var mount := script.new() as Node3D
	...
	add_child_autofree(mount)
	assert_true(mount.has_method("configure"))
	assert_true(mount.has_method("reset_for_player_position"))
```
  Untouched by any test: `_ensure_curve_from_markers()` (hog_mount.gd:156-168), `_connect_triggers()`
  (171-193), `_on_mount_trigger_body_entered()` (196-198), `_trigger_progress()` (206-214),
  `_path_is_usable()` (217-222), `_attach_visual()`/`_detach_visual()` (106-128),
  `progress_for_position()` (71-76), and both `mounted`/`dismounted` signals (4-5).
- Failure scenario: the whole `HogMount` node ships with, e.g., a swapped mount/dismount NodePath, an
  inverted `body == _player` guard, or a `_connect_triggers()` that never connects — and the suite is
  green, because the only HogMount test checks that two method *names* exist.

### `assert_true(has_method(...))` + `if not has_method: return` guards hide ~30 assertions behind one failure
- Severity: **P3** (pattern is *not* a silent pass, but it is a coverage cliff)
- File:line: `tests/gameplay/test_ride_state.gd:53-58`, `tests/gameplay/test_ride_state.gd:241-253`
- Claim: The brief suspected these turn a missing feature into a PASS. Verified: they do **not** — the
  preceding `assert_true`/`assert_not_null` records a real GUT failure before the `return`. The defect
  is different and milder: a missing method collapses a 30-assertion behavioural test into a single
  "method missing" failure, so the test can never tell you *how* the feature is broken, only that it is absent.
- Evidence:
```gdscript
	assert_true(
		fsm.has_method("enter_ride"),
		"the player FSM needs one explicit mounted state"
	)
	if not fsm.has_method("enter_ride"):
		return
```
  and
```gdscript
	if (
		not player.has_method("mount_hog")
		or not player.has_method("dismount_hog")
	):
		return
```
- Failure scenario: no undetected bug from the guard itself. Judgement: acceptable as a TDD scaffold,
  but it is dead weight now that the methods exist and should not be read as coverage.

### `test_hog_wild_has_the_eight_segment_graybox_contract` compares the LevelMeta to itself
- Severity: **P2**
- File:line: `tests/integration/test_level_scenes.gd` (+391 hunk) — `assert_eq(meta.crate_count, _hog_wild_authored_crate_count())`, helper at `_hog_wild_authored_crate_count()`
- Claim: A tautology. `meta` comes from `level.get_meta(&"level_meta")` and the helper does
  `load(HOG_WILD_LEVEL_META_PATH).crate_count` — the same `res://data/tuning/levels/hog_wild.tres`,
  which Godot's resource cache returns as the same instance. The assertion is `x == x`.
- Evidence:
```gdscript
	var meta := level.get_meta(&"level_meta") as LevelMeta
	...
	if meta != null:
		assert_eq(meta.level_id, &"wr1_hog_wild")
		assert_eq(meta.crate_count, _hog_wild_authored_crate_count())
```
```gdscript
func _hog_wild_authored_crate_count() -> int:
	var meta := load(HOG_WILD_LEVEL_META_PATH) as LevelMeta
	...
	return meta.crate_count if meta != null else -1
```
- Failure scenario: none caught, none missed — the *useful* version of this check does exist in
  `test_hog_wild_crate_lines_break_on_touch` (`assert_eq(collectible_count, _hog_wild_authored_crate_count())`),
  which counts real scene crates. The tautological copy is noise that inflates the apparent
  assertion count of the graybox contract test. Delete or replace with `assert_eq(meta, load(path))`
  if the intent was "the scene points at the authored resource".

### Level `wumpa_total = 46` is authored and never verified against the scene
- Severity: **P2**
- File:line: `data/tuning/levels/hog_wild.tres:11` (`wumpa_total = 46`); no match for `wumpa` anywhere in `tests/integration/test_level_scenes.gd`
- Claim: This commit adds a new LevelMeta with a wumpa budget and no test counts wumpa pickups in
  `scenes/levels/wr1_hog_wild.tscn`. `grep -n "wumpa" tests/integration/test_level_scenes.gd` returns nothing
  for any level, so the gap is pre-existing, but Wave D adds a fresh unverified number to it.
- Evidence: `hog_wild.tres` — `crate_count = 32`, `wumpa_total = 46`, `design_pace_mps = 9.0`.
  Only `crate_count` is cross-checked against the scene.
  **The authored number does currently balance** — I checked by hand: 32 crate instances across the
  eight `scenes/segments/hog_*.tscn` (4 each), of which 2 are `crate_checkpoint`
  (`hog_gap_combine.tscn:105`, `hog_jump_gaps.tscn:94`), leaves 30 standard crates ×
  `wumpa_per_standard_crate = 1` (`data/tuning/economy.tres:7`) plus 16 `wumpa.tscn` pickups
  (2 per segment) × `wumpa_per_pickup = 1` = **46**. So this is a regression-risk gap, not a live bug.
- Failure scenario: someone adds or removes a crate line or a wumpa pair in a later polish pass and does
  not update `wumpa_total`. The HUD (`src/ui/hud.gd:145-148`) shows a target the level cannot reach and
  the 100%-collection condition becomes unattainable. Nothing in `tests/` recomputes this sum for any
  level — `grep -rn wumpa_total tests/` finds only a fixture literal and a HUD-plumbing test.

### Hog Wild's required jumps skip the camera-region author rule that N Sanity Beach enforces
- Severity: **P2**
- File:line: `tests/integration/test_level_scenes.gd:408` (`test_required_jump_is_authored_inside_a_camera_region`, uses `_instantiate_level()` = N Sanity Beach only) vs. the new `test_hog_wild_uses_ride_pace_and_authors_required_jumps`
- Claim: The pre-existing camera-region enclosure rule is applied to exactly one level. The new
  Hog Wild equivalent asserts only that `RequiredJump*` nodes exist and each has `Takeoff` + `Landing`
  — the enclosing-`CameraRegion` half of the rule is dropped, on the one level where the camera is
  least forgiving (forced-run, no player brake).
- Evidence — the existing rule:
```gdscript
			if (
				bounds.has_point(takeoff.global_position)
				and bounds.has_point(landing.global_position)
			):
				enclosing_regions += 1
		assert_gt(
			enclosing_regions,
			0,
			"%s must stay inside one authored camera region"
			% required_jump.name
		)
```
  the new Hog Wild version:
```gdscript
	assert_gt(
		required_jumps.size(),
		0,
		"Hog Wild needs authored jump reads, not a flat corridor"
	)
	for required_jump: Node in required_jumps:
		assert_not_null(required_jump.get_node_or_null("Takeoff"))
		assert_not_null(required_jump.get_node_or_null("Landing"))
```
- Failure scenario: a required ride jump is authored in a camera gap or straddles two regions; the
  camera cuts mid-air on a jump the player cannot slow down for. CLAUDE.md names this rule
  ("every required jump passes the ≥15° camera rule") as author-lint scope, and it is not applied here.

### No test asserts the eight Hog Wild segments carry their CameraRegions
- Severity: **P2**
- File:line: Boulders has the rule at `tests/integration/test_level_scenes.gd:549-569`; the Hog Wild block (+391 hunk) has no equivalent
- Claim: Each of the eight hog segments authors two `CameraRegion` nodes
  (`grep -c CameraRegion scenes/segments/hog_*.tscn` → 2 each, 16 total; the level root itself has 0),
  and nothing in the new tests reads any of them. The `test_hog_wild_has_the_eight_segment_graybox_contract`
  loop only asserts `Segments/<Name>` is non-null.
- Evidence — the existing Boulders rule that was not replicated:
```gdscript
		var region := level.get_node_or_null(
			"Segments/%s/CameraRegion" % segment_name
		) as CameraRegion
		assert_not_null(
			region,
			"%s needs a real CameraRegion" % segment_name
		)
		...
		assert_eq(
			region.camera_mode,
			CameraRegion.MODE_TOWARD_CAMERA
		)
```
  the Hog Wild replacement:
```gdscript
	for segment_name: StringName in HOG_WILD_SEGMENT_NAMES:
		assert_not_null(
			level.get_node_or_null(
				"Segments/%s" % segment_name
			),
			"%s must be instanced into the Hog Wild route"
			% segment_name
		)
```
- Failure scenario: a segment's CameraRegion is authored with the wrong mode/extent, or a whole
  region is missing, and the ride has an uncovered stretch where the camera falls back to the default
  shot. Nothing fails. This is the direct answer to "do the camera regions cover the ride" — **no test does.**

### The Hog Wild ride Path3D has no authored curve and the marker-derived curve is untested
- Severity: **P2**
- File:line: `scenes/levels/wr1_hog_wild.tscn:105` (`[node name="Path" type="Path3D" parent="HogRide"]` — no `curve =` line), markers at 107-120; builder at `src/gameplay/ride/hog_mount.gd:156-168`
- Claim: The whole ride is progress-driven off a `Curve3D` that exists only at runtime, synthesised from
  five `Marker3D` children by `_ensure_curve_from_markers()`. No test asserts the curve is built, has five
  points, or has a baked length that spans the corridor — and no test covers `_path_is_usable() == false`.
- Evidence — the production builder, entirely uncovered:
```gdscript
func _ensure_curve_from_markers() -> void:
	if _ride_path == null:
		return
	if (
		_ride_path.curve != null
		and _ride_path.curve.point_count > 0
	):
		return
	var curve := Curve3D.new()
	for marker: Node in _ride_path.get_children():
		if marker is Marker3D:
			curve.add_point((marker as Marker3D).position)
	_ride_path.curve = curve
```
  and the guard whose false branch nothing reaches:
```gdscript
func _path_is_usable() -> bool:
	return (
		_ride_path != null
		and _ride_path.curve != null
		and _ride_path.curve.point_count > 0
	)
```
- Failure scenario: someone renames the markers to `Node3D`, reorders them, or nests them one level
  deeper (the loop is `get_children()`, not recursive). The curve silently becomes empty →
  `_path_is_usable()` false → `reset_for_player_position` force-dismounts at spawn →
  **Hog Wild boots unmounted and the level is a walking-pace corridor with no hog.** Green suite.
  Note `progress_for_position` also returns a hard `0.0` when the path is unusable
  (hog_mount.gd:71-76), so "player at progress 0, mount at progress 0" would then read as *mounted* on
  the trigger path while `reset_for_player_position` reads it as *dismounted* — an inconsistency no test pins.

### Only one of `reset_for_player_position`'s three branches is exercised
- Severity: **P2**
- File:line: `src/gameplay/ride/hog_mount.gd:56-64`; the only caller under test is `LevelSession.configure` → `_discover_and_configure_hog_mounts` (`src/gameplay/run/level_session.gd:240-252`) and `_reset_hog_mounts_for_position` (`src/gameplay/run/level_session.gd:1267-1279`)
- Claim: `test_hog_wild_mounts_forced_run_and_dismounts_at_finish` and
  `test_hog_wild_checkpoint_death_respawns_mounted` both land on the *inside-the-ride* branch. The
  before-mount branch and the past-dismount branch are never taken, and they differ in a way that
  matters — only the before-mount branch restores the authored hog transform.
- Evidence:
```gdscript
	if (
		player_progress_m >= mount_progress_m
		and player_progress_m < dismount_progress_m
	):
		_set_mounted(true)                # <-- the only branch under test
	elif player_progress_m < mount_progress_m:
		_set_mounted(false, true)         # restore_authored_visual = true
	else:
		_set_mounted(false)               # restore_authored_visual = false
```
- Failure scenario: a checkpoint authored past the `DismountTrigger` (z < -1019 in
  `scenes/levels/wr1_hog_wild.tscn:129-131`) respawns the player through the `else` branch. The hog
  visual is reparented home *keeping its world transform* rather than snapping back to the authored
  local transform, so the graybox capsule is left stranded wherever the player died. Nothing fails.

### The mount/dismount Area3D wiring is bypassed — the test calls the private handler directly
- Severity: **P1**
- File:line: `tests/integration/test_level_scenes.gd` (+391 hunk) — `mount.call("_on_dismount_trigger_body_entered", player)`; production wiring at `src/gameplay/ride/hog_mount.gd:171-203`
- Claim: The one test that dismounts does it by invoking the private signal handler by name. It therefore
  proves `_set_mounted(false)` works and proves nothing about `_connect_triggers()`, the exported
  NodePaths, the Area3D layer/mask, or the `body == _player` filter. `_on_mount_trigger_body_entered`
  is never called at all, by any test.
- Evidence — the test:
```gdscript
	mount.call("_on_dismount_trigger_body_entered", player)

	assert_false(mount.call("is_mounted"))
	assert_false(player.call("is_hog_mounted"))
	assert_ne(player.call("current_state"), &"ride")
	assert_eq(hog_visual.get_parent(), mount)
```
  the production wiring nothing reaches:
```gdscript
	if _dismount_trigger != null:
		var dismount_callback := Callable(
			self,
			&"_on_dismount_trigger_body_entered"
		)
		if not _dismount_trigger.body_entered.is_connected(
			dismount_callback
		):
			_dismount_trigger.body_entered.connect(
				dismount_callback
			)
```
- Failure scenario: the two exported NodePaths are swapped, or `MountTrigger.collision_mask`
  (`scenes/levels/wr1_hog_wild.tscn:121-124`, mask = 1) stops matching the player's layer, or
  `_connect_triggers()` is dropped from `_ready()`. The player rides straight through the finish
  line still mounted, or the connection never fires at all — and the suite is green because the
  test hand-calls the callback the engine was supposed to call.

### The non-player-body guard on both triggers is untested
- Severity: **P2**
- File:line: `src/gameplay/ride/hog_mount.gd:196-203`
- Claim: Both handlers filter on `body == _player`, and every test call passes the real player, so the
  guard's false branch is never taken.
- Evidence:
```gdscript
func _on_mount_trigger_body_entered(body: Node3D) -> void:
	if body == _player:
		_set_mounted(true)


func _on_dismount_trigger_body_entered(body: Node3D) -> void:
	if body == _player:
		_set_mounted(false)
```
- Failure scenario: the guard is removed or inverted during a later refactor. An enemy, a pushed crate,
  or any other `PhysicsBody3D` entering the dismount volume force-dismounts the player mid-ride (and
  entering the mount volume remotely re-mounts them, resetting their jump state). No test notices.

### Re-entering the mount trigger while already mounted silently resets ride state
- Severity: **P2**
- File:line: `src/gameplay/ride/hog_mount.gd:79-94` and `src/gameplay/player/player_controller.gd:149-163` (`mount_hog`)
- Claim: `_set_mounted(true)` guards only the *signal* against re-entry (`if not _mounted: mounted.emit()`),
  not the `mount_hog()` call. A second mount-trigger entry re-runs the full mount transition. Untested.
- Evidence:
```gdscript
	if next_mounted:
		if (
			_player == null
			or not _player.has_method("mount_hog")
		):
			return
		_player.call("mount_hog")
		_attach_visual()
		if not _mounted:
			mounted.emit()
		_mounted = true
		return
```
  and `mount_hog()` unconditionally does `_state_machine.enter_ride(...)`, which clears
  `_ground_jump_available`, `_double_jump_available`, `_air_spin_available`
  (`src/gameplay/player/player_state_machine.gd:139-146`).
- Failure scenario: the mount volume is authored large enough (or the corridor loops) that the player
  re-enters it mid-ride jump. `enter_ride` re-fires, the in-flight jump's state is reset, and the player
  is dropped back to a fresh ride state mid-air. Nothing tests idempotency in either direction.

### `hog_tuning == null` desyncs HogMount from the player, and no test pins any of the three null paths
- Severity: **P1**
- File:line: `src/gameplay/player/player_controller.gd:149-151` (`mount_hog` early return), `src/gameplay/player/player_motor.gd:58-60` (motor returns ZERO), `src/gameplay/player/player_motor.gd:171-176` (`impulse_velocity` no-op), `src/gameplay/player/player_controller.gd:565-567` (`tap_height_for_impulse` → 0.0); interaction at `src/gameplay/ride/hog_mount.gd:83-94`
- Claim: `configure()`'s new hog parameter is **optional with a null default**, and every null path is a
  silent no-op that no test covers. Worst of them: `mount_hog()` bails before setting `_ride_mounted`,
  but `HogMount._set_mounted(true)` only checks `has_method("mount_hog")` — so HogMount reparents the hog
  visual onto the player, emits `mounted`, and records `_mounted = true` while the player is still in a
  normal walking state.
- Evidence:
```gdscript
func mount_hog() -> void:
	if _hog_tuning == null:
		return
	_ride_mounted = true
```
```gdscript
	if state == STATE_RIDE:
		if hog_tuning == null:
			return Vector3.ZERO
```
```gdscript
		IMPULSE_RIDE_JUMP:
			if hog_tuning != null:
				result.y = JumpKinematicsType.upward_speed_for_height(
```
  the optional parameter that makes omission silent:
```gdscript
	phase_enabled: bool,
	hog_tuning: HogTuning = null
) -> void:
```
  and proof the omission is easy — a pre-existing helper already omits it:
  `tests/gameplay/test_wall_run_state.gd:774-785` calls `configure` with nine args, no hog.
- Failure scenario: any future call site forgets the tenth argument (or a stale on-device override
  loses the `hog` section in a way `_backfill_missing_sections` misses). Then: HogMount reports mounted
  and the level/HUD listens to `mounted`, the player keeps normal controls with a hog capsule
  parented to them, `horizontal_velocity` returns `Vector3.ZERO` if the ride state ever *is* entered
  (player frozen in place mid-corridor), ride jumps do nothing, and `dismount_hog()` early-returns
  because `_ride_mounted` was never set. This is exactly the "silently dead-wired config" failure mode
  CLAUDE.md rule 2 exists to prevent, and there is no test for it.

### `exit_ride`'s `grounded` argument is never distinguished — both branches pass the same assertion
- Severity: **P2**
- File:line: `src/gameplay/player/player_state_machine.gd:148-157`; asserted at `tests/gameplay/test_ride_state.gd:336-338` and in `test_hog_wild_mounts_forced_run_and_dismounts_at_finish`
- Claim: Every dismount assertion is `assert_ne(current_state, &"ride")`, which is satisfied by
  `STATE_GROUNDED` *and* `STATE_AIRBORNE`. The branch, and the jump-availability bookkeeping that
  hangs off it, is untested. There is no airborne-dismount test at all.
- Evidence — production:
```gdscript
func exit_ride(now_s: float, grounded: bool) -> void:
	_ground_jump_available = grounded
	_double_jump_available = true
	_air_spin_available = true
	_set_state(
		STATE_GROUNDED if grounded else STATE_AIRBORNE,
		now_s
	)
```
  every test assertion:
```gdscript
	player.call("dismount_hog")
	assert_false(player.call("is_hog_mounted"))
	assert_ne(player.call("current_state"), &"ride")
```
- Failure scenario: invert the ternary, or hardcode `grounded = true` in `dismount_hog`'s
  `is_on_floor()` call site (`player_controller.gd:172`), and the player either gets a free ground jump
  out of thin air at the finish line or loses their ground jump on solid ground. Both ship green.
  `_double_jump_available = true` / `_air_spin_available = true` are likewise unasserted — a dismount
  that forgot to restore them would leave the player unable to double-jump for the rest of the run.

### No test mounts or dismounts while airborne
- Severity: **P2**
- File:line: `src/gameplay/player/player_controller.gd:149-163` (`mount_hog` has no grounded precondition); `src/gameplay/player/player_state_machine.gd:158-190` (`_process_ride_actions` early-returns when `not grounded`)
- Claim: Every mount in the suite happens from a grounded spawn, and every dismount from
  `is_on_floor()` true. The airborne halves of both transitions are unexercised.
- Evidence: `test_ride_state.gd:129-138` steps the FSM with `grounded = true` on landing and
  `test_ride_state.gd:112-121` with `grounded = false` — but only to assert the *jump* is suppressed
  (`impulse == &"none"`). Nothing calls `mount_hog()` or `dismount_hog()` while off the floor.
- Failure scenario: the player is mid-jump when the mount trigger fires (easy — `MountTrigger` is at
  `position = Vector3(0, 2, 0)`, two metres up, in `scenes/levels/wr1_hog_wild.tscn:121-123`).
  `enter_ride` clears every jump flag and forces `ride_speed_mps` forward with gravity still applied,
  so the player is committed to a forced-run trajectory from an arbitrary height. No test says what
  should happen, so no behaviour is pinned either way.

### `_process_ride_actions` consumes DOWN and SPIN and nothing verifies the consumption
- Severity: **P2**
- File:line: `src/gameplay/player/player_state_machine.gd:158-172` (consumes at `:164-172`); assertions at `tests/gameplay/test_ride_state.gd:92`, `301-304`
- Claim: The tests assert the *effects* of suppression (state stays `ride`, `is_spinning` false) but never
  that the buffered intents were drained. Deleting both `consume_pressed` calls keeps every existing
  assertion green, because during the ride the elif-chain skips crouch/slide/spin handling anyway.
- Evidence — production:
```gdscript
	intents.consume_pressed(
		InputIntent.ACTION_DOWN,
		now_s,
		input_tuning.action_buffer_s
	)
	intents.consume_pressed(
		InputIntent.ACTION_SPIN,
		now_s,
		input_tuning.action_buffer_s
	)
```
  the only related assertions:
```gdscript
	assert_false(fsm.get("is_spinning"))
```
```gdscript
	assert_false(
		player.call("is_spinning"),
		"ride mode must keep Spin inert"
	)
```
- Failure scenario: remove the consumes. Every Spin/Down press mashed during the ride stays in the
  intent buffer; on dismount the player instantly spins or belly-flops from stale input within
  `action_buffer_s`. Suite green. The same gap applies to the Phase suppression at
  `player_controller.gd:308-310` — the test asserts `PhaseState.active_set()` is unchanged, which is also
  true if the press is merely *ignored* rather than *consumed*.

### The FSM's own suite covers the ride only as two constant literals
- Severity: **P3**
- File:line: `tests/gameplay/test_player_state_machine.gd:342`, `:349-352`
- Claim: The +5 lines added to the FSM suite are pure vocabulary assertions — a constant equals its own
  literal. `grep -c "ride\|hog" tests/gameplay/test_player_state_machine.gd` → 2, both of these.
  `tests/gameplay/test_player_motor.gd` has **zero** ride/hog references, so the motor suite gained no
  coverage at all for its two new branches.
- Evidence:
```gdscript
	assert_eq(state_constants.get("STATE_RIDE"), &"ride")
	...
	assert_eq(
		decision_constants.get("IMPULSE_RIDE_JUMP"),
		&"ride_jump"
	)
```
  Same shape at `tests/gameplay/test_ride_state.gd:93-98`:
```gdscript
	assert_eq(
		decision_script.get_script_constant_map().get(
			"IMPULSE_RIDE_JUMP"
		),
		&"ride_jump"
	)
```
- Failure scenario: nothing directly — these are honest declaration tests inside a test whose stated
  purpose is the vocabulary. The finding is that they are the *only* ride content in the two suites
  that own the changed files, and they should not be counted as behavioural coverage of `enter_ride`,
  `exit_ride` or `_process_ride_actions`.

### `test_ride_jump_uses_hog_height_through_jump_kinematics` recomputes production's own formula
- Severity: **P3**
- File:line: `tests/gameplay/test_ride_state.gd:185-213` vs `src/gameplay/player/player_motor.gd:171-176`
- Claim: The expected value is produced by calling the same `JumpKinematics.upward_speed_for_height`
  with the same two inputs that production uses. It pins the *wiring* (right tuning field, right helper)
  but cannot detect an error inside the shared formula.
- Evidence — test:
```gdscript
	assert_almost_eq(
		launch.y,
		JumpKinematics.upward_speed_for_height(
			float(_hog.get("hog_jump_height_m")),
			_move
		),
		FLOAT_TOLERANCE
	)
```
  production:
```gdscript
		IMPULSE_RIDE_JUMP:
			if hog_tuning != null:
				result.y = JumpKinematicsType.upward_speed_for_height(
					hog_tuning.hog_jump_height_m,
					move_tuning
				)
```
- Failure scenario: limited. It *would* catch reading `move_tuning.jump_full_height_m` instead
  (authored 2.0 for hog vs a different move value), so it is not fully vacuous. Judgement: acceptable
  given the repo's "no numbers in code" rule forbids a literal expectation — but a companion assertion
  on the *apex height actually reached* would be the non-tautological version.
  For contrast, `test_ride_motor_forces_forward_and_steers_only_laterally`
  (`tests/gameplay/test_ride_state.gd:142-182`) is **genuinely behavioural**: it loops
  `ignored_forward_input` over `[-1.0, 0.0, 1.0]`, feeds a non-zero incoming velocity
  `Vector3(20.0, 0.0, 20.0)` that production must discard, and would catch a flipped
  `forward.cross(UP)` sign. That one is good and should be kept as the model.

### The intermittent wall-run failure is an engine-uptime race: the test pins a fake absolute timestamp into a path that reads the real clock
- Severity: **P1** (flaky gate on a green-count claim)
- File:line: `tests/gameplay/test_wall_run_state.gd:439-477`, specifically `:459` and `:462`; clock at `src/core/monotonic_clock.gd:7-8`; consumer at `src/gameplay/player/player_controller.gd:739-748`
- Claim: The test attaches to the wall with a **hardcoded** `now_s = 6.0`, then hands control to two real
  physics ticks. `_physics_process` recomputes `now_s` from `Time.get_ticks_usec()` — *engine uptime* — so
  the wall-run deadline (`6.0 + maximum_duration_s = 8.0 s`) is compared against however long the Godot
  process has been alive. Whether the test passes depends on how much wall-clock work ran before it in the
  shared GUT process. This is time-dependent, and specifically **shared-process-uptime-dependent** — not
  physics-determinism-dependent and not caused by leaked state from another suite.
- Evidence — the test:
```gdscript
	player.velocity = Vector3.FORWARD * 6.0
	assert_true(player.call("try_wall_attach", strip, 6.0))
	var before_z := player.global_position.z

	await wait_physics_frames(2)
```
  the clock the ticks actually use:
```gdscript
static func now_s() -> float:
	return float(Time.get_ticks_usec()) / MICROSECONDS_PER_SECOND
```
```gdscript
func _physics_process(delta_s: float) -> void:
	...
	var now_s := MonotonicClockType.now_s()
	...
	advance_logic(now_s, is_on_floor(), delta_s, _corridor_forward)
```
  and the deadline it is compared against — `data/tuning/wall_run.tres:11` `maximum_duration_s = 2.0`,
  passed at `src/gameplay/player/player_controller.gd:865-868`:
```gdscript
	_state_machine.enter_wall_run(
		now_s,
		_wall_run_tuning.maximum_duration_s
	)
```
- **The arithmetic confirms it.** When uptime > 8.0 s the first tick times the wall run out, detaches, and
  applies `detach_outward_speed_mps = 5.0` (`data/tuning/wall_run.tres:13`) along the surface normal.
  The reported failure is distance **0.65** against expected **0.4** (`surface_stick_distance_m`, line 9):
  `0.65 − 0.40 = 0.25 = 5.0 m/s × 3/60 s`. That is exactly three physics ticks of outward detach
  velocity. The reported state (`airborne` instead of `wall_run`) is the same event. Re-attachment cannot
  rescue it because timeout sets `_wall_attach_blocked = strip`, and `try_wall_attach` rejects a blocked
  strip (`player_controller.gd:832-839`).
- **Does Wave D plausibly perturb it? Yes — by adding elapsed time upstream, not by changing physics.**
  `scripts/run_gut.sh:60` builds the shared list with `find … | sort`, so execution order is
  deterministic: `tests/gameplay/test_ride_state.gd` (position 26) runs **before**
  `tests/gameplay/test_wall_run_state.gd` (position 30). The new `test_ride_state.gd` instantiates the
  real `player.tscn`, awaits process frames, and mutates `PhaseState` — all real uptime added directly
  ahead of a test whose pass condition is "uptime < 8.0 s". `tests/gameplay/test_player_controller.gd`
  and `test_player_state_machine.gd` also grew. Nothing in the diff to `player_motor.gd`,
  `player_state_machine.gd` or `player_controller.gd` touches wall-run logic — the wall-run branch of
  `horizontal_velocity` is untouched and `STATE_RIDE` is a new, disjoint branch.
- **Confidence:** *high* (≈0.9) that the mechanism is the hardcoded 6.0 s vs. real uptime timeout — the
  0.25 m = 5.0 m/s × 3 ticks arithmetic is an exact match and I can name the deadline. *Medium* (≈0.6)
  that Wave D specifically tipped it; the test was already sitting on the 8-second edge, and any commit
  that adds uptime before position 30 has the same effect. I did not run GUT, so I cannot report the
  actual uptime at that point.
- Failure scenario: the fix is to stop pinning absolute timestamps — attach with
  `MonotonicClock.now_s()` (or drive `advance_logic` explicitly instead of awaiting real physics frames)
  so the deadline is relative. Until then, every future commit that adds a test before position 30
  randomly re-breaks this test, and the standing temptation is to "fix" it by loosening the 0.0001
  tolerance, which would delete a real wall-stick regression check.

### `scripts/run_gut.sh` `set -e` hides 71 tests behind the shared process's exit code — including the only new Hog Wild hub test
- Severity: **P1**
- File:line: `scripts/run_gut.sh:2`, `:69-73`, `:75-77`, isolated list at `:10-14`
- Claim: Confirmed by reading. `set -euo pipefail` is on line 2; the shared process runs at line 73;
  the three isolated suites run in a `for` loop at lines 75-77, *after* it. GUT is invoked with `-gexit`,
  so a failing shared process exits non-zero, `set -e` aborts the script, and the loop never executes.
- Evidence:
```bash
set -euo pipefail
```
```bash
run_gut_process -gdir= "-gtest=$shared_process_test_list"

for isolated_suite in "${isolated_suites[@]}"; do
    run_gut_process -gdir= "-gtest=$isolated_suite"
done
```
```bash
isolated_suites=(
    "res://tests/integration/test_main_boot.gd"
    "res://tests/integration/test_island_slice.gd"
    "res://tests/integration/test_warp_room.gd"
)
```
- Reporting consequence: a run that hits the flaky wall-run failure reports **461 tests (460 pass, 1 fail)**
  and silently omits **71 tests** — `test_main_boot` (40), `test_island_slice` (17), `test_warp_room` (14).
  Anyone quoting "460 passing" is quoting 460 of 532. CLAUDE.md's "Report test counts. Report what you did
  not test." is violated by the harness itself, not by the reporter.
- Failure scenario: **this commit is the worst case for that masking.** The only new test covering the
  hub→Hog Wild path, `test_boot_hub_level_list_reaches_hog_wild_scene`, lives in `tests/integration/test_warp_room.gd`
  — an isolated suite. So on any run where the wall-run flake fires, the *entire* Wave D level-entry
  integration check never executes and its absence is invisible in the reported count. Minimum fix:
  run the isolated suites regardless of the shared process's status (collect exit codes, exit non-zero at
  the end) so the count is always complete.

### No new test writes to live state — verified clean
- Severity: **P3** (informational; the check the brief asked for, answered)
- File:line: `tests/tuning/test_tuning_service.gd:5`, `:245-257`; `src/tuning/tuning_service.gd:142-147`, `:502-508`; `scripts/run_gut.sh:26-33`
- Claim: I checked all six touched test files for writes to `user://` tuning overrides, `data/`, or `logs/`.
  The new cases are clean on every axis.
- Evidence — the override path is a sandbox, created and removed per test:
```gdscript
const TEST_OVERRIDE_PATH := "user://test_sandbox/tuning_override.tres"
```
```gdscript
func before_each() -> void:
	_remove_test_override()
	...

func after_each() -> void:
	_remove_test_override()
```
  the new `test_pre_hog_override_backfills_hog_and_preserves_existing_edits` writes only there
  (`ResourceSaver.save(stale, TEST_OVERRIDE_PATH)`) and mutates only a deep copy
  (`authored.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)`).
  The three new tests that mutate `service.catalog.hog`
  (`test_fingerprint_moves_when_a_hog_value_changes` does `hog.set("ride_speed_mps", … + 0.1)` and never
  restores it) are safe because the service never hands out the cached `res://` resource:
```gdscript
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
```
```gdscript
func _clone_catalog(source: GameplayTuning) -> GameplayTuning:
	var clone := GameplayTuning.new()
	for section_name: StringName in SECTION_NAMES:
		var source_section := source.get(section_name) as Resource
		if source_section != null:
			clone.set(section_name, source_section.duplicate(true))
	return clone
```
  and the harness additionally redirects the whole user dir per process:
```bash
    test_user_root="$(mktemp -d /tmp/crash-remix-gut-user.XXXXXX)"
    ...
    XDG_DATA_HOME="$test_user_root" "$godot_bin" \
```
  `tests/integration/test_warp_room.gd:16` likewise pins `user://test_sandbox/task15_warp_room` and the
  new Hog Wild hub test sets `root.set("save_dir", TEST_SAVE_DIR)` before adding the scene.
  `grep` over the six files finds no write to `data/` or `logs/`.
- Failure scenario: none found. Reported so the batch has an explicit NOT-APPLICABLE column entry.

### `test_ride_state.gd` mutates the `PhaseState` autoload with no teardown
- Severity: **P2**
- File:line: `tests/gameplay/test_ride_state.gd:258-259`
- Claim: The new controller test reconfigures and resets a global autoload mid-suite and never restores it.
  Deterministic order puts `test_ride_state.gd` (position 26) ahead of
  `tests/integration/test_phase_state_integration.gd` (position 36) in the same shared process, so
  whatever it leaves behind is visible to later suites.
- Evidence:
```gdscript
	PhaseState.configure(_catalog.get("phase"))
	PhaseState.reset_to_authored_set()
	var phase_before := PhaseState.active_set()
```
  There is no `after_each`/`after_all` in the file — `before_all` (`:26-33`) is the only lifecycle hook.
- Failure scenario: a later phase test that expects a non-authored active set, or expects `PhaseState`
  unconfigured, starts depending on execution order. This is the same class of hazard as the wall-run
  flake and the reason that one is hard to attribute — the shared process has no per-suite global reset.

### `HogMount`'s `mounted` / `dismounted` signals have zero consumers and zero assertions
- Severity: **P3**
- File:line: `src/gameplay/ride/hog_mount.gd:4-5`, emitted at `:92` and `:102`
- Claim: Dead public API. `grep -rn '&"mounted"\|&"dismounted"\|\.mounted\.\|\.dismounted\.' src/ scenes/ tests/`
  returns nothing — nothing connects to either signal and no test asserts either is emitted (or that
  re-entry does not double-emit, which the `if not _mounted` / `if _mounted` guards exist to prevent).
- Evidence:
```gdscript
signal mounted
signal dismounted
```
```gdscript
		if not _mounted:
			mounted.emit()
		_mounted = true
```
- Failure scenario: no live bug today, because nothing listens. It matters because the guards around the
  emits are the *only* re-entry protection in `_set_mounted`, and they are untested — so when a HUD or
  audio hook is added later it can be double-fired without any existing test noticing.

### Integration-test honesty verdict: it instantiates and configures the real level, but never steps it
- Severity: **P2**
- File:line: the `test_hog_wild_*` block in `tests/integration/test_level_scenes.gd` (+391 hunk); helper `_configured_hog_wild()`
- Claim: Better than existence-only, worse than an integration test. It really does load
  `scenes/levels/wr1_hog_wild.tscn`, `add_child_autofree`, await a process frame, configure the router,
  player and `LevelSession` with the real catalog, and assert real geometry. But it drives exactly **one**
  hand-called logic frame with hand-supplied arguments and never lets the level run: no
  `wait_physics_frames`, no `move_and_slide`, so the player never travels a metre of the corridor.
- Evidence — the entire "forced run" simulation:
```gdscript
	player.velocity = Vector3.ZERO
	player.call(
		"advance_logic",
		5.0,
		true,
		1.0 / 60.0,
		Vector3.FORWARD
	)
```
  Note the injected arguments: `grounded = true` is a literal (not `player.is_on_floor()`), and the
  corridor forward is a literal `Vector3.FORWARD` — **not** the level's authored corridor direction. So
  nothing verifies the level actually establishes a corridor forward for the ride, and nothing verifies
  the player is on the floor where the scene puts them (`Player` is at
  `scenes/levels/wr1_hog_wild.tscn:94-95`, `position = Vector3(0, 0.05, 0)`).
- What it *does* assert for real, and these are good:
  - eight `Segments/<Name>` nodes are instanced, and the graybox Label3D text is
    `"HOG — GRAYBOX CAPSULE"` (honest-placeholder check);
  - `test_hog_wild_handoffs_overlap_on_all_three_axes` — real geometry: consecutive `Spine/Exit` and
    `Spine/Entry` markers must be `is_equal_approx`, and `ExitSurface`/`EntrySurface` AABBs must overlap
    in X, Y and Z. This is a genuine, non-tautological authoring constraint.
  - `dismount_trigger` X/Z must equal `Finish` X/Z — verified against the scene: `DismountTrigger`
    `position = Vector3(0, 2, -1019)` (`:129-131`) and `Finish` `position = Vector3(0, 1.5, -1019)`
    (`:208-209`). Real constraint, correctly authored.
  - crate count: 32 real `StaticBody3D` crates counted out of the scene against `meta.crate_count`,
    with each asserted `break_on_touch` and each `apply_verb(&"touch")` returning `breaks == true`.
    This is the strongest new assertion in the file and it is genuinely behavioural.
  - checkpoint **count** (2) — see below for what is missing.
- Failure scenario: anything that only manifests in motion ships undetected — the player failing to
  traverse a segment handoff, falling through a graybox floor, the dismount trigger never being reached
  because the ride path and the collision geometry disagree, or the eight segments' `CameraRegion`s
  leaving a gap. The suite proves the level *assembles*; it does not prove the level is *playable*,
  which is precisely the predecessor-project failure CLAUDE.md was written about ("shipped with a core
  loop nobody had played").

### Checkpoint **ordering** is assumed by a sort helper, not asserted
- Severity: **P3** (mitigated — see the Python lint note)
- File:line: `_hog_wild_checkpoint()` in `tests/integration/test_level_scenes.gd` (+391 hunk); count assertion `assert_eq(checkpoints, HOG_WILD_EXPECTED_CHECKPOINTS)` with `HOG_WILD_EXPECTED_CHECKPOINTS := 2`
- Claim: The GUT side asserts the checkpoint *count* only. Ordering is imposed by the test's own
  `sort_custom` on descending Z, so a mis-ordered `crate_id` would be silently re-sorted rather than caught.
- Evidence:
```gdscript
	checkpoints.sort_custom(
		func(first: Node, second: Node) -> bool:
			return (
				(first as Node3D).global_position.z
				> (second as Node3D).global_position.z
			)
	)
```
- **Mitigation, verified by running it:** `scripts/lint_level_authoring.py` auto-discovers every level
  (`sorted(levels_root.rglob("*.tscn"))`, line 1715) so Hog Wild is in scope automatically, and it does
  enforce `checkpoint_spacing` against `meta.design_pace_mps`, `checkpoint_progression`
  (`metadata/next_checkpoint_id` chain) and `checkpoint_off_spine`. I ran it read-only (it contains no
  file writes): **exit 0, no findings.** So ordering and ≤60 s spacing *are* enforced — in Python, not in GUT.
- Failure scenario: low. The residual risk is that the GUT suite reads as if it covers pacing when it does
  not, and `test_hog_wild_uses_ride_pace_and_authors_required_jumps`'s message
  ("checkpoint lint pace must match the forced ride") points at a lint in a different language that a
  GUT-only run never invokes.

### `test_hog_wild_handoffs_overlap_on_all_three_axes` can pass with **zero** assertions
- Severity: **P2**
- File:line: `tests/integration/test_level_scenes.gd:1103-1116`, helper at `:1497-1500`
- Claim: This is the "assert count is 0 for a branch it claims to cover" pattern the brief asked me to
  hunt, and it is real here. `_hog_wild_segment()` is a bare `get_node_or_null(...) as Node3D` with no
  assertion inside. If the segment lookups fail, all seven loop iterations `continue` before reaching any
  assertion and the test finishes having asserted **nothing** — a GUT pass. `.gutconfig.json` sets no
  fail-on-zero-assertions option.
- Evidence:
```gdscript
	for index: int in range(
		HOG_WILD_SEGMENT_NAMES.size() - 1
	):
		var current := _hog_wild_segment(level, index)
		var next := _hog_wild_segment(level, index + 1)
		if current == null or next == null:
			continue
```
```gdscript
func _hog_wild_segment(level: Node, index: int) -> Node3D:
	return level.get_node_or_null(
		"Segments/%s" % HOG_WILD_SEGMENT_NAMES[index]
	) as Node3D
```
  The same shape recurs at `:1129-1136` — missing `ExitSurface`/`EntrySurface`/`Spine/Exit`/`Spine/Entry`
  nodes are asserted first there, so those do fail loudly. Only the outer segment lookup is unguarded.
- Mitigation stated honestly: `test_hog_wild_has_the_eight_segment_graybox_contract:1062` *would* fail if
  the `Segments/<Name>` nodes went missing, so the suite as a whole catches that specific case. What is not
  caught is a *rename of the container path* combined with someone deleting or skipping the graybox test,
  or a partial rename that leaves only some names valid — the handoff test would then silently verify
  fewer pairs than the seven it advertises, with no signal that its coverage shrank.
- Failure scenario: refactor `Segments/` to `Route/` in the scene; the graybox test fails (good), someone
  updates that test's path but not `_hog_wild_segment`'s; the handoff test goes permanently vacuous and
  every future segment-handoff regression ships. Fix: assert non-null in `_hog_wild_segment`, or count
  verified pairs and `assert_eq(pairs, HOG_WILD_SEGMENT_NAMES.size() - 1)` at the end.

---

## Answers to the brief's coverage enumeration (Q2)

Each item the brief listed, with a verdict. "Not tested" means no assertion anywhere in `tests/`
reaches the branch.

| Ride behaviour | Tested? | Where / risk |
|---|---|---|
| Mounting while airborne | **No** | `mount_hog` has no grounded precondition; `MountTrigger` sits 2 m up. See "No test mounts or dismounts while airborne". |
| Dismounting while airborne (`exit_ride`'s `grounded`) | **No** | Every assertion is `assert_ne(state, &"ride")`, true for both branches. See dedicated finding. |
| Respawn **while mounted** | **Yes — twice, and honestly** | `tests/gameplay/test_ride_state.gd:329-335` and `test_hog_wild_checkpoint_death_respawns_mounted` both assert `is_hog_mounted()` and `current_state == &"ride"` after `respawn()`, covering `player_controller.gd:656-659`. Caveat: the `assert_true(mount.call("is_mounted"))` in the level test is near-vacuous — `_mounted` was already true and `respawn()` never touches `HogMount`. |
| Mount/dismount trigger firing for a **non-player** body | **No** | `body == _player` guard at `hog_mount.gd:196-203`, false branch unreached. |
| Re-entering the mount trigger a second time | **No** | `_set_mounted(true)` re-runs `mount_hog()`, resetting jump flags. |
| `hog_tuning == null` — motor returns `Vector3.ZERO` | **No** | `player_motor.gd:58-60`. `tests/gameplay/test_player_motor.gd` has zero ride references. |
| `hog_tuning == null` — `impulse_velocity` no-op | **No** | `player_motor.gd:171-176`. |
| `hog_tuning == null` — `mount_hog()` early-return vs. HogMount marking itself mounted | **No — and this is the P1** | `player_controller.gd:149-151` vs `hog_mount.gd:83-94`. Desync is real and unpinned. |
| `hog_tuning == null` — `tap_height_for_impulse` → 0.0 | **No** | `player_controller.gd:565-567`. |
| Path3D with empty/absent curve (`_path_is_usable()` false) | **No** | And the authored scene *has* no curve — it is synthesised from 5 markers at runtime. See dedicated finding. |
| `reset_for_player_position` past the dismount trigger | **No** | Only the inside-the-ride branch runs; the two else branches differ in visual restoration. |
| Crouch / slide suppression during the ride | **Partial** | `test_ride_state.gd:60-90` pushes `ACTION_DOWN` and asserts the state stays `&"ride"`, which does constrain the elif-chain at `player_state_machine.gd:70-77`. Not covered: that the DOWN intent is *consumed* rather than merely skipped. |
| Spin suppression | **Partial** | `assert_false(fsm.get("is_spinning"))` (`:92`) and `assert_false(player.call("is_spinning"))` (`:301-304`). Same consumption gap. |
| Phase suppression | **Partial** | `assert_eq(PhaseState.active_set(), phase_before)` (`:296-300`) proves the world set does not toggle; it does not distinguish "consumed" from "ignored", so a stale Phase press could still fire post-dismount. |
| Forward input (`input_vector.y`) genuinely ignored | **Yes, well** | `test_ride_state.gd:160-176` loops y over `[-1.0, 0.0, 1.0]` asserting constant forward speed, and the controller-level test at `:279-295` pushes `Vector2(0.5, 1.0)` and still gets exactly `ride_speed_mps` forward. This one is solid. |

## Positives worth keeping (so the report is not all deficit)

- All four `.githooks/pre-commit` lints are green at HEAD — I ran each read-only (none contain file
  writes): `lint_gameplay_numbers.py` (exit 0, "Gameplay numeric-literal lint passed"),
  `check_content_vocabulary.py` (exit 0), `lint_traversal_authoring.py` (exit 0),
  `lint_level_authoring.py` (exit 0, silent), plus
  `python3 -m unittest discover -s tests -p 'test_*.py'` → **78 tests, OK**. So the "no gameplay numbers
  in code" hard rule holds for the new `hog_mount.gd` / `player_motor.gd` / `player_controller.gd` code,
  and the new level passes the Python author lint.
- `test_ride_motor_forces_forward_and_steers_only_laterally` and
  `test_hog_wild_handoffs_overlap_on_all_three_axes` are model tests: real inputs, real geometry,
  would fail on a sign flip or a mis-authored handoff.
- The tuning side is thorough and honest: `test_fingerprint_moves_when_a_hog_value_changes` proves the
  new section reaches the fingerprint (CLAUDE.md rule 2),
  `test_pre_hog_override_backfills_hog_and_preserves_existing_edits` proves a pre-hog phone override
  migrates instead of resetting *and* that an unrelated operator edit survives, and
  `PHASE0_BASELINE_FIELD_SET_SHA256` was deliberately recomputed rather than left stale. This is the
  best-tested part of the commit.
