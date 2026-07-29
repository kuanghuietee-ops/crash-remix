extends GutTest

## Spec §5.4.2: "Hard blob shadow, always -- constant size/opacity decal on every
## dynamic object, gameplay element not lighting."
##
## Only the player had one. Crab, skink, plant and Papu had none, so on a phone
## screen nothing but the player was visibly connected to the ground -- the exact
## depth ambiguity the blob shadow exists to kill, on the objects the player has
## to judge a jump or a spin against.
##
## This also gets ahead of the baked-lighting end state (review F4): once
## LightmapGI lands and the realtime directional shadow is switched off, a
## dynamic object with no blob casts nothing at all and floats outright.

const BLOB_NODE := "BlobShadow"
const BLOB_SHADER := "res://assets/shaders/blob_shadow.gdshader"

## Every dynamic thing that must be grounded.
##
## The hog is deliberately NOT here, and this is the reasoning so it does not get
## "fixed" later: hog_mount.gd reparents HogVisual onto the player on mount and
## offsets it to (0, 1.07, 0), which shares the player's x/z exactly. A blob
## targeting the hog would therefore raycast to the same ground point as the
## player's own blob for the whole level -- two coincident quads, doubled alpha
## and z-fighting, which is worse than the one blob already there. Unmounted, the
## hog is parked scenery. If the mounted silhouette needs more ground contact the
## answer is to widen the *player's* blob while mounted, not to add a second one.
const GROUNDED_SCENES := [
	"res://scenes/player/player.tscn",
	"res://scenes/enemies/crab.tscn",
	"res://scenes/enemies/skink.tscn",
	"res://scenes/enemies/plant.tscn",
]

## Papu lives in his level rather than a prefab, so he is checked by path.
const PAPU_LEVEL := "res://scenes/levels/wr1_papu_papu.tscn"
const PAPU_BLOB_PATH := "PapuArena/PapuVisual/BlobShadow"


func _blob_of(scene_path: String) -> Node3D:
	var packed := load(scene_path) as PackedScene
	assert_not_null(packed, "scene must load: %s" % scene_path)
	if packed == null:
		return null
	var root := packed.instantiate()
	var blob := root.find_child(BLOB_NODE, true, false) as Node3D
	# The caller owns the root; hand back the blob still parented to it so the
	# mesh child is reachable, then free through the root.
	if blob == null:
		root.queue_free()
	return blob


func test_every_dynamic_object_carries_a_blob_shadow() -> void:
	for scene_path in GROUNDED_SCENES:
		var blob := _blob_of(scene_path)
		assert_not_null(
			blob,
			"%s must carry a %s node (spec §5.4.2)" % [scene_path, BLOB_NODE]
		)
		if blob != null:
			blob.get_parent().queue_free()


func test_blob_shadows_use_the_shared_shader_not_a_copy() -> void:
	for scene_path in GROUNDED_SCENES:
		var blob := _blob_of(scene_path)
		if blob == null:
			continue
		var mesh_instance := blob.get_node_or_null("MeshInstance3D") as MeshInstance3D
		assert_not_null(mesh_instance, "%s blob needs a MeshInstance3D" % scene_path)
		if mesh_instance != null:
			var material := mesh_instance.material_override as ShaderMaterial
			assert_not_null(
				material,
				"%s blob must use a ShaderMaterial override" % scene_path
			)
			if material != null and material.shader != null:
				assert_eq(
					material.shader.resource_path,
					BLOB_SHADER,
					"%s must reuse the shared blob shader" % scene_path
				)
			assert_eq(
				mesh_instance.cast_shadow,
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"%s blob must not itself cast a shadow" % scene_path
			)
		blob.get_parent().queue_free()


func test_enemy_blob_shadows_are_driven_by_the_shared_script() -> void:
	# A blob that no one configures never sizes itself from DepthTuning and
	# never raycasts -- it would sit frozen at the origin. The script is what
	# makes it follow the ground, so its presence is the wiring's fingerprint.
	for scene_path in GROUNDED_SCENES:
		var blob := _blob_of(scene_path)
		if blob == null:
			continue
		assert_true(
			blob.get_script() != null,
			"%s blob must carry the BlobShadow script" % scene_path
		)
		if blob.get_script() != null:
			assert_true(
				blob.has_method("configure"),
				"%s blob must expose configure()" % scene_path
			)
		blob.get_parent().queue_free()


func test_papu_is_grounded_on_his_moving_pivot() -> void:
	var packed := load(PAPU_LEVEL) as PackedScene
	assert_not_null(packed, "papu level must load")
	if packed == null:
		return
	var root := packed.instantiate()
	var blob := root.get_node_or_null(PAPU_BLOB_PATH)
	assert_not_null(blob, "Papu must carry a blob shadow at %s" % PAPU_BLOB_PATH)
	if blob != null:
		# The parent is what the visual driver drives; a blob hung off the
		# static arena node would never follow him across the terraces.
		assert_eq(
			blob.get_parent().name,
			StringName("PapuVisual"),
			"Papu's blob must hang off the pivot the visual driver moves"
		)
	root.queue_free()


func test_the_hog_does_not_get_a_second_coincident_blob() -> void:
	# Pins the decision above. If someone adds a blob under HogVisual, the
	# mounted player carries two overlapping shadow quads for the whole level.
	var packed := load("res://scenes/levels/wr1_hog_wild.tscn") as PackedScene
	assert_not_null(packed, "hog wild must load")
	if packed == null:
		return
	var root := packed.instantiate()
	var hog_visual := root.get_node_or_null("HogRide/HogVisual")
	assert_not_null(hog_visual, "hog visual must exist")
	if hog_visual != null:
		assert_null(
			hog_visual.get_node_or_null(BLOB_NODE),
			(
				"the hog must not carry its own blob: mounted it shares the "
				+ "player's x/z, so the two quads would coincide"
			)
		)
	root.queue_free()
