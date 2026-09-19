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
