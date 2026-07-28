extends GutTest

const DRIVER_PATH := "res://src/visual/player/crash_animation_driver.gd"
const IDLE := &"A_crash_idle"
const BORED_IDLE := &"A_crash_bored_idle"
const RUN := &"A_crash_run"
const CROUCH := &"A_crash_crouch"
const CRAWL := &"A_crash_crawl"
const JUMP := &"A_crash_jump"
const DOUBLE_JUMP := &"A_crash_double_jump"
const SPIN := &"A_crash_spin"
const SLIDE := &"A_crash_slide"
const SLAM := &"A_crash_slam"
const HIT := &"A_crash_hit"
const DEATH := &"A_crash_death_knockout"
const WIN := &"A_crash_win"
const WALL_RUN := &"A_crash_wall_run"
const GRIND := &"A_crash_grind"
const SWING := &"A_crash_swing"


func test_clip_selection_covers_gameplay_and_personality_actions() -> void:
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
		driver_script.call("clip_for", &"grounded", false, JUMP, false, false),
		IDLE
	)
	assert_eq(
		driver_script.call("clip_for", &"grounded", false, JUMP, false, true),
		BORED_IDLE,
		"standing still long enough should reveal Crash's personality"
	)
	assert_eq(
		driver_script.call("clip_for", &"grounded", false, JUMP, true, true),
		RUN
	)
	assert_eq(
		driver_script.call("clip_for", &"crouched", false, JUMP, false, false),
		CROUCH,
		"pressing down while still needs an authored crouch instead of squash"
	)
	assert_eq(
		driver_script.call("clip_for", &"crouched", false, JUMP, true, false),
		CRAWL,
		"moving while low needs a readable crawl cycle"
	)
	assert_eq(
		driver_script.call("clip_for", &"airborne", false, JUMP, true, false),
		JUMP
	)
	assert_eq(
		driver_script.call(
			"clip_for",
			&"airborne",
			false,
			DOUBLE_JUMP,
			true,
			false
		),
		DOUBLE_JUMP
	)
	assert_eq(
		driver_script.call("clip_for", &"sliding", false, JUMP, true, false),
		SLIDE
	)
	assert_eq(
		driver_script.call("clip_for", &"body_slam", false, JUMP, true, false),
		SLAM
	)
	assert_eq(
		driver_script.call(
			"clip_for",
			&"slam_recovery",
			false,
			JUMP,
			false,
			false
		),
		SLAM,
		"the impact pose must hold through the authored stomp recovery"
	)
	assert_eq(
		driver_script.call("clip_for", &"grounded", true, JUMP, true, true),
		SPIN
	)
	assert_eq(
		driver_script.call("clip_for", &"wall_run", false, JUMP, true, false),
		WALL_RUN
	)
	assert_eq(
		driver_script.call("clip_for", &"grind", false, JUMP, true, false),
		GRIND
	)
	assert_eq(
		driver_script.call("clip_for", &"swing", false, JUMP, true, false),
		SWING
	)
	assert_eq(
		driver_script.call("clip_for", &"ride", false, JUMP, true, false),
		RUN,
		"ride keeps the grounded locomotion cycle until its own art pass"
	)


func test_bored_idle_clock_only_advances_while_grounded_and_still() -> void:
	var driver_script := load(DRIVER_PATH) as Script
	assert_not_null(driver_script)
	if driver_script == null:
		return

	assert_almost_eq(
		driver_script.call(
			"idle_elapsed_after",
			1.25,
			0.5,
			&"grounded",
			false,
			false
		),
		1.75,
		0.0001
	)
	for reset_case: Array in [
		[&"grounded", false, true],
		[&"grounded", true, false],
		[&"crouched", false, false],
		[&"airborne", false, false],
	]:
		assert_eq(
			driver_script.call(
				"idle_elapsed_after",
				4.0,
				0.25,
				reset_case[0],
				reset_case[1],
				reset_case[2]
			),
			0.0,
			"movement and actions must reset the bored-idle delay"
		)


func test_damage_reactions_override_locomotion_and_death_wins() -> void:
	var driver_script := load(DRIVER_PATH) as Script
	assert_not_null(driver_script)
	if driver_script == null:
		return
	assert_eq(
		driver_script.call("reaction_clip_for", false, false),
		&""
	)
	assert_eq(
		driver_script.call("reaction_clip_for", false, true),
		HIT
	)
	assert_eq(
		driver_script.call("reaction_clip_for", true, true),
		DEATH,
		"fatal damage must interrupt an active mask-hit recoil"
	)


func test_victory_overrides_actions_but_not_a_fatal_respawn() -> void:
	var driver_script := load(DRIVER_PATH) as Script
	assert_not_null(driver_script)
	if driver_script == null:
		return
	assert_eq(
		driver_script.call("override_clip_for", false, false, false),
		&""
	)
	assert_eq(
		driver_script.call("override_clip_for", true, false, true),
		WIN,
		"crossing the finish must replace locomotion and hit recoil"
	)
	assert_eq(
		driver_script.call("override_clip_for", true, true, true),
		DEATH,
		"an already-fatal respawn remains safer than celebrating"
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
