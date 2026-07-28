extends GutTest

## Proves the beach kit's textures actually reach the meshes the segments use.
##
## This suite exists because the failure it guards against is invisible: the
## .glb files deliberately carry no texture, so if the post-import script stops
## running, every piece imports plain white, the lints still pass, the level
## still loads, and nothing says a word. That is the dead-wiring this repo was
## built to make impossible, so it gets an explicit test rather than a habit.

const MESH_DIR := "res://assets/models/kits/mesh"
const ATLAS_PATH := "res://assets/textures/T_beach_kit_atlas.png"
const TRIM_PATH := "res://assets/textures/T_beach_kit_trim.png"

## The pure-rock pieces routed onto the strata trim sheet by
## scripts/blender/build_beach_env_kit.py. Everything else takes the atlas.
const TRIM_PIECES := ["rock_boulder_a", "rock_boulder_b", "rock_cluster_a"]

const EXPECTED_PIECE_COUNT := 25


func _piece_names() -> Array:
	var names: Array = []
	var dir := DirAccess.open(MESH_DIR)
	assert_not_null(dir, "kit mesh directory must exist at %s" % MESH_DIR)
	if dir == null:
		return names
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".res"):
			names.append(entry.get_basename())
		entry = dir.get_next()
	dir.list_dir_end()
	names.sort()
	return names


func test_every_kit_piece_has_an_extracted_mesh() -> void:
	var names := _piece_names()

	assert_eq(
		names.size(),
		EXPECTED_PIECE_COUNT,
		"the kit should have %d extracted meshes" % EXPECTED_PIECE_COUNT
	)


## One material slot per piece is the whole point of moving colour into UVs --
## it is what keeps the kit inside design doc 9.4's 120-draw-call frame budget.
## If a piece regains slots, the atlas has stopped doing its job.
func test_every_piece_is_a_single_surface() -> void:
	for name: String in _piece_names():
		var mesh: Mesh = load("%s/%s.res" % [MESH_DIR, name])

		assert_not_null(mesh, "%s must load" % name)
		if mesh == null:
			continue
		assert_eq(mesh.get_surface_count(), 1, "%s should have one surface" % name)


func test_every_piece_carries_uvs() -> void:
	for name: String in _piece_names():
		var mesh: ArrayMesh = load("%s/%s.res" % [MESH_DIR, name]) as ArrayMesh

		assert_not_null(mesh, "%s must load as an ArrayMesh" % name)
		if mesh == null:
			continue
		var format := mesh.surface_get_format(0)
		assert_true(
			(format & Mesh.ARRAY_FORMAT_TEX_UV) != 0,
			"%s has no UV0, so the atlas cannot be sampled on it" % name
		)


func test_every_piece_has_one_of_the_kit_textures_attached() -> void:
	for name: String in _piece_names():
		var mesh: Mesh = load("%s/%s.res" % [MESH_DIR, name])
		if mesh == null:
			continue
		var material := mesh.surface_get_material(0) as BaseMaterial3D

		assert_not_null(material, "%s surface 0 has no BaseMaterial3D" % name)
		if material == null:
			continue
		assert_not_null(
			material.albedo_texture,
			(
				"%s imported with no albedo texture -- the post-import script "
				+ "scripts/godot/apply_kit_atlas_material.gd did not run"
			) % name
		)


func test_rock_pieces_take_the_trim_sheet_and_the_rest_take_the_atlas() -> void:
	for name: String in _piece_names():
		var mesh: Mesh = load("%s/%s.res" % [MESH_DIR, name])
		if mesh == null:
			continue
		var material := mesh.surface_get_material(0) as BaseMaterial3D
		if material == null or material.albedo_texture == null:
			continue
		var expected: String = TRIM_PATH if TRIM_PIECES.has(name) else ATLAS_PATH

		assert_eq(
			material.albedo_texture.resource_path,
			expected,
			"%s is on the wrong kit texture" % name
		)


## White, because the atlas carries the colour. A tint here would multiply the
## palette in twice and quietly darken the whole level.
func test_the_kit_material_does_not_tint_the_atlas() -> void:
	for name: String in _piece_names():
		var mesh: Mesh = load("%s/%s.res" % [MESH_DIR, name])
		if mesh == null:
			continue
		var material := mesh.surface_get_material(0) as BaseMaterial3D
		if material == null:
			continue

		assert_eq(material.albedo_color, Color.WHITE, "%s tints its atlas" % name)


func test_both_kit_textures_exist_and_are_referenced_by_the_kit() -> void:
	assert_true(ResourceLoader.exists(ATLAS_PATH), "atlas must be committed")
	assert_true(ResourceLoader.exists(TRIM_PATH), "trim sheet must be committed")

	var used := {}
	for name: String in _piece_names():
		var mesh: Mesh = load("%s/%s.res" % [MESH_DIR, name])
		if mesh == null:
			continue
		var material := mesh.surface_get_material(0) as BaseMaterial3D
		if material != null and material.albedo_texture != null:
			used[material.albedo_texture.resource_path] = true

	# A committed texture nothing samples is a dead asset, and the trim sheet is
	# the one most at risk of becoming that.
	assert_true(used.has(ATLAS_PATH), "no piece samples the atlas")
	assert_true(used.has(TRIM_PATH), "no piece samples the trim sheet")
