extends GutTest

## Papu Papu is the night level (review §6.4, Tier B3).
##
## The Island Cut shares one kit and one atlas, so per-level identity has to come
## from the Environment layer rather than new art. Papu is where that pays off
## most: flipping him to firelit night costs no meshes and no textures, uses the
## half of the palette nothing else touches (wood_post, thatch, cloth, ember,
## stone_carved), and turns the arena into a lit bowl in darkness -- which is
## what a boss room wants. It also gives his cyan/red tells sole ownership of
## those hues, instead of competing with a daylit warm-brown arena.

const PAPU_LEVEL := "res://scenes/levels/wr1_papu_papu.tscn"
const ARENA_SEGMENT := "res://scenes/segments/papu_arena.tscn"

## The lights live under this node, deliberately outside EnvironmentArt.
const TORCH_LIGHTS_NODE := "TorchLights"

## Terrace top surfaces, from papu_arena.tscn's floor slabs.
const TERRACE_COUNT := 3


func _instantiate(scene_path: String) -> Node:
	var packed := load(scene_path) as PackedScene
	assert_not_null(packed, "scene must load: %s" % scene_path)
	if packed == null:
		return null
	return packed.instantiate()


func _environment() -> Environment:
	var root := _instantiate(PAPU_LEVEL)
	if root == null:
		return null
	var world := root.find_child("WorldEnvironment", true, false) as WorldEnvironment
	var env: Environment = null
	if world != null:
		env = world.environment
	root.queue_free()
	return env


func test_the_sky_and_fog_read_as_night_not_dusk() -> void:
	var env := _environment()
	assert_not_null(env, "papu must have an Environment")
	if env == null:
		return
	var background := env.background_color
	assert_gt(
		background.b,
		background.r,
		"night background must be blue-dominant, not the old warm brown"
	)
	assert_lt(
		background.get_luminance(),
		0.15,
		"the boss room must actually be dark"
	)
	# Fog has to share the background's hue or geometry fades into a colour the
	# sky never shows, which reads as a grey wash rather than distance.
	assert_gt(
		env.fog_light_color.b,
		env.fog_light_color.r,
		"fog must share the night hue"
	)


func test_ambient_is_firelight_and_the_key_is_moonlight() -> void:
	var env := _environment()
	if env == null:
		return
	# The whole trick of the level: cool key, warm fill. Ambient stands in for
	# the bounce off the torches, so it is the warm half.
	assert_gt(
		env.ambient_light_color.r,
		env.ambient_light_color.b,
		"ambient must be firelit (warm), the counterweight to a cool key"
	)

	var root := _instantiate(PAPU_LEVEL)
	if root == null:
		return
	var light := root.find_child("DirectionalLight3D", true, false) as DirectionalLight3D
	assert_not_null(light, "papu must have a directional light")
	if light != null:
		assert_gt(
			light.light_color.b,
			light.light_color.r,
			"the key must be moonlight (cool), not the old warm sun"
		)
		assert_lte(
			light.light_energy,
			0.7,
			"a moon must not be as strong as the daylight key it replaced"
		)
	root.queue_free()


func test_each_terrace_gets_its_own_warm_pool() -> void:
	var root := _instantiate(ARENA_SEGMENT)
	if root == null:
		return
	var holder := root.get_node_or_null(TORCH_LIGHTS_NODE)
	assert_not_null(holder, "arena must carry a %s node" % TORCH_LIGHTS_NODE)
	if holder != null:
		var lights: Array[OmniLight3D] = []
		for child in holder.get_children():
			if child is OmniLight3D:
				lights.append(child as OmniLight3D)
		assert_eq(
			lights.size(),
			TERRACE_COUNT,
			"one warm pool per phase terrace"
		)
		for light in lights:
			assert_gt(
				light.light_color.r,
				light.light_color.b,
				"%s must be firelight, not moonlight" % light.name
			)
			# Every shadowed omni re-renders its casters six times into the cube
			# atlas. On a bandwidth-limited mobile GPU that is the one thing
			# these lights must never do.
			assert_false(
				light.shadow_enabled,
				"%s must be shadowless" % light.name
			)
			assert_gt(light.omni_range, 0.0, "%s needs a real range" % light.name)
		# The terraces climb, so the pools must climb with them rather than all
		# sitting at the entry floor.
		var heights: Array[float] = []
		for light in lights:
			heights.append(light.position.y)
		heights.sort()
		assert_true(
			heights[0] < heights[heights.size() - 1],
			"the pools must climb with the terraces"
		)
	root.queue_free()


func test_the_lights_survive_a_dresser_rerun() -> void:
	# scripts/dress_island_cut.py strips and regenerates the EnvironmentArt
	# subtree every run. Anything authored inside it is disposable, so the
	# lights must be parented somewhere else or they vanish the next time the
	# island is re-dressed.
	var root := _instantiate(ARENA_SEGMENT)
	if root == null:
		return
	var holder := root.get_node_or_null(TORCH_LIGHTS_NODE)
	if holder != null:
		assert_eq(
			holder.get_parent().name,
			root.name,
			(
				"%s must hang off the arena root, not EnvironmentArt, or the "
				+ "dresser deletes it"
			) % TORCH_LIGHTS_NODE
		)
	var environment_art := root.get_node_or_null("EnvironmentArt")
	if environment_art != null:
		assert_null(
			environment_art.get_node_or_null(TORCH_LIGHTS_NODE),
			"the lights must not be inside the regenerated subtree"
		)
	root.queue_free()
