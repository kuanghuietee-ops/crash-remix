class_name GhostPlayer
extends Node3D

## CTR R7 Task 6 (stretch, time-trial ghost) -- the PLAYBACK half. See
## ghost_recorder.gd's own class doc for the RECORDING half and the shared
## on-disk .ghost FILE FORMAT both classes agree on (this class is the one
## that decodes it back -- see load_for_track()'s own doc below for the
## corruption/version-mismatch handling).
##
## OWNERSHIP. RaceSession (race_session.gd) owns exactly one instance,
## lazily created and add_child()-ed the first time configure() needs one
## (see race_session.gd's own _ensure_ghost_player(), the SAME lazy-
## container shape _ai_root/_hazards_root already establish). RaceSession
## is always already inside the live scene tree by the time it calls
## configure() (GameRoot's own _render_state() racing branch always
## add_child()s a fresh race scene BEFORE calling its configure() -- see
## game_root.gd's own doc), so add_child()-ing a freshly `.new()`d
## GhostPlayer fires this class's own _ready() synchronously, before
## RaceSession's very next line can call configure()/load_for_track() on
## it -- unlike the AiKartAgent/KartFx "configure() called before
## add_child()" hazard those classes' own docs name (a NESTED pre-authored
## scene-child lookup problem), this class builds its own visual subtree
## from nothing, so there is no pre-authored child to have raced ahead of.
##
## PURE VISUAL, NO PHYSICS (spec: "the ghost must not interact with
## gates/boxes/pads/karts -- no Area3D, no body -- pure visual Node3D").
## This class and everything it instantiates stays a plain Node3D/
## MeshInstance3D subtree -- never a CollisionObject3D, CharacterBody3D, or
## Area3D of any kind -- so it is structurally incapable of tripping a
## gate, item box, pad, or kart-vs-kart hazard, the same "no collision
## layers" guarantee test_ghost_player.gd's own collision-free proof checks
## for by walking this subtree and asserting no CollisionObject3D exists
## anywhere in it.
##
## GHOST MODEL. Instances the SAME bare kart mesh kart.tscn's own "Visual"
## child wraps (assets/models/karts/SM_kart.glb), with the identical
## rotation.y = PI yaw correction kart.tscn authors on that node (the
## model's own forward axis is reversed relative to the body's -- see
## kart_controller.gd's own mount_character() doc for the identical
## correction applied to the player's character model) -- WITHOUT kart.
## tscn's CharacterBody3D wrapper, CollisionShape3D, BlobShadow, or Fx
## particle rig, exactly the "no character, no collision, no blob shadow"
## reduced shape the brief calls for. Every MeshInstance3D found in that
## subtree gets material_override set to a fresh ShaderMaterial on phase_
## ghost.gdshader (see phase_state.gd's own _apply_group() for the
## identical shader-swap idiom this reuses -- "reuse the phase_ghost shader
## convention", the exact path the task brief names), sized from a
## PhaseTuning resource handed to configure_visual() -- catalog.phase's own
## ghost_opacity/ghost_outline_width_m, the SAME fields PhaseState already
## uses for the platformer's own phase-ability ghost, already loaded as
## part of the same GameplayTuning catalog RaceSession.configure() already
## receives. No new opacity/outline tuning field exists for racing; this is
## the identical translucent-outline look, reused verbatim on a different
## mesh, not a new one authored from scratch.
##
## LOAD, NOT DECODE-ON-EVERY-FRAME. load_for_track() (called once, from
## RaceSession.configure(), solo sessions only -- see race_session.gd's own
## GHOST WIRING section) reads and decodes the whole .ghost file for a
## track up front into _keyframes/_interval_s/_driver_id (CTR R8 Task 3 --
## the recorded driver id, see that field's own doc; not used to mount
## anything this round, recorded for forward use only) and returns whether a
## usable ghost was found. Absent (no such file -- by far the common case, since a
## first-ever solo run has no prior best to ghost against), corrupt
## (truncated mid-record), a version mismatch, or a declared keyframe count
## above the currently-tuned ghost_max_keyframes ceiling (a defensive bound
## against a hostile/garbage file claiming an enormous count -- see the
## class doc reasoning inline in _load_from_path()) all fold into the same
## outcome: no ghost, never an error the caller has to handle specially
## (spec: "never blocks a run"). Absent pushes nothing; every other
## rejection pushes at most one push_warning naming the path, per the
## brief's own "push_warning at most" ceiling.
##
## REPLAY CLOCK -- PUSHED, NOT OWNED. This class keeps no clock of its own.
## RaceSession already computes ONE pause-correct elapsed-since-GO clock
## (_elapsed_s, see its own class doc TIMER section) for the real kart's
## own timer/HUD; advance(elapsed_s) is called with that SAME number every
## physics tick after GO (mirroring how ghost_recorder.gd's sample() is fed
## the identical value), so the ghost can never drift from the real race's
## own clock, and pausing the tree (process_mode = PROCESS_MODE_PAUSABLE,
## set in _ready()) freezes the ghost for free the same way pausing freezes
## everything else RaceSession drives from that same clock. start_replay()
## (called once, at GO, mirroring ghost_recorder.gd's own start()) reveals
## the visual; advance() past the LAST keyframe's own t hides it again
## (spec: "despawns/hides at replay end") -- a real race finishing early
## (_finish_race()) also calls stop_replay() defensively, so a ghost slower
## than the real run's own finish never keeps animating into the post-race
## freeze.
##
## INTERPOLATION MATH is a pure static function (interpolate_pose()),
## callable with no instance/scene-tree at all -- the same "pure logic
## stays separate from Node glue, so it can be tested headless" split this
## repo's CLAUDE.md requires, applied WITHIN a Node3D-extending file rather
## than a whole separate RefCounted class (mirrors src/gameplay/camera/
## camera_archetypes.gd's own top-level "static func" precedent for pure
## math that happens to live alongside impure glue).

const GhostRecorderType := preload("res://src/racing/flow/ghost_recorder.gd")
const KartModelSceneType := preload("res://assets/models/karts/SM_kart.glb")
const GhostShaderType := preload("res://assets/shaders/phase_ghost.gdshader")

const GHOST_DIRECTORY := "user://ghosts"
const GHOST_FILE_EXTENSION := ".ghost"

var _keyframes: Array[Dictionary] = []
var _interval_s: float = 0.0
## CTR R8 Task 3 (save v3->v4 + ghost v2): the driver id load_for_track()
## decoded off the .ghost file's own pascal string (or GhostRecorderType.
## DEFAULT_DRIVER_ID for a legacy v1 file, which predates the field
## entirely) -- see _load_from_path()'s own doc. Nothing in this class reads
## it back yet (the ghost stays a palette kart this round, per the class doc's
## GHOST MODEL section); it is recorded here purely for forward use by a
## future task, exposed read-only via driver_id() below.
var _driver_id: StringName = GhostRecorderType.DEFAULT_DRIVER_ID
var _active: bool = false
var _visual: Node3D
var _ghost_material := ShaderMaterial.new()


## The one place "user://ghosts/<track_id>.ghost" is spelled out -- both
## save_to_file()'s caller (race_session.gd's own save_ghost(), the write
## side) and load_for_track() (the read side, below) resolve through this
## SAME static function, so the two can never quietly disagree about where
## a given track's ghost lives.
static func path_for_track(track_id: StringName) -> String:
	return GHOST_DIRECTORY.path_join(String(track_id) + GHOST_FILE_EXTENSION)


## Pure interpolation: the ghost's own position/yaw at real time `t`
## (elapsed-since-GO seconds, the same clock advance() is fed), linearly
## interpolated between whichever pair of recorded keyframes brackets it.
## Clamps to the first/last keyframe's own pose outside the recorded range
## (before the first sample, or once queried past the last one -- advance()
## itself never queries past the last sample; see its own doc) rather than
## extrapolating. yaw_degrees is interpolated via lerp_angle() on the
## RADIAN form, not a naive lerp() on raw degrees -- a naive lerp would spin
## the ghost the LONG way around any 180-degree-crossing turn (e.g. 179deg
## toward -179deg lerping through 0deg instead of the true 2-degree short
## way), the identical wrap hazard Godot's own lerp_angle() exists to
## avoid. Returns {} for an empty keyframes array (nothing to show).
static func interpolate_pose(keyframes: Array[Dictionary], t: float) -> Dictionary:
	if keyframes.is_empty():
		return {}
	var last_index := keyframes.size() - 1
	if keyframes.size() == 1 or t <= float(keyframes[0]["t"]):
		return {
			"position": keyframes[0]["position"],
			"yaw_degrees": keyframes[0]["yaw_degrees"],
		}
	if t >= float(keyframes[last_index]["t"]):
		return {
			"position": keyframes[last_index]["position"],
			"yaw_degrees": keyframes[last_index]["yaw_degrees"],
		}
	for index: int in range(1, keyframes.size()):
		var next_frame: Dictionary = keyframes[index]
		var next_t := float(next_frame["t"])
		if t > next_t:
			continue
		var previous_frame: Dictionary = keyframes[index - 1]
		var previous_t := float(previous_frame["t"])
		var span := next_t - previous_t
		var weight := 0.0 if span <= 0.0 else (t - previous_t) / span
		var previous_position: Vector3 = previous_frame["position"]
		var next_position: Vector3 = next_frame["position"]
		return {
			"position": previous_position.lerp(next_position, weight),
			"yaw_degrees": rad_to_deg(
				lerp_angle(
					deg_to_rad(float(previous_frame["yaw_degrees"])),
					deg_to_rad(float(next_frame["yaw_degrees"])),
					weight
				)
			),
		}
	# Unreachable given the clamped bounds above -- kept only so every path
	# through this function returns the same typed shape.
	return {
		"position": keyframes[last_index]["position"],
		"yaw_degrees": keyframes[last_index]["yaw_degrees"],
	}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_ghost_material.shader = GhostShaderType
	_build_visual()
	visible = false


func _build_visual() -> void:
	if _visual != null:
		return
	_visual = KartModelSceneType.instantiate() as Node3D
	_visual.rotation.y = PI
	add_child(_visual)
	for mesh_instance: MeshInstance3D in _visual.find_children(
		"*",
		"MeshInstance3D",
		true,
		false
	):
		mesh_instance.material_override = _ghost_material


## Sizes the ghost shader's own opacity/outline parameters from the SAME
## PhaseTuning fields the platformer's own phase ability reads (see the
## class doc's GHOST MODEL section) -- safe to call before _ready() has run
## (configure()-before-add_child() is never actually possible for this
## class per the OWNERSHIP doc above, but this guard costs nothing and
## keeps the method safe to call defensively/repeatedly on a re-configure).
func configure_visual(phase_tuning: PhaseTuning) -> void:
	if phase_tuning == null:
		return
	_ghost_material.set_shader_parameter(
		&"ghost_opacity",
		phase_tuning.ghost_opacity
	)
	_ghost_material.set_shader_parameter(
		&"ghost_outline_width_m",
		phase_tuning.ghost_outline_width_m
	)


## Discards any loaded ghost and hides the visual -- called by RaceSession.
## configure() for a non-solo (AI) session, or a solo session on a track
## with no ghost file yet, so a re-configure()/retry reusing this same
## instance never keeps showing a PREVIOUS track's ghost.
func clear() -> void:
	_keyframes = []
	_interval_s = 0.0
	_driver_id = GhostRecorderType.DEFAULT_DRIVER_ID
	_active = false
	visible = false


## Reads and decodes user://ghosts/<track_id>.ghost (see path_for_track()),
## replacing any previously loaded ghost. Returns true only when a genuinely
## usable ghost was found -- false for every other outcome (absent, open
## failure, version mismatch, or a corrupt/truncated body), all of which
## leave this player exactly as clear() would. race_tuning supplies the
## CURRENT ghost_max_keyframes ceiling, used only as a sanity bound against
## a garbage file claiming an absurd keyframe count (never trusted for
## anything else -- a ghost recorded under an OLDER, smaller cap is still
## valid; only the file's own declared interval/keyframes are ever used to
## replay it).
func load_for_track(track_id: StringName, race_tuning: RaceTuning) -> bool:
	clear()
	if String(track_id).is_empty() or race_tuning == null:
		return false
	return _load_from_path(path_for_track(track_id), race_tuning)


func _load_from_path(path: String, race_tuning: RaceTuning) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Ghost file could not be opened: %s" % path)
		return false

	var version := file.get_32()
	if file.get_error() != OK:
		push_warning("Ghost file is corrupt, ignoring: %s" % path)
		file.close()
		return false
	# CTR R8 Task 3 (save v3->v4 + ghost v2): two accepted version words, not
	# one -- a genuine legacy FILE_VERSION_V1 file (no driver id pascal
	# string at all, see GhostRecorder's own FILE FORMAT doc) still loads;
	# anything else (a real version mismatch, or garbage bytes that happen
	# to land on neither) still rejects, unchanged from before this task.
	var is_legacy_v1 := version == GhostRecorderType.FILE_VERSION_V1
	if not is_legacy_v1 and version != GhostRecorderType.FILE_VERSION:
		push_warning("Ghost file version mismatch, ignoring: %s" % path)
		file.close()
		return false

	# A legacy v1 file has no pascal string to read here at all -- its
	# implied driver is always DEFAULT_DRIVER_ID (see FILE_VERSION_V1's own
	# doc on GhostRecorder). A v2+ file's id is read fresh off the file
	# itself; get_pascal_string() reading past a truncated/garbage-length
	# declaration sets get_error() the same way get_32()/get_float() do
	# elsewhere in this function (verified against Godot's own FileAccess
	# behavior, not assumed), so this folds into the SAME "corrupt -> no
	# ghost" outcome every other structural corruption in this function
	# already produces -- never a partial load with a garbage id.
	var driver_id := GhostRecorderType.DEFAULT_DRIVER_ID
	if not is_legacy_v1:
		var raw_driver_id := file.get_pascal_string()
		if file.get_error() != OK:
			push_warning("Ghost file is corrupt, ignoring: %s" % path)
			file.close()
			return false
		driver_id = StringName(raw_driver_id)

	var interval_s := file.get_float()
	var keyframe_count := file.get_32()
	var max_keyframes := int(race_tuning.ghost_max_keyframes)
	if (
		file.get_error() != OK
		or interval_s <= 0.0
		or keyframe_count > max_keyframes
	):
		push_warning("Ghost file is corrupt, ignoring: %s" % path)
		file.close()
		return false

	var keyframes: Array[Dictionary] = []
	for _index: int in range(keyframe_count):
		var t := file.get_float()
		var x := file.get_float()
		var y := file.get_float()
		var z := file.get_float()
		var yaw_degrees := file.get_float()
		keyframes.append({
			"t": t,
			"position": Vector3(x, y, z),
			"yaw_degrees": yaw_degrees,
		})
	var read_error := file.get_error()
	file.close()
	if read_error != OK:
		push_warning("Ghost file is truncated, ignoring: %s" % path)
		return false
	if keyframes.is_empty():
		return false

	_keyframes = keyframes
	_interval_s = interval_s
	_driver_id = driver_id
	return true


func has_ghost() -> bool:
	return not _keyframes.is_empty()


func interval_s() -> float:
	return _interval_s


## CTR R8 Task 3 (save v3->v4 + ghost v2): the id load_for_track() decoded
## off the loaded ghost file -- GhostRecorderType.DEFAULT_DRIVER_ID
## (&"crash") both before any ghost is loaded and for a genuine legacy v1
## file, which predates the field entirely. See _driver_id's own field doc.
func driver_id() -> StringName:
	return _driver_id


## Reveals the visual and begins replaying from the ghost's own first
## keyframe -- called once, at GO. A no-op (visual stays hidden) when no
## ghost was ever loaded (has_ghost() false), which is what keeps this
## class's own solo-only contract: RaceSession only ever populates
## _keyframes for a solo session with an existing ghost (see its own GHOST
## WIRING section), so an AI race or a track with no ghost yet naturally
## never shows one, with no extra flag needed here.
func start_replay() -> void:
	if not has_ghost():
		return
	_active = true
	visible = true
	advance(0.0)


## Hides the visual and stops replaying without discarding the loaded
## keyframes -- a fresh start_replay() (retry) can resume from the top.
func stop_replay() -> void:
	_active = false
	visible = false


## Pushed once per physics tick after GO with RaceSession's own elapsed-
## since-GO clock (see the class doc's REPLAY CLOCK section) -- a no-op
## whenever not actively replaying. Hides and stops itself the instant
## elapsed_s reaches the ghost's own final keyframe (spec: "despawns/hides
## at replay end") rather than holding a frozen last pose on screen.
##
## Moves THIS node (self.global_transform), never _visual's own transform
## directly -- mirrors kart.tscn's own Kart(outer, live yaw)/Visual(inner,
## static PI correction) split (see the class doc's GHOST MODEL section):
## _visual's own local rotation.y == PI, set once in _build_visual() and
## never touched again, is what keeps the model's reversed forward axis
## correctly compensated on every frame. Writing the replayed pose onto
## _visual directly would REPLACE that whole local transform outright
## (global_transform's setter solves for exactly the local transform that
## achieves the given global one), silently erasing the PI correction the
## instant the first keyframe played -- moving the PARENT instead leaves
## _visual's own untouched local rotation free to keep composing with it
## every frame, the same way the real kart's Visual child never needs its
## own rotation touched again after kart_controller.gd writes Kart's
## rotation.y each tick.
func advance(elapsed_s: float) -> void:
	if not _active or _keyframes.is_empty():
		return
	var last_t := float(_keyframes[_keyframes.size() - 1]["t"])
	if elapsed_s >= last_t:
		stop_replay()
		return
	var pose := interpolate_pose(_keyframes, elapsed_s)
	if pose.is_empty():
		return
	global_transform = Transform3D(
		Basis(Vector3.UP, deg_to_rad(float(pose["yaw_degrees"]))),
		pose["position"]
	)
