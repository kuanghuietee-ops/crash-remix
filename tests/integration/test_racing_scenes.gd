extends GutTest

# Task 7 (CTR racing mode, R1): scene-open smoke tests in the same pattern
# tests/integration/test_phase0_scenes.gd and test_level_scenes.gd already
# use for the platformer's own scenes -- prove the packed scenes load,
# instantiate, and boot without engine errors. Deeper behavior (lap/gate
# sequencing, wrong-way timing, timer freeze on finish) is
# tests/racing/test_race_session.gd's job; this file only proves the real
# scene files open cleanly.

const TRACK_SCENE_PATH := "res://scenes/racing/track_graybox_loop.tscn"
const RACE_SCENE_PATH := "res://scenes/racing/race_time_trial.tscn"
const CATALOG_PATH := "res://data/tuning/gameplay.tres"


func test_track_graybox_loop_scene_opens_with_spine_gates_and_spawn() -> void:
	assert_true(ResourceLoader.exists(TRACK_SCENE_PATH))
	if not ResourceLoader.exists(TRACK_SCENE_PATH):
		return
	var packed := load(TRACK_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var track := packed.instantiate()
	add_child_autofree(track)
	await wait_process_frames(1)

	assert_not_null(track.get_node_or_null("Spine"))
	assert_not_null(track.get_node_or_null("KartSpawn"))
	assert_not_null(track.get_node_or_null("StartLine"))
	var gates := track.get_node_or_null("Gates")
	assert_not_null(gates)
	if gates != null:
		assert_eq(gates.get_child_count(), 6)
	var spine := track.get_node_or_null("Spine") as Path3D
	assert_not_null(spine)
	if spine != null and spine.curve != null:
		assert_gt(
			spine.curve.point_count,
			6,
			"the closed spine must bake from all authored markers"
		)


func test_race_time_trial_scene_boots_end_to_end_without_engine_errors() -> void:
	assert_true(ResourceLoader.exists(RACE_SCENE_PATH))
	if not ResourceLoader.exists(RACE_SCENE_PATH):
		return
	var catalog: GameplayTuning = load(CATALOG_PATH)
	assert_not_null(catalog)
	var packed := load(RACE_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null or catalog == null:
		return
	var race := packed.instantiate()
	add_child_autofree(race)
	race.call("configure", catalog)
	await wait_physics_frames(4)

	var kart := race.get_node_or_null("Kart")
	var camera := race.get_node_or_null("CameraRig/Camera3D") as Camera3D
	assert_not_null(kart)
	assert_not_null(camera)
	if camera != null:
		assert_true(camera.current, "the kart camera must be the active viewport camera")
	assert_false(bool(race.call("is_finished")))
	assert_eq(int(race.call("gate_count")), 6)
