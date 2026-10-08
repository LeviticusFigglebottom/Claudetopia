extends TestCase
## The streamer's landmark collision. The forge's `*_col.glb` is instantiated to read its meshes
## and never enters the tree, so asking a mesh for its global transform there errors and returns
## identity: every trimesh shape landed at the landmark's origin, with a script error under it
## on every landmark load. The transform is composed from the local ones instead.


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## A collision scene the way the forge lays one out: a root, a transformed group, a mesh.
func _collision_scene(path: String) -> void:
	var root := Node3D.new()
	root.name = "Col"
	var group := Node3D.new()
	group.name = "Group"
	group.position = Vector3(10.0, 0.0, 0.0)
	group.rotation.y = PI * 0.5
	root.add_child(group)
	var mesh := MeshInstance3D.new()
	mesh.name = "Slab"
	mesh.mesh = BoxMesh.new()
	mesh.position = Vector3(0.0, 2.0, 0.0)
	group.add_child(mesh)
	group.owner = root
	mesh.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, path)
	root.free()


func test_transform_within_composes_the_chain_without_the_tree() -> void:
	var root := Node3D.new()
	var mid := Node3D.new()
	mid.position = Vector3(1.0, 0.0, 0.0)
	root.add_child(mid)
	var leaf := Node3D.new()
	leaf.position = Vector3(0.0, 3.0, 0.0)
	mid.add_child(leaf)
	var t := WorldStreamer._transform_within(leaf, root)
	assert_near(t.origin.x, 1.0, 0.001, "the parent's offset is carried")
	assert_near(t.origin.y, 3.0, 0.001, "the node's own offset is carried")
	root.free()


func test_landmark_collision_shapes_sit_where_the_col_scene_puts_them() -> void:
	var path := "user://test_landmark_col.tscn"
	_collision_scene(path)
	var streamer := WorldStreamer.new()
	var errors_before := Log.error_count
	var landmark := Node3D.new()
	_tree().root.add_child(landmark)
	streamer._add_collision(landmark, path)
	var body := landmark.get_node_or_null("Collision")
	assert_true(body != null, "a static body is put under the landmark")
	if body != null:
		var shapes := body.find_children("*", "CollisionShape3D", true, false)
		assert_eq(shapes.size(), 1, "one shape per mesh in the collision scene")
		if shapes.size() == 1:
			var origin: Vector3 = (shapes[0] as CollisionShape3D).transform.origin
			assert_near(origin.x, 10.0, 0.01, "the group's offset reaches the shape")
			assert_near(origin.y, 2.0, 0.01, "the mesh's own offset reaches the shape")
	assert_eq(Log.error_count, errors_before, "no script error while reading the col scene")
	landmark.queue_free()
	streamer.free()
	DirAccess.remove_absolute(path)
	await _tree().process_frame


## Every Briarwold flora asset's kind, by its own name: only the briars are bushes. The region's
## own name holds "briar", and once every herb of it (grass, fern, moss, foxglove) was taken for a
## bush, drawn to the bushes' 190 m and kept 30% in the far ring (HANDOFF §00000).
func test_every_briarwold_flora_asset_is_the_kind_its_own_name_says() -> void:
	var dir := "res://assets/models/flora"
	var seen := 0
	var bushes: Array = []
	for name in DirAccess.get_directories_at(dir):
		if not name.begins_with("briarwold_"):
			continue
		var path := "%s/%s/%s.glb" % [dir, name, name]
		var kind := WorldStreamer.asset_kind(path)
		seen += 1
		if kind == "bush":
			bushes.append(name)
		else:
			assert_eq(kind, "herb", "%s is a herb" % name)
		assert_eq(kind == "bush", name.begins_with("briarwold_briar_"), "%s: %s" % [name, kind])
	assert_gt(seen, 10, "the Briarwold flora is found (%d)" % seen)
	assert_eq(bushes.size(), 3, "the three briar vines are the bushes (%s)" % str(bushes))
	# the other regions' bushes still are, and a herb with no bush word is not
	assert_eq(WorldStreamer.asset_kind("res://assets/models/flora/skerrow_juniper_a/skerrow_juniper_a.glb"), "bush")
	assert_eq(WorldStreamer.asset_kind("res://assets/models/flora/hearthvale_hawthorn_bush_a/hearthvale_hawthorn_bush_a.glb"), "bush")
	assert_eq(WorldStreamer.asset_kind("res://assets/models/flora/briarwold_grass_clump_a/briarwold_grass_clump_a.glb"), "herb")
	assert_eq(WorldStreamer.asset_kind("res://assets/models/trees/briarwold_giant_oak_a/briarwold_giant_oak_a.glb"), "tree")
