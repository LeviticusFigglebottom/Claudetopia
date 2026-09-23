extends TestCase
## The coarse ground drawn from the runtime height map when Terrain3D cannot draw one.
##
## Three things have to be one surface for a body to stand on it: the mesh that is drawn, the
## HeightMapShape3D it collides with, and the height `TerrainProvider` answers with (which is what
## `snap_to_terrain`, spawning and every placement ask). These hold each against the others, and
## the forced fallback world against its own ground.

const WORLD_SCENE := "res://world/world.tscn"


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	WorldStatus.override = {}
	WorldStatus.force_fallback = false


func _ray_down(space: PhysicsDirectSpaceState3D, x: float, z: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 2000.0, z), Vector3(x, -500.0, z), 1 << 10)
	return space.intersect_ray(q)


# --- the mesh -------------------------------------------------------------------------------------

func test_the_chunk_mesh_is_a_grid_with_a_skirt_and_four_lods() -> void:
	var mesh := FallbackTerrain.chunk_mesh(4, 8.0)
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_eq(verts.size(), 5 * 5 + 4 * 5, "a 5 x 5 grid and a skirt vertex under each edge vertex")
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var skirt := 0
	for uv in uvs:
		skirt += 1 if uv.x > 0.5 else 0
	assert_eq(skirt, 20, "the skirt is marked for the shader to drop")
	var surface := RenderingServer.mesh_get_surface(mesh.get_rid(), 0)
	assert_eq((surface.get("lods", []) as Array).size(), FallbackTerrain.LODS.size(), "one index LOD per rung")


func test_the_mesh_splits_its_quads_the_way_the_heightfield_does_and_faces_up() -> void:
	var mesh := FallbackTerrain.chunk_mesh(2, 8.0)
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	# the first quad: (0,0) (1,0) (0,1) and (1,0) (1,1) (0,1) -- the diagonal from (1,0) to (0,1)
	assert_eq(verts[idx[0]], Vector3(0, 0, 0))
	assert_eq(verts[idx[1]], Vector3(8, 0, 0))
	assert_eq(verts[idx[2]], Vector3(0, 0, 8))
	assert_eq(verts[idx[5]], Vector3(0, 0, 8))
	assert_eq(verts[idx[4]], Vector3(8, 0, 8))
	# clockwise seen from above is Godot's front face: the right-hand normal points down
	var n := (verts[idx[1]] - verts[idx[0]]).cross(verts[idx[2]] - verts[idx[0]])
	assert_true(n.y < 0.0, "wound clockwise from above (right-hand normal %s)" % str(n))


func test_the_heightfield_splits_quads_where_triangle_height_says() -> void:
	# one twisted quad: a ridge along one diagonal and a trough along the other, so each split
	# puts the middle of the quad at a very different height
	var shape := HeightMapShape3D.new()
	shape.map_width = 2
	shape.map_depth = 2
	shape.map_data = PackedFloat32Array([0.0, 10.0, 10.0, 0.0])
	var body := StaticBody3D.new()
	body.collision_layer = 1 << 10
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	_tree().root.add_child(body)
	body.global_position = Vector3(1000.0, 0.0, 1000.0)
	await _tree().physics_frame
	await _tree().physics_frame
	var space := body.get_world_3d().direct_space_state
	# the shape spans x and z from -0.5 to 0.5 around its origin
	for p in [Vector2(0.3, 0.3), Vector2(0.7, 0.7), Vector2(0.5, 0.5), Vector2(0.2, 0.6), Vector2(0.9, 0.4)]:
		var tx: float = p.x
		var tz: float = p.y
		var hit := _ray_down(space, 1000.0 - 0.5 + tx, 1000.0 - 0.5 + tz)
		var want := TerrainProvider.triangle_height(0.0, 10.0, 10.0, 0.0, tx, tz)
		assert_true(not hit.is_empty(), "the ray finds the quad at %s" % str(p))
		if not hit.is_empty():
			assert_near((hit["position"] as Vector3).y, want, 0.01, "at %s the heightfield is where triangle_height puts it" % str(p))
	body.queue_free()
	await _tree().process_frame


# --- the world, drawn coarse -----------------------------------------------------------------------

func test_a_forced_fallback_world_stands_on_its_own_ground() -> void:
	if not FileAccess.file_exists("res://world/generated/world_manifest.json"):
		return
	WorldStatus.force_fallback = true
	var w := (load(WORLD_SCENE) as PackedScene).instantiate() as World
	_tree().root.add_child(w)
	await w.world_ready
	assert_eq(w.terrain_mode, "fallback")
	assert_eq(w.terrain_node, null, "Terrain3D is not loaded beside it")
	assert_true(w.fallback != null and w.fallback.chunks.size() == 256, "256 chunks of 512 m")
	assert_eq(w.provider.terrain_kind(), "fallback", "and the provider answers from it")
	await _tree().physics_frame
	await _tree().physics_frame
	var space := w.get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 8471
	var worst := 0.0
	for i in 40:
		var x := rng.randf_range(-3900.0, 3900.0)
		var z := rng.randf_range(-3900.0, 3900.0)
		var hit := _ray_down(space, x, z)
		assert_true(not hit.is_empty(), "there is ground at (%.0f, %.0f)" % [x, z])
		if hit.is_empty():
			continue
		worst = maxf(worst, absf((hit["position"] as Vector3).y - w.provider.get_height(x, z)))
	assert_true(worst < 0.05, "what the body collides with is what the provider answers (worst %.3f m)" % worst)
	var body: Node3D = w.get_node("PlayerSpawn").get("player")
	assert_true(body != null, "somebody is standing in it")
	if body != null:
		var under := _ray_down(space, body.global_position.x, body.global_position.z)
		assert_true(not under.is_empty() and absf((under["position"] as Vector3).y - body.global_position.y) < 1.0,
				"with the ground under their feet")
	_tree().root.remove_child(w)
	w.queue_free()
	await _tree().process_frame


func test_scatter_placed_on_the_full_ground_is_set_down_on_the_coarse_one() -> void:
	var provider := TerrainProvider.new()
	if not provider.load_data():
		provider.free()
		return
	var ground := Node3D.new()
	provider.bind_fallback(ground)
	var origin := Vector3(128.0, 0.0, -384.0)
	var spots := [Vector3(-40.0, 999.0, 12.0), Vector3(3.5, -50.0, -77.0), Vector3(100.0, 0.0, 100.0)]
	# a MultiMesh buffer as the engine lays it out: a row-major 3 x 4 transform, then the colour
	var stride := 16
	var buf := PackedFloat32Array()
	for i in 3:
		var t := Transform3D(Basis(Vector3.UP, 0.7 * i).scaled(Vector3.ONE * 1.3), spots[i])
		buf.append_array([t.basis.x.x, t.basis.y.x, t.basis.z.x, t.origin.x,
				t.basis.x.y, t.basis.y.y, t.basis.z.y, t.origin.y,
				t.basis.x.z, t.basis.y.z, t.basis.z.z, t.origin.z, 0.2, 0.4, 0.6, 1.0])
	var before := buf.duplicate()
	var after := FallbackTerrain.set_down(buf, stride, origin, provider)
	for i in 3:
		var o := i * stride
		var want := provider.get_height(spots[i].x + origin.x, spots[i].z + origin.z)
		assert_near(after[o + 7], want, 0.001, "instance %d is on the ground" % i)
		for k in stride:
			if k != 7:
				assert_eq(after[o + k], before[o + k], "and nothing else about it moved (float %d)" % k)
	# with a renderer that keeps instance data the MultiMesh itself is set down; the headless one
	# keeps none, and then the cell is left as it is rather than handed a buffer of the wrong size
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = 3
	for i in 3:
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, spots[i]))
	var cell := Node3D.new()
	cell.position = origin
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	cell.add_child(mmi)
	var kept := mm.buffer.size() == 3 * stride
	assert_eq(FallbackTerrain.reground(cell, provider), 3 if kept else 0)
	if kept:
		var t := mm.get_instance_transform(1)
		assert_near(t.origin.y, provider.get_height(spots[1].x + origin.x, spots[1].z + origin.z), 0.001)
	cell.free()
	ground.free()
	provider.free()


func test_a_runtime_height_is_read_where_its_texel_is_centred() -> void:
	var provider := TerrainProvider.new()
	if not provider.load_data():
		provider.free()
		return
	var hs := provider.height_origin()
	var n := provider.runtime_grid()
	var s := provider.runtime_spacing()
	var heights := provider.runtime_heights()
	for t in [Vector2i(300, 700), Vector2i(512, 512), Vector2i(10, 1000)]:
		var x := hs.x + float(t.x) * s
		var z := hs.y + float(t.y) * s
		assert_near(provider.sample_height(x, z), heights[t.y * n + t.x], 0.001,
				"texel %s answers at its own centre" % str(t))
	provider.free()
