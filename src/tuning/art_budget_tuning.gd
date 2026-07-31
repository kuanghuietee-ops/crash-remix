class_name ArtBudgetTuning
extends Resource

## Build-time art constraints from design doc §9.4. Deliberately outside
## TuningService.SECTION_NAMES: these are not values anyone tunes by thumb
## mid-session, and they must not move the gameplay tuning fingerprint.
## Follows the LevelMeta precedent for a standalone authored resource.

## Per-asset triangle caps. §9.4 specifies hero, enemy and boss bands. The
## operator approved the prop band after measuring the first real crate at
## 1,996 triangles; the kit_piece band after measuring the first beach/jungle
## kit at 100-1,564 across its 25 pieces; and 6,000-10,000 for rideables before
## the first hog. Every directory in CATEGORY_BY_DIRECTORY now has a band, so
## the lint's fail-closed path is exercised by a synthetic budget in its tests
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

## CTR R6 Task 3: a NEW category, deliberately separate from `rideable`
## (6,000-10,000 tris -- a creature mount, SK_hog). The kart is a stand-in
## tier vehicle chassis, explicitly authored low-poly (the design doc calls
## for "a few hundred triangles", replaced by the operator's art ladder
## later) -- reusing the rideable band would either fail the real kart
## outright (360 tris, an order of magnitude under 6,000) or force it to be
## padded with detail nobody asked for yet. 150-800 was chosen against the
## first real kart (scripts/blender/build_kart.py's own SM_kart.glb, measured
## 360 triangles): a genuine band around that number, not a knife's-edge
## ceiling, mirroring how the prop/kit_piece/rideable bands were each set
## from their own first real asset.
@export var kart_min_triangles: int = 0
@export var kart_max_triangles: int = 0

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
		&"kart":
			return kart_max_triangles
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
		&"kart":
			return kart_min_triangles
	return UNBUDGETED
