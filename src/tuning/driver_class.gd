class_name DriverClass
extends Resource

## CTR R8 Task 1 (characters/select/classes): a CTR-style handling class --
## three multipliers KartTuning.composed_with() (see that method's own doc)
## applies onto a per-kart duplicate of the shared data/tuning/racing/
## kart.tres, EXACTLY the three fields named below, nothing else. Four are
## authored under data/tuning/racing/classes/ (balanced/speed/accel/
## turning -- see each .tres's own values), one per driver archetype;
## Task 2's DriverRegistry assigns a specific one to each of the six roster
## drivers and RaceSession composes it onto that driver's kart at spawn and
## on every live-refresh (see race_session.gd's own kart-configure-path and
## refresh_tuning() docs).
##
## WHY THIS SITS OUTSIDE GameplayTuning/TuningService's OWN SECTION_NAMES
## CATALOG (contrast with kart.tres/ai.tres/race.tres/items.tres/fx.tres,
## which all DO join it): every existing SECTION_NAMES entry is exactly ONE
## canonical resource the whole race reads uniformly -- there is only ever
## one ai.tres, one fx.tres. A driver class is the opposite shape: FOUR
## independently-authored siblings, selectively assigned per driver (Task
## 2's DriverEntry.driver_class_path, loaded by string path the same way
## DriverEntry.character_scene_path loads a PackedScene -- see track_
## registry.gd's own const-table-of-paths precedent for the same "load by
## path per entry" shape). There is no natural single "classes" field for a
## fixed catalog built around "the one authored value" to hold four
## selectable options.
##
## This is still real, physics-affecting gameplay tuning though (top_speed_
## mps/accel_mps2/steer_rate_degrees_per_s all feed KartMotor directly), NOT
## visual-only data like SeatPoseTuning (contrast that class's own doc on
## why IT is exempt from CLAUDE.md rule 2's "the tuning loop must be
## provably live" requirement) -- so this class carries its own fingerprint()
## instead, the identical "canonical field=value lines, sorted, sha256"
## shape LevelMeta.fingerprint() already establishes for a resource that is
## ALSO loaded dynamically by path outside SECTION_NAMES. Editing a class
## .tres and reloading it moves ITS fingerprint, and (via composed_with())
## moves the resulting per-kart KartTuning values on the very next compose
## -- the same "edit, redeploy, hash moves" proof CLAUDE.md rule 2 asks for,
## just proven at this resource's own boundary rather than through
## TuningService's whole-catalog TUNING FINGERPRINT line.
@export var top_speed_mult: float
@export var accel_mult: float
@export var steer_rate_mult: float


func fingerprint() -> String:
	var canonical_lines := PackedStringArray()
	for property_info: Dictionary in get_property_list():
		var usage: int = property_info["usage"]
		if not usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			continue
		var property_name: StringName = property_info["name"]
		canonical_lines.append(
			String(property_name) + "=" + var_to_str(get(property_name))
		)
	canonical_lines.sort()
	return "\n".join(canonical_lines).sha256_text()
