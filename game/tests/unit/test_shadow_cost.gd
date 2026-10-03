extends TestCase
## The sun's shadow made cheaper in the wood (terrain-fidelity): a tree level with a coarser one
## below casts through that one (ScatterLod's shadow LOD), small dressing in a cell casts nothing
## (world/shadow_trim.gd), and the land casts from a coarse caster round the camera that never
## stands above the ground (world/shadow_ground.gd).

const TREE := "res://assets/models/trees/hearthvale_hawthorn_a/hearthvale_hawthorn_a.glb"

var _holder: Node3D


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	if _holder != null and is_instance_valid(_holder):
		_holder.queue_free()
	_holder = null


func _group(lad: ScatterLod.Ladder, distances: Array) -> ScatterLod.Group:
	_holder = Node3D.new()
	_tree().root.add_child(_holder)
	var rows: Array = []
	for d in distances:
		rows.append([float(d), 0.0, 0.0, 0.0, 1.0, "#ffffff"])
	return ScatterLod.make_group(lad, _holder, rows, false, true, 1000.0, TREE)


func _count(g: ScatterLod.Group, slot: String) -> int:
	var mmi: MultiMeshInstance3D = g.mmis.get(slot)
	return mmi.multimesh.instance_count if mmi != null else 0


func _cast(g: ScatterLod.Group, slot: String) -> int:
	return (g.mmis[slot] as GeometryInstance3D).cast_shadow


func test_the_full_tree_casts_through_its_lod1() -> void:
	if not ScatterLod.shadow_lod:
		return
	var lad := ScatterLod._build_ladder(TREE, load(TREE) as PackedScene)
	lad.set_bias(1.0)
	var nh := lad.near_fade * 0.5
	# close; in the band before the bark's line; in the band past it; at LOD1
	var g := _group(lad, [lad.near * 0.4, lad.near - nh * 0.5, lad.near + nh * 0.5, (lad.near + lad.far) * 0.5])
	g.update(Vector3.ZERO)
	var off := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var only := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	assert_eq(_cast(g, "solid0"), off, "the full bark casts nothing")
	assert_eq(_cast(g, "leaves0"), off, "nor the full crown")
	assert_eq(_cast(g, "shadow0_solid"), only, "LOD1's bark casts for it, unseen")
	assert_eq(_cast(g, "shadow0_leaves"), only, "and LOD1's cards")
	assert_eq(_cast(g, "solid1"), GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "LOD1 casts its own")
	assert_eq(_count(g, "shadow0_solid"), _count(g, "solid0"), "one bark shadow a full tree")
	assert_eq(_count(g, "shadow0_leaves"), _count(g, "leaves0"),
			"a crown casts whole wherever the full crown is drawn at all, through the band")
	assert_eq(_count(g, "shadow0_leaves"), 3)
	# the caster's cards never dissolve: LOD1's own cast dithered across the band
	var caster: Mesh = (g.mmis["shadow0_leaves"] as MultiMeshInstance3D).multimesh.mesh
	for i in caster.get_surface_count():
		var m := caster.surface_get_material(i) as ShaderMaterial
		if m != null:
			assert_eq(m.get_shader_parameter("lod_fade_in"), Vector2.ZERO)
			assert_eq(m.get_shader_parameter("lod_fade_out"), Vector2.ZERO)
	for m in lad.leaf_materials[1]:
		assert_ne((m as ShaderMaterial).get_shader_parameter("lod_fade_in"), Vector2.ZERO,
				"and the drawn LOD1 keeps its dissolve")


func _box(size: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * size
	mi.mesh = bm
	return mi


func test_small_things_in_a_cell_cast_no_shadow_and_large_ones_and_bodies_do() -> void:
	_holder = Node3D.new()
	_tree().root.add_child(_holder)
	var streamer := _holder
	var cell := Node3D.new()
	streamer.add_child(cell)
	var cup := _box(0.3)
	var wall := _box(3.0)
	var scaled := _box(0.4)
	scaled.scale = Vector3.ONE * 5.0
	var body := CharacterBody3D.new()
	var buckle := _box(0.1)
	body.add_child(buckle)
	for n in [cup, wall, scaled, body]:
		cell.add_child(n)
	var outside := _box(0.2)
	_holder.add_child(outside)
	var was := ShadowTrim.enabled
	ShadowTrim.enabled = true
	for n in [cup, wall, scaled, buckle, outside]:
		ShadowTrim.consider(n, streamer)
	ShadowTrim.enabled = was
	var on := GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	assert_eq(cup.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "a cup casts nothing")
	assert_eq(wall.cast_shadow, on, "a wall keeps its shadow")
	assert_eq(scaled.cast_shadow, on, "measured in the world, scale and all")
	assert_eq(buckle.cast_shadow, on, "what a body carries keeps its shadow")
	assert_eq(outside.cast_shadow, on, "nothing outside a cell is touched")


func test_the_land_casts_from_a_coarse_caster_that_never_stands_above_it() -> void:
	var provider := TerrainProvider.new()
	if not provider.load_data() or not provider.has_runtime_maps():
		provider.free()
		return
	var sg := ShadowGround.new(provider)
	_holder = Node3D.new()
	_tree().root.add_child(_holder)
	_holder.add_child(sg)
	sg.set_process(false)
	var eye := Vector3(2943.0, 220.0, 728.0)  # the Windthrow, in the Greatwood
	assert_eq(sg.update_around(eye, 0), 0, "every chunk built when unbudgeted")
	var side := ShadowGround.RADIUS * 2 + 1
	assert_eq(sg.chunk_count(), side * side)
	var grid := provider.runtime_grid()
	var heights := provider.runtime_heights()
	var sp := provider.runtime_spacing()
	var origin := provider.height_origin()
	var worst := -INF
	for c in sg.get_children():
		var mi := c as MeshInstance3D
		assert_eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "drawn only into the shadow")
		var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for v in verts:
			var gx := clampi(roundi((v.x - origin.x) / sp), 0, grid - 1)
			var gz := clampi(roundi((v.z - origin.y) / sp), 0, grid - 1)
			worst = maxf(worst, v.y - heights[gz * grid + gx])
	assert_true(worst <= -ShadowGround.SINK_M + 0.001, "never above its texel (worst %.2f m)" % worst)
	# the reach covers the sun's shadow distance, 260 m authored
	var reach := float(ShadowGround.RADIUS) * float(ShadowGround.CHUNK_TEXELS) * sp
	assert_true(reach >= 260.0, "the caster reaches %.0f m round the camera" % reach)
	# moving on lets go of the chunks left behind and budgets the new ones
	var left := sg.update_around(eye + Vector3(2000.0, 0.0, 0.0), 2)
	assert_true(left > 0, "a far move builds a few a frame")
	await _tree().process_frame
	provider.free()


func test_a_node_freed_before_its_turn_is_passed_over() -> void:
	# a place let go in the frame it rose: the deferred weighing is handed ids, not the freed node
	var streamer := Node3D.new()
	_tree().root.add_child(streamer)
	var cell := Node3D.new()
	streamer.add_child(cell)
	var mi := MeshInstance3D.new()
	cell.add_child(mi)
	var node_id := mi.get_instance_id()
	mi.free()
	ShadowTrim.consider_ids(node_id, streamer.get_instance_id())
	assert_true(true, "a freed node is passed over without an error")
	streamer.free()
