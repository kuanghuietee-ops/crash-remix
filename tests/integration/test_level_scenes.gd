extends GutTest

const LEVEL_SCENE_PATH := (
	"res://scenes/levels/wr1_n_sanity_beach.tscn"
)
const LEVEL_META_PATH := (
	"res://data/tuning/levels/n_sanity_beach.tres"
)
const BOULDERS_LEVEL_SCENE_PATH := (
	"res://scenes/levels/wr1_boulders.tscn"
)
const BOULDERS_LEVEL_META_PATH := (
	"res://data/tuning/levels/boulders.tres"
)
const HOG_WILD_LEVEL_SCENE_PATH := (
	"res://scenes/levels/wr1_hog_wild.tscn"
)
const HOG_WILD_LEVEL_META_PATH := (
	"res://data/tuning/levels/hog_wild.tres"
)
const BASE_CATALOG_PATH := "res://data/tuning/gameplay.tres"
const SEGMENT_NAMES: Array[StringName] = [
	&"BeachLanding",
	&"FirstCrates",
	&"JungleCorridor",
	&"CrateCadence",
	&"TNTIntroduction",
	&"PlantGauntlet",
	&"Crescendo",
]
const EXPECTED_CHECKPOINTS := 2
const EXPECTED_IRON_CRATES := 3
# H9: per 01-DESIGN.md §5, these three segments are the ones designated to
# receive an enemy once Task 17 builds them (jungle corridor = skink,
# crate cadence = crab, plant gauntlet = plant) -- the other four segments
# are not.
const ENEMY_BEARING_SEGMENTS: Array[StringName] = [
	&"JungleCorridor",
	&"CrateCadence",
	&"PlantGauntlet",
]
const EXPECTED_ENEMIES_BY_SEGMENT := {
	&"JungleCorridor": {
		&"skink": 1,
	},
	&"CrateCadence": {
		&"crab": 2,
	},
	&"PlantGauntlet": {
		&"plant": 2,
	},
}
const EXPECTED_ENEMY_TOTAL := 5
const BOULDERS_SEGMENT_NAMES: Array[StringName] = [
	&"BouldersIntro",
	&"ChaseGate",
	&"ChaseLeft",
	&"ChaseRight",
	&"ChaseWeave",
	&"ChaseBreather",
	&"FinalSprint",
	&"BoulderDropGate",
	&"CodaCorridor",
]
const BOULDERS_TOWARD_CAMERA_SEGMENTS: Array[StringName] = [
	&"ChaseGate",
	&"ChaseLeft",
	&"ChaseRight",
	&"ChaseWeave",
	&"ChaseBreather",
	&"FinalSprint",
]
const BOULDERS_EXPECTED_CHECKPOINTS := 2
const HOG_WILD_SEGMENT_NAMES: Array[StringName] = [
	&"HogMountStart",
	&"HogWeaveGates",
	&"HogJumpGaps",
	&"HogPlantChomp",
	&"HogCrateSlalom",
	&"HogGapCombine",
	&"HogCrescendo",
	&"HogDismountFinish",
]
const HOG_WILD_EXPECTED_CHECKPOINTS := 2
const CHASE_GAP_TOLERANCE_M := 0.001
const TOWARD_CAMERA_OPPOSITION_DOT := -0.9
const TOWARD_CAMERA_MINIMUM_DEPRESSION_DEGREES := 30.0
const TOWARD_CAMERA_MAXIMUM_DEPRESSION_DEGREES := 35.0


func test_n_sanity_beach_has_the_seven_segment_contract() -> void:
	var level := _instantiate_level()
	if level == null:
		return
	add_child_autofree(level)
	await wait_process_frames(1)

	var meta := level.get_meta(&"level_meta") as LevelMeta
	assert_not_null(meta)
	if meta != null:
		assert_eq(meta.level_id, &"wr1_n_sanity_beach")
		assert_eq(meta.crate_count, _authored_crate_count())
	assert_true(level is LevelSession)
	assert_not_null(level.get_node_or_null("Player"))
	assert_not_null(level.get_node_or_null("CameraRig"))
	assert_not_null(level.get_node_or_null("Input/InputRouter"))
	assert_not_null(level.get_node_or_null("UI/TouchControls"))
	assert_not_null(level.get_node_or_null("Finish"))

	for segment_name: StringName in SEGMENT_NAMES:
		var segment := level.get_node_or_null(
			"Segments/%s" % segment_name
		)
		assert_not_null(
			segment,
			"%s must be instanced into the authored route"
			% segment_name
		)


func test_segment_handoffs_overlap_as_full_aabbs_on_all_axes() -> void:
	var level := _instantiate_level()
	if level == null:
		return
	add_child_autofree(level)
	await wait_process_frames(1)

	for index: int in range(SEGMENT_NAMES.size() - 1):
		var current := _segment(level, index)
		var next := _segment(level, index + 1)
		if current == null or next == null:
			continue
		var exit_surface := (
			current.get_node_or_null("ExitSurface") as Node3D
		)
		var entry_surface := (
			next.get_node_or_null("EntrySurface") as Node3D
		)
		var exit_marker := (
			current.get_node_or_null("Spine/Exit") as Marker3D
		)
		var entry_marker := (
			next.get_node_or_null("Spine/Entry") as Marker3D
		)
		assert_not_null(exit_surface)
		assert_not_null(entry_surface)
		assert_not_null(exit_marker)
		assert_not_null(entry_marker)
		if (
			exit_surface == null
			or entry_surface == null
			or exit_marker == null
			or entry_marker == null
		):
			continue
		assert_true(
			exit_marker.global_position.is_equal_approx(
				entry_marker.global_position
			),
			"%s → %s spine markers must meet exactly"
			% [current.name, next.name]
		)
		assert_true(
			_full_aabbs_overlap(exit_surface, entry_surface),
			"%s → %s must overlap in X, Y, and Z"
			% [current.name, next.name]
		)


func test_handoff_check_rejects_breaks_on_each_world_axis() -> void:
	var level := _instantiate_level()
	if level == null:
		return
	add_child_autofree(level)
	await wait_process_frames(1)
	var current := _segment(level, 0)
	var next := _segment(level, 1)
	if current == null or next == null:
		return
	var exit_surface := current.get_node("ExitSurface") as Node3D
	var entry_surface := next.get_node("EntrySurface") as Node3D
	var authored_position := next.position

	next.position.x += 30.0
	assert_false(
		_full_aabbs_overlap(exit_surface, entry_surface),
		"a longitudinal-only check would miss a lateral break"
	)
	next.position = authored_position
	next.position.y += 10.0
	assert_false(
		_full_aabbs_overlap(exit_surface, entry_surface),
		"a planar check would miss a vertical break"
	)
	next.position = authored_position
	next.position.z += 30.0
	assert_false(
		_full_aabbs_overlap(exit_surface, entry_surface),
		"the authored route also needs longitudinal overlap"
	)


func test_level_has_collectible_counts_optional_iron_and_wave_b_enemies() -> void:
	var level := _instantiate_level()
	if level == null:
		return
	add_child_autofree(level)
	await wait_process_frames(1)
	var collectible_ids: Array[int] = []
	var all_ids: Array[int] = []
	var checkpoint_count := 0
	var iron_count := 0

	for crate: Node in _crates(level):
		var crate_id := int(crate.get("crate_id"))
		var crate_type := StringName(crate.get("crate_type"))
		assert_false(
			crate_id in all_ids,
			"crate_id %d must be unique" % crate_id
		)
		all_ids.append(crate_id)
		if crate_type == &"iron":
			iron_count += 1
		elif crate_type != &"time":
			collectible_ids.append(crate_id)
		if crate_type == &"checkpoint":
			checkpoint_count += 1
		assert_eq(
			(crate as CollisionObject3D).collision_layer & 2,
			2,
			"player attack areas must be able to detect every crate"
		)

	assert_eq(
		collectible_ids.size(),
		_authored_crate_count()
	)
	assert_eq(checkpoint_count, EXPECTED_CHECKPOINTS)
	assert_eq(iron_count, EXPECTED_IRON_CRATES)
	assert_eq(
		_enemy_count_within(level),
		EXPECTED_ENEMY_TOTAL,
		"Task 17 must populate the three designated beach segments"
	)


func test_enemy_count_stays_scoped_to_the_authored_level() -> void:
	var level := _instantiate_level()
	if level == null:
		return
	add_child_autofree(level)
	await wait_process_frames(1)

	assert_eq(
		_enemy_count_within(level),
		EXPECTED_ENEMY_TOTAL
	)

	var probe := Node.new()
	probe.add_to_group(&"enemy")
	level.add_child(probe)

	assert_eq(
		_enemy_count_within(level),
		EXPECTED_ENEMY_TOTAL + 1,
		"a real enemy group member under the level must be counted"
	)


func test_enemy_bearing_segments_have_the_authored_behavior_mix() -> void:
	var level := _instantiate_level()
	if level == null:
		return
	add_child_autofree(level)
	await wait_process_frames(1)

	for segment_name: StringName in ENEMY_BEARING_SEGMENTS:
		var segment := level.get_node_or_null(
			"Segments/%s" % segment_name
		)
		assert_not_null(segment)
		if segment == null:
			continue
		var actual_counts := {}
		for enemy: Node in _enemies(level):
			if not segment.is_ancestor_of(enemy):
				continue
			assert_true(
				enemy.has_method("enemy_kind"),
				"every authored enemy must identify its behavior type"
			)
			if not enemy.has_method("enemy_kind"):
				continue
			var enemy_kind := StringName(enemy.call("enemy_kind"))
			actual_counts[enemy_kind] = (
				int(actual_counts.get(enemy_kind, 0)) + 1
			)
			assert_eq(
				(enemy as CollisionObject3D).collision_layer & 2,
				2,
				"player attack areas must detect every enemy"
			)
		assert_eq(
			actual_counts,
			EXPECTED_ENEMIES_BY_SEGMENT[segment_name],
			"%s must carry its designed Wave B enemy mix"
			% segment_name
		)


func test_authored_skink_reacts_on_centerline_and_returns_over_floor() -> void:
	var level := _instantiate_level()
	if level == null:
		return
	add_child_autofree(level)
	await wait_process_frames(1)
	var skink := level.get_node_or_null(
		"Segments/JungleCorridor/SkinkIntro"
	) as Node3D
	var approach_run := level.get_node_or_null(
		"Segments/JungleCorridor/ApproachRun"
	) as Node3D
	var catalog := load(BASE_CATALOG_PATH) as GameplayTuning
	assert_not_null(skink)
	assert_not_null(approach_run)
	assert_not_null(catalog)
	if skink == null or approach_run == null or catalog == null:
		return
	var tuning := catalog.enemy_skink
	assert_not_null(tuning)
	if tuning == null:
		return
	skink.call("configure", tuning, catalog.move)
	var spawn := skink.global_position
	var lateral_axis := (
		skink.global_transform.basis.x.normalized()
	)
	var forward_axis := (
		skink.global_transform.basis.z.normalized()
	)
	var centerline_lateral_m := (
		approach_run.global_position - spawn
	).dot(lateral_axis)
	var centerline_player := (
		spawn
		+ lateral_axis * centerline_lateral_m
		+ forward_axis * tuning.trigger_range_m
	)
	var trigger_s := 25.0

	skink.call("advance_logic", trigger_s, centerline_player)
	assert_eq(
		skink.call("behavior_state"),
		&"telegraph",
		"the real edge placement must detect Crash on centerline"
	)
	var active_s := trigger_s + tuning.telegraph_s
	skink.call("advance_logic", active_s, centerline_player)
	var dart_end_s := active_s + tuning.attack_active_s
	skink.call("advance_logic", dart_end_s, centerline_player)
	assert_eq(skink.call("behavior_state"), &"cooldown")
	var dart_offset_m := (
		skink.global_position - spawn
	).dot(lateral_axis)
	assert_gt(
		dart_offset_m,
		0.0,
		"the real skink must finish its dart toward corridor center"
	)
	var platform_bounds := _box_world_bounds(approach_run)
	var skink_bounds := _box_world_bounds(skink)
	assert_gte(
		skink_bounds.position.x,
		platform_bounds.position.x,
		"the skink's dart must keep its left edge over floor"
	)
	assert_lte(
		skink_bounds.end.x,
		platform_bounds.end.x,
		"the skink's dart must keep its right edge over floor"
	)
	assert_gte(
		skink_bounds.position.z,
		platform_bounds.position.z,
		"the skink's dart must stay within the floor length"
	)
	assert_lte(
		skink_bounds.end.z,
		platform_bounds.end.z,
		"the skink's dart must stay within the floor length"
	)
	skink.call(
		"advance_logic",
		dart_end_s + tuning.attack_active_s * 0.5,
		centerline_player
	)
	var return_offset_m := (
		skink.global_position - spawn
	).dot(lateral_axis)
	assert_between(
		return_offset_m,
		0.0,
		dart_offset_m,
		"the real skink must travel home without teleporting"
	)


func test_required_jump_is_authored_inside_a_camera_region() -> void:
	var level := _instantiate_level()
	if level == null:
		return
	add_child_autofree(level)
	await wait_process_frames(1)
	var required_jumps := level.find_children(
		"RequiredJump*",
		"Node3D",
		true,
		false
	)

	assert_gt(required_jumps.size(), 0)
	for required_jump: Node in required_jumps:
		assert_not_null(required_jump.get_node_or_null("Takeoff"))
		assert_not_null(required_jump.get_node_or_null("Landing"))
		var enclosing_regions := 0
		var takeoff := (
			required_jump.get_node_or_null("Takeoff") as Marker3D
		)
		var landing := (
			required_jump.get_node_or_null("Landing") as Marker3D
		)
		if takeoff == null or landing == null:
			continue
		for candidate: Node in level.find_children(
			"*",
			"Area3D",
			true,
			false
		):
			if not candidate is CameraRegion:
				continue
			var bounds := _box_world_bounds(candidate as Node3D)
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


func test_boulders_has_the_nine_segment_chase_contract() -> void:
	var level := _instantiate_boulders()
	if level == null:
		return
	add_child_autofree(level)
	await wait_process_frames(1)

	var meta := level.get_meta(&"level_meta") as LevelMeta
	assert_not_null(meta)
	if meta != null:
		assert_eq(meta.level_id, &"wr1_boulders")
		assert_eq(
			meta.crate_count,
			_boulders_authored_crate_count()
		)
	assert_true(level is LevelSession)
	assert_not_null(level.get_node_or_null("Player"))
	assert_not_null(level.get_node_or_null("CameraRig"))
	assert_not_null(level.get_node_or_null("ChaseHazard"))
	assert_not_null(level.get_node_or_null("Finish"))

	for segment_name: StringName in BOULDERS_SEGMENT_NAMES:
		assert_not_null(
			level.get_node_or_null(
				"Segments/%s" % segment_name
			),
			"%s must be instanced into the Boulders route"
			% segment_name
		)


func test_boulders_handoffs_overlap_on_all_three_axes() -> void:
	var level := _instantiate_boulders()
	if level == null:
		return
	add_child_autofree(level)
	await wait_process_frames(1)

	for index: int in range(
		BOULDERS_SEGMENT_NAMES.size() - 1
	):
		var current := _boulders_segment(level, index)
		var next := _boulders_segment(level, index + 1)
		if current == null or next == null:
			continue
		var exit_surface := (
			current.get_node_or_null("ExitSurface") as Node3D
		)
		var entry_surface := (
			next.get_node_or_null("EntrySurface") as Node3D
		)
		var exit_marker := (
			current.get_node_or_null("Spine/Exit") as Marker3D
		)
		var entry_marker := (
			next.get_node_or_null("Spine/Entry") as Marker3D
		)
		assert_not_null(exit_surface)
		assert_not_null(entry_surface)
		assert_not_null(exit_marker)
		assert_not_null(entry_marker)
		if (
			exit_surface == null
			or entry_surface == null
			or exit_marker == null
			or entry_marker == null
		):
			continue
		assert_true(
			exit_marker.global_position.is_equal_approx(
				entry_marker.global_position
			),
			"%s → %s spine markers must meet exactly"
			% [current.name, next.name]
		)
		assert_true(
			_full_aabbs_overlap(exit_surface, entry_surface),
			"%s → %s must overlap in X, Y, and Z"
			% [current.name, next.name]
		)


func test_boulders_real_chase_segments_use_toward_camera() -> void:
	var level := _instantiate_boulders()
	if level == null:
		return
	add_child_autofree(level)
	await wait_process_frames(1)
	var catalog := load(BASE_CATALOG_PATH) as GameplayTuning
	assert_not_null(catalog)
	if catalog == null:
		return

	for segment_name: StringName in (
		BOULDERS_TOWARD_CAMERA_SEGMENTS
	):
		var region := level.get_node_or_null(
			"Segments/%s/CameraRegion" % segment_name
		) as CameraRegion
		assert_not_null(
			region,
			"%s needs a real CameraRegion" % segment_name
		)
		if region == null:
			continue
		assert_eq(
			region.camera_mode,
			CameraRegion.MODE_TOWARD_CAMERA
		)
		assert_eq(
			region.offset_for(catalog.camera),
			catalog.camera.toward_camera_offset,
			"the assembled scene must resolve the live chase shot"
		)


func test_boulders_live_camera_basis_faces_back_down_corridor() -> void:
	var level := _instantiate_boulders()
	if level == null:
		return
	add_child_autofree(level)
	await wait_process_frames(1)
	var catalog := load(BASE_CATALOG_PATH) as GameplayTuning
	var player := level.get_node_or_null(
		"Player"
	) as CharacterBody3D
	var controller := level.get_node_or_null(
		"CameraRig"
	) as Node3D
	var rail := level.get_node_or_null(
		"CameraRig/Rail"
	) as Path3D
	var camera := level.get_node_or_null(
		"CameraRig/Camera3D"
	) as Camera3D
	var region := level.get_node_or_null(
		"Segments/ChaseLeft/CameraRegion"
	) as CameraRegion
	assert_not_null(catalog)
	assert_not_null(player)
	assert_not_null(controller)
	assert_not_null(rail)
	assert_not_null(camera)
	assert_not_null(region)
	if (
		catalog == null
		or player == null
		or controller == null
		or rail == null
		or camera == null
		or region == null
	):
		return
	var regions: Array = []
	for candidate: Node in level.find_children(
		"*",
		"",
		true,
		false
	):
		if candidate is CameraRegion:
			regions.append(candidate)
	player.global_position = Vector3(
		region.global_position.x,
		player.global_position.y,
		region.global_position.z
	)
	controller.call(
		"configure",
		player,
		rail,
		camera,
		catalog.camera,
		regions
	)
	var ordinary_view := -camera.global_basis.z
	assert_gt(
		Vector3(
			ordinary_view.x,
			0.0,
			ordinary_view.z
		).normalized().dot(
			controller.call("corridor_forward")
		),
		0.0,
		"the ordinary chase-behind rig must fail the toward-camera shot"
	)

	controller.call(
		"_on_region_body_entered",
		player,
		region
	)
	for _settle_step: int in range(4):
		controller.call(
			"update_camera",
			catalog.camera.region_blend_s
		)
	var view_direction := -camera.global_basis.z
	var horizontal_view := Vector3(
		view_direction.x,
		0.0,
		view_direction.z
	).normalized()
	var corridor_forward := (
		controller.call("corridor_forward") as Vector3
	).normalized()
	var depression_degrees := rad_to_deg(atan2(
		-view_direction.y,
		Vector2(
			view_direction.x,
			view_direction.z
		).length()
	))

	assert_lte(
		horizontal_view.dot(corridor_forward),
		TOWARD_CAMERA_OPPOSITION_DOT,
		"the actual camera basis must look back against chase progress"
	)
	assert_between(
		depression_degrees,
		TOWARD_CAMERA_MINIMUM_DEPRESSION_DEGREES,
		TOWARD_CAMERA_MAXIMUM_DEPRESSION_DEGREES,
		"the actual camera basis must preserve the authored chase angle"
	)
	assert_gt(
		(
			camera.global_position
			- player.global_position
		).dot(corridor_forward),
		0.0,
		"the actual camera must sit ahead of the player"
	)


func test_boulders_chase_auto_runs_then_hands_off_normal_control() -> void:
	var level := await _configured_boulders()
	if level == null:
		return
	var catalog := load(BASE_CATALOG_PATH) as GameplayTuning
	var player := level.get_node_or_null(
		"Player"
	) as CharacterBody3D
	var hazard := level.get_node_or_null("ChaseHazard")
	var router := level.get_node_or_null(
		"Input/InputRouter"
	) as InputRouter
	var controller := level.get_node_or_null(
		"CameraRig"
	) as Node3D
	var rail := level.get_node_or_null(
		"CameraRig/Rail"
	) as Path3D
	var camera := level.get_node_or_null(
		"CameraRig/Camera3D"
	) as Camera3D
	var region := level.get_node_or_null(
		"Segments/ChaseLeft/CameraRegion"
	) as CameraRegion
	assert_not_null(catalog)
	assert_not_null(player)
	assert_not_null(hazard)
	assert_not_null(router)
	assert_not_null(controller)
	assert_not_null(rail)
	assert_not_null(camera)
	assert_not_null(region)
	if (
		catalog == null
		or player == null
		or hazard == null
		or router == null
		or controller == null
		or rail == null
		or camera == null
		or region == null
	):
		return
	assert_true(
		player.has_method("set_chase_auto_run_duration"),
		"the real player must expose the timed chase handoff"
	)
	if not player.has_method("set_chase_auto_run_duration"):
		return
	var regions: Array = []
	for candidate: Node in level.find_children(
		"*",
		"",
		true,
		false
	):
		if candidate is CameraRegion:
			regions.append(candidate)
	player.global_position = Vector3(
		region.global_position.x,
		player.global_position.y,
		region.global_position.z
	)
	controller.call(
		"configure",
		player,
		rail,
		camera,
		catalog.camera,
		regions,
		router
	)
	hazard.call(
		"start_at_progress",
		hazard.call(
			"progress_for_position",
			player.global_position
		)
	)
	controller.call(
		"_on_region_body_entered",
		player,
		region
	)
	for _settle_step: int in range(4):
		controller.call(
			"update_camera",
			catalog.camera.region_blend_s
		)
	var corridor_forward := (
		controller.call("corridor_forward") as Vector3
	).normalized()
	player.velocity = Vector3.ZERO
	player.call(
		"advance_logic",
		2.0,
		true,
		catalog.chase.opening_auto_run_duration_s,
		corridor_forward
	)
	assert_almost_eq(
		player.velocity.dot(corridor_forward),
		catalog.move.run_speed_mps,
		CHASE_GAP_TOLERANCE_M,
		"the real chase trigger must auto-run for the opening window"
	)
	assert_true(
		bool(router.get("_screen_relative_tracking_enabled")),
		"the chase must still keep screen-relative control tracking active"
	)

	router.push_move(
		Vector2.ZERO,
		2.1,
		InputIntent.SOURCE_TOUCH
	)
	player.velocity = Vector3.ZERO
	player.call(
		"advance_logic",
		2.1,
		true,
		0.0,
		corridor_forward
	)
	assert_eq(
		player.velocity,
		Vector3.ZERO,
		"the player must regain fully manual movement after three seconds"
	)

	router.push_move(
		Vector2.RIGHT,
		2.2,
		InputIntent.SOURCE_TOUCH
	)
	player.velocity = Vector3.ZERO
	player.call(
		"advance_logic",
		2.2,
		true,
		1.0,
		corridor_forward
	)
	var screen_origin := camera.unproject_position(
		player.global_position
	)
	var screen_motion := camera.unproject_position(
		player.global_position + player.velocity
	) - screen_origin

	assert_gt(
		screen_motion.x,
		0.0,
		"a screen-right gesture must still move right after "
		+ "the chase camera reverses"
	)
	hazard.call(
		"start_at_progress",
		hazard.call(
			"progress_for_position",
			player.global_position
		)
	)
	hazard.call("stop")
	assert_false(
		bool(router.get("_screen_relative_tracking_enabled")),
		"the stop trigger must restore gesture-stable camera mapping"
	)
	router.push_move(
		Vector2.ZERO,
		2.3,
		InputIntent.SOURCE_TOUCH
	)
	player.velocity = Vector3.ZERO
	player.call(
		"advance_logic",
		2.3,
		true,
		0.0,
		corridor_forward
	)
	assert_eq(
		player.velocity,
		Vector3.ZERO,
		"stopping the chase must cancel any remaining auto-run"
	)


func test_boulders_checkpoints_are_collectible_pass_through_crates() -> void:
	var level := _instantiate_boulders()
	if level == null:
		return
	add_child_autofree(level)
	await wait_process_frames(1)
	var checkpoints: Array[Node] = []
	var collectible_ids: Array[int] = []

	for crate: Node in _crates(level):
		var crate_type := StringName(crate.get("crate_type"))
		if crate_type != &"time" and crate_type != &"iron":
			collectible_ids.append(int(crate.get("crate_id")))
		if crate_type == &"checkpoint":
			checkpoints.append(crate)

	assert_eq(
		collectible_ids.size(),
		_boulders_authored_crate_count()
	)
	assert_eq(
		checkpoints.size(),
		BOULDERS_EXPECTED_CHECKPOINTS
	)
	for checkpoint: Node in checkpoints:
		assert_true(
			bool(checkpoint.get("break_on_touch")),
			"chase-line checkpoints must opt into pass-through"
		)


func test_boulders_checkpoint_breaks_during_real_pass_through() -> void:
	var level := await _configured_boulders()
	if level == null:
		return
	var checkpoint := _boulders_checkpoint(level, 0)
	assert_not_null(checkpoint)
	if checkpoint == null:
		return

	var result: Dictionary = checkpoint.call(
		"apply_verb",
		&"touch",
		1.0
	)

	assert_true(
		bool(result.get("breaks", false)),
		"touching the chase-line checkpoint must break it"
	)
	assert_true(checkpoint.call("is_broken"))
	assert_eq(
		level.run_state.checkpoint_id,
		int(checkpoint.get("crate_id")),
		"pass-through must establish the respawn checkpoint"
	)


func test_boulders_death_mid_chase_restarts_behind_checkpoint() -> void:
	var level := await _configured_boulders()
	if level == null:
		return
	var checkpoint := _boulders_checkpoint(level, 1)
	var player := level.get_node_or_null("Player") as Node3D
	var hazard := level.get_node_or_null("ChaseHazard")
	var catalog := load(BASE_CATALOG_PATH) as GameplayTuning
	assert_not_null(checkpoint)
	assert_not_null(player)
	assert_not_null(hazard)
	assert_not_null(catalog)
	if (
		checkpoint == null
		or player == null
		or hazard == null
		or catalog == null
	):
		return
	checkpoint.call("apply_verb", &"touch", 1.0)
	var respawn_transform: Transform3D = player.get(
		"_spawn_transform"
	)
	player.global_transform = respawn_transform
	player.reset_physics_interpolation()
	var checkpoint_progress_m := float(hazard.call(
		"progress_for_position",
		respawn_transform.origin
	))
	hazard.call(
		"start_at_progress",
		checkpoint_progress_m
	)
	var catch_delta_s := (
		catalog.chase.boulder_start_gap_m
		- catalog.chase.boulder_kill_distance_m
		+ CHASE_GAP_TOLERANCE_M
	) / catalog.chase.boulder_speed_mps
	level.call(
		"_physics_process",
		catch_delta_s
	)
	var advanced_progress_m := float(
		hazard.call("boulder_progress_m")
	)
	assert_true(
		player.call("is_respawning"),
		"the real boulder catch must request a player death"
	)

	player.call("respawn")

	assert_true(
		hazard.call("is_active"),
		"a mid-chase checkpoint respawn must restart the chase"
	)
	assert_lt(
		float(hazard.call("boulder_progress_m")),
		advanced_progress_m,
		"death must rewind the advanced boulder"
	)
	assert_almost_eq(
		float(hazard.call(
			"gap_to_position_m",
			respawn_transform.origin
		)),
		catalog.chase.boulder_start_gap_m,
		CHASE_GAP_TOLERANCE_M,
		"the restarted boulder must sit the tuned gap behind spawn"
	)


func test_boulders_obstacles_author_binary_reads_and_early_previews() -> void:
	var level := _instantiate_boulders()
	if level == null:
		return
	add_child_autofree(level)
	await wait_process_frames(1)
	var obstacles: Array[Node] = []
	for candidate: Node in level.get_tree().get_nodes_in_group(
		&"chase_obstacle"
	):
		if level.is_ancestor_of(candidate):
			obstacles.append(candidate)
	assert_gt(
		obstacles.size(),
		0,
		"the chase needs authored obstacle reads"
	)

	for obstacle: Node in obstacles:
		var lane := StringName(
			obstacle.get_meta(&"blocked_lane", &"")
		)
		var geometry := obstacle.get_node_or_null(
			"Geometry"
		) as Node3D
		var shadow := obstacle.get_node_or_null(
			"BlobShadowPreview"
		) as Node3D
		var edge := obstacle.get_node_or_null(
			"GroundEdgePreview"
		) as Node3D
		assert_true(
			lane in [&"left", &"right"],
			"%s must encode a binary lane read" % obstacle.name
		)
		assert_not_null(geometry)
		assert_not_null(shadow)
		assert_not_null(edge)
		if geometry == null or shadow == null or edge == null:
			continue
		assert_gt(
			shadow.global_position.z,
			geometry.global_position.z,
			"the blob shadow must enter before obstacle geometry"
		)
		assert_gt(
			edge.global_position.z,
			geometry.global_position.z,
			"the ground-edge highlight must preview the obstacle"
		)


func test_hog_wild_has_the_eight_segment_graybox_contract() -> void:
	var level := _instantiate_hog_wild()
	if level == null:
		return
	add_child_autofree(level)
	await wait_process_frames(1)

	var meta := level.get_meta(&"level_meta") as LevelMeta
	var mount := level.get_node_or_null("HogRide")
	var graybox_label := level.get_node_or_null(
		"HogRide/HogVisual/GrayboxNotice"
	) as Label3D
	assert_not_null(meta)
	assert_true(level is LevelSession)
	assert_not_null(level.get_node_or_null("Player"))
	assert_not_null(level.get_node_or_null("CameraRig"))
	assert_not_null(level.get_node_or_null("Input/InputRouter"))
	assert_not_null(level.get_node_or_null("UI/TouchControls"))
	assert_not_null(level.get_node_or_null("Finish"))
	assert_not_null(mount, "Hog Wild needs the real runtime mount")
	assert_not_null(graybox_label)
	if meta != null:
		assert_eq(meta.level_id, &"wr1_hog_wild")
		assert_eq(meta.crate_count, _hog_wild_authored_crate_count())
	if graybox_label != null:
		assert_eq(
			graybox_label.text,
			"HOG — GRAYBOX CAPSULE",
			"the placeholder must identify itself honestly"
		)

	for segment_name: StringName in HOG_WILD_SEGMENT_NAMES:
		assert_not_null(
			level.get_node_or_null(
				"Segments/%s" % segment_name
			),
			"%s must be instanced into the Hog Wild route"
			% segment_name
		)


func test_hog_wild_spine_marker_names_match_authored_landmarks() -> void:
	var level := _instantiate_hog_wild()
	if level == null:
		return
	add_child_autofree(level)
	await wait_process_frames(1)

	var intro := level.get_node_or_null(
		"Segments/HogMountStart"
	)
	var finish := level.get_node_or_null(
		"Segments/HogDismountFinish"
	)
	assert_not_null(intro)
	assert_not_null(finish)
	if intro == null or finish == null:
		return
	var title_line := intro.get_node_or_null(
		"Spine/TitleLine"
	) as Marker3D
	var midpoint := intro.get_node_or_null(
		"Spine/Midpoint"
	) as Marker3D
	var finish_arch := finish.get_node_or_null(
		"Spine/FinishArch"
	) as Marker3D
	assert_not_null(title_line)
	assert_not_null(midpoint)
	assert_not_null(finish_arch)
	assert_null(intro.get_node_or_null("Spine/MountLine"))
	assert_null(intro.get_node_or_null("Spine/FirstRead"))
	assert_null(finish.get_node_or_null("Spine/DismountLine"))
	if (
		title_line == null
		or midpoint == null
		or finish_arch == null
	):
		return
	assert_eq(title_line.position, Vector3(0.0, 0.0, -8.0))
	assert_eq(midpoint.position, Vector3(0.0, 0.0, -62.0))
	assert_eq(finish_arch.position, Vector3(0.0, 0.0, -112.0))


func test_hog_wild_handoffs_overlap_on_all_three_axes() -> void:
	var level := _instantiate_hog_wild()
	if level == null:
		return
	add_child_autofree(level)
	await wait_process_frames(1)

	var verified_handoffs := 0
	for index: int in range(
		HOG_WILD_SEGMENT_NAMES.size() - 1
	):
		var current := _hog_wild_segment(level, index)
		var next := _hog_wild_segment(level, index + 1)
		if current == null or next == null:
			continue
		var exit_surface := (
			current.get_node_or_null("ExitSurface") as Node3D
		)
		var entry_surface := (
			next.get_node_or_null("EntrySurface") as Node3D
		)
		var exit_marker := (
			current.get_node_or_null("Spine/Exit") as Marker3D
		)
		var entry_marker := (
			next.get_node_or_null("Spine/Entry") as Marker3D
		)
		assert_not_null(exit_surface)
		assert_not_null(entry_surface)
		assert_not_null(exit_marker)
		assert_not_null(entry_marker)
		if (
			exit_surface == null
			or entry_surface == null
			or exit_marker == null
			or entry_marker == null
		):
			continue
		assert_true(
			exit_marker.global_position.is_equal_approx(
				entry_marker.global_position
			),
			"%s → %s spine markers must meet exactly"
			% [current.name, next.name]
		)
		assert_true(
			_full_aabbs_overlap(exit_surface, entry_surface),
			"%s → %s must overlap in X, Y, and Z"
			% [current.name, next.name]
		)
		verified_handoffs += 1
	assert_eq(
		verified_handoffs,
		HOG_WILD_SEGMENT_NAMES.size() - 1,
		"every adjacent Hog Wild segment pair must be verified"
	)


func test_hog_wild_mounted_hog_visual_rests_on_player_floor() -> void:
	var level := await _configured_hog_wild()
	if level == null:
		return
	var mount := level.get_node_or_null("HogRide")
	var player := level.get_node_or_null(
		"Player"
	) as CharacterBody3D
	var hog_visual := player.get_node_or_null(
		"HogVisual"
	) as Node3D
	var capsule := hog_visual.get_node_or_null(
		"Capsule"
	) as MeshInstance3D
	assert_not_null(mount)
	assert_not_null(player)
	assert_not_null(hog_visual)
	assert_not_null(capsule)
	if (
		mount == null
		or player == null
		or hog_visual == null
		or capsule == null
	):
		return
	assert_true(mount.call("is_mounted"))
	assert_eq(hog_visual.get_parent(), player)
	var world_bounds := capsule.global_transform * capsule.get_aabb()
	assert_almost_eq(
		world_bounds.position.y,
		player.global_position.y,
		CHASE_GAP_TOLERANCE_M,
		"the mounted Hog capsule must rest on the player's floor plane"
	)


func test_hog_wild_mounted_player_visual_rests_on_hog_back() -> void:
	var level := await _configured_hog_wild()
	if level == null:
		return
	var mount := level.get_node_or_null("HogRide")
	var player := level.get_node_or_null(
		"Player"
	) as CharacterBody3D
	var player_body := player.get_node_or_null(
		"Visual/SpinPivot/Body"
	) as MeshInstance3D
	var hog_capsule := player.get_node_or_null(
		"HogVisual/Capsule"
	) as MeshInstance3D
	assert_not_null(mount)
	assert_not_null(player)
	assert_not_null(player_body)
	assert_not_null(hog_capsule)
	if (
		mount == null
		or player == null
		or player_body == null
		or hog_capsule == null
	):
		return
	assert_true(mount.call("is_mounted"))
	assert_true(player_body.is_visible_in_tree())
	var player_bounds := (
		player_body.global_transform * player_body.get_aabb()
	)
	var hog_bounds := (
		hog_capsule.global_transform * hog_capsule.get_aabb()
	)
	var hog_back_y := hog_bounds.position.y + hog_bounds.size.y
	assert_almost_eq(
		player_bounds.position.y,
		hog_back_y,
		CHASE_GAP_TOLERANCE_M,
		"the mounted player body must sit visibly above the Hog capsule"
	)


func test_hog_wild_mounts_forced_run_and_dismounts_at_finish() -> void:
	var level := await _configured_hog_wild()
	if level == null:
		return
	var catalog := load(BASE_CATALOG_PATH) as GameplayTuning
	var mount := level.get_node_or_null("HogRide")
	var player := level.get_node_or_null(
		"Player"
	) as CharacterBody3D
	var router := level.get_node_or_null(
		"Input/InputRouter"
	) as InputRouter
	var hog_visual := player.get_node_or_null(
		"HogVisual"
	) as Node3D
	var mount_trigger := level.get_node_or_null(
		"HogRide/MountTrigger"
	) as Area3D
	var dismount_trigger := level.get_node_or_null(
		"HogRide/DismountTrigger"
	) as Area3D
	var finish := level.get_node_or_null("Finish") as Area3D
	assert_not_null(catalog)
	assert_not_null(mount)
	assert_not_null(player)
	assert_not_null(router)
	assert_not_null(hog_visual)
	assert_not_null(mount_trigger)
	assert_not_null(dismount_trigger)
	assert_not_null(finish)
	if (
		catalog == null
		or mount == null
		or player == null
		or router == null
		or hog_visual == null
		or mount_trigger == null
		or dismount_trigger == null
		or finish == null
	):
		return
	var mount_shape := mount_trigger.get_node_or_null(
		"CollisionShape3D"
	) as CollisionShape3D
	var dismount_shape := dismount_trigger.get_node_or_null(
		"CollisionShape3D"
	) as CollisionShape3D
	assert_not_null(mount_shape)
	assert_not_null(dismount_shape)
	if mount_shape == null or dismount_shape == null:
		return
	var mount_box := mount_shape.shape as BoxShape3D
	var dismount_box := dismount_shape.shape as BoxShape3D
	assert_not_null(mount_box)
	assert_not_null(dismount_box)
	if mount_box == null or dismount_box == null:
		return
	assert_true(
		dismount_trigger.global_position.is_equal_approx(
			Vector3(
				finish.global_position.x,
				dismount_trigger.global_position.y,
				finish.global_position.z
			)
		),
		"dismount must coincide with finish so manual braking cannot stall the run"
	)

	player.set_physics_process(false)
	player.global_position = (
		mount_trigger.global_position
		+ Vector3(mount_box.size.x, 0.0, 0.0)
	)
	player.reset_physics_interpolation()
	await wait_physics_frames(2)
	assert_false(mount_trigger.overlaps_body(player))
	mount.call(
		"reset_for_player_position",
		dismount_trigger.global_position
	)
	assert_false(mount.call("is_mounted"))
	var mount_entries: Array[Node3D] = []
	mount_trigger.body_entered.connect(
		func(body: Node3D) -> void:
			if body == player:
				mount_entries.append(body)
	)
	player.global_position = mount_trigger.global_position
	player.reset_physics_interpolation()
	await wait_physics_frames(2)

	assert_true(mount_trigger.overlaps_body(player))
	assert_eq(mount_entries, [player])
	assert_true(mount.call("is_mounted"))
	assert_true(player.call("is_hog_mounted"))
	assert_eq(player.call("current_state"), &"ride")
	assert_eq(hog_visual.get_parent(), player)
	router.push_move(
		Vector2(0.5, 0.0),
		5.0,
		InputIntent.SOURCE_TOUCH
	)
	player.velocity = Vector3.ZERO
	player.call(
		"advance_logic",
		5.0,
		true,
		1.0 / 60.0,
		Vector3.FORWARD
	)
	assert_almost_eq(
		player.velocity.dot(Vector3.FORWARD),
		catalog.hog.ride_speed_mps,
		CHASE_GAP_TOLERANCE_M,
		"the real level must force the authored ride pace"
	)
	assert_almost_eq(
		player.velocity.x,
		catalog.hog.steer_lateral_speed_mps * 0.5,
		CHASE_GAP_TOLERANCE_M,
		"the real level must preserve analog lateral steering"
	)

	player.global_position = (
		dismount_trigger.global_position
		+ Vector3(dismount_box.size.x, 0.0, 0.0)
	)
	player.reset_physics_interpolation()
	await wait_physics_frames(2)
	assert_false(dismount_trigger.overlaps_body(player))
	var dismount_entries: Array[Node3D] = []
	dismount_trigger.body_entered.connect(
		func(body: Node3D) -> void:
			if body == player:
				dismount_entries.append(body)
	)
	player.global_position = dismount_trigger.global_position
	player.reset_physics_interpolation()
	await wait_physics_frames(2)

	assert_true(dismount_trigger.overlaps_body(player))
	assert_eq(dismount_entries, [player])
	assert_false(mount.call("is_mounted"))
	assert_false(player.call("is_hog_mounted"))
	assert_ne(player.call("current_state"), &"ride")
	assert_eq(hog_visual.get_parent(), mount)


func test_hog_wild_crate_lines_break_on_touch() -> void:
	var level := await _configured_hog_wild()
	if level == null:
		return
	var checkpoints := 0
	var collectible_count := 0

	for crate: Node in _crates(level):
		var crate_type := StringName(crate.get("crate_type"))
		if crate_type in [&"time", &"iron"]:
			continue
		collectible_count += 1
		if crate_type == &"checkpoint":
			checkpoints += 1
		assert_true(
			bool(crate.get("break_on_touch")),
			"%s is in the forced-run line and must pass through"
			% crate.name
		)
		var result: Dictionary = crate.call(
			"apply_verb",
			&"touch",
			1.0
		)
		assert_true(
			bool(result.get("breaks", false)),
			"%s must really break on mounted contact" % crate.name
		)

	assert_eq(
		collectible_count,
		_hog_wild_authored_crate_count()
	)
	assert_eq(checkpoints, HOG_WILD_EXPECTED_CHECKPOINTS)


func test_hog_wild_checkpoint_death_respawns_mounted() -> void:
	var level := await _configured_hog_wild()
	if level == null:
		return
	var checkpoint := _hog_wild_checkpoint(level, 1)
	var player := level.get_node_or_null(
		"Player"
	) as CharacterBody3D
	var mount := level.get_node_or_null("HogRide")
	assert_not_null(checkpoint)
	assert_not_null(player)
	assert_not_null(mount)
	if checkpoint == null or player == null or mount == null:
		return
	checkpoint.call("apply_verb", &"touch", 1.0)
	var expected_spawn: Transform3D = player.get(
		"_spawn_transform"
	)
	player.global_position += Vector3(4.0, 0.0, -20.0)

	player.call("respawn")

	assert_true(mount.call("is_mounted"))
	assert_true(player.call("is_hog_mounted"))
	assert_eq(player.call("current_state"), &"ride")
	assert_true(
		player.global_position.is_equal_approx(
			expected_spawn.origin
		),
		"checkpoint death must restore the mounted spawn"
	)


func test_hog_wild_uses_ride_pace_and_authors_required_jumps() -> void:
	var level := _instantiate_hog_wild()
	if level == null:
		return
	add_child_autofree(level)
	await wait_process_frames(1)
	var meta := level.get_meta(&"level_meta") as LevelMeta
	var catalog := load(BASE_CATALOG_PATH) as GameplayTuning
	var required_jumps := level.find_children(
		"RequiredJump*",
		"Node3D",
		true,
		false
	)
	assert_not_null(meta)
	assert_not_null(catalog)
	if meta != null and catalog != null:
		assert_eq(
			meta.design_pace_mps,
			catalog.hog.ride_speed_mps,
			"checkpoint lint pace must match the forced ride"
		)
	assert_gt(
		required_jumps.size(),
		0,
		"Hog Wild needs authored jump reads, not a flat corridor"
	)
	for required_jump: Node in required_jumps:
		assert_not_null(required_jump.get_node_or_null("Takeoff"))
		assert_not_null(required_jump.get_node_or_null("Landing"))


func _instantiate_level() -> Node:
	assert_true(
		ResourceLoader.exists(LEVEL_SCENE_PATH),
		"N. Sanity Beach must be authored before this test can pass"
	)
	if not ResourceLoader.exists(LEVEL_SCENE_PATH):
		return null
	var packed := load(LEVEL_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	return packed.instantiate() if packed != null else null


func _instantiate_boulders() -> Node:
	assert_true(
		ResourceLoader.exists(BOULDERS_LEVEL_SCENE_PATH),
		"Boulders must be authored before this test can pass"
	)
	if not ResourceLoader.exists(BOULDERS_LEVEL_SCENE_PATH):
		return null
	var packed := load(BOULDERS_LEVEL_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	return packed.instantiate() if packed != null else null


func _instantiate_hog_wild() -> Node:
	assert_true(
		ResourceLoader.exists(HOG_WILD_LEVEL_SCENE_PATH),
		"Hog Wild must be authored before this test can pass"
	)
	if not ResourceLoader.exists(HOG_WILD_LEVEL_SCENE_PATH):
		return null
	var packed := load(HOG_WILD_LEVEL_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	return packed.instantiate() if packed != null else null


func _configured_boulders() -> LevelSession:
	var level := _instantiate_boulders() as LevelSession
	if level == null:
		return null
	add_child_autofree(level)
	await wait_process_frames(1)
	var meta := load(BOULDERS_LEVEL_META_PATH) as LevelMeta
	var catalog := load(BASE_CATALOG_PATH) as GameplayTuning
	var player := level.get_node_or_null("Player")
	var router := level.get_node_or_null(
		"Input/InputRouter"
	)
	assert_not_null(meta)
	assert_not_null(catalog)
	assert_not_null(player)
	assert_not_null(router)
	if (
		meta == null
		or catalog == null
		or player == null
		or router == null
	):
		return null
	router.call("configure", catalog.input)
	player.call(
		"configure",
		catalog.move,
		catalog.input,
		catalog.depth,
		catalog.wall_run,
		catalog.grind,
		catalog.swing,
		router.get("buffer"),
		catalog.economy,
		true,
		catalog.hog
	)
	assert_true(level.configure(
		meta,
		LevelRunState.MODE_NORMAL,
		catalog.economy,
		player,
		catalog.move,
		catalog.input,
		catalog
	))
	return level


func _configured_hog_wild() -> LevelSession:
	var level := _instantiate_hog_wild() as LevelSession
	if level == null:
		return null
	add_child_autofree(level)
	await wait_process_frames(1)
	var meta := load(HOG_WILD_LEVEL_META_PATH) as LevelMeta
	var catalog := load(BASE_CATALOG_PATH) as GameplayTuning
	var player := level.get_node_or_null("Player")
	var router := level.get_node_or_null(
		"Input/InputRouter"
	)
	assert_not_null(meta)
	assert_not_null(catalog)
	assert_not_null(player)
	assert_not_null(router)
	if (
		meta == null
		or catalog == null
		or player == null
		or router == null
	):
		return null
	router.call("configure", catalog.input)
	player.call(
		"configure",
		catalog.move,
		catalog.input,
		catalog.depth,
		catalog.wall_run,
		catalog.grind,
		catalog.swing,
		router.get("buffer"),
		catalog.economy,
		true,
		catalog.hog
	)
	assert_true(level.configure(
		meta,
		LevelRunState.MODE_NORMAL,
		catalog.economy,
		player,
		catalog.move,
		catalog.input,
		catalog
	))
	return level


func _boulders_authored_crate_count() -> int:
	var meta := load(BOULDERS_LEVEL_META_PATH) as LevelMeta
	assert_not_null(
		meta,
		"Boulders LevelMeta must load before its crates are checked"
	)
	return meta.crate_count if meta != null else -1


func _hog_wild_authored_crate_count() -> int:
	var meta := load(HOG_WILD_LEVEL_META_PATH) as LevelMeta
	assert_not_null(
		meta,
		"Hog Wild LevelMeta must load before its crates are checked"
	)
	return meta.crate_count if meta != null else -1


func _boulders_segment(level: Node, index: int) -> Node3D:
	return level.get_node_or_null(
		"Segments/%s" % BOULDERS_SEGMENT_NAMES[index]
	) as Node3D


func _hog_wild_segment(level: Node, index: int) -> Node3D:
	return level.get_node_or_null(
		"Segments/%s" % HOG_WILD_SEGMENT_NAMES[index]
	) as Node3D


func _boulders_checkpoint(
	level: Node,
	index: int
) -> Node:
	var checkpoints: Array[Node] = []
	for crate: Node in _crates(level):
		if StringName(crate.get("crate_type")) == &"checkpoint":
			checkpoints.append(crate)
	checkpoints.sort_custom(
		func(first: Node, second: Node) -> bool:
			return (
				(first as Node3D).global_position.z
				> (second as Node3D).global_position.z
			)
	)
	if index < 0 or index >= checkpoints.size():
		return null
	return checkpoints[index]


func _hog_wild_checkpoint(
	level: Node,
	index: int
) -> Node:
	var checkpoints: Array[Node] = []
	for crate: Node in _crates(level):
		if StringName(crate.get("crate_type")) == &"checkpoint":
			checkpoints.append(crate)
	checkpoints.sort_custom(
		func(first: Node, second: Node) -> bool:
			return (
				(first as Node3D).global_position.z
				> (second as Node3D).global_position.z
			)
	)
	if index < 0 or index >= checkpoints.size():
		return null
	return checkpoints[index]


# H7: read the authored crate count from the real LevelMeta resource instead
# of re-declaring it as a literal here. A hardcoded copy can silently drift
# from the authoritative `.tres` file -- proved by mutation: bumping
# n_sanity_beach.tres's crate_count while leaving the scene's real crate
# count untouched left the old hardcoded-literal assertions green, entirely
# blind to the authoritative field having moved. Reading it here means any
# future crate-count change is picked up automatically, and a genuine
# mismatch between the authored count and the real scene's crates is what
# fails the test, not a forgotten manual edit to this file.
func _authored_crate_count() -> int:
	var meta := load(LEVEL_META_PATH) as LevelMeta
	assert_not_null(
		meta,
		"N. Sanity Beach's LevelMeta must load before its crate_count can be checked"
	)
	return meta.crate_count if meta != null else -1


func _segment(level: Node, index: int) -> Node3D:
	return level.get_node_or_null(
		"Segments/%s" % SEGMENT_NAMES[index]
	) as Node3D


func _crates(level: Node) -> Array[Node]:
	var result: Array[Node] = []
	for candidate: Node in level.find_children(
		"*",
		"StaticBody3D",
		true,
		false
	):
		if (
			candidate.has_method("apply_verb")
			and candidate.has_signal(&"broken")
		):
			result.append(candidate)
	return result


func _enemy_count_within(level: Node) -> int:
	return _enemies(level).size()


func _enemies(level: Node) -> Array[Node]:
	var result: Array[Node] = []
	for candidate: Node in level.get_tree().get_nodes_in_group(&"enemy"):
		if level.is_ancestor_of(candidate):
			result.append(candidate)
	return result


func _full_aabbs_overlap(
	first: Node3D,
	second: Node3D
) -> bool:
	var first_bounds := _box_world_bounds(first)
	var second_bounds := _box_world_bounds(second)
	return (
		minf(first_bounds.end.x, second_bounds.end.x)
		> maxf(first_bounds.position.x, second_bounds.position.x)
		and minf(first_bounds.end.y, second_bounds.end.y)
		> maxf(first_bounds.position.y, second_bounds.position.y)
		and minf(first_bounds.end.z, second_bounds.end.z)
		> maxf(first_bounds.position.z, second_bounds.position.z)
	)


func _box_world_bounds(body: Node3D) -> AABB:
	var collision := body.find_child(
		"CollisionShape3D",
		true,
		false
	) as CollisionShape3D
	if collision == null or not collision.shape is BoxShape3D:
		return AABB()
	var box := collision.shape as BoxShape3D
	return collision.global_transform * AABB(
		-box.size * 0.5,
		box.size
	)


const PAPU_LEVEL_SCENE_PATH := "res://scenes/levels/wr1_papu_papu.tscn"
const PAPU_LEVEL_META_PATH := (
	"res://data/tuning/levels/papu_papu.tres"
)


func _configured_papu_papu() -> LevelSession:
	assert_true(
		ResourceLoader.exists(PAPU_LEVEL_SCENE_PATH),
		"the Papu arena must be authored before this test can pass"
	)
	if not ResourceLoader.exists(PAPU_LEVEL_SCENE_PATH):
		return null
	var packed := load(PAPU_LEVEL_SCENE_PATH) as PackedScene
	var level := packed.instantiate() as LevelSession
	if level == null:
		return null
	add_child_autofree(level)
	await wait_process_frames(1)
	var meta := load(PAPU_LEVEL_META_PATH) as LevelMeta
	var catalog := load(BASE_CATALOG_PATH) as GameplayTuning
	var player := level.get_node_or_null("Player")
	var router := level.get_node_or_null("Input/InputRouter")
	assert_not_null(meta)
	assert_not_null(catalog)
	assert_not_null(player)
	assert_not_null(router)
	if meta == null or catalog == null or player == null or router == null:
		return null
	router.call("configure", catalog.input)
	player.call(
		"configure",
		catalog.move,
		catalog.input,
		catalog.depth,
		catalog.wall_run,
		catalog.grind,
		catalog.swing,
		router.get("buffer"),
		catalog.economy,
		true,
		catalog.hog
	)
	assert_true(level.configure(
		meta,
		LevelRunState.MODE_NORMAL,
		catalog.economy,
		player,
		catalog.move,
		catalog.input,
		catalog
	))
	return level


func test_papu_arena_advances_a_phase_per_real_strike_volume() -> void:
	# D5's lesson: drive the real Area3D with the real player body, never the
	# handler by hand, or a swapped NodePath or bad collision mask ships green.
	var level := await _configured_papu_papu()
	if level == null:
		return
	var arena := level.get_node_or_null("PapuArena")
	var player := level.get_node_or_null("Player") as CharacterBody3D
	assert_not_null(arena, "the level must carry the arena")
	assert_not_null(player)
	if arena == null or player == null:
		return
	assert_eq(arena.call("current_phase"), 1)
	assert_false(arena.call("is_defeated"))

	var strikes := level.find_children("Strike*", "Area3D", true, false)
	assert_eq(
		strikes.size(),
		3,
		"one strike volume per authored phase [spec §8.2]"
	)
	if strikes.size() != 3:
		return

	var reached: Array[int] = []
	for strike: Area3D in strikes:
		player.global_position = strike.global_position
		await wait_physics_frames(2)
		reached.append(int(arena.call("current_phase")))
		player.global_position = (
			strike.global_position + Vector3(0, 0, 40)
		)
		await wait_physics_frames(2)

	assert_eq(
		reached,
		([2, 3, 3] as Array[int]),
		"each strike must clear exactly one phase"
	)
	assert_true(
		arena.call("is_defeated"),
		"three cleared phases must end the fight"
	)


func test_papu_arena_death_restarts_the_phase_not_the_fight() -> void:
	var level := await _configured_papu_papu()
	if level == null:
		return
	var arena := level.get_node_or_null("PapuArena")
	var player := level.get_node_or_null("Player") as CharacterBody3D
	if arena == null or player == null:
		return
	var strikes := level.find_children("Strike*", "Area3D", true, false)
	if strikes.is_empty():
		return
	player.global_position = (strikes[0] as Area3D).global_position
	await wait_physics_frames(2)
	assert_eq(arena.call("current_phase"), 2, "precondition: phase 2")

	arena.call("on_player_death")

	assert_eq(
		arena.call("current_phase"),
		2,
		"death must not send the player back to phase 1 [spec §8.2]"
	)


func test_papu_shockwave_catches_a_grounded_player_but_not_a_jumped_one() -> void:
	# §4.14: the ripple is jumpable. Height is measured above the player's own
	# supporting surface, not world Y, because each phase floor sits 2 m higher
	# than the last -- standing safely on tier 3 is a world Y that would read as
	# airborne on tier 1.
	var level := await _configured_papu_papu()
	if level == null:
		return
	var arena := level.get_node_or_null("PapuArena")
	var player := level.get_node_or_null("Player") as CharacterBody3D
	if arena == null or player == null:
		return
	var catalog := load(BASE_CATALOG_PATH) as GameplayTuning
	var wave_height: float = catalog.boss_papu.shockwave_height_m

	# Grounded on the phase-one floor, in the ripple's path.
	player.global_position = Vector3(0, 0.05, -12)
	await wait_physics_frames(2)
	# Long enough for the first slam (slam_period_s) plus the ripple's travel
	# across the 12 m gap at shockwave_speed_mps.
	var grounded_caught := false
	for _index in range(600):
		if bool(arena.call("advance_runtime", 1.0 / 60.0).get(&"caught")):
			grounded_caught = true
			break
	assert_true(
		grounded_caught,
		"a grounded player must eventually be caught by a slam ripple"
	)

	# Same spot, but above the authored wave height.
	arena.call("reset_phase_hazards")
	player.global_position = Vector3(0, 0.05 + wave_height * 2.0, -12)
	await wait_physics_frames(2)
	var jumped_caught := false
	for _index in range(600):
		if bool(arena.call("advance_runtime", 1.0 / 60.0).get(&"caught")):
			jumped_caught = true
			break
	assert_false(
		jumped_caught,
		"a player above the authored wave height must pass over it"
	)


func test_papu_debris_cannot_kill_inside_its_telegraph() -> void:
	var level := await _configured_papu_papu()
	if level == null:
		return
	var arena := level.get_node_or_null("PapuArena")
	var player := level.get_node_or_null("Player") as CharacterBody3D
	if arena == null or player == null:
		return
	var catalog := load(BASE_CATALOG_PATH) as GameplayTuning
	var telegraph_s: float = catalog.boss_papu.debris_telegraph_s
	player.global_position = Vector3(0, 0.05, -12)
	await wait_physics_frames(2)

	assert_false(
		bool(arena.call("debris_is_lethal_now")),
		"debris must be harmless the instant it is telegraphed"
	)
	arena.call("advance_runtime", telegraph_s * 0.5)
	assert_false(
		bool(arena.call("debris_is_lethal_now")),
		"and still harmless halfway through its telegraph"
	)
	arena.call("advance_runtime", telegraph_s)
	assert_true(
		bool(arena.call("debris_is_lethal_now")),
		"and lethal once the telegraph has elapsed"
	)


func test_a_papu_ripple_actually_damages_the_player() -> void:
	# Computing "caught" is not the same as anybody dying of it. This drives
	# the real physics step LevelSession runs, so an arena that reports a catch
	# nobody consumes fails here rather than in a playtest.
	var level := await _configured_papu_papu()
	if level == null:
		return
	var player := level.get_node_or_null("Player") as CharacterBody3D
	var arena := level.get_node_or_null("PapuArena")
	if player == null or arena == null:
		return
	player.global_position = Vector3(0, 0.05, -12)
	await wait_physics_frames(2)
	var deaths_before: int = level.run_state.deaths_at_checkpoint
	assert_true(level.run_state.flawless, "precondition: nobody has died yet")

	# Real physics frames, so LevelSession's own _physics_process drives the
	# hazard loop and the player's death actually resolves. No private call.
	for _index in range(420):
		await wait_physics_frames(1)
		if not level.run_state.flawless:
			break

	assert_false(
		level.run_state.flawless,
		"a ripple that catches the player must actually kill them"
	)
	assert_gt(
		level.run_state.deaths_at_checkpoint,
		deaths_before,
		"and the death must be recorded against the phase checkpoint"
	)
