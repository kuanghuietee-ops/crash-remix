extends GutTest

# Task 5 (CTR kart chase camera): KartCamera is a Node3D that positions a
# Camera3D child every tick from a kart's own facing basis (never its
# velocity -- see kart_camera.gd's class doc for why) plus RaceTuning/
# KartTuning. It has no Node deps on the real KartController beyond the
# duck-typed API surface (speed_mps(), is_sliding(), slide_direction()) it
# already exposes (see kart_controller.gd), so FakeKart below stands in for
# it the same way test_camera_archetypes.gd's FakeTraversalPlayer and
# test_hog_mount.gd's HogPlayerStub stand in for the real player.

const KART_CAMERA_SCRIPT_PATH := "res://src/racing/camera/kart_camera.gd"
const RACE_TUNING_PATH := "res://data/tuning/racing/race.tres"
const KART_TUNING_PATH := "res://data/tuning/racing/kart.tres"

var _race: RaceTuning
var _kart_tuning: KartTuning


class FakeKart:
	extends Node3D

	var sliding := false
	var speed := 0.0
	# Fix round 1 (review): KartCamera now reads this directly (matching
	# KartController's real slide_direction() proxy) instead of inferring a
	# sign from the fixture's own rotation between ticks.
	var slide_dir := 1

	func is_sliding() -> bool:
		return sliding

	func speed_mps() -> float:
		return speed

	func slide_direction() -> int:
		return slide_dir


func before_all() -> void:
	_race = load(RACE_TUNING_PATH)
	_kart_tuning = load(KART_TUNING_PATH)
	assert_not_null(_race, "race.tres must load — Task 1 registers it")
	assert_not_null(_kart_tuning, "kart.tres must load — Task 1 registers it")


# ---------------------------------------------------------------------------
# Position geometry: trail behind + height above, facing the kart.
# ---------------------------------------------------------------------------


func test_at_rest_camera_sits_trail_behind_and_height_above_the_kart() -> void:
	var rig := _new_rig()
	if rig == null:
		return
	var kart: FakeKart = rig["kart"]
	var kart_camera: Node3D = rig["kart_camera"]
	var camera: Camera3D = rig["camera"]

	kart.global_position = Vector3(3.0, 0.0, -7.0)
	# Identity rotation faces -Z (Godot's FORWARD), matching kart_motor.gd's
	# own Vector3.FORWARD.rotated(...) convention.
	kart.rotation = Vector3.ZERO

	kart_camera.call("configure", kart, camera, _race, _kart_tuning)

	var kart_forward := Vector3.FORWARD
	var expected_position := (
		kart.global_position
		- kart_forward * _race.camera_trail_m
		+ Vector3.UP * _race.camera_height_m
	)
	assert_true(
		camera.global_position.is_equal_approx(expected_position),
		"expected %s, got %s" % [expected_position, camera.global_position]
	)


func test_camera_tracks_a_new_kart_position_every_tick() -> void:
	var rig := _new_rig()
	if rig == null:
		return
	var kart: FakeKart = rig["kart"]
	var kart_camera: Node3D = rig["kart_camera"]
	var camera: Camera3D = rig["camera"]

	kart.global_position = Vector3.ZERO
	kart.rotation = Vector3.ZERO
	kart_camera.call("configure", kart, camera, _race, _kart_tuning)

	kart.global_position = Vector3(0.0, 0.0, -20.0)
	kart_camera.call("tick", 0.016)

	var expected_position := (
		kart.global_position
		- Vector3.FORWARD * _race.camera_trail_m
		+ Vector3.UP * _race.camera_height_m
	)
	assert_true(
		camera.global_position.is_equal_approx(expected_position),
		"the rig must follow the kart's new position, not stay parked"
	)


# ---------------------------------------------------------------------------
# FOV: base at rest, base+gain at top speed, above that while boosted.
# ---------------------------------------------------------------------------


func test_fov_is_base_at_zero_speed() -> void:
	var rig := _new_rig()
	if rig == null:
		return
	var kart: FakeKart = rig["kart"]
	var kart_camera: Node3D = rig["kart_camera"]
	var camera: Camera3D = rig["camera"]

	kart.speed = 0.0
	kart_camera.call("configure", kart, camera, _race, _kart_tuning)

	assert_almost_eq(camera.fov, _race.camera_fov_base, 0.001)


func test_fov_is_base_plus_gain_at_top_speed() -> void:
	var rig := _new_rig()
	if rig == null:
		return
	var kart: FakeKart = rig["kart"]
	var kart_camera: Node3D = rig["kart_camera"]
	var camera: Camera3D = rig["camera"]

	kart.speed = _kart_tuning.top_speed_mps
	kart_camera.call("configure", kart, camera, _race, _kart_tuning)

	assert_almost_eq(
		camera.fov,
		_race.camera_fov_base + _race.camera_fov_speed_gain,
		0.001
	)


func test_fov_exceeds_base_plus_gain_while_boosted_above_top_speed() -> void:
	var rig := _new_rig()
	if rig == null:
		return
	var kart: FakeKart = rig["kart"]
	var kart_camera: Node3D = rig["kart_camera"]
	var camera: Camera3D = rig["camera"]

	kart.speed = _kart_tuning.top_speed_mps + _kart_tuning.boost_speed_bonus_mps
	kart_camera.call("configure", kart, camera, _race, _kart_tuning)

	assert_gt(
		camera.fov,
		_race.camera_fov_base + _race.camera_fov_speed_gain,
		"a boosted kart must visibly widen the FOV past the top-speed value"
	)


## Low (review): a real boost only ever reaches a ratio of roughly 1.28
## (top_speed_mps + boost_speed_bonus_mps, per kart.tres), which would not
## by itself catch a clamp with a ceiling somewhere between 1 and that. A
## synthetic ratio of 2.0 -- far past anything the tuned kart can actually
## produce -- proves the fov formula itself carries no hidden clamp at all,
## not just that today's boost happens to stay under one.
func test_fov_matches_unclamped_formula_at_synthetic_double_top_speed() -> void:
	var rig := _new_rig()
	if rig == null:
		return
	var kart: FakeKart = rig["kart"]
	var kart_camera: Node3D = rig["kart_camera"]
	var camera: Camera3D = rig["camera"]

	kart.speed = _kart_tuning.top_speed_mps * 2.0
	kart_camera.call("configure", kart, camera, _race, _kart_tuning)

	assert_almost_eq(
		camera.fov,
		_race.camera_fov_base + _race.camera_fov_speed_gain * 2.0,
		0.001,
		"the fov formula must stay exactly unclamped even at a 2x speed ratio"
	)


# ---------------------------------------------------------------------------
# Yaw lag: exponential convergence toward the kart's facing.
# ---------------------------------------------------------------------------


func test_yaw_lag_converges_exponentially_two_ticks_halve_remaining_angle() -> void:
	var rig := _new_rig()
	if rig == null:
		return
	var kart: FakeKart = rig["kart"]
	var kart_camera: Node3D = rig["kart_camera"]
	var camera: Camera3D = rig["camera"]

	var race := _race.duplicate() as RaceTuning
	var tau_s := race.camera_yaw_lag_s
	kart.rotation = Vector3.ZERO
	kart_camera.call("configure", kart, camera, race, _kart_tuning)

	# A sudden 90-degree kart turn, as if it just rounded a hairpin.
	kart.rotation.y = PI / 2.0
	var target_forward: Vector3 = -kart.global_transform.basis.z
	var initial_forward: Vector3 = kart_camera.call("look_forward")
	var initial_angle := initial_forward.angle_to(target_forward)
	assert_gt(
		initial_angle,
		0.1,
		"fixture setup must actually diverge before convergence can be measured"
	)

	# 1 - exp(-delta/tau) = 0.5 exactly when delta = tau * ln(2) -- each tick
	# at this delta closes exactly half of whatever angle remains.
	var half_life_delta_s := tau_s * log(2.0)

	kart_camera.call("tick", half_life_delta_s)
	var angle_after_one: float = (
		(kart_camera.call("look_forward") as Vector3).angle_to(target_forward)
	)
	assert_almost_eq(
		angle_after_one,
		initial_angle * 0.5,
		0.01,
		"one half-life tick must leave half the original angle remaining"
	)

	kart_camera.call("tick", half_life_delta_s)
	var angle_after_two: float = (
		(kart_camera.call("look_forward") as Vector3).angle_to(target_forward)
	)
	assert_almost_eq(
		angle_after_two,
		initial_angle * 0.25,
		0.01,
		"two half-life ticks must leave a quarter of the original angle"
	)


func test_zero_or_negative_yaw_lag_snaps_instantly() -> void:
	var rig := _new_rig()
	if rig == null:
		return
	var kart: FakeKart = rig["kart"]
	var kart_camera: Node3D = rig["kart_camera"]
	var camera: Camera3D = rig["camera"]

	var race := _race.duplicate() as RaceTuning
	race.camera_yaw_lag_s = 0.0
	kart.rotation = Vector3.ZERO
	kart_camera.call("configure", kart, camera, race, _kart_tuning)

	kart.rotation.y = PI / 2.0
	var target_forward: Vector3 = -kart.global_transform.basis.z

	kart_camera.call("tick", 0.016)

	var look_forward: Vector3 = kart_camera.call("look_forward")
	assert_almost_eq(
		look_forward.angle_to(target_forward),
		0.0,
		0.001,
		"tau <= 0 must snap to the target the same tick, no lag"
	)


# ---------------------------------------------------------------------------
# Drift yaw: signed offset into the slide direction.
# ---------------------------------------------------------------------------


func test_drift_yaw_offset_flips_sign_with_slide_direction() -> void:
	var positive_angle := _drift_offset_signed_angle(1)
	var negative_angle := _drift_offset_signed_angle(-1)

	assert_almost_eq(
		absf(positive_angle),
		deg_to_rad(_race.camera_drift_yaw_degrees),
		0.01,
		"a converged drift offset must reach the full tuned angle"
	)
	assert_almost_eq(
		absf(negative_angle),
		deg_to_rad(_race.camera_drift_yaw_degrees),
		0.01,
		"a converged drift offset must reach the full tuned angle"
	)
	assert_true(
		signf(positive_angle) != signf(negative_angle),
		"slide_direction() = 1 vs -1 must bias the look yaw to opposite sides"
	)


func test_no_drift_offset_while_not_sliding() -> void:
	var rig := _new_rig()
	if rig == null:
		return
	var kart: FakeKart = rig["kart"]
	var kart_camera: Node3D = rig["kart_camera"]
	var camera: Camera3D = rig["camera"]

	var race := _race.duplicate() as RaceTuning
	race.camera_yaw_lag_s = 0.0
	kart.sliding = false
	kart.rotation = Vector3.ZERO
	kart_camera.call("configure", kart, camera, race, _kart_tuning)

	kart.rotation.y = 0.3
	kart_camera.call("tick", 0.016)

	var kart_forward: Vector3 = -kart.global_transform.basis.z
	var look_forward: Vector3 = kart_camera.call("look_forward")
	assert_almost_eq(
		look_forward.angle_to(kart_forward),
		0.0,
		0.001,
		"with no slide, the eased yaw must track the kart's own facing exactly"
	)


## Builds a sliding kart reporting the given slide_direction() (1 or -1),
## using an instant (tau<=0) rig so configure() alone fully converges --
## isolating the sign question from the separately-tested lag convergence.
## The kart's own facing never turns here (identity rotation throughout):
## fix round 1 replaced the earlier "infer the sign from a simulated turn"
## approach with a direct slide_direction() read, so this only needs to
## prove KartCamera relays whatever sign it's told, not reproduce a turn.
## Returns the SIGNED angle from the kart's facing to the camera's
## resulting look_forward(), measured around world UP, so slide_direction()
## = 1 vs -1 must produce opposite signs.
func _drift_offset_signed_angle(slide_dir: int) -> float:
	var rig := _new_rig()
	var kart: FakeKart = rig["kart"]
	var kart_camera: Node3D = rig["kart_camera"]
	var camera: Camera3D = rig["camera"]

	var race := _race.duplicate() as RaceTuning
	race.camera_yaw_lag_s = 0.0
	kart.sliding = true
	kart.slide_dir = slide_dir
	kart.rotation = Vector3.ZERO
	kart_camera.call("configure", kart, camera, race, _kart_tuning)

	var kart_forward: Vector3 = -kart.global_transform.basis.z
	var look_forward: Vector3 = kart_camera.call("look_forward")
	var unsigned_angle := kart_forward.angle_to(look_forward)
	var cross_y := kart_forward.cross(look_forward).y
	return unsigned_angle if cross_y >= 0.0 else -unsigned_angle


## Common rig: a FakeKart and a KartCamera (with its Camera3D child) both
## parented under an autofreed root already in the tree, matching the
## "parent before assigning global_position" lesson from
## test_camera_rail_controller.gd (an unparented Node3D logs a spurious
## is_inside_tree engine error even when the position still lands right).
func _new_rig() -> Dictionary:
	var script: Script = load(KART_CAMERA_SCRIPT_PATH)
	assert_not_null(script, "KartCamera implementation must exist")
	if script == null:
		return {}

	var root := Node3D.new()
	add_child_autofree(root)

	var kart := FakeKart.new()
	root.add_child(kart)

	var kart_camera := Node3D.new()
	kart_camera.set_script(script)
	root.add_child(kart_camera)

	var camera := Camera3D.new()
	kart_camera.add_child(camera)

	return {
		"kart": kart,
		"kart_camera": kart_camera,
		"camera": camera,
	}
