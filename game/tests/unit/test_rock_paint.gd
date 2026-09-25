extends TestCase
## The painted stone (world/rock_paint.gd, assets/shaders/painted_rock.gdshader): every rock the
## forge makes is drawn with it wherever the game loads it -- the scatter's multimeshes and a
## POI's placed copies alike -- keeping the forge's own textures; wood in the rocks folder is left
## alone; and the ground correction each scattered rock carries in its tint's alpha comes back out
## as the shader reads it.

const GRANITE := "res://assets/models/rocks/briarwold_boulder_a/briarwold_boulder_a.glb"
const FUSED := "res://assets/models/rocks/cinderlea_boulder_a/cinderlea_boulder_a.glb"
const DRIFTWOOD_GLOB := "driftwood"


func _surfaces(packed: PackedScene) -> Array:
	var out: Array = []
	var state := packed.get_state()
	for i in state.get_node_count():
		for p in state.get_node_property_count(i):
			if state.get_node_property_name(i, p) == "mesh":
				var m: Variant = state.get_node_property_value(i, p)
				if m is Mesh:
					for s in (m as Mesh).get_surface_count():
						out.append((m as Mesh).surface_get_material(s))
	return out


func _painted(mat: Material) -> bool:
	return mat is ShaderMaterial and (mat as ShaderMaterial).shader == RockPaint.SHADER


func test_a_placed_rock_is_painted_with_its_own_textures() -> void:
	if not ResourceLoader.exists(GRANITE):
		return
	var packed := PoiKit.scene(GRANITE)
	var mats := _surfaces(packed)
	assert_gt(mats.size(), 1, "the boulder has its levels of detail")
	for m in mats:
		assert_true(_painted(m), "every surface of every level is the painted stone")
		assert_true((m as ShaderMaterial).get_shader_parameter("albedo_texture") is Texture2D,
			"the forge's albedo is kept")
	assert_eq(RockPaint.stone_of(GRANITE), "granite")
	var m0 := mats[0] as ShaderMaterial
	assert_near(float(m0.get_shader_parameter("speckle")), float(RockPaint.STONES["granite"]["speckle"]),
		0.0001, "the stone keeps its own grain")


func test_a_scattered_rock_is_painted_without_its_ladder() -> void:
	if not ResourceLoader.exists(FUSED):
		return
	var streamer := WorldStreamer.new()
	streamer.lod_enabled = false
	var mesh := streamer._mesh_for(FUSED, 0)
	streamer.free()
	assert_true(mesh != null, "the scatter finds the fused stone's mesh")
	for s in mesh.get_surface_count():
		assert_true(_painted(mesh.surface_get_material(s)), "the scatter's mesh is the painted stone")


func test_wood_in_the_rocks_folder_is_left_alone() -> void:
	var dir := DirAccess.open("res://assets/models/rocks")
	if dir == null:
		return
	var found := false
	for sub in dir.get_directories():
		if not sub.contains(DRIFTWOOD_GLOB):
			continue
		var path := "res://assets/models/rocks/%s/%s.glb" % [sub, sub]
		if not ResourceLoader.exists(path):
			continue
		found = true
		for m in _surfaces(PoiKit.scene(path)):
			assert_false(_painted(m), "%s is wood, not stone" % sub)
	assert_true(found, "a driftwood log is in the rocks folder to check")


func test_the_ground_correction_survives_the_tint() -> void:
	for corr in [-1.9, -0.6, 0.0, 0.35, 1.2, 1.95]:
		var c := Color("#8a7f70")
		c.a = RockPaint.corr_alpha(corr)
		# the row carries it as an 8-bit hex, as the scatter's tint
		var back := Color.from_string("#" + c.to_html(true), Color.WHITE)
		assert_near(RockPaint.alpha_corr(back.a), corr, 0.02, "a correction of %.2f m comes back" % corr)
		assert_near(back.r, c.r, 0.003, "the tint's colour is kept")
	assert_eq(RockPaint.alpha_corr(1.0), 0.0, "a white placed rock carries no correction")


func test_seat_rows_pads_a_bare_row_and_keeps_a_tint() -> void:
	var provider := World.terrain()
	if provider == null or not provider.has_runtime_maps():
		return
	var rows: Array = [[10.0, 5.0, -20.0], [30.0, 4.0, 12.0, 90.0, 1.3, "#806040"]]
	RockPaint.seat_rows(rows, provider)
	assert_eq((rows[0] as Array).size(), 6, "a bare row gains yaw, scale and a tint")
	assert_near(float(rows[0][4]), 1.0, 0.0001, "at scale one")
	var t := Color.from_string(str(rows[1][5]), Color.WHITE)
	assert_near(t.r, Color("#806040").r, 0.003, "the scatter's own tint is kept")
	var want := provider.get_height(30.0, 12.0) - provider.sample_height(30.0, 12.0)
	assert_near(RockPaint.alpha_corr(t.a), clampf(want, -2.0, 2.0), 0.02, "the correction is the ground's")


func test_the_near_black_stone_is_lifted_to_its_floor() -> void:
	if not ResourceLoader.exists(FUSED):
		return
	var m := _surfaces(PoiKit.scene(FUSED))[0] as ShaderMaterial
	var lift := float(m.get_shader_parameter("value_lift"))
	# measured from the source picture the forge wrote, as test_ground_albedo measures the ground
	# (its mean over the whole atlas, padding and all, so the floor is checked loosely)
	var mean := RockPaint.mean_of(FUSED, Color.WHITE)
	assert_true(mean.a > 0.0, "the fused stone is in the measured table")
	var lum := (mean.r + mean.g + mean.b) / 3.0
	assert_near(lum * lift, RockPaint.VALUE_FLOOR, 0.002, "drawn at %.3f (%.3f x %.2f), at its floor" % [lum * lift, lum, lift])
	var granite := _surfaces(PoiKit.scene(GRANITE))[0] as ShaderMaterial
	assert_near(float(granite.get_shader_parameter("value_lift")), 1.0, 0.0001, "a mid-grey granite keeps its own value")


func test_no_stone_draws_near_white() -> void:
	# Hearthvale's chalk slab, painted at 0.43 linear, read as white paper on a green slope
	var slab := "res://assets/models/rocks/hearthvale_cliff_slab_a/hearthvale_cliff_slab_a.glb"
	if not ResourceLoader.exists(slab):
		return
	var m := _surfaces(PoiKit.scene(slab))[0] as ShaderMaterial
	var mean := RockPaint.mean_of(slab, Color.WHITE)
	var lum := (mean.r + mean.g + mean.b) / 3.0
	assert_gt(lum, RockPaint.VALUE_CEILING, "the slab's picture is pale")
	assert_near(lum * float(m.get_shader_parameter("value_lift")), RockPaint.VALUE_CEILING, 0.002,
			"and it is drawn at the ceiling")


func test_every_rock_is_measured() -> void:
	var dir := DirAccess.open("res://assets/models/rocks")
	if dir == null:
		return
	var n := 0
	for sub in dir.get_directories():
		var png := "res://assets/models/rocks/%s/%s_albedo.png" % [sub, sub]
		if not FileAccess.file_exists(png):
			continue
		var mean := RockPaint.mean_of("res://assets/models/rocks/%s/%s.glb" % [sub, sub], Color.WHITE)
		assert_true(mean.a > 0.0, "%s is in world/rock_values.json (python3 tools/world/rock_values.py)" % sub)
		n += 1
	assert_gt(n, 30, "the rocks were found")


func test_a_stretched_ledge_row_keeps_its_bed() -> void:
	# a sea-cliff ledge bed (the world builder's 96e87959): lean, lean bearing and a fitted
	# [sx, sy, sz] scale after the tint. The ground line is taken at the row's own x and z, so the
	# bed's stretch cannot move it; and nothing after the tint is touched.
	var provider := World.terrain()
	if provider == null or not provider.has_runtime_maps():
		return
	var row: Array = [40.0, 3.0, 12.0, 30.0, 1.0, "#9a9080", 2.5, 140.0, [1.2, 1.5, 0.9]]
	RockPaint.seat_rows([row], provider)
	assert_eq(row.size(), 9, "the row keeps its nine fields")
	assert_near(float(row[6]), 2.5, 0.0001, "the lean is kept")
	assert_near(float(row[7]), 140.0, 0.0001, "and its bearing")
	assert_eq(row[8], [1.2, 1.5, 0.9], "and the bed's fitted scale")
	var want := provider.get_height(40.0, 12.0) - provider.sample_height(40.0, 12.0)
	var t := Color.from_string(str(row[5]), Color.WHITE)
	assert_near(RockPaint.alpha_corr(t.a), clampf(want, -2.0, 2.0), 0.02, "the ground line is the ground's at the row")
