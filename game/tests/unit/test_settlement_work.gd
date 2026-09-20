extends TestCase
## Somewhere to read the day's work, and somewhere to do it.
##
## `JobBoard` and `JobStation` were complete, tested and placed by nothing: no file outside
## their own two scripts and the tests ever named either class, so there was no notice post in
## any village and no bellows, mash tun or eel trap anywhere in eight kilometres of country.
## `Jobs` generated work that nobody could be handed.

const MERROWBY := "core:place/merrowby"


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _raise(place_id: String, kind: String, region: String) -> Settlement:
	var s := Settlement.raise_at(place_id, kind, region, Vector3(900.0, 30.0, 2350.0), 64.0,
		[], [] as Array[Rect2])
	_tree().root.add_child(s)
	return s


func test_a_village_has_somewhere_to_read_the_work() -> void:
	var s := _raise(MERROWBY, "village", "core:region/hearthvale")
	var boards := s.find_children("*", "JobBoard", true, false)
	assert_eq(boards.size(), 1, "a village with no notice post has no radiant work in it")
	assert_eq(str(boards[0].get("place_id")), MERROWBY,
		"the board does not know which place's work it lists")
	s.queue_free()


func test_a_hamlet_has_no_charter_board() -> void:
	var s := _raise("core:place/isseva", "hamlet", "core:region/sedgemire")
	assert_empty(s.find_children("*", "JobBoard", true, false),
		"eight houses on stilts had a charter-board")
	s.queue_free()


## Merrowby has a smith, a brewer and a baker among its authored interiors, so its yards
## should hold the work those trades do and not somebody else's.
func test_the_work_follows_the_people_who_live_there() -> void:
	var s := _raise(MERROWBY, "village", "core:region/hearthvale")
	var kinds: Array[String] = []
	for station in s.find_children("*", "JobStation", true, false):
		kinds.append(str(station.get("kind")))
	assert_true(kinds.has("smith"), "the village with two smithies has no bellows: %s" % [kinds])
	assert_true(kinds.has("brew"), "the village with a brewhouse has no mash tun: %s" % [kinds])
	assert_false(kinds.has("fish"), "an inland chalk village was given an eel trap")
	s.queue_free()


## A place whose residents have no authored trade still has its own work, because the reed
## beds are cut whether or not anybody wrote down who cuts them.
func test_a_place_with_no_authored_trade_still_has_its_regions_work() -> void:
	var s := _raise("core:place/tamwick", "village", "core:region/sedgemire")
	var kinds: Array[String] = []
	for station in s.find_children("*", "JobStation", true, false):
		kinds.append(str(station.get("kind")))
	assert_eq(kinds, ["dig"] as Array[String],
		"a reedfolk village was left with nothing to do: %s" % [kinds])
	s.queue_free()


## Both classes are a collision shape and a signal each; they were written to be dropped into a
## hand-built scene next to a mesh. Out in the country they have to carry their own.
func test_the_board_and_the_stations_are_things_you_can_see() -> void:
	var s := _raise(MERROWBY, "village", "core:region/hearthvale")
	for node in s.find_children("*", "JobBoard", true, false) \
			+ s.find_children("*", "JobStation", true, false):
		assert_false(node.find_children("*", "MeshInstance3D", true, false).is_empty(),
			"%s is an invisible collision box in the middle of a village" % node.name)
	s.queue_free()


func test_everything_placed_is_interactable() -> void:
	var s := _raise(MERROWBY, "village", "core:region/hearthvale")
	for node in s.find_children("*", "JobBoard", true, false) \
			+ s.find_children("*", "JobStation", true, false):
		assert_true(node.is_in_group("interactable"), "%s cannot be walked up to" % node.name)
	s.queue_free()
