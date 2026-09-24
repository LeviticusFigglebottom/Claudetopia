extends TestCase
## The horizon layer (world/horizon_layer.gd, docs/HORIZON.md): every landmark model and every
## tall point of interest has a stand-in past the streamed ring, the stand-in gives way to its
## cell in the frame the cell is built and comes back when it goes, the setting reaches its
## reach and the camera's far plane, and nothing on the skyline can be walked into or found.

var _holder: Node3D
var _layer: HorizonLayer
var _saved: Dictionary


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	_saved = Settings.data.duplicate(true)


func after_each() -> void:
	Settings.data = _saved.duplicate(true)
	Settings.apply_all()
	if _holder != null and is_instance_valid(_holder):
		_holder.queue_free()
	_holder = null
	_layer = null


func _pois() -> Array:
	var path := "%s/pois.json" % HorizonLayer.GENERATED
	if not FileAccess.file_exists(path):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Array else []


## A layer built from the built world's pois.json and the dressings WorldPois would raise.
func _built() -> HorizonLayer:
	var pois := _pois()
	if pois.is_empty():
		return null
	_holder = Node3D.new()
	_tree().root.add_child(_holder)
	_layer = HorizonLayer.new()
	_holder.add_child(_layer)
	_layer.build(pois, WorldPois.candidates(pois), [])
	return _layer


func test_every_landmark_model_and_tall_place_stands_on_the_skyline() -> void:
	var layer := _built()
	if layer == null:
		return
	var models := 0
	for e_v in _pois():
		var e: Dictionary = e_v
		var id := str(e.get("place_id", ""))
		if str(e.get("scene", "")) != "" and not (id in HorizonLayer.LANDMARK_LEAVE_OFF):
			models += 1
			assert_true(layer.proxy(id) != null, "%s's model is on the skyline" % id)
	assert_gt(layer.count("A"), models, "the Choir is a ring of colossi, not one")
	var choir := 0
	for p in layer.proxies:
		if p.id == "core:place/sunken_choir":
			choir += 1
	assert_eq(choir, 12, "all twelve of the Choir's colossi, where its cells stand them")
	for id in HorizonLayer.LANDMARK_LEAVE_OFF:
		assert_true(layer.proxy(id) == null, "%s is left off the skyline" % id)
	assert_gt(layer.count("B"), 0, "the tall places are there too")
	for p in layer.proxies:
		if p.tier == "B":
			var def := ContentDB.get_or_empty(p.id)
			assert_true(PoiDressing.kind_of(p.id, def) in HorizonLayer.TALL_KINDS, "%s is of a tall kind" % p.id)
			assert_true((p.node as PoiDressing).far, "and is its dressing's far silhouette")


func test_a_stand_in_is_a_picture_and_nothing_else() -> void:
	var layer := _built()
	if layer == null:
		return
	await _tree().process_frame
	for p in layer.proxies:
		assert_false(p.node.is_in_group(PoiDressing.GROUP), "%s is not counted as the place's dressing" % p.id)
		assert_eq(p.node.find_children("*", "CollisionObject3D", true, false).size(), 0,
				"%s cannot be walked into" % p.id)
		for g in p.node.find_children("*", "GeometryInstance3D", true, false):
			assert_eq((g as GeometryInstance3D).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
					"%s casts no shadow past the sun's reach" % p.id)
	# a landmark's stand-in is the model's far levels, which is what its cell draws out there
	var grand := layer.proxy("core:place/grandfather")
	if grand != null:
		var names: Array[String] = []
		for mi in grand.node.find_children("*", "MeshInstance3D", true, false):
			names.append(str(mi.name))
		assert_false(names.is_empty(), "the Grandfather stands on the skyline")
		for n in names:
			assert_true(LandmarkLod.level_of(n) > 0, "at its far levels, not its full mesh (%s)" % n)


func test_a_stand_in_gives_way_to_its_cell_and_comes_back() -> void:
	var layer := _built()
	if layer == null:
		return
	layer.setting = 1
	layer.apply_setting()
	var p: HorizonLayer.Proxy = layer.proxies[0]
	assert_true(p.node.visible, "shown while its cell is not built")
	EventBus.cell_loaded.emit(p.cell)
	assert_false(p.node.visible, "hidden in the frame its cell is built: never drawn twice")
	EventBus.cell_unloaded.emit(p.cell)
	assert_true(p.node.visible, "and back in the frame the cell goes: never a gap")


func test_view_distance_reaches_the_skyline_the_camera_and_the_ground() -> void:
	var layer := _built()
	if layer == null:
		return
	var want := [[2500.0, 1500.0], [4200.0, 2500.0], [6000.0, 4200.0]]
	var last_far := 0.0
	var last_mesh := 0
	for v in 3:
		Settings.set_value("graphics", "view_distance", v)
		assert_eq(layer.reach("A"), float(want[v][0]), "view distance %d: landmarks to %.0f m" % [v, want[v][0]])
		assert_eq(layer.reach("B"), float(want[v][1]), "and tall places to %.0f m" % want[v][1])
		var far := Graphics.camera_far(Settings.data["graphics"])
		assert_gt(far, last_far, "the camera sees further at each step")
		assert_true(far >= layer.reach("A") or v == 0, "and past the landmarks it draws")
		var mesh := Graphics.terrain_mesh_size(Settings.data["graphics"])
		assert_gt(mesh, last_mesh, "and the far ground is finer (%d vertices a ring)" % mesh)
		last_far = far
		last_mesh = mesh
		for p in layer.proxies:
			for g in p.node.find_children("*", "GeometryInstance3D", true, false):
				assert_true((g as GeometryInstance3D).visibility_range_end <= layer.reach(p.tier) + 0.01,
						"%s is drawn no further than its tier's reach" % p.id)
	for preset in Graphics.PRESET_ORDER:
		assert_true((Graphics.PRESETS[preset] as Dictionary).has("view_distance"), "%s sets the view distance" % preset)


## The playtest's colossi faded to half-transparent as the player walked up to them: the import
## gave every model 28 and 75 m level lines that dissolved each level in and out by itself.
func test_a_landmark_is_wholly_one_opaque_level_at_every_distance() -> void:
	var path := "res://assets/models/landmarks/cinderlea_choir_colossus_a/cinderlea_choir_colossus_a.glb"
	if not ResourceLoader.exists(path):
		return
	var inst := (load(path) as PackedScene).instantiate()
	var h := LandmarkLod.apply(inst)
	assert_gt(h, 40.0, "a colossus is %.0f m tall" % h)
	var levels: Array = []
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		assert_eq(g.visibility_range_fade_mode, GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED,
				"%s switches outright: no half-dithered level" % g.name)
		levels.append(g)
	assert_eq(levels.size(), 3, "three levels")
	for d in [2.0, 20.0, 60.0, 150.0, 300.0, 700.0, 3000.0]:
		var drawn := 0
		for g in levels:
			var mi := g as MeshInstance3D
			if d >= mi.visibility_range_begin and (mi.visibility_range_end == 0.0 or d < mi.visibility_range_end):
				drawn += 1
		assert_eq(drawn, 1, "at %.0f m exactly one level is drawn, whole" % d)
	# the full mesh holds to four heights, where a player at its foot is
	for g in levels:
		var mi := g as MeshInstance3D
		if LandmarkLod.level_of(mi.name) == 0:
			assert_true(mi.visibility_range_end >= 4.0 * h - 0.01, "the full colossus to %.0f m" % mi.visibility_range_end)
	inst.free()


func test_the_streamer_stands_landmarks_on_the_sized_levels() -> void:
	var path := "res://assets/models/landmarks/cinderlea_choir_colossus_a/cinderlea_choir_colossus_a.glb"
	if not ResourceLoader.exists(path):
		return
	_holder = Node3D.new()
	_tree().root.add_child(_holder)
	var streamer := WorldStreamer.new()
	_holder.add_child(streamer)
	var cell := Node3D.new()
	_holder.add_child(cell)
	streamer._build_scene(cell, {"scene": path, "pos": [10.0, 0.0, 10.0], "yaw": 0.0})
	var meshes := cell.find_children("*", "MeshInstance3D", true, false)
	assert_gt(meshes.size(), 0, "the colossus stands in its cell")
	for mi in meshes:
		assert_eq((mi as GeometryInstance3D).visibility_range_fade_mode, GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED,
				"%s in the cell switches outright" % mi.name)


func test_a_cells_scenes_are_read_without_its_scatter() -> void:
	# the colossi stand in the cells round the Choir; only their `scenes` line is read
	var choir := Vector3.ZERO
	for e_v in _pois():
		if str((e_v as Dictionary).get("place_id", "")) == "core:place/sunken_choir":
			choir = HorizonLayer._vec((e_v as Dictionary).get("pos"))
	if choir == Vector3.ZERO:
		return
	var layer := HorizonLayer.new()
	var scenes := layer._cell_scenes_round(choir)
	layer.free()
	assert_true(scenes.size() >= 12, "the cells round the Choir stand its colossi (%d scenes)" % scenes.size())
	for s in scenes:
		assert_true(str((s as Dictionary).get("scene", "")).begins_with("res://"), "each names its model")
