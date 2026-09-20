extends TestCase
## Finding a place by going to it, and reading the country off a high place.
##
## `GameState.discover()` had two callers — a dialogue effect and resting at a Hearthstone —
## so the chart and the compass filled up by being *told* about places. You could walk from
## Merrowby to Tollmere and arrive with blank paper. `surveyed:<place>`, which the map screen
## reads for its much wider reveal, was set by nothing outside the UI review's fake save. And
## every one of the 48 POIs carries a `visible_from` list that nothing read.

const MERROWBY := "core:place/merrowby"

var disco: PlaceDiscovery


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	GameState.discovered_places.clear()
	GameState.flags.clear()
	disco = PlaceDiscovery.new()
	disco.enabled = false          # driven by hand; no player to follow in a unit test
	_tree().root.add_child(disco)


func after_each() -> void:
	if is_instance_valid(disco):
		disco.queue_free()
	GameState.discovered_places.clear()
	GameState.flags.clear()


# --- arriving -------------------------------------------------------------------------------

func test_walking_into_a_village_finds_it() -> void:
	var at := disco.position_of(MERROWBY)
	if at == Vector3.ZERO:
		return                      # no built world in this checkout
	assert_false(GameState.is_discovered(MERROWBY))
	disco.look_around(at)
	assert_true(GameState.is_discovered(MERROWBY),
		"standing in the middle of Merrowby did not find Merrowby")


func test_a_place_across_the_country_is_not_found_by_standing_here() -> void:
	var at := disco.position_of(MERROWBY)
	if at == Vector3.ZERO:
		return
	disco.look_around(at)
	assert_false(GameState.is_discovered("core:place/tollmere"),
		"the whole chart filled up from one village green")


func test_arriving_announces_the_place_by_name() -> void:
	var said: Array[String] = []
	var note := func(text: String, _kind: String) -> void: said.append(text)
	EventBus.notify.connect(note)
	disco.arrive(MERROWBY)
	EventBus.notify.disconnect(note)
	assert_eq(said, ["Merrowby"] as Array[String], "arriving said nothing, or said the id")


# --- surveying -------------------------------------------------------------------------------

func test_the_authored_sightlines_are_read_at_all() -> void:
	var lines := disco.sightlines()
	assert_gt(lines.size(), 40,
		"the 48 POIs carry a visible_from each and this found %d sightlines" % lines.size())


## A vista is somewhere a POI says it can be seen from. That is what the authored data means,
## and it saves keeping a second list that can disagree with the first.
func test_the_vistas_are_places_that_exist() -> void:
	for v in disco.vistas():
		assert_true(ContentDB.has(v), "%s is named as a vantage and is not a place" % v)


func test_surveying_sets_the_flag_the_chart_reads() -> void:
	var vistas := disco.vistas()
	if vistas.is_empty():
		return
	disco.survey(vistas[0])
	assert_true(GameState.has_flag("surveyed:" + vistas[0]),
		"the map's wider reveal is keyed on this flag and surveying did not set it")


func test_surveying_finds_what_the_country_shows_you() -> void:
	var found_any := false
	for v in disco.vistas():
		if disco.survey(v).size() > 0:
			found_any = true
			break
	assert_true(found_any,
		"not one of the authored sightlines survives a look at the built terrain")


func test_you_cannot_survey_a_place_you_have_not_reached() -> void:
	var vistas := disco.vistas()
	if vistas.is_empty():
		return
	var at := disco.position_of(vistas[0])
	if at == Vector3.ZERO:
		return
	# Standing on it, but it has not been arrived at yet: look_around finds it first, then
	# surveys it. Surveying an undiscovered place from across the map must not happen.
	disco.look_around(Vector3(at.x + 3000.0, at.y, at.z + 3000.0))
	assert_false(GameState.has_flag("surveyed:" + vistas[0]),
		"a vista was surveyed from three kilometres away")


# --- the line of sight ------------------------------------------------------------------------

func test_a_hill_in_the_way_hides_what_is_behind_it() -> void:
	# A point on the ground and a point directly under the terrain: never visible.
	var at := disco.position_of(MERROWBY)
	if at == Vector3.ZERO:
		return
	assert_false(disco.can_see(at, Vector3(at.x + 900.0, at.y - 400.0, at.z)),
		"something four hundred metres underground was in plain view")


func test_you_can_see_where_you_are_standing() -> void:
	var at := disco.position_of(MERROWBY)
	if at == Vector3.ZERO:
		return
	assert_true(disco.can_see(at, at), "a place was not visible from itself")


func test_the_far_side_of_the_world_is_out_of_sight() -> void:
	assert_false(disco.can_see(Vector3(0.0, 40.0, 0.0), Vector3(8000.0, 40.0, 8000.0)),
		"a landmark eleven kilometres off was legible through the haze")


# --- it is installed ---------------------------------------------------------------------------

func test_the_world_installs_it() -> void:
	assert_true(GameServices.ORDER.any(func(pair: Array) -> bool:
			return str(pair[0]) == "PlaceDiscovery"),
			"nothing installs it, so the chart fills up by conversation only")
