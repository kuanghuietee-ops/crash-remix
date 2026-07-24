extends GutTest

const LEVEL_SCENE_PATH := (
	"res://scenes/levels/wr1_n_sanity_beach.tscn"
)
const LEVEL_META_PATH := (
	"res://data/tuning/levels/n_sanity_beach.tres"
)
const SEGMENT_NAMES: Array[StringName] = [
	&"BeachLanding",
	&"FirstCrates",
	&"JungleCorridor",
	&"CrateCadence",
	&"TNTIntroduction",
	&"PlantGauntlet",
	&"Crescendo",
]
const EXPECTED_COLLECTIBLE_CRATES := 40
const EXPECTED_CHECKPOINTS := 2
const EXPECTED_IRON_CRATES := 3


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
		assert_eq(meta.crate_count, EXPECTED_COLLECTIBLE_CRATES)
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


func test_level_has_collectible_counts_optional_iron_and_no_enemies() -> void:
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
		EXPECTED_COLLECTIBLE_CRATES
	)
	assert_eq(checkpoint_count, EXPECTED_CHECKPOINTS)
	assert_eq(iron_count, EXPECTED_IRON_CRATES)
	var enemy_count := 0
	for candidate: Node in level.get_tree().get_nodes_in_group(
		&"enemy"
	):
		if level.is_ancestor_of(candidate):
			enemy_count += 1
	assert_eq(
		enemy_count,
		0,
		"Task 13 is intentionally enemy-free"
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
		if candidate.has_method("apply_verb"):
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
