extends GutTest

const ArtBudgetTuningType := preload("res://src/tuning/art_budget_tuning.gd")
const AUTHORED_PATH := "res://data/tuning/art_budget.tres"


func test_authored_budget_matches_the_design_doc_per_asset_caps() -> void:
	var budget: ArtBudgetTuning = load(AUTHORED_PATH)

	assert_not_null(budget, "art_budget.tres must load as an ArtBudgetTuning")
	assert_eq(budget.hero_min_triangles, 10000)
	assert_eq(budget.hero_max_triangles, 12000)
	assert_eq(budget.enemy_min_triangles, 3000)
	assert_eq(budget.enemy_max_triangles, 6000)
	assert_eq(budget.boss_min_triangles, 15000)
	assert_eq(budget.boss_max_triangles, 25000)
	assert_eq(budget.prop_min_triangles, 100)
	assert_eq(budget.prop_max_triangles, 2500)
	assert_eq(budget.rideable_min_triangles, 6000)
	assert_eq(budget.rideable_max_triangles, 10000)


func test_authored_budget_matches_the_design_doc_frame_budgets() -> void:
	var budget: ArtBudgetTuning = load(AUTHORED_PATH)

	assert_eq(budget.frame_draw_calls_typical, 120)
	assert_eq(budget.frame_draw_calls_peak, 180)
	assert_eq(budget.frame_triangles_typical, 150000)
	assert_eq(budget.frame_triangles_peak, 250000)
	assert_eq(budget.max_texture_dimension_px, 2048)


func test_lookup_returns_the_category_cap() -> void:
	var budget: ArtBudgetTuning = load(AUTHORED_PATH)

	assert_eq(budget.max_triangles_for(&"hero"), 12000)
	assert_eq(budget.min_triangles_for(&"enemy"), 3000)
	assert_eq(budget.max_triangles_for(&"boss"), 25000)
	assert_eq(budget.min_triangles_for(&"prop"), 100)
	assert_eq(budget.max_triangles_for(&"prop"), 2500)
	assert_eq(budget.min_triangles_for(&"rideable"), 6000)
	assert_eq(budget.max_triangles_for(&"rideable"), 10000)


## Kit pieces still have no operator-approved per-asset figure. They must
## report themselves as unbudgeted so the lint fails closed and asks rather
## than silently passing through a default nobody chose.
func test_categories_without_an_operator_budget_report_no_cap() -> void:
	var budget: ArtBudgetTuning = load(AUTHORED_PATH)

	assert_eq(budget.max_triangles_for(&"kit_piece"), -1)
	assert_eq(budget.max_triangles_for(&"not_a_category"), -1)
