extends GutTest

# Final fix wave (HIGH-1, blocker): RaceSession.configure() places the kart
# on KartSpawn.global_transform (authored yaw -90 degrees on both tracks --
# "the south straight" -- see race_session.gd's own configure() and
# test_race_session.gd's "spawn tangent faces +X" comment), but
# KartMotor._yaw_degrees always initializes to 0.0 with no setter, and
# KartController._physics_process() unconditionally overwrites
# rotation.y from that motor yaw on the very first physics tick (see
# kart_controller.gd). Pre-fix, that snaps a freshly-placed kart to face
# world -Z regardless of what the authored spawn transform said -- straight
# across the road and into scenery -- so zero checkpoint gates ever
# validate from a real drive on either track. This is the "missing test
# class" the fix-wave brief calls for: it drives the REAL configure() path
# on both shipped race scenes (not a synthetic stand-in) and proves the
# kart actually makes forward progress and validates the start gate.
#
# It also folds in a previously-deferred proof: a real slide-boosted right
# turn, driven from the graybox track's own authored spawn orientation
# (not an arbitrary world axis), must carve a WORLD-SPACE tighter right
# curve than plain right steering alone -- the same "don't just check
# relative signs, pin the absolute world direction" discipline
# test_kart_controller.gd's own steering-polarity test already applies,
# now extended to the slide-vs-steer comparison and anchored to a real
# authored spawn instead of the kart scene's raw default orientation.
#
# All three tests must FAIL before the fix (KartController has no
# set_yaw_degrees(); rotation snaps to 0.0 every tick regardless of the
# spawn transform) and pass after it.

const RACE_TIME_TRIAL_SCENE_PATH := "res://scenes/racing/race_time_trial.tscn"
const RACE_SANITY_SHORES_SCENE_PATH := "res://scenes/racing/race_sanity_shores.tscn"
const CATALOG_PATH := "res://data/tuning/gameplay.tres"
const KART_TUNING_PATH := "res://data/tuning/racing/kart.tres"

var _catalog: GameplayTuning
var _kart_tuning: KartTuning


func before_all() -> void:
	_catalog = load(CATALOG_PATH)
	assert_not_null(_catalog, "gameplay.tres must load")
	_kart_tuning = load(KART_TUNING_PATH)
	assert_not_null(_kart_tuning, "kart.tres must load")


func test_time_trial_kart_makes_real_forward_progress_and_validates_the_start_gate() -> void:
	await _assert_real_drive_validates_start_gate(RACE_TIME_TRIAL_SCENE_PATH)


func test_sanity_shores_kart_makes_real_forward_progress_and_validates_the_start_gate() -> void:
	await _assert_real_drive_validates_start_gate(RACE_SANITY_SHORES_SCENE_PATH)


## Boots the REAL race scene via its real configure() path (not a stand-in),
## then lets it run with ZERO steer input -- RacingInputAdapter.apply_move()
## routes InputRouter's idle (Vector2.ZERO) buffered movement straight to
## kart.steer(0.0) every tick (see racing_input_adapter.gd), so simply never
## touching input already gives the exact "zero steer, real physics" drive
## the fix-wave brief calls for; nothing here needs to disable RaceSession's
## own _physics_process. Both KartSpawn markers sit exactly 10m before gate
## 0 along the spawn-facing axis on their own track (graybox: (-10,*,-20)
## to gate 0 at (0,*,-20); Sanity Shores: (290,*,300) to gate 0 at
## (300,*,300)), so a kart that is actually facing down that straight (the
## fix) reaches and validates gate 0 well inside the frame budget below; a
## kart snapped to face -Z instead (the bug) drives straight into the wall
## behind the spawn line and never does.
func _assert_real_drive_validates_start_gate(scene_path: String) -> void:
	assert_true(
		ResourceLoader.exists(scene_path),
		"%s must exist" % scene_path
	)
	if not ResourceLoader.exists(scene_path):
		return
	var packed := load(scene_path) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var race := packed.instantiate()
	add_child_autofree(race)
	race.call("configure", _catalog)

	var spine := race.get_node("Track/Spine") as TrackSpine
	assert_not_null(spine, "session must find the track's spine")
	if spine == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	assert_not_null(kart, "session must find the kart")
	if kart == null:
		return

	var start_position := kart.global_position
	var start_progress_m := spine.progress_for_position(start_position)

	# 4s at 60 physics ticks/s comfortably covers the ~10m spawn-to-gate-0
	# gap even accounting for the kart's own settle-onto-floor drop and its
	# accel_mps2 ramp-up to top_speed_mps (well under 1.5s on the authored
	# kart.tres) -- generous margin, not a tight race against the clock.
	await wait_physics_frames(240)

	var end_progress_m := spine.progress_for_position(kart.global_position)
	# KartSpawn sits right at the start/finish line -- exactly where
	# track_spine.gd's own class doc says the closed-loop polyline's seam
	# lives (offset ~0 and offset ~length_m() are the SAME physical spot).
	# A real forward drive from there is expected to cross that seam, so a
	# raw end > start comparison would wrongly read genuine forward travel
	# as having gone backward (confirmed empirically: the un-wrapped delta
	# here is negative on both tracks even though the kart plainly drove
	# forward). fposmod(...) against the loop's own length is the wrap-
	# aware reading the class doc recommends for exactly this situation.
	var wrapped_progress_delta_m := fposmod(
		end_progress_m - start_progress_m,
		spine.length_m()
	)
	assert_gt(
		wrapped_progress_delta_m,
		5.0,
		(
			"a kart facing the authored spawn direction must make real "
			+ "forward progress along the spine (seam-wrap-aware) with "
			+ "zero steer input -- got start=%s end=%s wrapped_delta=%s "
			+ "(a kart snapped to face -Z instead would stall against the "
			+ "wall behind the spawn line and never cross the seam at all)"
		) % [start_progress_m, end_progress_m, wrapped_progress_delta_m]
	)
	# A world-space displacement check as a second, seam-immune signal --
	# fposmod above trusts the spine to correctly represent "how far
	# around the loop", but this confirms the kart also physically moved a
	# real distance, independent of that projection entirely.
	assert_gt(
		kart.global_position.distance_to(start_position),
		5.0,
		"the kart must have physically moved a real distance from its spawn point"
	)
	assert_gte(
		int(race.call("progress_gates")),
		1,
		(
			"the kart must actually reach and validate the start/finish "
			+ "gate (index 0) under its own real drive -- zero gates "
			+ "validating is exactly the bug this test pins"
		)
	)


## FOLD IN (deferred world-space slide test). Two full race sessions on the
## SAME real graybox loop scene, offset far apart in world space (RaceSession
## extends Node3D, so shifting its own position shifts every child --
## Track, Kart, gates, walls -- with it, the same isolation
## test_kart_controller.gd's _spawn_kart_on_floor(origin) gets from a
## throwaway floor). Both karts are placed via the REAL configure() path, so
## both inherit the graybox track's authored spawn orientation (forward =
## world +X, "the south straight" -- see the class doc and
## test_race_session.gd's identical comment). Each race's own
## _physics_process is disabled so its zero-input routing can't fight the
## steer()/hop_pressed() calls driven directly against its kart below --
## the same reason test_finishing_mid_slide_ends_the_slide_with_no_further_
## rotation in test_race_session.gd disables it.
func test_right_slide_from_the_graybox_spawn_turns_tighter_than_plain_right_steering_in_world_space() -> void:
	var steer_only_race := _boot_isolated_race(Vector3.ZERO)
	var slide_race := _boot_isolated_race(Vector3(2000.0, 0.0, 0.0))
	if steer_only_race == null or slide_race == null:
		return
	var steer_only_kart := steer_only_race.get_node("Kart") as CharacterBody3D
	var slide_kart := slide_race.get_node("Kart") as CharacterBody3D

	await wait_physics_frames(10)
	assert_true(
		steer_only_kart.is_on_floor(),
		"fixture setup: the steer-only kart must be grounded before steering"
	)
	assert_true(
		slide_kart.is_on_floor(),
		"fixture setup: the slide kart must be grounded before sliding"
	)

	# The graybox spawn's authored forward is world +X (see class doc) --
	# both karts must actually start out facing it, or the rest of this
	# comparison proves nothing about the "from spawn on the graybox track"
	# scenario it is meant to cover.
	var steer_only_start_forward := -steer_only_kart.global_transform.basis.z
	var slide_start_forward := -slide_kart.global_transform.basis.z
	assert_gt(
		steer_only_start_forward.x,
		0.9,
		"fixture setup: the steer-only kart must start facing the authored spawn direction (+X)"
	)
	assert_gt(
		slide_start_forward.x,
		0.9,
		"fixture setup: the slide kart must start facing the authored spawn direction (+X)"
	)

	# Plain right steering: no slide at all.
	steer_only_kart.call("steer", 1.0)

	# A real right slide: steer past threshold, hop to start it, then hold
	# full deflection into the locked direction so the motor stacks full
	# steer authority on top of the slide's own yaw bonus (see kart_motor.gd
	# -- this is the same "steering into the locked slide direction" shape
	# test_kart_controller.gd's own counter-steer comparison test uses).
	slide_kart.call("steer", _kart_tuning.slide_min_steer)
	slide_kart.call("hop_pressed")
	await wait_physics_frames(1)
	assert_true(
		bool(slide_kart.call("is_sliding")),
		"fixture setup: the slide kart must really be sliding before the comparison"
	)
	slide_kart.call("steer", 1.0)

	await wait_physics_frames(30)

	assert_true(
		bool(slide_kart.call("is_sliding")),
		"the slide must still be active after ticking"
	)

	var steer_only_forward := -steer_only_kart.global_transform.basis.z
	var slide_forward := -slide_kart.global_transform.basis.z

	# World-space direction, not just relative sign: turning right from a
	# +X-facing start sweeps the facing vector toward +Z (see kart_motor.gd's
	# single sign-conversion comment for the underlying convention) -- both
	# karts must have actually turned that way, and the slide kart must have
	# turned FURTHER (a bigger sweep off the original +X heading over the
	# same real elapsed time at materially the same speed -- steer never
	# touches forward speed -- is exactly what "a tighter curve" means here).
	assert_gt(
		steer_only_forward.z,
		0.01,
		"plain right steering must turn the kart toward world +Z"
	)
	assert_gt(
		slide_forward.z,
		steer_only_forward.z,
		(
			"a real right slide (steer authority + slide_yaw_bonus_degrees_per_s "
			+ "stacked) must sweep further toward world +Z than plain right "
			+ "steering alone over the same real physics ticks -- i.e. carve a "
			+ "tighter right curve, not merely an equally-tight one"
		)
	)


func _boot_isolated_race(origin: Vector3) -> Node3D:
	assert_true(
		ResourceLoader.exists(RACE_TIME_TRIAL_SCENE_PATH),
		"race_time_trial.tscn must exist"
	)
	if not ResourceLoader.exists(RACE_TIME_TRIAL_SCENE_PATH):
		return null
	var packed := load(RACE_TIME_TRIAL_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return null
	var race := packed.instantiate() as Node3D
	assert_not_null(race)
	if race == null:
		return null
	race.position = origin
	add_child_autofree(race)
	race.call("configure", _catalog)
	race.set_physics_process(false)
	return race
