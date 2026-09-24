extends TestCase
## The built fabric: the houses nobody lives in, which are what turn four doors on a paved
## circle into a place. Twenty-four interiors do not make eleven settlements, so the rest of
## each town is generated from its plan — and it has to be the same town every time you walk
## back into it, or the world moves behind your back.

## Merrowby, wherever the map puts it (docs/COORDINATES.md).
var CENTRE := at_place("core:place/merrowby", 56.0)


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _raise(kind: String, region: String = "core:region/hearthvale",
		roads: Array = [], taken: Array[Rect2] = [], id: String = "core:place/test") -> Settlement:
	var s := Settlement.raise_at(id, kind, region, CENTRE, 90.0, roads, taken)
	_tree().root.add_child(s)
	return s


func _drop(s: Node) -> void:
	_tree().root.remove_child(s)
	s.queue_free()


func _houses(s: Settlement) -> Array:
	var out: Array = []
	for child in s.get_children():
		if child is StaticBody3D:
			out.append(child)
	return out


# --- every kind of place gets the right amount of town -------------------------------------------

func test_a_town_is_bigger_than_a_hamlet() -> void:
	var town := _raise("town")
	var hamlet := _raise("hamlet", "core:region/hearthvale", [], [], "core:place/test_hamlet")
	assert_true(_houses(town).size() > _houses(hamlet).size(),
			"a town raised %d houses and a hamlet %d" % [_houses(town).size(), _houses(hamlet).size()])
	assert_true(_houses(hamlet).size() > 0, "a hamlet with no houses is not a hamlet")
	_drop(town)
	_drop(hamlet)


func test_a_camp_builds_nothing() -> void:
	var camp := _raise("camp")
	assert_eq(_houses(camp).size(), 0, "a camp is tents, not houses")
	_drop(camp)


func test_an_unknown_kind_builds_nothing() -> void:
	var odd := _raise("interior_dungeon")
	assert_eq(_houses(odd).size(), 0, "a place with no fabric plan should raise nothing")
	_drop(odd)


# --- it is the same town every time --------------------------------------------------------------

func test_the_same_place_is_built_the_same_way_twice() -> void:
	var a := _raise("village")
	var b := _raise("village")
	var ha := _houses(a)
	var hb := _houses(b)
	assert_eq(ha.size(), hb.size(), "the same village built two different sizes")
	for i in range(ha.size()):
		var pa: Vector3 = (ha[i] as Node3D).position
		var pb: Vector3 = (hb[i] as Node3D).position
		assert_true(pa.distance_to(pb) < 0.001, "house %d moved between builds" % i)
	_drop(a)
	_drop(b)


func test_two_different_places_are_different_towns() -> void:
	var a := _raise("village", "core:region/hearthvale", [], [], "core:place/one")
	var b := _raise("village", "core:region/hearthvale", [], [], "core:place/two")
	var ha := _houses(a)
	var hb := _houses(b)
	var same := 0
	for i in range(mini(ha.size(), hb.size())):
		if (ha[i] as Node3D).position.distance_to((hb[i] as Node3D).position) < 0.001:
			same += 1
	assert_true(same < maxi(ha.size(), 1), "two places laid out identically")
	_drop(a)
	_drop(b)


# --- nothing is built on top of anything else ----------------------------------------------------

func test_houses_do_not_stand_inside_each_other() -> void:
	var s := _raise("town")
	var bodies := _houses(s)
	for i in range(bodies.size()):
		for j in range(i + 1, bodies.size()):
			var a: Node3D = bodies[i]
			var b: Node3D = bodies[j]
			var flat := Vector2(a.position.x - b.position.x, a.position.z - b.position.z)
			assert_true(flat.length() > 4.0,
					"houses %d and %d are %.1f m apart" % [i, j, flat.length()])
	_drop(s)


func test_reserved_ground_is_left_alone() -> void:
	# the real interiors' own footprints: the fabric must not be raised through a front door
	var taken: Array[Rect2] = [Rect2(CENTRE.x - 30.0, CENTRE.z - 30.0, 60.0, 60.0)]
	var s := _raise("town", "core:region/hearthvale", [], taken)
	for body in _houses(s):
		var at: Node3D = body
		var here := Vector2(at.global_position.x, at.global_position.z)
		assert_false(taken[0].has_point(here), "a house was raised on reserved ground at %s" % here)
	_drop(s)


func test_nothing_is_built_outside_the_flattened_ground() -> void:
	var s := _raise("town")
	for body in _houses(s):
		var at: Node3D = body
		var out := Vector2(at.global_position.x - CENTRE.x, at.global_position.z - CENTRE.z).length()
		assert_true(out < 90.0, "a house stands %.1f m out, past the pad" % out)
	_drop(s)


# --- a town is built of the right stuff -----------------------------------------------------------

func test_every_region_has_a_culture_and_every_culture_has_a_roof() -> void:
	for region in ContentDB.all("region"):
		var id := str(region.get("id", ""))
		assert_true(Settlement.CULTURE_BY_REGION.has(id), "%s has no culture for its buildings" % id)
		var culture: String = Settlement.CULTURE_BY_REGION[id]
		assert_true(Building.ROOF_BY_CULTURE.has(culture), "%s roofs nothing" % culture)
		assert_true(HouseInterior.CULTURE_SURFACES.has(culture), "%s walls nothing" % culture)
		assert_true(Settlement.PROP_PREFIX.has(culture), "%s has nothing lying about" % culture)


func test_every_settlement_kind_in_the_world_can_be_built() -> void:
	var unplanned: Array[String] = []
	for place in ContentDB.all("place"):
		var kind := str(place.get("kind", ""))
		if kind in ["deep_place", "landmark", "poi", "edge", "interior_dungeon"]:
			continue
		if not Settlement.FABRIC.has(kind):
			unplanned.append("%s (%s)" % [place.get("id", "?"), kind])
	assert_true(unplanned.is_empty(), "places nobody knows how to build: %s" % ", ".join(unplanned))


func test_a_settlement_uses_its_own_regions_roof() -> void:
	var fen := _raise("village", "core:region/sedgemire")
	assert_eq(fen.culture, "reedfolk", "a Sedgemire village should be built by the Reedfolk")
	var hills := _raise("village", "core:region/skerrow", [], [], "core:place/test_hills")
	assert_eq(hills.culture, "clans", "a Skerrow village should be built by the clans")
	_drop(fen)
	_drop(hills)


# --- roads are the grain of a street --------------------------------------------------------------

func test_a_road_through_a_place_lines_the_houses_up_along_it() -> void:
	# a straight road due east through the middle of the pad
	var line: Array = []
	for i in range(-8, 9):
		line.append([CENTRE.x + float(i) * 9.0, CENTRE.z])
	var s := _raise("village", "core:region/hearthvale", [line])
	var bodies := _houses(s)
	assert_true(bodies.size() > 0, "a village on a road raised nothing")
	var fronting := 0
	for body in _houses(s):
		var at: Node3D = body
		var off := absf(at.global_position.z - CENTRE.z)
		if off > 4.0 and off < 18.0:
			fronting += 1
	assert_true(fronting >= bodies.size() / 2,
			"only %d of %d houses front the road" % [fronting, bodies.size()])
	_drop(s)


# --- the fabric is under the draw-call budget -----------------------------------------------------

## Merrowby's street was the worst frame in the game: 2438 draw calls against a budget of 2000,
## and 1093 of them were the eleven entered houses in view, every wall, slab, gable, sill and
## frame its own MeshInstance3D drawn once for the eye and about twice more for the sun. The
## fabric is merged now, and this is the ratchet that keeps it merged: a village of Merrowby's
## kind, with its board, its stations and its for-sale signs, raises at most this many meshes.
const MESH_RATCHET := 31
const MERROWBY := "core:place/merrowby"


func _meshes(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		out.append(n)
	for n in root.find_children("*", "MultiMeshInstance3D", true, false):
		out.append(n)
	return out


func _direct(s: Node, type: String) -> Array[Node]:
	var out: Array[Node] = []
	for c in s.get_children():
		if c.is_class(type):
			out.append(c)
	return out


func test_a_village_of_merrowbys_kind_stays_under_the_mesh_ratchet() -> void:
	var s := _raise("village", "core:region/hearthvale", [], [], MERROWBY)
	var meshes := _meshes(s)
	assert_true(meshes.size() <= MESH_RATCHET,
			"Merrowby's fabric is %d meshes; the ratchet is %d" % [meshes.size(), MESH_RATCHET])
	assert_true(_houses(s).size() >= 10, "a village with %d houses is not Merrowby" % _houses(s).size())
	_drop(s)


func test_the_fabric_is_four_meshes_however_many_houses() -> void:
	var city := _raise("city", "core:region/brightwater", [], [], "core:place/test_city")
	var hamlet := _raise("hamlet", "core:region/hearthvale", [], [], "core:place/test_small")
	for s in [city, hamlet]:
		var own: Array[String] = []
		for m in _direct(s, "MeshInstance3D"):
			own.append(m.name)
		own.sort()
		assert_eq(own, ["Joinery", "Roofs", "Stone", "Walls"] as Array[String],
				"%s raised %s rather than one mesh per surface" % [s.name, own])
	assert_true(_houses(city).size() > _houses(hamlet).size() * 3,
			"a city of %d houses and a hamlet of %d cost the same four draws" % [_houses(city).size(), _houses(hamlet).size()])
	_drop(city)
	_drop(hamlet)


func test_every_house_keeps_its_own_wash() -> void:
	var s := _raise("village")
	var walls: MeshInstance3D = s.get_node("Walls")
	var arrays: Array = walls.mesh.surface_get_arrays(0)
	var colours: Variant = arrays[Mesh.ARRAY_COLOR]
	assert_true(colours != null, "the merged walls carry no vertex colour, so every house is the same cream")
	var distinct: Dictionary = {}
	for c in colours:
		distinct[str(c)] = true
	assert_true(distinct.size() >= 6,
			"%d houses in one mesh with %d washes between them" % [_houses(s).size(), distinct.size()])
	_drop(s)


func test_the_joinery_is_near_only_and_casts_no_shadow() -> void:
	var s := _raise("town")
	var joinery: MeshInstance3D = s.get_node("Joinery")
	assert_true(joinery.visibility_range_end > 0.0, "door frames drawn to the horizon")
	assert_eq(joinery.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"shutters cast a shadow: a whole extra pass for the sun and a line nobody sees")
	var walls: MeshInstance3D = s.get_node("Walls")
	assert_eq(walls.visibility_range_end, 0.0, "the roofs are how a village is read from the next hill")
	_drop(s)


func test_props_are_one_multimesh_per_asset() -> void:
	var s := _raise("village", "core:region/hearthvale", [], [], MERROWBY)
	var seen: Dictionary = {}
	var instances := 0
	for m in _direct(s, "MultiMeshInstance3D"):
		var mmi := m as MultiMeshInstance3D
		assert_false(seen.has(mmi.name), "%s is strewn as two MultiMeshes" % mmi.name)
		seen[mmi.name] = true
		assert_true(mmi.visibility_range_end > 0.0, "%s is drawn to the horizon" % mmi.name)
		for i in mmi.multimesh.instance_count:
			var at := mmi.multimesh.get_instance_transform(i).origin
			assert_true(Vector2(at.x, at.z).length() < 100.0, "%s #%d lies %.0f m out" % [mmi.name, i, Vector2(at.x, at.z).length()])
			instances += 1
	assert_true(seen.size() >= 6, "a Vale village with only %d kinds of prop" % seen.size())
	assert_true(instances > seen.size(), "%d props in %d MultiMeshes: nothing was batched" % [instances, seen.size()])
	assert_empty(s.find_children("*", "MeshInstance3D", false, false).filter(
			func(n: Node) -> bool: return not (n.name in ["Walls", "Roofs", "Stone", "Joinery"])),
			"a prop is still its own MeshInstance3D beside the merged fabric")
	_drop(s)


func test_boards_stations_and_signs_are_still_their_own_bodies() -> void:
	var s := _raise("village", "core:region/hearthvale", [], [], MERROWBY)
	var walkable := s.find_children("*", "JobBoard", false, false) \
			+ s.find_children("*", "JobStation", false, false) \
			+ s.find_children("*", "PropertySign", false, false)
	assert_true(walkable.size() >= 4, "Merrowby has a board, three stations and two signs; found %d" % walkable.size())
	for node in walkable:
		var body := node as CollisionObject3D
		assert_true(body != null, "%s was merged into something the ray cannot hit" % node.name)
		assert_true((body.collision_layer & Interactor.MASK_INTERACT) != 0,
				"%s is off the interaction layer" % node.name)
		assert_true(node.is_in_group("interactable"), "%s is not interactable" % node.name)
	for m in _direct(s, "MeshInstance3D"):
		assert_false(m is CollisionObject3D, "the merged fabric has grown a body")
	_drop(s)


func test_a_building_is_four_meshes_and_a_body_a_room() -> void:
	var b := Building.raise_for("core:interior/tolls_lip", CENTRE, 0.0)
	_tree().root.add_child(b)
	var own: Array[String] = []
	for m in _direct(b, "MeshInstance3D"):
		own.append(m.name)
	own.sort()
	assert_eq(own, ["Joinery", "Roof", "Stone", "Walls"] as Array[String],
			"the inn raised %s rather than one mesh per surface" % [own])
	var rooms := 0
	for r in b.meta.get("rooms", []):
		if int((r as Dictionary).get("storey", 0)) == 0:
			rooms += 1
	assert_true(rooms >= 2, "the inn has %d ground rooms" % rooms)
	assert_eq(_direct(b, "StaticBody3D").size(), rooms, "a wall you can walk through")
	var joinery: MeshInstance3D = b.get_node("Joinery")
	assert_true(joinery.mesh.get_faces().size() / 3 >= 60,
			"a door and %d windows made only %d triangles of joinery" % [(b.meta.get("windows", []) as Array).size(), joinery.mesh.get_faces().size() / 3])
	_tree().root.remove_child(b)
	b.queue_free()


## A box emitted into the fabric must face outward on every side, or a house is a set of open
## walls seen from the wrong side. The winding is taken from the engine's own BoxMesh and the
## normal from that winding; this is the test that catches either being turned around.
func test_the_fabric_boxes_face_outward() -> void:
	var fabric := FabricMesh.new()
	var centre := Vector3(3.0, 1.5, -2.0)
	var xf := Transform3D(Basis(Vector3.UP, 0.7), centre)
	fabric.box("wall", xf, Vector3(4.0, 3.0, 5.0), Color(0.9, 0.8, 0.7))
	var host := Node3D.new()
	_tree().root.add_child(host)
	var inst := fabric.commit(host, "wall", StandardMaterial3D.new(), "Walls")
	assert_true(inst != null, "nothing committed")
	var arrays: Array = inst.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	assert_eq(verts.size(), 36, "a box is twelve triangles")
	var inward := 0
	var i := 0
	while i + 2 < verts.size():
		var mid := (verts[i] + verts[i + 1] + verts[i + 2]) / 3.0
		var wound := (verts[i + 2] - verts[i]).cross(verts[i + 1] - verts[i]).normalized()
		if wound.dot(mid - centre) <= 0.0 or normals[i].dot(mid - centre) <= 0.0:
			inward += 1
		i += 3
	assert_eq(inward, 0, "%d of 12 faces wound or lit from inside the box" % inward)
	# vertex colours are stored eight bits a channel, so the tint comes back to the nearest 1/255
	var tint := colours[0]
	assert_true(absf(tint.r - 0.9) < 0.006 and absf(tint.g - 0.8) < 0.006 and absf(tint.b - 0.7) < 0.006,
			"the tint did not reach the vertices: %s" % tint)
	_tree().root.remove_child(host)
	host.queue_free()
