extends GutTest

const AudioServiceType := preload("res://src/core/audio_service.gd")
const AUDIO_DIR := "res://assets/audio"


func _service() -> AudioServiceType:
	var service: AudioServiceType = add_child_autofree(
		AudioServiceType.new()
	)
	service.configure(AUDIO_DIR)
	return service


func test_every_named_slot_resolves_to_a_path_under_the_audio_directory() -> void:
	var service := _service()

	assert_gt(
		AudioServiceType.SLOT_NAMES.size(),
		0,
		"the service must name the slots the game actually asks for"
	)
	for slot: StringName in AudioServiceType.SLOT_NAMES:
		assert_string_starts_with(
			service.clip_path_for(slot),
			AUDIO_DIR,
			"every slot resolves under assets/audio"
		)


func test_an_absent_clip_is_silent_rather_than_an_error() -> void:
	# assets/audio holds only .gitkeep today: H10 has not happened, so every
	# slot is legitimately missing and none of it may read as a fault.
	var service := _service()

	for slot: StringName in AudioServiceType.SLOT_NAMES:
		assert_false(
			service.has_clip(slot),
			"no audio exists yet, so nothing may claim to"
		)
		assert_false(
			service.play(slot),
			"a missing slot plays nothing and says so"
		)


func test_missing_audio_is_reported_once_at_boot_not_once_per_play() -> void:
	# A silent game must not spew a line every time a crate pops.
	var service := _service()
	var report_at_boot := service.boot_report()
	assert_false(
		report_at_boot.is_empty(),
		"the operator is told once that the game is silent"
	)

	for _index in range(20):
		for slot: StringName in AudioServiceType.SLOT_NAMES:
			service.play(slot)

	assert_eq(
		service.boot_report(),
		report_at_boot,
		"playing missing slots must not add further reporting"
	)
	assert_eq(
		service.boot_report().split("\n").size(),
		1,
		"one line, not one per slot"
	)


func test_an_unknown_slot_is_refused_rather_than_guessed_at() -> void:
	var service := _service()

	assert_false(service.has_clip(&"not_a_real_slot"))
	assert_false(service.play(&"not_a_real_slot"))
	assert_eq(
		service.clip_path_for(&"not_a_real_slot"),
		"",
		"an unnamed slot has no path at all"
	)
