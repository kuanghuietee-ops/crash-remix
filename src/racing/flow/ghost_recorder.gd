class_name GhostRecorder
extends RefCounted

## CTR R7 Task 6 (stretch, time-trial ghost) -- the RECORDING half. Pure
## logic only (no Node/scene tree dependency), the same configure()-then-
## poll shape countdown_timer.gd/start_boost_judge.gd already establish for
## this codebase's other pure racing-flow classes -- see ghost_player.gd's
## own class doc for the PLAYBACK half and the shared on-disk .ghost format
## both classes agree on.
##
## OWNERSHIP. RaceSession (race_session.gd) owns exactly one instance,
## configure()d fresh on every configure()/retry the same way _countdown/
## _start_boost_judge already are. Recording only ever happens for SOLO
## sessions (spawn_opponents == false) -- RaceSession is the one place that
## decides that, by simply never calling start()/sample() at all for a
## race with AI opponents (see race_session.gd's own GHOST WIRING section).
## This class has no opinion of its own about solo-ness; it only ever
## records when told to.
##
## CLOCK -- PUSHED, NOT OWNED. sample(elapsed_s, ...) is fed RaceSession's
## own already-computed, pause-correct elapsed-since-GO clock (_elapsed_s,
## see race_session.gd's own TIMER section) every physics tick after GO --
## this class keeps no timer of its own, so it can never drift from the
## real race clock the HUD/finish time already use, and pausing the tree
## freezes recording for free the same way it freezes everything else
## driven from that identical clock.
##
## CADENCE. The first sample() call after start() always records (the GO
## pose, t == 0.0-ish) -- _next_sample_s starts at 0.0, and every real
## elapsed_s a caller can pass is >= 0.0. Every call after that only
## records once elapsed_s has reached the next ghost_keyframe_interval_s
## boundary, then advances that threshold by exactly one interval (not to
## elapsed_s itself), so the recorded cadence never drifts even if a caller
## occasionally skips a physics tick.
##
## CAP. Once keyframes().size() reaches RaceTuning.ghost_max_keyframes
## (int()'d -- a float field with COUNT semantics, see race_tuning.gd's own
## doc), sample() becomes a silent no-op forever (is_capped() reports it) --
## a stuck or pathologically long solo run can never grow an unbounded
## recording or an unbounded .ghost file on disk.
##
## KEYFRAME SHAPE, one Dictionary per sample in keyframes() (mirrors race_
## ranking.gd's own "ENTRY SHAPE" documented-Dictionary convention):
## - t: float, elapsed_s at the instant this keyframe was sampled.
## - position: Vector3, the kart's own global_position at that instant.
## - yaw_degrees: float, the kart's own world-facing yaw at that instant
##   (see race_session.gd's GHOST WIRING section for how this is derived
##   from the kart's real global_transform.basis -- the same forward-vector
##   idiom _seed_kart_transform() already uses for spawn placement).
##
## FILE FORMAT (version header + interval + keyframe array, per the task
## brief), written by save_to_file() and read back by ghost_player.gd's
## load_for_track(): a flat, versioned binary stream via FileAccess's own
## typed store_32/store_float methods (never JSON -- a compact per-tick
## sample stream has no need for SaveService's text/dictionary shape, and
## this is a disposable derived artifact outside the profile, not save
## data that ever needs hand-editing or cross-version diffing):
##   store_32   FILE_VERSION
##   store_float interval_s
##   store_32   keyframe_count
##   keyframe_count times: store_float t, x, y, z, yaw_degrees
## ghost_player.gd's own load_for_track() is the one place that decodes
## this back -- see its class doc for the corruption/version-mismatch
## handling, which never touches this class.
##
## ATOMIC WRITE. save_to_file() mirrors SaveService's own temp-file-then-
## rename pattern (write to "<path>.tmp", flush, check the write actually
## succeeded, close, then DirAccess.rename_absolute() over the real path)
## WITHOUT touching SaveService itself -- ghost files are deliberately kept
## entirely outside the profile save (spec: "Persistence OUTSIDE the
## profile save"), so this class owns its own tiny atomic-write path rather
## than routing through SaveService's dictionary/JSON-shaped API. There is
## no backup-file/corrupt-evidence-preservation step here (unlike
## SaveService) -- a ghost is a disposable "nice to have" replay aid, never
## authoritative save data, so a failed write just means "no ghost this
## time" (the caller pushes at most a warning, see race_session.gd's own
## GHOST WIRING section), never a loud error that could look like the run
## itself failed.

const FILE_VERSION := 1

var _interval_s: float
var _max_keyframes: int
var _keyframes: Array[Dictionary] = []
var _next_sample_s: float
var _recording: bool = false
var _capped: bool = false


## Reads ghost_keyframe_interval_s/ghost_max_keyframes off the SAME
## RaceTuning resource RaceSession already holds (the whole-resource-typed-
## param shape CountdownTimer.configure()/StartBoostJudge.configure()
## already establish, not individual float args) and resets recording state
## to empty/idle -- safe to call again on a re-configure()/retry, the same
## "configure() always restarts the whole flow fresh" contract every other
## pure flow class in this file honors.
func configure(race_tuning: RaceTuning) -> void:
	_interval_s = race_tuning.ghost_keyframe_interval_s
	_max_keyframes = int(race_tuning.ghost_max_keyframes)
	reset()


## Discards any in-progress recording and returns to the pre-start() idle
## state. Called by configure() itself and available separately so a caller
## can abandon a partial recording (e.g. a race scene that decides mid-flow
## it will never persist this run) without a full re-configure().
func reset() -> void:
	_keyframes.clear()
	_next_sample_s = 0.0
	_recording = false
	_capped = false


## Begins a fresh recording -- called once, at GO (mirrors CountdownTimer's
## own one-shot &"go" edge, see race_session.gd's _start_race()). Always
## resets first, so a defensive double-call (e.g. a re-configure() reusing
## this same instance) can never append a second run's keyframes onto a
## stale leftover from a previous one.
func start() -> void:
	reset()
	_recording = true


## Stops recording without discarding what has already been captured --
## called once, at the real race's own finish (see race_session.gd's
## _finish_race()), so keyframes() still returns the completed run's full
## recording afterward for save_to_file() to persist.
func stop() -> void:
	_recording = false


func is_recording() -> bool:
	return _recording


func is_capped() -> bool:
	return _capped


## One candidate sample per call, expected once per physics tick while
## recording -- see the class doc's CADENCE section for the threshold math
## and CAP section for why this silently stops appending once _max_
## keyframes is reached. A no-op whenever not recording (before start(),
## after stop(), or once capped), so a caller never needs its own guard.
func sample(elapsed_s: float, position: Vector3, yaw_degrees: float) -> void:
	if not _recording or _capped:
		return
	if elapsed_s < _next_sample_s:
		return
	_keyframes.append({
		"t": elapsed_s,
		"position": position,
		"yaw_degrees": yaw_degrees,
	})
	_next_sample_s += _interval_s
	if _keyframes.size() >= _max_keyframes:
		_capped = true
		_recording = false


## A duplicate, never the live internal array -- a caller mutating the
## returned Array must never be able to corrupt this recorder's own state
## (the same defensive-copy convention SaveModel's own getters already use
## for a Dictionary/Array-typed save record).
func keyframes() -> Array[Dictionary]:
	return _keyframes.duplicate(true)


func has_keyframes() -> bool:
	return not _keyframes.is_empty()


func interval_s() -> float:
	return _interval_s


## Atomically writes this recorder's own current keyframes() to `path` in
## the FILE FORMAT the class doc documents -- see that section for the full
## byte layout and the ATOMIC WRITE section for the temp-then-rename shape.
## Returns OK on success, or the first Error encountered (directory
## creation, file open, or the write itself) -- never pushes an error/
## warning itself; the caller (race_session.gd's GHOST WIRING section)
## decides how loud a failed ghost write should be, since it must never be
## loud enough to look like the RACE failed.
func save_to_file(path: String) -> Error:
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(path.get_base_dir())
	)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return directory_error

	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

	file.store_32(FILE_VERSION)
	file.store_float(_interval_s)
	file.store_32(_keyframes.size())
	for keyframe: Dictionary in _keyframes:
		file.store_float(float(keyframe["t"]))
		var position: Vector3 = keyframe["position"]
		file.store_float(position.x)
		file.store_float(position.y)
		file.store_float(position.z)
		file.store_float(float(keyframe["yaw_degrees"]))

	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return write_error

	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temp_path),
		ProjectSettings.globalize_path(path)
	)
