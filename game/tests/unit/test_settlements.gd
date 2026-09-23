extends TestCase
## The built fabric: the houses nobody lives in, which are what turn four doors on a paved
## circle into a place. Twenty-four interiors do not make eleven settlements, so the rest of
## each town is generated from its plan — and it has to be the same town every time you walk
## back into it, or the world moves behind your back.

const CENTRE := Vector3(900.0, 56.0, 2350.0)


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


## The houses' own bodies: a notice post or a stall in the square is not a house.
func _houses(s: Settlement) -> Array:
	var out: Array = []
	for child in s.get_children():
		if child is StaticBody3D and child.has_meta("house"):
			out.append(child)
	return out


## A straight road due east through the middle of the pad.
func _east_road() -> Array:
	var line: Array = []
	for i in range(-12, 13):
		line.append([CENTRE.x + float(i) * 9.0, CENTRE.z])
	return line


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
	var s := _raise("village", "core:region/hearthvale", [_east_road()])
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
##
## It was 31 meshes before the streets, when a mesh was a draw for the eye and another for each
## cascade of the sun. It is two ratchets now, because the two are no longer the same meshes: every
## prop that throws a shadow throws it from its forge's lowest rung (a MultiMesh of the same
## instances that casts and is never seen), and the one the eye sees casts none. So: this many
## meshes drawn for the eye, and this many drawn for the sun. The eye's count is the fabric's nine
## surfaces (the gardens' in four quarters, so a camera in a street draws the ones it faces), one
## MultiMesh for each kind of thing lying about (a kind's two variants are two), the market's
## stalls and wares, the beasts, the gardens' apple trees (three variants, each its trunk and its
## leaf cards near and its impostor far, one band drawn at a time), the smoke, the shop signs'
## emblems, and the stations' props, whose three nodes are the forge's LOD bands drawn one at a
## time. The small things (the crockery, a bucket, a hen) throw no shadow and are gone past seventy
## metres. Measured against DESIGN section 11 on the streets plan's Merrowby shot, which is in
## PROGRESS.md.
const EYE_RATCHET := 73
const SHADOW_RATCHET := 49
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
	var eye: Array[String] = []
	var sun: Array[String] = []
	for m in _meshes(s):
		var gi := m as GeometryInstance3D
		if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			eye.append(str(gi.name))
		if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			sun.append(str(gi.name))
	eye.sort()
	sun.sort()
	assert_true(eye.size() <= EYE_RATCHET,
			"Merrowby's fabric is %d meshes for the eye; the ratchet is %d: %s" % [eye.size(), EYE_RATCHET, ", ".join(eye)])
	assert_true(sun.size() <= SHADOW_RATCHET,
			"and %d for the sun; the ratchet is %d: %s" % [sun.size(), SHADOW_RATCHET, ", ".join(sun)])
	assert_true(_houses(s).size() >= 10, "a village with %d houses is not Merrowby" % _houses(s).size())
	_drop(s)


## The surfaces a settlement's fabric is drawn in, however many houses it has: its walls in the
## region's own surface and in its stone, the roofs, the stone, the joinery, and the made ground.
const SURFACES := ["Drystone", "Earth", "Garden", "Joinery", "Paving", "Roofs", "Stone", "Walls", "WallsAlt"]


func test_the_fabric_is_one_mesh_a_surface_however_many_houses() -> void:
	var city := _raise("city", "core:region/brightwater", [], [], "core:place/test_city")
	var hamlet := _raise("hamlet", "core:region/hearthvale", [], [], "core:place/test_small")
	for s in [city, hamlet]:
		var own: Array[String] = []
		for m in _direct(s, "MeshInstance3D"):
			own.append(str(m.name))
			# the gardens are the one surface drawn in quarters (Garden_ne ...)
			var surface := str(m.name).get_slice("_", 0)
			assert_true(SURFACES.has(surface), "%s raised %s beside its surfaces" % [s.name, m.name])
			if surface == "Garden":
				assert_true(FabricMesh.QUARTERS.has(str(m.name).get_slice("_", 1)), "%s is no quarter" % m.name)
		assert_true(own.has("Walls") and own.has("Roofs") and own.has("Joinery"), "%s raised %s" % [s.name, own])
	assert_true(_houses(city).size() > _houses(hamlet).size() * 3,
			"a city of %d houses and a hamlet of %d cost the same draws" % [_houses(city).size(), _houses(hamlet).size()])
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


## The sun is drawn the cheapest rung of a thing: every kind that throws a shadow throws its forge
## LOD2's, a MultiMesh of the same instances that casts and is never seen, and the eye's copy casts
## none. An apple tree's shadow was its 1 400 triangles again for every cascade; its impostor's
## eight say the same on the ground.
func test_the_sun_draws_the_cheap_rung_of_every_prop() -> void:
	var s := _raise("village", "core:region/hearthvale", [], [], MERROWBY)
	var proxies := 0
	for node in s.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := node as MultiMeshInstance3D
		if mmi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue
		proxies += 1
		var eye := mmi.get_parent().get_node_or_null(NodePath(str(mmi.name).trim_suffix("_shadow"))) as MultiMeshInstance3D
		assert_true(eye != null, "%s is the shadow of nothing" % mmi.name)
		if eye == null:
			continue
		assert_eq(eye.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s throws its own shadow as well" % eye.name)
		assert_eq(mmi.multimesh.instance_count, eye.multimesh.instance_count, "%s: a shadow for every one" % eye.name)
		assert_true(_tris(mmi.multimesh.mesh) < _tris(eye.multimesh.mesh),
				"%s's shadow is %d triangles against %d seen" % [eye.name, _tris(mmi.multimesh.mesh), _tris(eye.multimesh.mesh)])
	assert_gt(proxies, 5, "the village's props throw their shadows from the cheap rung")
	_drop(s)


## A settlement's apple trees are the forge's LOD1 (a trunk and its leaf cards) near, and its
## crossed-card impostor from TREE_NEAR_M past the middle of their spread out, casting its own
## shadow: the orchards of the next village are eight triangles a tree, not fourteen hundred.
func test_the_next_villages_orchards_are_impostors() -> void:
	var s := _raise("village", "core:region/hearthvale", [], [], MERROWBY)
	var fars := 0
	for node in _direct(s, "MultiMeshInstance3D"):
		var far := node as MultiMeshInstance3D
		if not str(far.name).ends_with("_far"):
			continue
		fars += 1
		var stem := str(far.name).trim_suffix("_far")
		var near := s.get_node_or_null(NodePath(stem + "_lod1_0")) as MultiMeshInstance3D
		assert_true(near != null, "%s is the far band of nothing" % far.name)
		if near == null:
			continue
		assert_gt(near.visibility_range_end, Settlement.TREE_NEAR_M, "%s is drawn to %.0f m" % [near.name, near.visibility_range_end])
		assert_near(far.visibility_range_begin, near.visibility_range_end, 0.01, "%s begins where the near trees end" % far.name)
		assert_gt(far.visibility_range_end, far.visibility_range_begin, "%s is drawn from there out" % far.name)
		assert_eq(far.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "%s throws its own shadow" % far.name)
		assert_eq(far.multimesh.instance_count, near.multimesh.instance_count, "%s: an impostor for every tree" % far.name)
		assert_true(_tris(far.multimesh.mesh) < _tris(near.multimesh.mesh),
				"%s is %d triangles against the near trunk's %d" % [far.name, _tris(far.multimesh.mesh), _tris(near.multimesh.mesh)])
		# the near band's leaf cards and the shadow it casts end there too
		for other in [stem + "_lod1_1", stem + "_lod1_0_shadow"]:
			var gi := s.get_node_or_null(NodePath(other)) as GeometryInstance3D
			if gi != null:
				assert_near(gi.visibility_range_end, near.visibility_range_end, 0.01, "%s ends with the near band" % other)
	assert_gt(fars, 0, "a Vale village's apple trees have a far band")
	_drop(s)


func _tris(mesh: Mesh) -> int:
	var n := 0
	for i in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(i)
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		n += ((idx as PackedInt32Array).size() if idx != null and (idx as PackedInt32Array).size() > 0
				else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return n


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
			func(n: Node) -> bool: return not SURFACES.has(str(n.name).get_slice("_", 0))),
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
	# the four surfaces, and the jug the innkeeper hangs out over the street
	assert_eq(own, ["Emblem", "Joinery", "Roof", "Stone", "Walls"] as Array[String],
			"the inn raised %s rather than one mesh per surface and its sign" % [own])
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


# --- a street, not a ring round a green ------------------------------------------------------------

## Every house the fabric raises turns its door to its street: the road here is the line
## z = CENTRE.z, so a house north of it faces south and one south of it faces north.
func test_every_house_faces_its_street() -> void:
	var s := _raise("village", "core:region/hearthvale", [_east_road()])
	var fronting := 0
	for h in s.street.houses:
		var door: Vector2 = h["door"]
		var facing: Vector2 = h["facing"]
		var off := door.y - CENTRE.z
		assert_true(absf(off) > StreetPlan.ROAD_HALF_M, "a front door in the road at %s" % door)
		if absf(off) < 25.0:
			fronting += 1
			assert_true(facing.y * off < 0.0, "a house on the street with its back to it at %s" % door)
	assert_gt(fronting, 6, "only %d houses front the road through the village" % fronting)
	_drop(s)


## The ground in front of a town house is paved and a cottage has a path to its door, so a street
## is never a lawn with houses on it. Made ground lies on the ground, a few centimetres up.
func test_a_town_paves_its_street_fronts_and_a_village_walks_on_earth() -> void:
	var town := _raise("town", "core:region/hearthvale", [_east_road()], [], "core:place/test_paved")
	var paving := town.get_node_or_null("Paving") as MeshInstance3D
	assert_true(paving != null, "a town with no setts in front of its houses")
	for v in paving.mesh.get_faces():
		assert_true(v.y > 0.0 and v.y < 0.2, "paving %.2f m off the ground" % v.y)
	var village := _raise("village", "core:region/hearthvale", [_east_road()], [], "core:place/test_earth")
	assert_true(village.get_node_or_null("Paving") == null, "a village street paved like a town's")
	assert_true(village.get_node_or_null("Earth") != null, "no path to any cottage door")
	_drop(town)
	_drop(village)


## A garden is fenced, and fenced the way its country fences: hurdles and hedges in the Vale,
## drystone walls on the hills, rails in the wood.
func test_gardens_are_fenced_the_way_their_region_fences() -> void:
	var vale := _raise("village", "core:region/hearthvale", [_east_road()], [], "core:place/test_fenced_vale")
	var hills := _raise("village", "core:region/skerrow", [_east_road()], [], "core:place/test_fenced_hills")
	var wood := _raise("village", "core:region/briarwold", [_east_road()], [], "core:place/test_fenced_wood")
	var vale_runs := 0
	for k in vale.fences_laid:
		assert_true(k in Settlement.FENCE_BY_CULTURE["vale"], "a Vale garden fenced with %s" % k)
		vale_runs += int(vale.fences_laid[k])
	assert_gt(vale_runs, 10, "a village of gardens with %d runs of fence" % vale_runs)
	assert_eq(hills.fences_laid.keys(), ["drystone"], "the clans fence in %s" % [hills.fences_laid.keys()])
	assert_eq(wood.fences_laid.keys(), ["rail"], "the Woodfolk fence in %s" % [wood.fences_laid.keys()])
	_drop(vale)
	_drop(hills)
	_drop(wood)


## Windows on every side of a house, because a house is lived in all the way round: the front's
## bays, the back's, and the gables. The fabric used to glaze the street side and leave the rest.
func test_a_house_has_windows_on_every_side() -> void:
	var fabric := FabricMesh.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var lights := RandomNumberGenerator.new()
	lights.seed = 8
	var spec := {"w": 8.0, "d": 6.0, "storeys": 2, "culture": "vale", "style": HouseKit.STYLES["vale"][0],
			"roof": Building.ROOF_BY_CULTURE["vale"]}
	HouseKit.build(fabric, Transform3D.IDENTITY, spec, rng, lights)
	var host := Node3D.new()
	_tree().root.add_child(host)
	var mi := fabric.commit(host, "joinery", FabricMesh.joinery_material(), "Joinery")
	var arrays: Array = mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var panes := {"front": 0, "back": 0, "gable": 0}
	var i := 0
	while i + 2 < verts.size():
		if colours[i].a < 0.995:
			var mid := (verts[i] + verts[i + 1] + verts[i + 2]) / 3.0
			if absf(mid.x) > 3.8:
				panes["gable"] += 1
			elif mid.z < -2.8:
				panes["front"] += 1
			elif mid.z > 2.8:
				panes["back"] += 1
		i += 3
	for side in panes:
		assert_gt(panes[side], 0, "a house with no window in its %s" % side)
	host.free()


func test_a_timber_framed_house_shows_its_frame() -> void:
	var framed := _frame_boxes({"frame": true})
	var plain := _frame_boxes({"frame": false})
	assert_gt(framed, plain + 20, "a timber-framed house with %d more members than a cob one" % (framed - plain))


func _frame_boxes(style_patch: Dictionary) -> int:
	var fabric := FabricMesh.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var lights := RandomNumberGenerator.new()
	var style: Dictionary = (HouseKit.STYLES["vale"][0] as Dictionary).duplicate()
	style.merge(style_patch, true)
	HouseKit.build(fabric, Transform3D.IDENTITY, {"w": 8.0, "d": 6.0, "storeys": 2, "culture": "vale",
			"style": style, "roof": Building.ROOF_BY_CULTURE["vale"]}, rng, lights)
	return fabric.triangles("joinery") / 12


## Each region builds in its own walls: plaster in the Vale, tarred boards in the fen, laid logs
## in the wood, drystone on the hills.
func test_each_region_builds_in_its_own_walls() -> void:
	var cases := {"core:region/hearthvale": 0, "core:region/sedgemire": 1,
			"core:region/briarwold": 1, "core:region/skerrow": 2}
	var n := 0
	for region in cases:
		n += 1
		var s := _raise("village", str(region), [_east_road()], [], "core:place/test_walls_%d" % n)
		var walls := s.get_node("Walls") as MeshInstance3D
		assert_eq(int((walls.material_override as ShaderMaterial).get_shader_parameter("pattern")), int(cases[region]),
				"%s builds in the wrong wall" % region)
		_drop(s)


## A shop hangs the thing it sells out over the street; a house with an inside and a trade hangs
## its own name as well, and a house with no trade hangs nothing.
func test_a_shop_hangs_its_sign_over_the_street() -> void:
	var s := _raise("town", "core:region/hearthvale", [_east_road()], [], "core:place/test_shops")
	assert_false(s.find_children("Sign_*", "MultiMeshInstance3D", false, false).is_empty(), "a town with no shop signs")
	_drop(s)
	var inn := Building.raise_for("core:interior/tolls_lip", CENTRE, 0.0)
	_tree().root.add_child(inn)
	var name_board := inn.get_node_or_null("SignName") as Label3D
	assert_true(name_board != null, "the inn has no name over its door")
	assert_eq(name_board.text, "The Toll's Lip")
	var cottage := Building.raise_for("core:interior/hesta_bell_house", CENTRE + Vector3(40.0, 0.0, 0.0), 0.0)
	_tree().root.add_child(cottage)
	assert_true(cottage.get_node_or_null("SignName") == null, "a house with no trade hung out a sign")
	for b in [inn, cottage]:
		_tree().root.remove_child(b)
		b.queue_free()


## A house with an inside is put on its street by the size of its own ground floor: the footprint
## is in its door's frame, the door on its front, the house behind it.
func test_a_real_house_knows_its_own_footprint() -> void:
	var foot := Building.footprint_of("core:interior/tolls_lip")
	assert_true(foot.size.x > 11.6 and foot.size.y > 12.0, "the inn is %s" % foot.size)
	assert_true(foot.position.x < 0.0 and foot.end.x > 0.0, "the inn's door is not in its front wall")
	assert_true(foot.position.y >= 0.0, "part of the inn stands in front of its own door")
	assert_eq(Building.footprint_of("core:interior/undercroft"), Rect2(), "a deep place has no house to put on a street")


func test_the_chimneys_smoke() -> void:
	var s := _raise("village", "core:region/hearthvale", [_east_road()], [], "core:place/test_smoke")
	var smoke := s.get_node_or_null("ChimneySmoke") as MultiMeshInstance3D
	assert_true(smoke != null, "not one chimney in the village is drawing")
	assert_gt(smoke.multimesh.instance_count, 0)
	assert_eq(smoke.multimesh.instance_count % ChimneySmoke.PUFFS, 0, "a chimney with a puff missing")
	assert_eq(smoke.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "smoke casting a shadow")
	assert_true((smoke.material_override as ShaderMaterial).shader == ChimneySmoke.SHADER)
	var ruin := _raise("ruin_village", "core:region/cinderlea", [_east_road()], [], "core:place/test_cold")
	assert_true(ruin.get_node_or_null("ChimneySmoke") == null, "smoke over a ruin nobody lives in")
	_drop(s)
	_drop(ruin)


## The people whose days send them to the market's stalls, the well and the green stand there:
## each stallholder at a stall of their own, and the rest at the well and on the green.
func test_people_stand_where_their_day_sends_them() -> void:
	var s := _raise("town", "core:region/hearthvale", [_east_road()], [], MERROWBY)
	var marks := {}
	for m in s.get_children():
		if m is Marker3D and m.is_in_group(NpcRegistry.SPOT_GROUP):
			marks[str(m.name)] = m
			assert_eq(str(m.get_meta("place", "")), MERROWBY, "%s does not say whose place it is in" % m.name)
	for want in ["market_stall", "market_stall_flour", "market_stall_bread", "market_stall_ale", "well", "green"]:
		assert_true(marks.has(want), "nowhere to stand for %s: %s" % [want, marks.keys()])
	var at: Array = []
	for stall in ["market_stall", "market_stall_flour", "market_stall_bread", "market_stall_ale"]:
		if not marks.has(stall):
			continue
		for other in at:
			assert_true((marks[stall] as Node3D).position.distance_to(other) > 2.0, "two stallholders at one stall")
		at.append((marks[stall] as Node3D).position)
	if marks.has("market_stall_flour") and marks.has("well"):
		assert_false(bool(marks["market_stall_flour"].get_meta("gather", true)), "a stall is one person's")
		assert_true(bool(marks["well"].get_meta("gather", false)), "the well is everybody's")
	_drop(s)


func test_people_sent_to_one_spot_stand_round_it_not_in_one_another() -> void:
	var m := Marker3D.new()
	m.set_meta("gather", true)
	var a := NpcRegistry.gather_offset("core:npc/one", m)
	var b := NpcRegistry.gather_offset("core:npc/two", m)
	assert_true(a.distance_to(b) > 0.2, "two people in one place at the well")
	assert_true(a.length() >= 0.9 and a.length() <= 2.6, "somebody %.1f m from the well" % a.length())
	assert_eq(NpcRegistry.gather_offset("core:npc/one", m), a, "and the same place each time")
	m.set_meta("gather", false)
	assert_eq(NpcRegistry.gather_offset("core:npc/one", m), Vector3.ZERO, "a stool is sat on, not stood round")
	m.free()


## The Vale paints a door for the trade behind it ("blue miller, red smith, green grower, yellow
## brewer", its identity says): Mullard's Yellow Door is yellow, and a house of no trade is not.
func test_a_vale_door_is_painted_for_its_trade() -> void:
	var yellow: Color = HouseKit.VALE_DOOR_PAINT["brewer"]
	var brewhouse := Building.raise_for("core:interior/corwen_brewhouse", CENTRE, 0.0)
	_tree().root.add_child(brewhouse)
	assert_true(_has_colour(brewhouse, yellow), "Mullard's Yellow Door is not yellow")
	var bell_house := Building.raise_for("core:interior/hesta_bell_house", CENTRE + Vector3(40.0, 0.0, 0.0), 0.0)
	_tree().root.add_child(bell_house)
	for paint in HouseKit.VALE_DOOR_PAINT.values():
		assert_false(_has_colour(bell_house, paint), "the bell-keeper's door is painted for a trade she does not keep")
	for b in [brewhouse, bell_house]:
		_tree().root.remove_child(b)
		b.queue_free()


func _has_colour(b: Node, c: Color) -> bool:
	var joinery := b.get_node("Joinery") as MeshInstance3D
	for col in joinery.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]:
		if absf(col.r - c.r) < 0.01 and absf(col.g - c.g) < 0.01 and absf(col.b - c.b) < 0.01:
			return true
	return false
