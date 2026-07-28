extends GutTest

const DRIVER_PATH := "res://src/visual/player/crash_animation_driver.gd"
const IDLE := &"A_crash_idle"
const RUN := &"A_crash_run"
const CROUCH := &"A_crash_crouch"
const JUMP := &"A_crash_jump"
const DOUBLE_JUMP := &"A_crash_double_jump"
const SPIN := &"A_crash_spin"
const SLIDE := &"A_crash_slide"
const SLAM := &"A_crash_slam"


func test_clip_selection_covers_the_seven_core_gameplay_actions() -> void:
	assert_true(
		ResourceLoader.exists(DRIVER_PATH),
		"the player scene needs a visual-only Crash animation driver"
	)
	if not ResourceLoader.exists(DRIVER_PATH):
		return
	var driver_script := load(DRIVER_PATH) as Script
	assert_not_null(driver_script)
	if driver_script == null:
		return

	assert_eq(
		driver_script.call("clip_for", &"grounded", false, JUMP, false),
		IDLE
	)
	assert_eq(
		driver_script.call("clip_for", &"grounded", false, JUMP, true),
		RUN
	)
	assert_eq(
		driver_script.call("clip_for", &"crouched", false, JUMP, false),
		CROUCH,
		"pressing down while still needs an authored crouch instead of squash"
	)
	assert_eq(
		driver_script.call("clip_for", &"airborne", false, JUMP, true),
		JUMP
	)
	assert_eq(
		driver_script.call(
			"clip_for",
			&"airborne",
			false,
			DOUBLE_JUMP,
			true
		),
		DOUBLE_JUMP
	)
	assert_eq(
		driver_script.call("clip_for", &"sliding", false, JUMP, true),
		SLIDE
	)
	assert_eq(
		driver_script.call("clip_for", &"body_slam", false, JUMP, true),
		SLAM
	)
	assert_eq(
		driver_script.call("clip_for", &"slam_recovery", false, JUMP, false),
		SLAM,
		"the impact pose must hold through the authored stomp recovery"
	)
	assert_eq(
		driver_script.call("clip_for", &"grounded", true, JUMP, true),
		SPIN
	)


func test_impulse_selection_distinguishes_jump_double_jump_and_slam() -> void:
	if not ResourceLoader.exists(DRIVER_PATH):
		return
	var driver_script := load(DRIVER_PATH) as Script
	assert_not_null(driver_script)
	if driver_script == null:
		return

	assert_eq(driver_script.call("clip_for_impulse", &"jump"), JUMP)
	assert_eq(
		driver_script.call("clip_for_impulse", &"double_jump"),
		DOUBLE_JUMP
	)
	assert_eq(driver_script.call("clip_for_impulse", &"body_slam"), SLAM)


func test_travel_yaw_faces_the_model_in_every_horizontal_direction() -> void:
	if not ResourceLoader.exists(DRIVER_PATH):
		return
	var driver_script := load(DRIVER_PATH) as Script
	assert_not_null(driver_script)
	if driver_script == null:
		return
	assert_true(
		driver_script.has_method("yaw_for_velocity"),
		"the visual driver must turn Crash instead of reverse-walking"
	)
	if not driver_script.has_method("yaw_for_velocity"):
		return

	assert_almost_eq(
		driver_script.call(
			"yaw_for_velocity",
			Vector3.FORWARD,
			0.0
		),
		PI,
		0.0001
	)
	assert_almost_eq(
		driver_script.call(
			"yaw_for_velocity",
			Vector3.BACK,
			PI
		),
		0.0,
		0.0001
	)
	assert_almost_eq(
		driver_script.call(
			"yaw_for_velocity",
			Vector3.RIGHT,
			PI
		),
		PI * 0.5,
		0.0001
	)
	assert_almost_eq(
		driver_script.call(
			"yaw_for_velocity",
			Vector3.ZERO,
			1.25
		),
		1.25,
		0.0001,
		"stopping must preserve the last readable facing"
	)
