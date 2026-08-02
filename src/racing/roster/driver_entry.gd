class_name DriverEntry
extends Resource

## CTR R8 Task 2 (characters/select/classes): one authored row per roster
## driver -- data/racing/drivers/{crash,papu,cortex,coco,ripper_roo,
## lab_assistant}.tres, one per id, always read through DriverRegistry
## (driver_registry.gd's own class doc carries the fixed roster ORDER and
## the FALLBACK rule; this class only carries the per-driver FIELDS).
## Mirrors DriverClass's own "authored .tres per archetype" shape (driver_
## class.gd's own class doc) rather than RacingTrackRegistry's inline-
## Dictionary rows: a driver needs real per-instance Resource identity --
## the same object loaded once and reused -- where a track row's few plain
## strings/preloaded PackedScenes never did.
##
## character_scene_path/driver_class_path are authored as plain STRINGS,
## loaded by DriverRegistry at the point of use (character_scene()/driver_
## class()) rather than preloaded here -- a preload() needs a real path at
## parse time, which an unfinished driver's own empty character_scene_path
## cannot give it. See DriverRegistry.character_scene()'s own FALLBACK doc
## for what an empty/unloadable path resolves to, and DriverClass's own
## class doc ("loaded by string path the same way DriverEntry.character_
## scene_path loads a PackedScene") for why driver_class_path follows the
## identical shape.
@export var id: StringName
@export var display_name: String
## res:// path to this driver's character PackedScene (a .glb import, the
## same kind of asset the two hardcoded consts this task deletes from race_
## session.gd used to preload directly) -- or "" for a driver whose face is
## not yet gated. papu/cortex/coco/ripper_roo currently ship "" (Tasks 5-8
## land their real builds); crash/lab_assistant ship their existing real
## paths.
@export var character_scene_path: String
## res:// path to one of data/tuning/racing/classes/{balanced,speed,accel,
## turning}.tres -- see driver_class.gd's own class doc for why these four
## live outside TuningService's own SECTION_NAMES catalog and are loaded by
## path per driver instead of through that catalog.
@export var driver_class_path: String
## Task 5's own seat-fit authoring target (papu is much larger than Crash --
## see the design spec's Roster section). Declared here now so Task 5 only
## ever adds VALUES to an already-existing field, never a schema change.
## Task 2 itself never reads these two fields -- no driver's mount needs a
## non-neutral fit yet (Crash/lab-assistant already fit; every other driver
## is fallback-active, see DriverRegistry's own doc) -- so every entry below
## authors the neutral no-op value (seat_scale 1.0, seat_offset ZERO) until
## Task 5 gives papu real ones.
@export var seat_scale: float
@export var seat_offset: Vector3
