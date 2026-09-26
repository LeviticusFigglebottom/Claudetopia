extends TestCase
## The ewe on WM_Quadruped_v1 (playtest 6: "the sheep appear disemboweled"). Livestock draws a
## kind the forge has rigged from its GLB: a MultiMesh of her standing body far off, and near the
## camera a live model that walks and grazes with her clips; the prop sheep are gone from it.

const EWE := "res://assets/models/creatures/sheep_ewe/sheep_ewe.glb"

var _nodes: Array[Node] = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()


func _ticks(n: int) -> void:
	for i in n:
		await _tree().process_frame


func test_the_ewe_is_rigged_with_her_clips() -> void:
	assert_true(ResourceLoader.exists(EWE), "no rigged ewe at %s" % EWE)
	var m := HorseModel.new()
	m.model_path = EWE
	_tree().root.add_child(m)
	_nodes.append(m)
	assert_true(m.skeleton != null, "the ewe has no skeleton")
	for c in ["Idle", "Graze", "Walk", "Trot", "Run", "Turn_L90", "Turn_R90"]:
		assert_true(m.has_clip(c), "the ewe has no %s" % c)
	var names: Array[String] = []
	for mi in m.meshes():
		names.append(String((mi as MeshInstance3D).name))
	for want in ["Sheep_Body", "Sheep_Body_LOD1", "Sheep_Body_LOD2"]:
		assert_true(names.has(want), "no %s among %s" % [want, str(names)])
	# closed underneath: the body's mesh has triangles facing down under the middle of the belly
	var body: MeshInstance3D = null
	for mi in m.meshes():
		if String((mi as MeshInstance3D).name) == "Sheep_Body":
			body = mi
	if body != null:
		var aabb := body.mesh.get_aabb()
		assert_true(aabb.size.y > 0.7 and aabb.size.y < 1.0, "the ewe stands %.2f m" % aabb.size.y)
		var faces := body.mesh.get_faces()
		var under := 0
		for i in range(0, faces.size(), 3):
			var a := faces[i]
			var b := faces[i + 1]
			var c := faces[i + 2]
			var mid := (a + b + c) / 3.0
			var n := (b - a).cross(c - a)
			if n.y < 0.0 and absf(mid.x) < 0.08 and absf(mid.z) < 0.15 and mid.y > 0.25:
				under += 1
		assert_true(under > 10, "only %d triangles close the belly: she can be seen through" % under)


func test_a_flock_near_the_camera_walks_and_grazes_on_its_rig() -> void:
	if not ResourceLoader.exists(EWE):
		return
	var cam := Camera3D.new()
	_tree().root.add_child(cam)
	_nodes.append(cam)
	cam.make_current()
	cam.global_position = Vector3(0.0, 2.0, 12.0)
	var flock := Livestock.new()
	flock.seed_with(4)
	var props := Livestock.paths_of("sheep")
	assert_true(not props.is_empty(), "no prop sheep to keep the old path with")
	flock.keep("sheep", props, Vector3.ZERO, 5.0, 5)
	_tree().root.add_child(flock)
	_nodes.append(flock)
	await _ticks(20)
	for b in flock.beasts:
		assert_eq(str(b["path"]), EWE, "a sheep is still the prop %s" % str(b["path"]))
	assert_eq(flock.live_count(), 5, "five ewes 12 m from the camera, %d drawn live" % flock.live_count())
	var clips: Dictionary = {}
	for i in 90:
		await _tree().process_frame
		for c in flock.get_children():
			if c is HorseModel:
				clips[(c as HorseModel).current_clip()] = true
	assert_true(clips.has("Walk") or clips.has("Graze") or clips.has("Idle"), "the live ewes played %s" % str(clips.keys()))
	# far off, nobody is live and the MultiMesh draws them all
	cam.global_position = Vector3(0.0, 2.0, 90.0)
	await _ticks(30)
	assert_eq(flock.live_count(), 0, "90 m off, %d ewes still live" % flock.live_count())


## Far off, a rigged kind is its forge LOD2 in the herd_far shader, one MultiMesh beside the near
## body's, drawn from where the near one stops out to the next hill, and posed: walking or grazing.
func test_a_flock_far_off_is_the_forge_lod2_posed_in_a_shader() -> void:
	if not ResourceLoader.exists(EWE) or not ResourceLoader.exists(str(Livestock.FAR["sheep"]["mesh"])):
		return
	var mesh := Livestock.far_mesh(str(Livestock.FAR["sheep"]["mesh"]))
	assert_true(mesh != null, "the ewe's far mesh loads")
	if mesh == null:
		return
	var marks := Livestock.far_marks(mesh)
	var legs: Vector4 = marks["legs"]
	for i in 4:
		assert_true(legs[i] > 0.15 and legs[i] < 0.6, "leg %d hinges at %.2f m" % [i, legs[i]])
	assert_gt((marks["neck"] as Vector3).z, 0.1, "the withers are forward of the middle")
	assert_true((marks["tail"] as Vector3).z < -0.1, "the tail is behind")
	var flock := Livestock.new()
	flock.seed_with(4)
	flock.keep("sheep", Livestock.paths_of("sheep"), Vector3.ZERO, 5.0, 6)
	_tree().root.add_child(flock)
	_nodes.append(flock)
	await _ticks(2)
	var far: MultiMeshInstance3D = null
	var near: MultiMeshInstance3D = null
	for c in flock.get_children():
		if c is MultiMeshInstance3D and str(c.name).ends_with("_far"):
			far = c
		elif c is MultiMeshInstance3D and near == null:
			near = c
	assert_true(far != null, "a far flock is drawn")
	if far == null:
		return
	assert_eq(far.multimesh.instance_count, 6, "all six in it")
	assert_true((far.material_override as ShaderMaterial).shader.resource_path.ends_with("herd_far.gdshader"), "posed by the herd shader")
	assert_near(far.visibility_range_begin, Livestock.FAR_FROM_M, 0.01, "from where the near body gives way")
	assert_gt(near.visibility_range_end, far.visibility_range_begin, "and the two overlap, so none blinks out")
	assert_gt(far.visibility_range_end, 600.0, "out to the next hill")
	var grazing := 0
	for b in flock.beasts:
		var pose: Color = b.get("far_pose", Color(0, 0, 0, 0))
		grazing += int(pose.b > 0.5)
	assert_gt(grazing, 0, "some of them graze")
