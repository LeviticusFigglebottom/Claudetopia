extends TestCase
## The red deer (world/wildlife/deer_herds.gd, the forge's `deer_red`): herds at the woods' edges of
## the Briarwold, Hearthvale and Skerrow, the same herds on every visit, a stag with his rack among
## hinds without, heads up when you come near and off at a bound when you come nearer, and drawn
## as rigged deer near the eye and the far herd's two meshes past them.

const DEER := "res://assets/models/creatures/deer_red/deer_red.glb"
## A Briarwold cell of the built world (the streamer's, 256 m) with a long wood's edge in it.
const BRIAR := Vector2i(27, 17)

var _provider: TerrainProvider = null
var _nodes: Array[Node] = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()


func _world_maps() -> TerrainProvider:
	if _provider == null:
		_provider = TerrainProvider.new()
		_provider.load_data()
	return _provider


## Reads the cells round `cell` into TreeCover, as the streamer does when it loads them.
func _cover_round(cell: Vector2i) -> void:
	var p := _world_maps()
	TreeCover.set_grid(p.origin, float(p.manifest.get("cell_size_m", 256)))
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var c := cell + Vector2i(dx, dz)
			var path := "%s/cells/%d_%d.json" % [TerrainProvider.GENERATED, c.x, c.y]
			if not FileAccess.file_exists(path):
				continue
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if data is Dictionary:
				TreeCover.note(c, data)


func _centre(cell: Vector2i) -> Vector3:
	var p := _world_maps()
	var x := p.origin.x + (float(cell.x) + 0.5) * 256.0
	var z := p.origin.y + (float(cell.y) + 0.5) * 256.0
	return Vector3(x, p.get_height(x, z), z)


func _herds(density: float) -> DeerHerds:
	var d := DeerHerds.new()
	d.provider = _world_maps()
	d.density = density
	d.spooked_by = "test_deer_walker"
	_tree().root.add_child(d)
	_nodes.append(d)
	return d


func _walker(at: Vector3) -> Node3D:
	var n := Node3D.new()
	n.add_to_group("test_deer_walker")
	_tree().root.add_child(n)
	_nodes.append(n)
	n.global_position = at
	return n


func _run(d: DeerHerds, eye: Vector3, seconds: float, walker: Node3D = null, walk_to := Vector3.INF, mps := 0.0) -> void:
	var t := 0.0
	while t < seconds:
		if walker != null and walk_to != Vector3.INF:
			var p := walker.global_position
			walker.global_position = p.move_toward(walk_to, mps * 0.1)
		d.update(eye, 0.1)
		t += 0.1


func test_the_deer_is_rigged_with_a_wild_beasts_clips() -> void:
	assert_true(ResourceLoader.exists(DEER), "no red deer at %s" % DEER)
	var m := HorseModel.new()
	m.model_path = DEER
	m.antlers = false
	_tree().root.add_child(m)
	_nodes.append(m)
	assert_true(m.skeleton != null, "the deer has a skeleton")
	for c in ["Idle", "Graze", "Graze_Step", "Alert", "Walk", "Trot", "Run", "Hit", "Death", "Turn_L90", "Turn_R90"]:
		assert_true(m.has_clip(c), "the deer has %s" % c)
	assert_gt(m.gait_speed("Run"), 8.0, "the flight is a deer's bound")
	var names := {}
	for mi in m.meshes():
		names[String((mi as MeshInstance3D).name)] = mi
	for want in ["Deer_Body", "Deer_Body_LOD1", "Deer_Body_LOD2", "Deer_Antlers"]:
		assert_true(names.has(want), "a %s among %s" % [want, str(names.keys())])
	if names.has("Deer_Antlers"):
		assert_false((names["Deer_Antlers"] as MeshInstance3D).visible, "a hind has no antlers")
		m.set_antlers(true)
		assert_true((names["Deer_Antlers"] as MeshInstance3D).visible, "a stag has his")
		assert_gt((names["Deer_Antlers"] as MeshInstance3D).visibility_range_end, 100.0,
				"and keeps them past the body's first rung")
	for far in [DeerHerds.FAR_HIND, DeerHerds.FAR_STAG]:
		var mesh := Livestock.far_mesh(far)
		assert_true(mesh != null, "a far herd mesh at %s" % far)
		if mesh != null:
			var marks := Livestock.far_marks(mesh)
			assert_gt((marks["legs"] as Vector4).x, 0.3, "%s marks its legs" % far)
	var stag := Livestock.far_mesh(DeerHerds.FAR_STAG)
	if stag != null:
		var cols: PackedColorArray = stag.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var antler := 0
		for c in cols:
			if c.a < 0.75:
				antler += 1
		assert_gt(antler, 20, "the far stag's antlers are marked for their own colour")


func test_herds_are_at_the_woods_edge_in_the_briarwold() -> void:
	_cover_round(BRIAR)
	var d := _herds(4.0)
	var at := _centre(BRIAR)
	for i in 40:
		d.update(at, 0.05)
	assert_gt(d.herds.size(), 0, "a herd within reach of a Briarwold wood's edge")
	assert_gt(d.count(), 2, "of a few deer")
	for h in d.herds:
		var home: Vector3 = h["home"]
		assert_true(TreeCover.is_edge(home.x, home.z), "a herd grazes at a wood's edge")
		assert_true(REGION_OK.has(d.provider.region_id_at(home.x, home.z)), "in deer country")
		for deer in h["deer"]:
			var p: Vector3 = deer["pos"]
			assert_false(d.provider.is_water(p.x, p.z), "a deer on dry ground")
			assert_near(p.y, d.provider.get_height(p.x, p.z), 0.05, "standing on it")
	# the same herds on every visit
	var again := _herds(4.0)
	for i in 40:
		again.update(at, 0.05)
	assert_eq(again.count(), d.count(), "as many deer the second time")
	if again.herds.size() > 0 and d.herds.size() > 0:
		assert_true((again.herds[0]["home"] as Vector3).is_equal_approx(d.herds[0]["home"]), "in the same place")
	var none := _herds(0.0)
	for i in 40:
		none.update(at, 0.05)
	assert_eq(none.count(), 0, "none with the wildlife setting at 0")


const REGION_OK := {"core:region/briarwold": true, "core:region/hearthvale": true, "core:region/skerrow": true}


func test_a_herd_is_hinds_with_a_stag_or_stags_together() -> void:
	var d := _herds(1.0)
	var at := _centre(BRIAR)
	var seen_mixed := false
	for i in 30:
		var h := d.add_herd(at + Vector3(float(i) * 300.0, 0.0, 0.0), 5, false, 1000 + i)
		var stags := 0
		for deer in h["deer"]:
			stags += 1 if bool(deer["stag"]) else 0
		assert_true(stags <= 1, "a herd of hinds has one stag keeping it at most")
		if stags == 1:
			seen_mixed = true
	assert_true(seen_mixed, "most herds have their stag")
	var bach := d.add_herd(at, 3, true, 7)
	for deer in bach["deer"]:
		assert_true(bool(deer["stag"]), "stags together are all stags")


func test_they_look_up_then_bound_away_together() -> void:
	var d := _herds(1.0)
	var at := _centre(BRIAR)
	var h := d.add_herd(at, 5, false, 42)
	_run(d, at + Vector3(300.0, 0.0, 0.0), 2.0)
	assert_eq(int(h["state"]), DeerHerds.S.GRAZE, "grazing with nobody near")
	# somebody walking up: at 70 m the heads come up and they watch
	var w := _walker(at + Vector3(120.0, 0.0, 0.0))
	_run(d, at + Vector3(300.0, 0.0, 0.0), 12.0, w, at + Vector3(62.0, 0.0, 0.0), 1.5)
	assert_eq(int(h["state"]), DeerHerds.S.ALERT, "at 62 m they stand and watch")
	var facing := 0
	for deer in h["deer"]:
		var p: Vector3 = deer["pos"]
		var to := atan2(w.global_position.x - p.x, w.global_position.z - p.z)
		if absf(wrapf(to - float(deer["yaw"]), -PI, PI)) < 0.6:
			facing += 1
	assert_gt(facing, 2, "most turned to look (%d of 5)" % facing)
	# nearer, and they go: all of them, fast, away
	var start := {}
	for deer in h["deer"]:
		start[deer["id"]] = deer["pos"]
	_run(d, at, 2.0, w, at + Vector3(30.0, 0.0, 0.0), 1.5)
	assert_eq(int(h["state"]), DeerHerds.S.RUN, "at 30 m they are off")
	var fastest := 0.0
	for deer in h["deer"]:
		fastest = maxf(fastest, float(deer["speed"]))
	assert_gt(fastest, 8.0, "at a bound (%.1f m/s)" % fastest)
	_run(d, at, 30.0)
	for deer in h["deer"]:
		var p: Vector3 = deer["pos"]
		assert_gt(DeerHerds._flat(p, w.global_position), 120.0, "every deer well away from the walker")
		assert_gt(DeerHerds._flat(p, at), 120.0, "and from where it was grazing")
	assert_eq(int(h["state"]), DeerHerds.S.GRAZE, "and grazing again, somewhere else")


func test_someone_running_puts_them_up_sooner() -> void:
	var d := _herds(1.0)
	var at := _centre(BRIAR)
	var h := d.add_herd(at, 4, false, 9)
	var w := _walker(at + Vector3(100.0, 0.0, 0.0))
	_run(d, at + Vector3(300.0, 0.0, 0.0), 6.0, w, at + Vector3(50.0, 0.0, 0.0), 8.0)
	assert_eq(int(h["state"]), DeerHerds.S.RUN, "a runner at 50 m sends them off")


func test_near_deer_are_rigged_and_the_rest_are_two_draws() -> void:
	if not ResourceLoader.exists(DEER):
		assert_true(false, "no deer model")
		return
	var d := _herds(1.0)
	var at := _centre(BRIAR)
	d.add_herd(at, 6, false, 3)
	d.add_herd(at + Vector3(200.0, 0.0, 0.0), 6, false, 4)
	d.update(at + Vector3(0.0, 1.7, 25.0), 0.1)
	assert_true(d.live_count() > 0 and d.live_count() <= DeerHerds.MAX_LIVE, "the near herd is rigged deer (%d)" % d.live_count())
	var stags := 0
	for m in d.live_models():
		if (m as HorseModel).antlers:
			stags += 1
	assert_true(stags <= 1, "one stag among the near herd")
	var far := 0
	for kind in ["hind", "stag"]:
		var mm := d.multimesh_of(kind)
		assert_true(mm != null, "a far %s draw" % kind)
		if mm != null:
			far += mm.visible_instance_count
	assert_eq(far + d.live_count(), d.count(), "every deer drawn once, one way or the other")
	var draws := 0
	for c in d.get_children():
		if c is MultiMeshInstance3D:
			draws += 1
	assert_eq(draws, 2, "the far herds are two draws")
