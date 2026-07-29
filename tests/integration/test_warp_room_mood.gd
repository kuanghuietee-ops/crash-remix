extends GutTest

## Warp Room 1 is the cold vault -- the inverse of Papu (review §6.5, Tier B4).
##
## The hub's whole composition is warm accents inside a cool room: the braziers
## are meant to be the only warm light, pointing the player at the door that
## matters, and the dresser's own comment says exactly that. They emitted
## nothing. Two plain MeshInstance3Ds sat where the light was supposed to be, so
## the room was uniformly steel-blue and the dais had no more pull than a wall.
##
## This is also the one scene where a couple of real lights are affordable: a
## 24 m box with about twenty meshes in it, nothing like the corridor levels.

const WARP_ROOM := "res://scenes/levels/warp_room_1.tscn"

## Lights live here, deliberately outside EnvironmentArt, which the dresser
## strips and rebuilds on every run.
const BRAZIER_LIGHTS_NODE := "BrazierLights"

## Where dress_island_cut.py puts the braziers flanking the boss dais. The
## lights have to be *at* them -- a warm pool somewhere else would read as an
## unexplained glow rather than as fire.
const BRAZIER_X := 3.4
const BRAZIER_Z := 6.4
const PLACEMENT_TOLERANCE_M := 0.6


func _root() -> Node:
	var packed := load(WARP_ROOM) as PackedScene
	assert_not_null(packed, "warp room must load")
	if packed == null:
		return null
	return packed.instantiate()


func test_the_room_stays_cool_while_its_accents_are_warm() -> void:
	var root := _root()
	if root == null:
		return
	var world := root.find_child("WorldEnvironment", true, false) as WorldEnvironment
	assert_not_null(world, "warp room must have a WorldEnvironment")
	if world != null and world.environment != null:
		var env := world.environment
		assert_gt(
			env.ambient_light_color.b,
			env.ambient_light_color.r,
			"the vault's ambient must stay cool; the braziers supply the warmth"
		)
		assert_gt(
			env.fog_light_color.b,
			env.fog_light_color.r,
			"fog must share the cool key, or the mist turns the room warm"
		)
	root.queue_free()


func test_floor_mist_is_present_and_low() -> void:
	var root := _root()
	if root == null:
		return
	var world := root.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if world != null and world.environment != null:
		var env := world.environment
		assert_true(env.fog_enabled, "the hub needs fog")
		# Height fog is what makes it read as mist pooling on the floor rather
		# than a haze filling the room. Verified against the engine's own shader:
		# sc_use_depth_fog() and sc_use_fog_height_density() are independent
		# specialisations, so this works alongside the depth fog already set.
		assert_gt(
			env.fog_height_density,
			0.0,
			"floor mist needs a non-zero height density or it does nothing"
		)
		assert_lt(
			env.fog_height,
			2.0,
			"mist must pool near the floor, not at head height"
		)
	root.queue_free()


func test_the_braziers_actually_emit() -> void:
	var root := _root()
	if root == null:
		return
	var holder := root.get_node_or_null(BRAZIER_LIGHTS_NODE)
	assert_not_null(holder, "warp room must carry a %s node" % BRAZIER_LIGHTS_NODE)
	if holder != null:
		var lights: Array[OmniLight3D] = []
		for child in holder.get_children():
			if child is OmniLight3D:
				lights.append(child as OmniLight3D)
		assert_eq(lights.size(), 2, "one light per brazier, flanking the dais")
		for light in lights:
			assert_gt(
				light.light_color.r,
				light.light_color.b,
				"%s must be firelight against the cool room" % light.name
			)
			assert_false(
				light.shadow_enabled,
				"%s must be shadowless; a shadowed omni re-renders casters six times"
				% light.name
			)
	root.queue_free()


func test_each_light_sits_in_a_brazier() -> void:
	var root := _root()
	if root == null:
		return
	var holder := root.get_node_or_null(BRAZIER_LIGHTS_NODE)
	if holder == null:
		return
	var seen_west := false
	var seen_east := false
	for child in holder.get_children():
		if not (child is OmniLight3D):
			continue
		var light := child as OmniLight3D
		assert_almost_eq(
			light.position.z,
			BRAZIER_Z,
			PLACEMENT_TOLERANCE_M,
			"%s is not at the dais braziers" % light.name
		)
		if absf(light.position.x + BRAZIER_X) <= PLACEMENT_TOLERANCE_M:
			seen_west = true
		if absf(light.position.x - BRAZIER_X) <= PLACEMENT_TOLERANCE_M:
			seen_east = true
		# In the bowl, not on the floor: the ember cup sits at y 1.18.
		assert_gt(light.position.y, 0.8, "%s should sit in the fire bowl" % light.name)
	assert_true(seen_west and seen_east, "both braziers must be lit")
	root.queue_free()


func test_the_lights_survive_a_dresser_rerun() -> void:
	# dress_island_cut.py rebuilds the warp room's EnvironmentArt subtree, so
	# anything authored inside it is disposable -- including the braziers these
	# lights belong to. The lights therefore hang off the room root instead.
	var root := _root()
	if root == null:
		return
	var environment_art := root.get_node_or_null("EnvironmentArt")
	if environment_art != null:
		assert_null(
			environment_art.get_node_or_null(BRAZIER_LIGHTS_NODE),
			"the lights must not live inside the regenerated subtree"
		)
	var holder := root.get_node_or_null(BRAZIER_LIGHTS_NODE)
	if holder != null:
		assert_eq(holder.get_parent().name, root.name, "lights hang off the room root")
	root.queue_free()
