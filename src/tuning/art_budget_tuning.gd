class_name ArtBudgetTuning
extends Resource

## Build-time art constraints from design doc §9.4. Deliberately outside
## TuningService.SECTION_NAMES: these are not values anyone tunes by thumb
## mid-session, and they must not move the gameplay tuning fingerprint.
## Follows the LevelMeta precedent for a standalone authored resource.

## Per-asset triangle caps. §9.4 specifies hero, enemy and boss bands. The
## operator approved the prop band after measuring the first real crate at
## 1,996 triangles; the rideable band before the first hog; and the kit_piece
## band after measuring the first beach/jungle kit at 100-1,564 across its 25
## pieces. Every directory in CATEGORY_BY_DIRECTORY now has a band, so the
## lint's fail-closed path is exercised by a synthetic budget in its tests
## rather than by a real category nobody has chosen a number for yet.
@export var hero_min_triangles: int = 0
@export var hero_max_triangles: int = 0
@export var enemy_min_triangles: int = 0
@export var enemy_max_triangles: int = 0
@export var boss_min_triangles: int = 0
@export var boss_max_triangles: int = 0
@export var prop_min_triangles: int = 0
@export var prop_max_triangles: int = 0
@export var kit_piece_min_triangles: int = 0
@export var kit_piece_max_triangles: int = 0
@export var rideable_min_triangles: int = 0
@export var rideable_max_triangles: int = 0

## Texture rules. §9.4: 1-2 x 2048 atlases + trim sheet per kit, ASTC.
@export var max_texture_dimension_px: int = 0

## Whole-frame budgets. These can only be measured in an assembled scene, so
## they belong to the on-device readout (src/debug/perf_readout.gd), never to a
## per-asset lint.
@export var frame_draw_calls_typical: int = 0
@export var frame_draw_calls_peak: int = 0
@export var frame_triangles_typical: int = 0
@export var frame_triangles_peak: int = 0

const UNBUDGETED := -1


func max_triangles_for(category: StringName) -> int:
	match category:
		&"hero":
			return hero_max_triangles
		&"enemy":
			return enemy_max_triangles
		&"boss":
			return boss_max_triangles
		&"prop":
			return prop_max_triangles
		&"kit_piece":
			return kit_piece_max_triangles
		&"rideable":
			return rideable_max_triangles
	return UNBUDGETED


func min_triangles_for(category: StringName) -> int:
	match category:
		&"hero":
			return hero_min_triangles
		&"enemy":
			return enemy_min_triangles
		&"boss":
			return boss_min_triangles
		&"prop":
			return prop_min_triangles
		&"kit_piece":
			return kit_piece_min_triangles
		&"rideable":
			return rideable_min_triangles
	return UNBUDGETED
