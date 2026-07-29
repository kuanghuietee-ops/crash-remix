extends GutTest

## Pins the Environment-layer rendering policy for the Island Cut and the hub.
##
## These are the invariants from the 2026-07-29 environment/rendering review
## (docs/audits/2026-07-29-environment-render-review.md). They exist because
## every one of them failed silently: a level with black ambient, no fog and
## four shadow splits still loads, still plays, and still passes every other
## suite in this repo. Nothing announces a dead render setting, so it gets an
## explicit test rather than a habit.
##
## The single most important assertion here is the ambient source. With
## ambient_light_source = AMBIENT_SOURCE_SKY and no Sky resource, Godot binds
## its default *black* radiance cubemap and mixes the authored ambient colour
## toward it by ambient_light_sky_contribution, which defaults to 1.0. The
## authored per-level ambient tints are therefore multiplied to zero and every
## surface is lit by the directional light alone. Verified against the engine:
## AMBIENT_SOURCE_COLOR = 2, AMBIENT_SOURCE_SKY = 3, sky contribution = 1.0.

## Every scene whose Environment must use COLOR ambient.
## scenes/game.tscn is here because phase05_gauntlet.tscn defines no Environment
## of its own and inherits this one -- so the gauntlet was lit by black ambient
## too, through a scene that is not itself a level.
const AMBIENT_SCENES := [
	"res://scenes/game.tscn",
	"res://scenes/debug/look_dev.tscn",
	"res://scenes/levels/wr1_n_sanity_beach.tscn",
	"res://scenes/levels/wr1_boulders.tscn",
	"res://scenes/levels/wr1_hog_wild.tscn",
	"res://scenes/levels/wr1_papu_papu.tscn",
	"res://scenes/levels/warp_room_1.tscn",
]

## Playable levels: these additionally carry fog, a shadow policy and camera
## planes. look_dev is deliberately excluded -- it is the turntable the operator
## judges individual assets in, and fogging it would grade the very asset under
## review.
const LEVEL_SCENES := [
	"res://scenes/levels/wr1_n_sanity_beach.tscn",
	"res://scenes/levels/wr1_boulders.tscn",
	"res://scenes/levels/wr1_hog_wild.tscn",
	"res://scenes/levels/wr1_papu_papu.tscn",
	"res://scenes/levels/warp_room_1.tscn",
]

## Shadows must not exceed 2 parallel splits. Godot's default is
## SHADOW_PARALLEL_4_SPLITS (2), which draws an object appearing in all four
## splits five times -- the largest per-frame GPU and thermal cost in the build,
## and spent on a look the spec (§9.4, all lighting baked) explicitly rejects.
const MAX_SHADOW_MODE := DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS

## Godot defaults directional_shadow_max_distance to 100 m. Nothing at this
## camera is legible that far out, so the texels are spent on nothing.
const MAX_SHADOW_DISTANCE_M := 60.0

## Godot defaults the camera to near 0.05 / far 4000. The near plane wrecks
## depth precision at the shelf/floor tuck; the far plane keeps geometry in
## passes it can never be seen in.
const MIN_CAMERA_NEAR_M := 0.2
const MAX_CAMERA_FAR_M := 400.0


func _instantiate(scene_path: String) -> Node:
	var packed := load(scene_path) as PackedScene
	assert_not_null(packed, "scene must load: %s" % scene_path)
	if packed == null:
		return null
	# instantiate() applies the authored property values without entering the
	# tree, so nothing here runs _ready or touches live state.
	return packed.instantiate()


func _environment_of(root: Node, scene_path: String) -> Environment:
	var world := root.find_child("WorldEnvironment", true, false) as WorldEnvironment
	assert_not_null(world, "%s must have a WorldEnvironment" % scene_path)
	if world == null:
		return null
	assert_not_null(world.environment, "%s WorldEnvironment must carry an Environment" % scene_path)
	return world.environment


func test_ambient_source_is_colour_not_sky() -> void:
	for scene_path in AMBIENT_SCENES:
		var root := _instantiate(scene_path)
		if root == null:
			continue
		var env := _environment_of(root, scene_path)
		if env != null:
			assert_eq(
				env.ambient_light_source,
				Environment.AMBIENT_SOURCE_COLOR,
				(
					"%s must source ambient from its authored colour; SKY with no Sky "
					+ "resource binds a black cubemap and zeroes the ambient"
				) % scene_path
			)
			assert_gt(
				env.ambient_light_energy,
				0.0,
				"%s must have non-zero ambient energy" % scene_path
			)
		root.queue_free()


func test_no_scene_relies_on_a_missing_sky() -> void:
	# Guards the other half of the same bug: if a future change puts the ambient
	# source back to SKY, it must come with an actual Sky resource.
	for scene_path in AMBIENT_SCENES:
		var root := _instantiate(scene_path)
		if root == null:
			continue
		var env := _environment_of(root, scene_path)
		if env != null and env.ambient_light_source == Environment.AMBIENT_SOURCE_SKY:
			assert_not_null(
				env.sky,
				"%s uses SKY ambient so it must define a Sky resource" % scene_path
			)
		root.queue_free()


func test_levels_have_depth_fog() -> void:
	for scene_path in LEVEL_SCENES:
		var root := _instantiate(scene_path)
		if root == null:
			continue
		var env := _environment_of(root, scene_path)
		if env != null:
			assert_true(env.fog_enabled, "%s must enable fog for depth cueing" % scene_path)
			assert_eq(
				env.fog_mode,
				Environment.FOG_MODE_DEPTH,
				(
					"%s must use depth fog (FOG_MODE_DEPTH = 1); mode 0 is "
					+ "exponential and ignores the authored begin/end distances"
				) % scene_path
			)
			assert_lt(
				env.fog_depth_begin,
				env.fog_depth_end,
				"%s fog must begin before it ends" % scene_path
			)
			assert_gt(env.fog_depth_end, 0.0, "%s fog needs a real end distance" % scene_path)
			# fog_aerial_perspective requires BG_SKY; with a flat colour
			# background it does nothing, so it must stay off until a sky exists.
			if env.background_mode != Environment.BG_SKY:
				assert_almost_eq(
					env.fog_aerial_perspective,
					0.0,
					0.001,
					"%s has no sky, so aerial perspective must stay 0" % scene_path
				)
		root.queue_free()


func test_levels_cap_directional_shadow_cost() -> void:
	for scene_path in LEVEL_SCENES:
		var root := _instantiate(scene_path)
		if root == null:
			continue
		var light := root.find_child("DirectionalLight3D", true, false) as DirectionalLight3D
		assert_not_null(light, "%s must have a DirectionalLight3D" % scene_path)
		if light != null:
			assert_lte(
				light.directional_shadow_mode,
				MAX_SHADOW_MODE,
				(
					"%s must use at most 2 parallel shadow splits; the default 4 "
					+ "draws casters up to five times"
				) % scene_path
			)
			assert_lte(
				light.directional_shadow_max_distance,
				MAX_SHADOW_DISTANCE_M,
				"%s must cap shadow distance at %s m" % [scene_path, MAX_SHADOW_DISTANCE_M]
			)
		root.queue_free()


func test_levels_set_camera_planes() -> void:
	for scene_path in LEVEL_SCENES:
		var root := _instantiate(scene_path)
		if root == null:
			continue
		var camera := root.find_child("Camera3D", true, false) as Camera3D
		assert_not_null(camera, "%s must have a Camera3D" % scene_path)
		if camera != null:
			assert_gte(
				camera.near,
				MIN_CAMERA_NEAR_M,
				"%s near plane must be lifted off the 0.05 default" % scene_path
			)
			assert_lte(
				camera.far,
				MAX_CAMERA_FAR_M,
				"%s far plane must be capped well under the 4000 default" % scene_path
			)
		root.queue_free()


func test_every_playable_level_is_covered_by_this_policy() -> void:
	# The policy is only worth having if it covers the whole game. Hog Wild was
	# briefly held out while a concurrent agent owned that file; this asserts
	# nothing is quietly left out again.
	var level_dir := "res://scenes/levels"
	var dir := DirAccess.open(level_dir)
	assert_not_null(dir, "level directory must exist")
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".tscn"):
			var scene_path := "%s/%s" % [level_dir, entry]
			# phase05_gauntlet is a traversal test bed, not a shipped level.
			if not entry.begins_with("phase05_"):
				assert_true(
					scene_path in LEVEL_SCENES,
					(
						"%s is a playable level but is not in LEVEL_SCENES, so no "
						+ "fog/shadow/camera policy is asserted for it"
					) % scene_path
				)
		entry = dir.get_next()
	dir.list_dir_end()
