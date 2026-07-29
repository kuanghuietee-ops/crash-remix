extends GutTest

const TUNING_PATH := "res://data/tuning/gameplay.tres"

var _economy: EconomyTuning


func before_each() -> void:
	var catalog: GameplayTuning = load(TUNING_PATH)
	_economy = catalog.economy.duplicate() as EconomyTuning
	_economy.checkpoint_respawn_offset = Vector3(0.5, 0.0, -1.5)


# IMPORTANT-4: the player CharacterBody3D root must stay at identity
# rotation forever -- crash_animation_driver.gd writes the model's WORLD
# yaw into the visual's LOCAL rotation, which only produces the right
# facing when the root itself carries no rotation. A checkpoint crate in a
# turned level (N. Sanity Beach / Hog Wild's corners) is itself yawed, and
# _checkpoint_spawn_transform used to hand back the crate's full
# global_transform, basis included -- so respawning at a rotated
# checkpoint permanently skewed the player model's facing.
func test_checkpoint_spawn_transform_keeps_identity_basis_for_a_yawed_crate() -> void:
	var crate := Node3D.new()
	add_child_autofree(crate)
	crate.position = Vector3(10.0, 0.0, 20.0)
	crate.rotation_degrees.y = 90.0

	var session := LevelSession.new()
	add_child_autofree(session)
	session._economy = _economy

	var spawn_transform: Transform3D = session.call(
		"_checkpoint_spawn_transform",
		crate
	)

	assert_true(
		spawn_transform.basis.is_equal_approx(Basis.IDENTITY),
		(
			"the player body must always respawn at identity rotation, " +
			"even at a checkpoint crate yawed 90 degrees"
		)
	)
	var expected_origin := (
		crate.global_transform.origin
		+ crate.global_transform.basis * _economy.checkpoint_respawn_offset
	)
	assert_true(
		spawn_transform.origin.is_equal_approx(expected_origin),
		(
			"the spawn origin must still be basis-rotated by the " +
			"checkpoint's own yaw -- only the returned transform's " +
			"rotation is forced to identity"
		)
	)
	assert_false(
		expected_origin.is_equal_approx(
			crate.global_transform.origin + _economy.checkpoint_respawn_offset
		),
		(
			"this fixture must actually exercise a basis-rotated offset " +
			"or the origin assertion above proves nothing"
		)
	)


func test_checkpoint_spawn_transform_stays_identity_basis_with_no_economy() -> void:
	var crate := Node3D.new()
	add_child_autofree(crate)
	crate.position = Vector3(3.0, 0.0, -4.0)
	crate.rotation_degrees.y = 45.0

	var session := LevelSession.new()
	add_child_autofree(session)
	session._economy = null

	var spawn_transform: Transform3D = session.call(
		"_checkpoint_spawn_transform",
		crate
	)

	assert_true(spawn_transform.basis.is_equal_approx(Basis.IDENTITY))
	assert_true(
		spawn_transform.origin.is_equal_approx(crate.global_transform.origin)
	)
