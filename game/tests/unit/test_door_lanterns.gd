extends TestCase
## A house's door light burns in something: a lantern on an iron bracket beside the door
## (HouseKit.door_lantern), drawn in the house's own joinery. It was a light and a glow 0.6 m out
## in front of the door with nothing round it, in every town at night.

var CENTRE := at_place("core:place/merrowby", 56.0)

const SeatAudit := preload("res://tools_gd/seat_audit.gd")


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## Every vertex of `root`'s own joinery meshes (a settlement's or a Building's), in the world.
func _joinery_points(root: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for c in root.get_children():
		var m := c as MeshInstance3D
		if m == null or m.mesh == null or not str(m.name).begins_with("Joinery"):
			continue
		for p in m.mesh.get_faces():
			out.append(m.global_transform * p)
	return out


## Each door light of `owner` is inside one of its lamp boxes grown by the seat audit's reach, and
## that box holds drawn joinery: the bracket and the lantern round the flame. Returns the lights.
func _check_held(owner: Node3D, label: String) -> int:
	var doors: Array = []
	for s in NightLights.sources_of(owner):
		if str(s[1]) == "door":
			doors.append(s[0])
	var boxes: Array[AABB] = []
	for b: AABB in owner.get_meta("lamp_boxes", [] as Array[AABB]):
		boxes.append(owner.global_transform * b)
	assert_eq(boxes.size(), doors.size(), "%s: %d door lights and %d lanterns" % [label, doors.size(), boxes.size()])
	var points := _joinery_points(owner)
	for p_v in doors:
		var p: Vector3 = p_v
		var held := false
		for b in boxes:
			if not b.grow(SeatAudit.LIGHT_REACH_M).has_point(p):
				continue
			# the lantern round the flame: iron and panes within a hand of it, on every side
			var near := 0
			var sides := {}
			for q in points:
				if b.has_point(q) and q.distance_to(p) < 0.2:
					near += 1
					sides[Vector2i(signi(int(signf(q.x - p.x))), signi(int(signf(q.z - p.z))))] = true
			if near >= 24 and sides.size() >= 4:
				held = true
				break
		assert_true(held, "%s: the door light at %s has no lantern drawn round it" % [label, p])
	return doors.size()


func test_every_settlement_door_light_burns_in_a_drawn_lantern() -> void:
	var lights := 0
	var at := CENTRE
	for spec in [["village", "core:region/hearthvale"], ["town", "core:region/brightwater"],
			["village", "core:region/sedgemire"], ["village", "core:region/skerrow"],
			["village", "core:region/briarwold"], ["village", "core:region/cinderlea"]]:
		var s := Settlement.raise_at("core:place/test_lantern_%s" % str(spec[1]).get_file(), str(spec[0]),
				str(spec[1]), at, 90.0, [], [])
		_tree().root.add_child(s)
		lights += _check_held(s, "%s %s" % [spec[0], spec[1]])
		_tree().root.remove_child(s)
		s.queue_free()
		at += Vector3(400.0, 0.0, 0.0)
	assert_true(lights >= 12, "only %d door lights in six places: nobody home" % lights)


func test_a_buildings_door_light_burns_in_a_drawn_lantern() -> void:
	var lights := 0
	var i := 0
	for id in ["core:interior/tolls_lip", "core:interior/hesta_bell_house", "core:interior/corwen_brewhouse"]:
		var b := Building.raise_for(id, CENTRE + Vector3(40.0 * float(i), 0.0, 0.0), 0.7 * float(i))
		_tree().root.add_child(b)
		lights += _check_held(b, id)
		_tree().root.remove_child(b)
		b.queue_free()
		i += 1
	assert_eq(lights, 3, "every house with an inside has a lit door")


func test_the_lantern_hangs_beside_the_door_not_in_front_of_it() -> void:
	var fabric := FabricMesh.new()
	var at := Transform3D(Basis(Vector3.UP, 0.4), Vector3(5.0, 1.0, -3.0))
	var lantern := HouseKit.door_lantern(fabric, at)
	var local: Vector3 = at.affine_inverse() * (lantern["flame"] as Vector3)
	# out from the wall no further than its own arm, at the height of the door's head
	assert_true(local.z > 0.2 and local.z < 0.45, "the flame %.2f m out from the wall" % local.z)
	assert_true(local.y > 2.1 and local.y < 2.5, "the flame %.2f m up" % local.y)
	var box: AABB = lantern["box"]
	assert_true(box.has_point(lantern["flame"]), "the flame is outside its own lantern")
	# it is fixed to the wall: the bracket's plate lies on the wall's face
	var holder := Node3D.new()
	var joinery := fabric.commit(holder, "joinery", FabricMesh.joinery_material(), "Joinery")
	var touches_wall := false
	for p in joinery.mesh.get_faces():
		if absf((at.affine_inverse() * p).z) < 0.005:
			touches_wall = true
			break
	assert_true(touches_wall, "the bracket stands off the wall: a lantern held up by nothing")
	holder.free()
