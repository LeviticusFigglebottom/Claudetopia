extends TestCase
## Level of detail per tree (world/scatter_lod.gd): each instance drawn at the level its own
## distance asks for, the canopy dissolving between levels over a band written into its
## materials, the bark switching outright with a little hysteresis, the bias moving every line,
## and nothing drawn twice outside a band or not at all inside one.

const TREE := "res://assets/models/trees/hearthvale_hawthorn_a/hearthvale_hawthorn_a.glb"

var _holder: Node3D


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	if _holder != null and is_instance_valid(_holder):
		_holder.queue_free()
	_holder = null


func _ladder() -> ScatterLod.Ladder:
	var lad := ScatterLod._build_ladder(TREE, load(TREE) as PackedScene)
	if lad != null:
		lad.set_bias(1.0)
	return lad


## A group of hawthorns strung out along +x from an eye at the origin, one per distance.
func _group(lad: ScatterLod.Ladder, distances: Array) -> ScatterLod.Group:
	_holder = Node3D.new()
	_tree().root.add_child(_holder)
	var rows: Array = []
	for d in distances:
		rows.append([float(d), 0.0, 0.0, 0.0, 1.0, "#ffffff"])
	return ScatterLod.make_group(lad, _holder, rows, false, true, 1000.0, TREE)


func _count(g: ScatterLod.Group, slot: String) -> int:
	var mmi: MultiMeshInstance3D = g.mmis.get(slot)
	return mmi.multimesh.instance_count if mmi != null and mmi.visible else 0


func test_the_hawthorn_has_three_levels_and_its_picture() -> void:
	var lad := _ladder()
	assert_true(lad != null, "a tree with a LOD1 is drawn down a ladder")
	if lad == null:
		return
	assert_eq(lad.levels.size(), 2, "full mesh and LOD1")
	assert_true(lad.has_impostor(), "and the forge's impostor past them")
	assert_true(lad.levels[0]["solid"] != null and lad.levels[0]["leaves"] != null,
			"LOD0 split into bark and canopy")
	var h := float(ScatterLod._meta(TREE)["bounds"]["height"])
	assert_near(lad.near, maxf(ScatterLod.NEAR_MIN, ScatterLod.NEAR_PER_METRE * h), 0.001)
	assert_near(lad.far, maxf(ScatterLod.FAR_MIN, ScatterLod.FAR_PER_METRE * h), 0.001)


func test_the_dissolve_bands_are_written_into_each_levels_materials() -> void:
	var lad := _ladder()
	var near_band := Vector2(lad.near - lad.near_fade * 0.5, lad.near + lad.near_fade * 0.5)
	var far_band := Vector2(lad.far - lad.far_fade * 0.5, lad.far + lad.far_fade * 0.5)
	for m in lad.leaf_materials[0]:
		assert_eq((m as ShaderMaterial).get_shader_parameter("lod_fade_out"), near_band, "LOD0 leaves out")
	for m in lad.leaf_materials[1]:
		assert_eq((m as ShaderMaterial).get_shader_parameter("lod_fade_in"), near_band, "LOD1 leaves in")
		assert_eq((m as ShaderMaterial).get_shader_parameter("lod_fade_out"), far_band, "and out")
	assert_eq(lad.impostor_material.get_shader_parameter("lod_fade_in"), far_band, "the picture in")
	# each level's materials are its own: a band set on one is not set on another
	assert_ne(lad.leaf_materials[0][0], lad.leaf_materials[1][0])


func test_each_tree_is_drawn_at_its_own_level() -> void:
	var lad := _ladder()
	var close := lad.near * 0.5
	var mid := (lad.near + lad.far) * 0.5
	var far := lad.far * 2.0
	var g := _group(lad, [close, mid, far])
	g.update(Vector3.ZERO)
	assert_eq(_count(g, "solid0"), 1, "the near tree's bark at full detail")
	assert_eq(_count(g, "leaves0"), 1, "and its canopy")
	assert_eq(_count(g, "solid1"), 1, "the middle tree at LOD1")
	assert_eq(_count(g, "leaves1"), 1)
	assert_eq(_count(g, "impostor"), 1, "the far tree as its picture")
	assert_eq(g.level_of[0], 0)
	assert_eq(g.level_of[1], 1)
	assert_eq(g.level_of[2], 2)


func test_inside_a_band_a_tree_is_in_both_levels_and_outside_in_one() -> void:
	var lad := _ladder()
	var g := _group(lad, [lad.far])
	g.update(Vector3.ZERO)
	assert_eq(_count(g, "leaves1"), 1, "the mid canopy still dissolving out at the far line")
	assert_eq(_count(g, "impostor"), 1, "while the picture dissolves in")
	g.update(Vector3(-lad.far, 0.0, 0.0))
	assert_eq(_count(g, "leaves1"), 0, "past the band only the picture")
	assert_eq(_count(g, "impostor"), 1)


func test_walking_toward_a_tree_brings_it_back_to_full_detail() -> void:
	var lad := _ladder()
	var g := _group(lad, [lad.far * 3.0])
	g.update(Vector3.ZERO)
	assert_eq(g.level_of[0], 2, "far away, a picture")
	g.update(Vector3(lad.far * 3.0 - 5.0, 0.0, 0.0))
	assert_eq(g.level_of[0], 0, "five metres off, the full tree")
	assert_eq(_count(g, "solid0"), 1)
	assert_eq(_count(g, "impostor"), 0)


func test_the_bark_does_not_flap_at_its_line() -> void:
	var lad := _ladder()
	var g := _group(lad, [lad.near + ScatterLod.HYSTERESIS * 0.5])
	g.update(Vector3.ZERO)
	var first := g.level_of[0]
	for i in 6:
		g.update(Vector3(0.0, 0.0, 0.1 * float(i % 2)))
		assert_eq(g.level_of[0], first, "inside the hysteresis the level stays put")


func test_the_bias_moves_every_line() -> void:
	var lad := _ladder()
	var near := lad.near
	var far := lad.far
	lad.set_bias(2.0)
	assert_near(lad.near, near * 2.0, 0.001)
	assert_near(lad.far, far * 2.0, 0.001)
	var g := _group(lad, [near * 1.5])
	g.update(Vector3.ZERO)
	assert_eq(g.level_of[0], 0, "at twice the bias a tree at one and a half lines is still whole")


func test_the_far_ring_is_all_pictures_and_never_resorted() -> void:
	var lad := _ladder()
	_holder = Node3D.new()
	_tree().root.add_child(_holder)
	var rows := [[500.0, 0.0, 0.0, 0.0, 1.0, "#ffffff"], [600.0, 0.0, 0.0, 0.0, 1.0, "#ffffff"]]
	var g := ScatterLod.make_group(lad, _holder, rows, true, false, 920.0, TREE)
	g.fill_far()
	assert_eq(_count(g, "impostor"), 2)
	assert_false(g.mmis.has("solid0"), "no mesh levels built for the far ring")
	assert_false(g.wants_update(Vector3(490.0, 0.0, 0.0)), "and nothing to sort as the eye moves")
	assert_eq((g.mmis["impostor"] as GeometryInstance3D).cast_shadow,
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "far ring casts no shadow, as before")


func test_the_streamer_draws_trees_down_the_ladder_and_counts_each_once() -> void:
	_holder = Node3D.new()
	_tree().root.add_child(_holder)
	var streamer := WorldStreamer.new()
	_holder.add_child(streamer)
	var eye := Node3D.new()
	_holder.add_child(eye)
	eye.position = Vector3(128.0, 0.0, 128.0)
	streamer.target = eye
	var lad := _ladder()
	var rows: Array = []
	for d in [5.0, lad.near, lad.far, 200.0]:
		rows.append([128.0 + d, 0.0, 128.0, 0.0, 1.0, "#ffffff"])
	streamer._build_cell(Vector2i(16, 16), 0, {"instances": {TREE: rows}})
	var cell: Node3D = streamer._loaded[Vector2i(16, 16)]
	var lod_nodes := 0
	for c in cell.get_children():
		if c.has_meta("lod_group"):
			lod_nodes += 1
			assert_eq(str(c.get_meta("asset_path")), TREE, "attribution can still name the asset")
	assert_gt(lod_nodes, 2, "the cell's hawthorns are level MultiMeshes, not one")
	assert_eq(streamer.instance_count(), 4, "four trees, however many levels they straddle")
	assert_true(streamer.lods_settled(), "sorted for the eye as they were built")
	streamer._unload(Vector2i(16, 16))
	assert_eq(streamer._lod_groups.size(), 0, "unloading a cell lets its groups go")


## The coarse ground (FallbackTerrain) sets a cell's scatter down through its MultiMeshes as the
## cell arrives, and a group's levels are refilled from its own rows whenever the eye moves: set
## down only in the buffers, the trees went back up to the 2 m ground at the next re-sort.
func test_trees_set_down_on_the_coarse_ground_stay_down_as_the_eye_moves() -> void:
	var provider := TerrainProvider.new()
	if not provider.load_data():
		provider.free()
		return
	var ground := Node3D.new()
	provider.bind_fallback(ground)
	_holder = Node3D.new()
	_tree().root.add_child(_holder)
	var streamer := WorldStreamer.new()
	_holder.add_child(streamer)
	var eye := Node3D.new()
	_holder.add_child(eye)
	eye.position = Vector3(128.0, 0.0, 128.0)
	streamer.target = eye
	var lad := _ladder()
	# placed a hundred metres up, as if on some other ground, and strung out through every level
	var rows: Array = []
	for d in [5.0, lad.near, lad.far, 200.0]:
		rows.append([128.0 + d, 100.0, 128.0, 0.0, 1.0, "#ffffff"])
	streamer._build_cell(Vector2i(16, 16), 0, {"instances": {TREE: rows}})
	var cell: Node3D = streamer._loaded[Vector2i(16, 16)]
	assert_eq(streamer.set_lod_groups_down(cell, provider), 4, "every tree of the cell's groups")
	var g: ScatterLod.Group = streamer._lod_groups[0]
	var lowest := INF
	for i in g.count():
		var want := provider.get_height(g.positions[i].x, g.positions[i].z)
		assert_near(g.positions[i].y, want, 0.001, "tree %d stands on the coarse ground" % i)
		lowest = minf(lowest, want)
	assert_near(g.box.position.y, lowest, 0.001, "and the group's box came down with it")
	# the eye walks out past the picture line and back: every re-sort refills the levels from the
	# rows, and the rows are what was set down
	for e in [Vector3(128.0 + lad.far, 0.0, 128.0), Vector3(128.0, 0.0, 128.0)]:
		g.update(e)
		for i in g.count():
			assert_near(g.rows[i * ScatterLod.STRIDE + 7], g.positions[i].y - cell.position.y, 0.001,
					"tree %d is still drawn on the coarse ground after a re-sort" % i)
	streamer._unload(Vector2i(16, 16))
	ground.free()
	provider.free()


func test_a_trees_picture_takes_its_measured_gain_and_cut() -> void:
	var oak := "res://assets/models/trees/hearthvale_oak_a/hearthvale_oak_a.glb"
	var saved: Variant = ScatterLod._calibration
	ScatterLod._calibration = {"hearthvale_hawthorn_a": {
		Graphics.renderer(): {"gain": [1.2, 1.1, 1.3], "alpha_scissor": 0.4}}}
	var lad := ScatterLod._build_ladder(TREE, load(TREE) as PackedScene)
	var other := ScatterLod._build_ladder(oak, load(oak) as PackedScene)
	ScatterLod._calibration = saved
	var tint: Color = lad.impostor_material.get_shader_parameter("tint")
	assert_near(tint.r, 1.2, 0.001, "the measured gain, red")
	assert_near(tint.b, 1.3, 0.001, "and blue")
	assert_near(float(lad.impostor_material.get_shader_parameter("alpha_scissor")), 0.4, 0.001)
	var plain: Variant = other.impostor_material.get_shader_parameter("tint")
	assert_true(plain == null or (plain as Color).is_equal_approx(Color.WHITE),
			"a tree with no measurement keeps the shader's own")


func test_the_calibration_file_names_only_trees_that_exist() -> void:
	var cal := ScatterLod.calibration()
	for tree_name: String in cal:
		var path := "res://assets/models/trees/%s/%s.glb" % [tree_name, tree_name]
		assert_true(ResourceLoader.exists(path), "%s in the calibration is a tree the forge ships" % tree_name)
		for r: String in cal[tree_name]:
			assert_true(r in [Graphics.RENDERER_COMPATIBILITY, Graphics.RENDERER_FORWARD_PLUS],
					"%s measured on a renderer the game has (%s)" % [tree_name, r])
			var gain: Array = (cal[tree_name][r] as Dictionary).get("gain", [])
			assert_eq(gain.size(), 3, "%s on %s has a gain per channel" % [tree_name, r])
	# a renderer with no measurement of its own takes Compatibility's
	if cal.has("hearthvale_oak_a") and not (cal["hearthvale_oak_a"] as Dictionary).has(Graphics.RENDERER_FORWARD_PLUS):
		assert_eq(ScatterLod.calibration_for("hearthvale_oak_a", Graphics.RENDERER_FORWARD_PLUS),
				cal["hearthvale_oak_a"][Graphics.RENDERER_COMPATIBILITY])
