extends TestCase
## Which places the compass strip shows (CompassRules, DESIGN §5.16), asked at the spots the user's
## playtest 6 was about: in a town, in the thick of the POIs, on an empty road, and at the start.
## "Becomes too crowded with POI, should be more of a Skyrim distance-based mechanic"; "other POI
## aside from intro area don't seem to have distant icons (like towns)".

const MERROWBY := "core:place/merrowby"
const TOLL := "core:place/cracked_toll"
const CHOIR := "core:place/sunken_choir"
const START := "core:poi/stair_head"
## Where the atlas's POIs stand thickest: eight within 400 m of the Glass Bridge.
const CLUSTER := Vector2(60.0, 2860.0)
## The emptiest stretch of road on the map, 380 m from the nearest place (the West Walk).
const OPEN_ROAD := Vector2(-3528.0, 1584.0)

var _places: Array = []


func before_each() -> void:
	if _places.is_empty():
		_places = CompassRules.places_from_content()


func _xz(id: String) -> Vector2:
	return PlaceRef.xz(id)


func _none(_id: String) -> bool:
	return false


func _all(_id: String) -> bool:
	return true


func _ids(picked: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for m in picked:
		out.append(str(m["id"]))
	return out


func test_every_place_on_the_map_is_a_candidate() -> void:
	assert_gt(_places.size(), 250, "the places and POIs with a position (%d)" % _places.size())


func test_in_the_thick_of_the_pois_the_strip_never_crowds() -> void:
	var picked := CompassRules.select(CLUSTER, _places, _all)
	assert_eq(picked.size(), CompassRules.CAP, "everything found, the strip holds %d and no more" % CompassRules.CAP)
	var within := 0
	for p in _places:
		if CLUSTER.distance_to(p["xz"]) <= float(CompassRules.rule(str(p["kind"]))["range"]):
			within += 1
	assert_gt(within, CompassRules.CAP, "there are more in range (%d) than the strip shows" % within)
	for m in picked:
		assert_true(float(m["distance"]) <= float(CompassRules.rule(str(m["kind"]))["range"]),
				"%s is within its kind's range" % m["id"])
	# nearest and biggest first: nothing left off stands nearer, in its own range's terms, than
	# the last one kept
	var last := float(picked[picked.size() - 1]["score"])
	var all_in := CompassRules.select(CLUSTER, _places, _all, 1000)
	for m in all_in.slice(CompassRules.CAP):
		assert_true(float(m["score"]) >= last, "%s was left off for something further" % m["id"])


func test_a_town_shows_from_far_off_and_a_small_place_only_near() -> void:
	var town := _xz(MERROWBY)
	# 1.5 km south of Merrowby, found: the town is there, a POI as far off is not
	var off := town + Vector2(0.0, 1500.0)
	var picked := _ids(CompassRules.select(off, _places, _all, 1000))
	assert_true(MERROWBY in picked, "Merrowby, found, shows from 1.5 km: %s" % ", ".join(picked))
	for m in CompassRules.select(off, _places, _all, 1000):
		if str(m["kind"]) in ["ruins", "shrine", "camp", "standing_stones", "bridge"]:
			assert_true(float(m["distance"]) <= 380.0, "a %s shows only near (%s at %.0f m)" % [m["kind"], m["id"], m["distance"]])
	# not yet found: from 900 m the town shows, faintly; from 1.2 km it does not yet
	var faint := CompassRules.select(town + Vector2(0.0, 900.0), _places, _none, 1000)
	var seen := false
	for m in faint:
		if str(m["id"]) == MERROWBY:
			seen = true
			assert_false(bool(m["found"]), "unfound, it is drawn faint")
	assert_true(seen, "an unfound town is noticed from 900 m")
	assert_false(MERROWBY in _ids(CompassRules.select(town + Vector2(0.0, 1200.0), _places, _none, 1000)),
			"but not from 1.2 km")


func test_in_a_town_its_landmark_shows_and_the_count_stays_under_the_cap() -> void:
	var picked := CompassRules.select(_xz(MERROWBY) + Vector2(20.0, 20.0), _places, _none)
	assert_true(picked.size() <= CompassRules.CAP)
	assert_true(TOLL in _ids(picked), "the Cracked Toll over the town is on the strip, unfound: %s" % ", ".join(_ids(picked)))
	assert_false(MERROWBY in _ids(picked), "the town you stand in is not a marker")


func test_on_an_empty_road_the_strip_still_says_where_the_country_is() -> void:
	var picked := CompassRules.select(OPEN_ROAD, _places, _all)
	assert_true(picked.size() <= CompassRules.CAP)
	var far := 0.0
	for m in picked:
		far = maxf(far, float(m["distance"]))
	assert_gt(picked.size(), 0, "something found shows from the emptiest road on the map")
	assert_gt(far, 400.0, "and it is a place further off than a POI's range (%.0f m)" % far)


func test_at_the_start_the_choir_shows_before_it_is_found() -> void:
	var picked := CompassRules.select(_xz(START) + Vector2(0.0, 3.0), _places, _none)
	assert_true(CHOIR in _ids(picked), "the Sunken Choir, the first place the Warden sends you, shows from the camp: %s" % ", ".join(_ids(picked)))


func test_what_is_underground_or_hidden_is_not_given_away() -> void:
	for p in _places:
		var kind := str(p["kind"])
		if kind in ["deep_place", "hidden_valley", "wayside"]:
			var near: Vector2 = p["xz"] + Vector2(30.0, 0.0)
			assert_false(str(p["id"]) in _ids(CompassRules.select(near, _places, _none, 1000)),
					"%s (%s) does not show before it is found" % [p["id"], kind])
