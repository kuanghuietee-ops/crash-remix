extends GutTest

# CTR R7 Task 6 (stretch, time-trial ghost): the shared on-disk .ghost FILE
# FORMAT ghost_recorder.gd (writer) and ghost_player.gd (reader) both agree
# on -- see ghost_recorder.gd's own class doc for the exact byte layout and
# ATOMIC WRITE shape. Proves the round trip is byte-exact and that every
# named corruption shape (truncated, wrong version, garbage) loads as
# "silently no ghost", never an error -- real FileAccess I/O against a real
# user:// path (see GHOST_TRACK_ID below for how this stays sandboxed from
# any genuine track's own ghost file), the same real-file-round-trip shape
# test_save_service.gd's own before_each/after_each cleanup already
# establishes for SaveService.

const GhostRecorderType := preload("res://src/racing/flow/ghost_recorder.gd")
const GhostPlayerType := preload("res://src/racing/flow/ghost_player.gd")

# GhostPlayer.path_for_track() -- the one place "user://ghosts/<id>.ghost"
# is spelled out (see its own doc) -- resolves every track id under the
# SAME real user://ghosts directory the live game uses; there is no
# sandboxed/parameterized save_dir the way SaveService takes one. A track
# id no real track registry ever authors keeps this file's own fixture from
# ever colliding with a genuine track's ghost, and before_each/after_each
# below only ever remove that ONE file, never the whole directory, so a
# concurrently-authored ghost-touching test elsewhere in this shared GUT
# process is never at risk of this file wiping its fixture out from under
# it.
const GHOST_TRACK_ID := &"__test_ghost_format_fixture__"

var _ghost_path: String


func before_each() -> void:
	_ghost_path = GhostPlayerType.path_for_track(GHOST_TRACK_ID)
	_remove_ghost_file()
	assert_eq(
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(_ghost_path.get_base_dir())
		) in [OK, ERR_ALREADY_EXISTS],
		true
	)


func after_each() -> void:
	_remove_ghost_file()


func _remove_ghost_file() -> void:
	for suffix: String in ["", ".tmp"]:
		var candidate := _ghost_path + suffix
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(
				ProjectSettings.globalize_path(candidate)
			)


func _tuning(interval_s: float = 0.1, max_keyframes: float = 3600.0) -> RaceTuning:
	var tuning := RaceTuning.new()
	tuning.ghost_keyframe_interval_s = interval_s
	tuning.ghost_max_keyframes = max_keyframes
	return tuning


func _recorded(tuning: RaceTuning, samples: Array) -> GhostRecorderType:
	var recorder := GhostRecorderType.new() as GhostRecorderType
	recorder.configure(tuning)
	recorder.start()
	for sample: Array in samples:
		recorder.sample(sample[0], sample[1], sample[2])
	recorder.stop()
	return recorder


# ---------------------------------------------------------------------------
# Round trip: byte-exact.
# ---------------------------------------------------------------------------


func test_round_trip_persists_and_loads_the_exact_same_keyframes() -> void:
	var tuning := _tuning()
	var recorder := _recorded(tuning, [
		[0.0, Vector3(1.0, 2.0, 3.0), 0.0],
		[0.1, Vector3(4.5, -2.25, 8.0), 90.0],
		[0.2, Vector3(-9.0, 0.0, 12.75), -179.5],
	])

	assert_eq(recorder.save_to_file(_ghost_path), OK)
	assert_true(FileAccess.file_exists(_ghost_path))

	var player := GhostPlayerType.new()
	add_child_autofree(player)
	var loaded := player.load_for_track(GHOST_TRACK_ID, tuning)

	assert_true(loaded)
	assert_true(player.has_ghost())
	assert_almost_eq(player.interval_s(), 0.1, 0.0001)

	var written := recorder.keyframes()
	var read: Array[Dictionary] = player._keyframes
	assert_eq(read.size(), written.size())
	for index: int in range(written.size()):
		assert_almost_eq(
			float(read[index]["t"]),
			float(written[index]["t"]),
			0.0001,
			"keyframe %d's t did not round-trip byte-exact" % index
		)
		assert_eq(
			(read[index]["position"] as Vector3),
			(written[index]["position"] as Vector3),
			"keyframe %d's position did not round-trip byte-exact" % index
		)
		assert_almost_eq(
			float(read[index]["yaw_degrees"]),
			float(written[index]["yaw_degrees"]),
			0.0001,
			"keyframe %d's yaw did not round-trip byte-exact" % index
		)


func test_round_trip_survives_a_solo_track_id_with_no_recorded_keyframes_by_never_writing() -> void:
	var tuning := _tuning()
	var recorder := GhostRecorderType.new() as GhostRecorderType
	recorder.configure(tuning)
	# Never start()ed -- has_keyframes() must stay false, the same guard
	# race_session.gd's own save_ghost() checks before ever calling
	# save_to_file() (see its own GHOST WIRING doc).
	assert_false(recorder.has_keyframes())


func test_a_missing_ghost_file_loads_as_no_ghost_without_warning() -> void:
	var player := GhostPlayerType.new()
	add_child_autofree(player)

	var loaded := player.load_for_track(&"track_with_no_ghost_yet", _tuning())

	assert_false(loaded)
	assert_false(player.has_ghost())


# ---------------------------------------------------------------------------
# Corruption: truncated, wrong version, garbage -- all "silently no ghost".
# ---------------------------------------------------------------------------


func test_a_truncated_ghost_file_loads_as_no_ghost() -> void:
	var tuning := _tuning()
	var recorder := _recorded(tuning, [
		[0.0, Vector3.ZERO, 0.0],
		[0.1, Vector3(1.0, 1.0, 1.0), 0.0],
		[0.2, Vector3(2.0, 2.0, 2.0), 0.0],
	])
	assert_eq(recorder.save_to_file(_ghost_path), OK)

	# Chop the file down to well short of its declared keyframe_count's own
	# byte payload -- a real "the write got cut off mid-record" shape (a
	# crash, a full disk, a killed process between store_32(count) and the
	# last keyframe's own bytes actually landing).
	var full_bytes := FileAccess.get_file_as_bytes(_ghost_path)
	assert_gt(full_bytes.size(), 12)
	var truncated := full_bytes.slice(0, 12)
	var file := FileAccess.open(_ghost_path, FileAccess.WRITE)
	file.store_buffer(truncated)
	file.close()

	var player := GhostPlayerType.new()
	add_child_autofree(player)
	var loaded := player.load_for_track(GHOST_TRACK_ID, tuning)

	assert_false(loaded)
	assert_false(player.has_ghost())


func test_a_wrong_version_ghost_file_loads_as_no_ghost() -> void:
	var tuning := _tuning()
	var recorder := _recorded(tuning, [[0.0, Vector3.ZERO, 0.0]])
	assert_eq(recorder.save_to_file(_ghost_path), OK)

	# Overwrite just the leading version header with a value that can never
	# match GhostRecorder.FILE_VERSION, leaving the rest of a genuinely
	# well-formed body untouched -- proves this is a VERSION check, not
	# incidentally just another truncation/garbage case.
	var file := FileAccess.open(_ghost_path, FileAccess.READ_WRITE)
	file.store_32(GhostRecorderType.FILE_VERSION + 1)
	file.close()

	var player := GhostPlayerType.new()
	add_child_autofree(player)
	var loaded := player.load_for_track(GHOST_TRACK_ID, tuning)

	assert_false(loaded)
	assert_false(player.has_ghost())


func test_a_garbage_ghost_file_loads_as_no_ghost() -> void:
	var file := FileAccess.open(_ghost_path, FileAccess.WRITE)
	# Plausible-length noise, not a well-formed header at all -- proves the
	# reader survives on bytes that never came from save_to_file() in the
	# first place, not only a damaged real one.
	for _index: int in range(64):
		file.store_8(_index * 7 % 256)
	file.close()

	var player := GhostPlayerType.new()
	add_child_autofree(player)
	var loaded := player.load_for_track(GHOST_TRACK_ID, _tuning())

	assert_false(loaded)
	assert_false(player.has_ghost())


func test_a_declared_keyframe_count_above_the_tuned_cap_loads_as_no_ghost() -> void:
	# A hostile/garbage header claiming an absurd keyframe count must never
	# make the reader loop that many times -- bounded against the CURRENT
	# ghost_max_keyframes ceiling instead (see _load_from_path()'s own doc).
	var file := FileAccess.open(_ghost_path, FileAccess.WRITE)
	file.store_32(GhostRecorderType.FILE_VERSION)
	file.store_float(0.1)
	file.store_32(1000000)
	file.close()

	var player := GhostPlayerType.new()
	add_child_autofree(player)
	var loaded := player.load_for_track(GHOST_TRACK_ID, _tuning(0.1, 3600.0))

	assert_false(loaded)
	assert_false(player.has_ghost())


func test_writing_over_an_existing_ghost_file_replaces_it_atomically() -> void:
	var tuning := _tuning()
	var first := _recorded(tuning, [[0.0, Vector3(1.0, 0.0, 0.0), 0.0]])
	assert_eq(first.save_to_file(_ghost_path), OK)

	var second := _recorded(tuning, [
		[0.0, Vector3(9.0, 9.0, 9.0), 0.0],
		[0.1, Vector3(8.0, 8.0, 8.0), 0.0],
	])
	assert_eq(second.save_to_file(_ghost_path), OK)

	var player := GhostPlayerType.new()
	add_child_autofree(player)
	assert_true(player.load_for_track(GHOST_TRACK_ID, tuning))
	var read: Array[Dictionary] = player._keyframes
	assert_eq(read.size(), 2)
	assert_eq((read[0]["position"] as Vector3), Vector3(9.0, 9.0, 9.0))

	# No leftover ".tmp" file from the atomic rename.
	assert_false(FileAccess.file_exists(_ghost_path + ".tmp"))
