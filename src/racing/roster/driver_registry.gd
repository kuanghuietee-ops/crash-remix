class_name DriverRegistry
extends RefCounted

## CTR R8 Task 2 (characters/select/classes): the six-driver roster table --
## supersedes RaceSession's two hardcoded character consts (CrashCharacter
## SceneType/LabAssistantCharacterSceneType, R6 Task 3) with one authored
## row per driver, id-keyed. Mirrors RacingTrackRegistry's (track_registry.
## gd) own "const table of preloaded rows, no instantiation" shape -- every
## method below is `static func`, called directly off the class the same
## way RacingTrackRegistryType.TRACKS is read directly off ITS class, never
## through a `.new()` instance (ghost_player.gd's own path_for_track() is
## this repo's identical static-utility precedent).
##
## ROSTER ORDER is fixed and load-bearing: crash, papu, cortex, coco,
## ripper_roo, lab_assistant -- see the design spec's own Roster section for
## why these six. RaceSession's own AI-fill logic walks entries() in this
## exact order, skipping only the player's own pick, so the order below IS
## the AI-fill order for every player pick -- deterministic and duplicate-
## free by construction (there are exactly 6 unique ids here; removing the
## one the player picked leaves exactly 5, in the same relative order).
##
## FALLBACK. A driver whose character_scene_path is empty, or whose path
## fails to resolve to a real PackedScene, races with the lab-assistant
## mesh instead -- the spec's own "an unfinished face can never break a
## race or block the round" rule. Exactly one push_warning() fires per
## fallback resolution -- never push_error() -- so an unfinished face is
## loud enough to show up in a diagnostic sweep but never loud enough to
## look like a real failure (GUT only auto-fails a test on an unhandled
## push_error/engine error, never an unhandled push_warning -- see addons/
## gut/error_tracker.gd's own _is_error_failable(), which has no push_
## warning branch at all).
##
## R8 gate flip 2026-08-02: at Task 2 time, papu/cortex/coco/ripper_roo all
## shipped an EMPTY character_scene_path pending their own likeness gates
## (Tasks 5-8), so every one of them was fallback-active from the moment
## this registry existed, proven by that task's own tests rather than
## assumed. Task 5 flipped papu to a real path first (posing his already
## operator-accepted platformer mesh, not a new likeness gate); cortex/coco/
## ripper_roo's own gates (docs/art/gates/2026-08-02-{cortex,coco,ripper-
## roo}/gate-record.md) were operator-accepted the same day this comment
## was last touched. No driver in ENTRIES ships an empty path any more, so
## _fallback_scene() below is no longer reachable from a live roster row --
## see test_driver_registry.gd's own synthetic-DriverEntry test for how its
## coverage is kept regardless.
const CRASH := preload("res://data/racing/drivers/crash.tres")
const PAPU := preload("res://data/racing/drivers/papu.tres")
const CORTEX := preload("res://data/racing/drivers/cortex.tres")
const COCO := preload("res://data/racing/drivers/coco.tres")
const RIPPER_ROO := preload("res://data/racing/drivers/ripper_roo.tres")
const LAB_ASSISTANT := preload("res://data/racing/drivers/lab_assistant.tres")

const ENTRIES: Array[DriverEntry] = [
	CRASH,
	PAPU,
	CORTEX,
	COCO,
	RIPPER_ROO,
	LAB_ASSISTANT,
]

## The one entry every fallback resolves to -- see the class doc's own
## FALLBACK section. A plain id lookup (never LAB_ASSISTANT directly) so a
## future reorder of ENTRIES can never silently desync this from the real
## roster row.
const _FALLBACK_ID := &"lab_assistant"


static func entries() -> Array[DriverEntry]:
	return ENTRIES


## A plain, honest lookup: null for an id absent from the roster (a bad save
## value, a stale ghost id, an unrecognized pick), never a silent
## substitution -- callers that need a guaranteed-non-null result use
## character_scene()/driver_class() below, which already fall back on the
## caller's behalf.
static func entry(id: StringName) -> DriverEntry:
	for candidate: DriverEntry in ENTRIES:
		if candidate.id == id:
			return candidate
	return null


## See the class doc's own FALLBACK section. Every exit that is NOT "id
## resolved to a real, loadable PackedScene" routes through _fallback_scene()
## exactly once, with exactly one push_warning() -- never push_error().
static func character_scene(id: StringName) -> PackedScene:
	var found := entry(id)
	var path := found.character_scene_path if found != null else ""
	if path.is_empty() or not ResourceLoader.exists(path):
		return _fallback_scene(id, path)
	var loaded := load(path)
	if not (loaded is PackedScene):
		return _fallback_scene(id, path)
	return loaded as PackedScene


## Null-safe: an id absent from the roster, or a driver_class_path that is
## empty/fails to resolve to a real DriverClass, both return null -- Kart
## Tuning.composed_with(null) (Task 1) already degrades to a plain
## uncomposed duplicate, so null here is a correct, harmless "no class
## multiplier" result. Unlike character_scene(), there is no mesh a missing
## class could fall back to seat instead -- "no multiplier applied" already
## IS the safe fallback -- so this never warns.
static func driver_class(id: StringName) -> DriverClass:
	var found := entry(id)
	if found == null or found.driver_class_path.is_empty():
		return null
	if not ResourceLoader.exists(found.driver_class_path):
		return null
	var loaded := load(found.driver_class_path)
	return loaded as DriverClass


static func _fallback_scene(id: StringName, attempted_path: String) -> PackedScene:
	push_warning(
		(
			"DriverRegistry.character_scene: driver %s has no usable "
			+ "character scene (path=\"%s\") -- seating the lab assistant "
			+ "instead."
		) % [id, attempted_path]
	)
	return load(entry(_FALLBACK_ID).character_scene_path) as PackedScene
