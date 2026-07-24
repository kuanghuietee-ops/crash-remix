extends GutTest

const GAME_FLOW_PATH := "res://src/core/game_flow.gd"


func test_boot_reaches_warp_room_after_save_load() -> void:
	var flow := _new_flow()
	if flow == null:
		return

	assert_eq(flow.call("state_name"), &"boot")
	assert_eq(flow.call("dispatch", {"type": &"save_loaded"}), OK)
	assert_eq(flow.call("state_name"), &"warp_room")


func test_portal_entry_reaches_level_and_keeps_event_payload() -> void:
	var flow := _new_flow()
	if flow == null:
		return
	assert_eq(flow.call("dispatch", {"type": &"save_loaded"}), OK)

	assert_eq(
		flow.call(
			"dispatch",
			{
				"type": &"portal_enter",
				"level_id": &"wr1_n_sanity_beach",
			}
		),
		OK
	)

	assert_eq(flow.call("state_name"), &"level")
	assert_eq(flow.get("active_level_id"), &"wr1_n_sanity_beach")
	assert_eq(flow.get("active_level_mode"), &"normal")


func test_portal_and_results_retry_keep_the_requested_relic_mode() -> void:
	var flow := _new_flow()
	if flow == null:
		return
	assert_eq(flow.call("dispatch", {"type": &"save_loaded"}), OK)
	assert_eq(
		flow.call(
			"dispatch",
			{
				"type": &"portal_enter",
				"level_id": &"wr1_n_sanity_beach",
				"mode": &"relic",
			}
		),
		OK
	)
	assert_eq(flow.get("active_level_mode"), &"relic")
	assert_eq(flow.call("dispatch", {"type": &"level_complete"}), OK)
	assert_eq(flow.call("dispatch", {"type": &"retry_level"}), OK)
	assert_eq(flow.get("active_level_mode"), &"relic")


func test_unknown_portal_mode_is_rejected_without_leaving_hub() -> void:
	var flow := _new_flow()
	if flow == null:
		return
	assert_eq(flow.call("dispatch", {"type": &"save_loaded"}), OK)

	assert_eq(
		flow.call(
			"dispatch",
			{
				"type": &"portal_enter",
				"level_id": &"wr1_n_sanity_beach",
				"mode": &"unknown",
			}
		),
		ERR_INVALID_DATA
	)
	assert_eq(flow.call("state_name"), &"warp_room")
	assert_eq(flow.get("active_level_id"), &"")
	assert_eq(flow.get("active_level_mode"), &"normal")


func test_level_completion_reaches_results() -> void:
	var flow := _flow_in_level()
	if flow == null:
		return

	assert_eq(flow.call("dispatch", {"type": &"level_complete"}), OK)
	assert_eq(flow.call("state_name"), &"results")


func test_one_tap_results_retry_reenters_the_same_level() -> void:
	var flow := _flow_in_state(&"results")
	if flow == null:
		return

	assert_eq(flow.call("dispatch", {"type": &"retry_level"}), OK)
	assert_eq(flow.call("state_name"), &"level")
	assert_eq(flow.get("active_level_id"), &"wr1_n_sanity_beach")


func test_results_continue_returns_to_hub_and_clears_level() -> void:
	var flow := _flow_in_state(&"results")
	if flow == null:
		return

	assert_eq(
		flow.call("dispatch", {"type": &"results_to_hub"}),
		OK
	)
	assert_eq(flow.call("state_name"), &"warp_room")
	assert_eq(flow.get("active_level_id"), &"")
	assert_eq(flow.get("active_level_mode"), &"normal")


func test_quitting_level_returns_to_warp_room() -> void:
	var flow := _flow_in_level()
	if flow == null:
		return

	assert_eq(flow.call("dispatch", {"type": &"quit_level"}), OK)
	assert_eq(flow.call("state_name"), &"warp_room")
	assert_eq(flow.get("active_level_id"), &"")
	assert_eq(flow.get("active_level_mode"), &"normal")


func test_every_state_pauses_and_resumes_to_the_same_state() -> void:
	for target_state: StringName in [
		&"boot",
		&"warp_room",
		&"level",
		&"results",
	]:
		var flow := _flow_in_state(target_state)
		if flow == null:
			return

		assert_eq(flow.call("dispatch", {"type": &"pause"}), OK)
		assert_eq(flow.call("state_name"), &"paused")
		assert_eq(flow.call("dispatch", {"type": &"resume"}), OK)
		assert_eq(flow.call("state_name"), target_state)


func test_illegal_level_to_boot_event_is_rejected() -> void:
	var flow := _flow_in_level()
	if flow == null:
		return

	assert_eq(
		flow.call("dispatch", {"type": &"boot"}),
		ERR_INVALID_PARAMETER
	)
	assert_eq(flow.call("state_name"), &"level")


func test_valid_events_are_rejected_outside_their_owning_state() -> void:
	var flow := _new_flow()
	if flow == null:
		return

	assert_eq(
		flow.call("dispatch", {"type": &"level_complete"}),
		ERR_INVALID_PARAMETER
	)
	assert_eq(flow.call("state_name"), &"boot")
	assert_eq(flow.call("dispatch", {"type": &"save_loaded"}), OK)
	assert_eq(
		flow.call("dispatch", {"type": &"level_complete"}),
		ERR_INVALID_PARAMETER
	)
	assert_eq(flow.call("state_name"), &"warp_room")
	assert_eq(
		flow.call(
			"dispatch",
			{
				"type": &"portal_enter",
				"level_id": &"wr1_n_sanity_beach",
			}
		),
		OK
	)
	assert_eq(
		flow.call("dispatch", {"type": &"save_loaded"}),
		ERR_INVALID_PARAMETER
	)
	assert_eq(flow.call("state_name"), &"level")
	assert_eq(flow.call("dispatch", {"type": &"level_complete"}), OK)
	assert_eq(
		flow.call(
			"dispatch",
			{
				"type": &"portal_enter",
				"level_id": &"wr1_n_sanity_beach",
			}
		),
		ERR_INVALID_PARAMETER
	)
	assert_eq(flow.call("state_name"), &"results")


func _new_flow() -> RefCounted:
	assert_true(
		ResourceLoader.exists(GAME_FLOW_PATH),
		"GameFlow implementation must exist"
	)
	if not ResourceLoader.exists(GAME_FLOW_PATH):
		return null
	var script := load(GAME_FLOW_PATH) as Script
	assert_not_null(script)
	return script.new() as RefCounted if script != null else null


func _flow_in_level() -> RefCounted:
	return _flow_in_state(&"level")


func _flow_in_state(target_state: StringName) -> RefCounted:
	var flow := _new_flow()
	if flow == null:
		return null
	if target_state == &"boot":
		return flow
	assert_eq(flow.call("dispatch", {"type": &"save_loaded"}), OK)
	if target_state == &"warp_room":
		return flow
	assert_eq(
		flow.call(
			"dispatch",
			{
				"type": &"portal_enter",
				"level_id": &"wr1_n_sanity_beach",
			}
		),
		OK
	)
	if target_state == &"level":
		return flow
	assert_eq(flow.call("dispatch", {"type": &"level_complete"}), OK)
	return flow
