## Task 4 (CTR R7): single source of truth for every racing track's menu
## and session wiring. Before this file, src/core/game_root.gd's racing
## branch and src/ui/level_list_overlay.gd's own button wiring each
## hand-carried a near-duplicate copy of "which track, which scene, which
## debug level id, what does the button say" -- one pair of consts+signals
## per track, on BOTH sides, doubling with every new circuit (Sanity
## Shores was the first repeat; Temple Twilight's own two pending menu
## entries are what triggered this refactor rather than a third). Both
## files now read the SAME rows from here instead of keeping their own
## copies -- see game_root.gd's RacingTrackRegistryType usage (scene
## launch + tuning refresh + run-display visibility, all keyed by
## level_id/solo_level_id) and level_list_overlay.gd's own usage (button
## wiring + dynamically-derived button text, keyed by track_id).
##
## `level_id`/`solo_level_id` are carried explicitly, not derived from
## `track_id`, because the two pre-existing tracks (graybox_loop,
## sanity_shores) keep their historical, slightly inconsistent debug-level-
## id spelling verbatim -- pre-Task-4, these lived in game_root.gd as its
## own DEBUG_RACING_LEVEL_ID/DEBUG_RACING_SANITY_SHORES_LEVEL_ID/etc.
## consts, whose own old naming debt (fix-wave MEDIUM-5: the ids still say
## "time_trial" even for the AI-populated RACE entry) is preserved
## verbatim in the `level_id`/`solo_level_id` string values below. This
## refactor changes NOTHING about existing behavior for either track; only
## Temple Twilight's new row gets a clean, track-id-derived id scheme,
## since it has no old naming to preserve.
class_name RacingTrackRegistry
extends RefCounted

const TRACKS: Array[Dictionary] = [
	{
		track_id = &"graybox_loop",
		display_name = "GRAYBOX LOOP",
		level_id = &"debug_racing_time_trial",
		solo_level_id = &"debug_racing_time_trial_solo",
		race_scene = preload("res://scenes/racing/race_time_trial.tscn"),
		solo_scene = preload(
			"res://scenes/racing/race_time_trial_solo.tscn"
		),
	},
	{
		track_id = &"sanity_shores",
		display_name = "SANITY SHORES",
		level_id = &"debug_racing_sanity_shores",
		solo_level_id = &"debug_racing_sanity_shores_time_trial",
		race_scene = preload(
			"res://scenes/racing/race_sanity_shores.tscn"
		),
		solo_scene = preload(
			"res://scenes/racing/race_sanity_shores_solo.tscn"
		),
	},
	{
		track_id = &"temple_twilight",
		display_name = "TEMPLE TWILIGHT",
		level_id = &"debug_racing_temple_twilight",
		solo_level_id = &"debug_racing_temple_twilight_time_trial",
		race_scene = preload(
			"res://scenes/racing/race_temple_twilight.tscn"
		),
		solo_scene = preload(
			"res://scenes/racing/race_temple_twilight_solo.tscn"
		),
	},
]
