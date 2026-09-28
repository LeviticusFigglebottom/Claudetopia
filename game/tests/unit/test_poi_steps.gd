extends TestCase
## A place raised a step at a time is the place raised in one go (TRIAGE item 36's second pass).
##
## Where the world is drawn, a place's builder waits for a later frame whenever the frame's budget is
## spent (`PoiDressing.stepwise`, `PoiKit.step`), so a ruin or a mill is many small pieces rather than
## one frame of 20-150 ms. Headless it is built in one go, as it always was. These raise every place of
## the built world both ways (a third of them far as well), the stepwise one waiting a frame at every step, and compare what stands:
## every node where it stands, every collision shape and what it is, every mesh, every light.
##
## These read the built world (`./run.sh world`); when it is missing they say so once and skip.

const GENERATED := "res://world/generated"

var provider: TerrainProvider = null
var pois: Array = []
var roads: Array = []
var _scratch: Node3D = null


func before_each() -> void:
	if provider != null:
		return
	if not FileAccess.file_exists("%s/pois.json" % GENERATED):
		skip("world data missing: run ./run.sh world")
		return
	provider = TerrainProvider.new()
	provider.load_data()
	pois = JSON.parse_string(FileAccess.get_file_as_string("%s/pois.json" % GENERATED))
	roads = WorldPois.roads_from_disk()


func _host() -> Node3D:
	if _scratch == null or not is_instance_valid(_scratch):
		_scratch = Node3D.new()
		_scratch.name = "PoiStepsScratch"
		(Engine.get_main_loop() as SceneTree).root.add_child(_scratch)
	return _scratch


func _drop(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.get_parent().remove_child(node)
		node.free()


## Everything standing in a dressing, as text: each node's path (Godot's own names for a node named by
## a counter left out), class and transform in the dressing; each collision shape's kind and size;
## each mesh's bounds and surfaces; each MultiMesh's instances; the lights it registered.
## Crows and a flock move from the frame they stand (their own _process): where they have got to is
## not what was built.
static func _alive(n: Node, d: PoiDressing) -> bool:
	var p := n.get_parent()
	while p != null and p != d:
		if p is Crows or p is Livestock:
			return true
		p = p.get_parent()
	return false


static func _going(n: Node, d: PoiDressing) -> bool:
	while n != null and n != d:
		if n.is_queued_for_deletion():
			return true
		n = n.get_parent()
	return false


static var _counted := RegEx.create_from_string("_[A-Za-z0-9]+3D_[0-9]+_")


static func _described(d: PoiDressing) -> Array[String]:
	var out: Array[String] = []
	for n in d.find_children("*", "", true, false):
		if _going(n, d):
			# freed at the end of the frame (a fall's pool the river's water replaces): raised at once it
			# is still there when this is read, raised in steps it has gone
			continue
		var path := str(d.get_path_to(n))
		var parts: Array[String] = []
		for bit in path.split("/"):
			# a node Godot renamed for a clash carries a counter, and so does what is named after it
			parts.append("@" if bit.begins_with("@") else _counted.sub(bit, "_@_", true))
		var line := "%s %s" % ["/".join(parts), n.get_class()]
		if n is Node3D and not _alive(n, d):
			line += " " + str(d._local_of(n as Node3D))
		if n is CollisionShape3D:
			var shape := (n as CollisionShape3D).shape
			line += " shape %s" % (shape.get_class() if shape != null else "none")
			if shape is BoxShape3D:
				line += str((shape as BoxShape3D).size)
			elif shape is ConvexPolygonShape3D:
				line += " %d points" % (shape as ConvexPolygonShape3D).points.size()
			elif shape is ConcavePolygonShape3D:
				line += " %d faces" % (shape as ConcavePolygonShape3D).get_faces().size()
			elif shape is CapsuleShape3D:
				line += " %s %s" % [(shape as CapsuleShape3D).radius, (shape as CapsuleShape3D).height]
			line += " meta %s" % str(n.get_meta(PoiKit.SURFACE_META, ""))
		if n is CollisionObject3D:
			line += " layer %d meta %s" % [(n as CollisionObject3D).collision_layer, str(n.get_meta(PoiKit.SURFACE_META, ""))]
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mesh := (n as MeshInstance3D).mesh
			line += " mesh %s %d surfaces" % [str(mesh.get_aabb()), mesh.get_surface_count()]
		if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
			var mm := (n as MultiMeshInstance3D).multimesh
			line += " x%d" % mm.instance_count
			for i in mm.instance_count:
				line += " " + str(mm.get_instance_transform(i))
		if n is GeometryInstance3D:
			line += " vis %s %s" % [(n as GeometryInstance3D).visible, (n as GeometryInstance3D).visibility_range_end]
		out.append(line)
	for s in d.light_sources():
		out.append("light %s %s %s %s %s" % [str(d.to_local(s[0])), s[1], s[2], s[3], s[4]])
	return out


func _items() -> Array:
	var out: Array = []
	for item_v in WorldPois.candidates(pois + WorldPois.unbuilt_entries(pois, provider)):
		var item: Dictionary = item_v
		if PoiDressing.KINDS_BUILT.has(PoiDressing.kind_of(str((item["entry"] as Dictionary)["place_id"]), item["def"])):
			out.append(item)
	return out


func _raise(item: Dictionary, far: bool, stepwise: bool) -> PoiDressing:
	var d := PoiDressing.raise(item["entry"], item["def"], far, provider, roads)
	d.stepwise = stepwise
	d.step_every = stepwise
	_host().add_child(d)
	return d


## Raised both ways, near and far: the same things, in the same places, with the same collision.
func test_a_place_raised_in_steps_is_the_place_raised_at_once() -> void:
	if provider == null:
		return
	var tree := Engine.get_main_loop() as SceneTree
	var checked := 0
	var differ: Array[String] = []
	var in_one: Array[String] = []
	var most_steps := 0
	var items := _items()
	for n in items.size():
		var item: Dictionary = items[n]
		var id := str((item["entry"] as Dictionary)["place_id"])
		# every place near, and every third far (a silhouette is the same builder, less of it)
		for far in ([false, true] if n % 3 == 0 else [false]):
			var whole := _raise(item, far, false)
			assert_true(whole.finished, "%s was built in one go where nothing is paced" % id)
			var want := _described(whole)
			var one_go_steps := whole.kit.steps
			_drop(whole)
			var paced := _raise(item, far, true)
			var frames := 0
			while not paced.finished and frames < 20000:
				await tree.process_frame
				frames += 1
			assert_true(paced.finished, "%s%s finished its steps" % [id, " (far)" if far else ""])
			var got := _described(paced)
			assert_eq(paced.kit.steps, one_go_steps, "%s took the same steps" % id)
			if got != want:
				var first := ""
				for i in mini(got.size(), want.size()):
					if got[i] != want[i]:
						first = "\n    at once: %s\n    stepwise: %s" % [want[i], got[i]]
						break
				differ.append("%s%s (%d vs %d nodes)%s" % [id, " (far)" if far else "", want.size(), got.size(), first])
			if not far and frames < 2:
				in_one.append(id)
			most_steps = maxi(most_steps, frames)
			checked += 1
			_drop(paced)
	assert_gt(checked, 60, "every place of the built world")
	assert_true(differ.is_empty(), "raised in steps, not as raised at once:\n  %s" % "\n  ".join(differ))
	assert_true(in_one.is_empty(), "places that were not raised in steps: %s" % ", ".join(in_one))
	print("  (%d raisings compared; the most steps a place took: %d)" % [checked, most_steps])


## Headless nothing is paced, and a place is built in the frame it is raised, whoever raises it.
func test_headless_a_place_is_built_at_once() -> void:
	if provider == null:
		return
	var items := _items()
	assert_gt(items.size(), 0)
	var d := _raise(items[0], false, false)
	assert_true(d.finished and d.meshes_ready(), "built and ready in the frame it was raised")
	assert_false(d.kit.stepwise)
	_drop(d)
