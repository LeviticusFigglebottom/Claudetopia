extends TestCase
## A town raised a piece at a time is the town raised at once (TRIAGE item 36's second pass).
##
## Where the world is drawn a settlement is raised stepwise (`Settlement.stepwise`, WorldDoors): its
## streets laid out on a worker thread, its meshes' arrays gathered on one, and the rest paced by the
## frame's budget between houses, gardens, runs of fence, rings of paving and the pieces of its middle
## and its fort. Headless nothing is paced; here the pacing is turned on (WorldPace.paced_override) and
## the budget spent, so every pause waits a frame, and what stands is compared with the town raised
## in one go: every node where it stands, every collision shape, every mesh's bounds.

const CENTRE := Vector3(0.0, 0.0, 0.0)
const TOWNS := [["town", "core:region/hearthvale"], ["village", "core:region/briarwold"],
		["fort", "core:region/hearthvale"], ["hamlet", "core:region/skerrow"], ["city", "core:region/brightwater"]]


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func _described(s: Settlement) -> Array[String]:
	var out: Array[String] = []
	for n in s.find_children("*", "", true, false):
		if n.is_queued_for_deletion() or n is Livestock or n.get_parent() is Livestock:
			continue
		var path := str(s.get_path_to(n))
		var parts: Array[String] = []
		for bit in path.split("/"):
			parts.append("@" if bit.begins_with("@") else bit)
		var line := "%s %s" % ["/".join(parts), n.get_class()]
		if n is Node3D:
			line += " " + str((n as Node3D).transform)
		if n is CollisionShape3D and (n as CollisionShape3D).shape is BoxShape3D:
			line += " box " + str(((n as CollisionShape3D).shape as BoxShape3D).size)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mesh := (n as MeshInstance3D).mesh
			line += " mesh %s %d" % [str(mesh.get_aabb()), mesh.get_surface_count()]
			if mesh.get_surface_count() > 0:
				line += " %d verts" % (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
			var mm := (n as MultiMeshInstance3D).multimesh
			line += " x%d" % mm.instance_count
			for i in mm.instance_count:
				line += " " + str(mm.get_instance_transform(i))
		out.append(line)
	return out


func _raise(kind: String, region: String, stepwise: bool) -> Settlement:
	var id := "core:place/steps_" + kind
	var s := Settlement.raise_at(id, kind, region, CENTRE, 90.0, [[[-200.0, 5.0], [200.0, -3.0]]], [])
	s.stepwise = stepwise
	_tree().root.add_child(s)
	return s


func _drop(s: Node) -> void:
	if is_instance_valid(s):
		s.get_parent().remove_child(s)
		s.free()


func test_a_town_raised_in_pieces_is_the_town_raised_at_once() -> void:
	var differ: Array[String] = []
	for t in TOWNS:
		var whole := _raise(str(t[0]), str(t[1]), false)
		assert_true(whole.is_raised, "%s raised at once" % t[0])
		var want := _described(whole)
		_drop(whole)
		WorldPace.paced_override = 1
		var paced := _raise(str(t[0]), str(t[1]), true)
		var frames := 0
		while not paced.is_raised and frames < 20000:
			await _tree().process_frame
			frames += 1
		WorldPace.paced_override = -1
		assert_true(paced.is_raised, "%s raised stepwise" % t[0])
		assert_gt(frames, 5, "%s was raised over many frames" % t[0])
		var got := _described(paced)
		if got != want:
			var first := ""
			for i in mini(got.size(), want.size()):
				if got[i] != want[i]:
					first = "\n    at once: %s\n    stepwise: %s" % [want[i], got[i]]
					break
			differ.append("%s (%d vs %d nodes)%s" % [t[0], want.size(), got.size(), first])
		_drop(paced)
	assert_true(differ.is_empty(), "raised in pieces, not as raised at once:\n  %s" % "\n  ".join(differ))
