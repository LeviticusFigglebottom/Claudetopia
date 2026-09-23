extends TestCase
## What follows a place when the map is redrawn (docs/COORDINATES.md): the specs `PlaceRef`
## reads, a way drawn between two places, what a save remembers, and the content kept free of
## coordinates that would stay behind in the old country.
##
## A redrawn map is played here by moving a place's definition for the length of one test.

const MERROWBY := "core:place/merrowby"
const STAIR_HEAD := "core:poi/stair_head"
const CHOIR := "core:place/sunken_choir"
const MOVE := Vector2(-650.0, -1020.0)

## Keys that hold a point on the map. A definition that uses one for coordinates, rather than to
## name a place, has written down where something was instead of what it is beside.
const POINT_KEYS: Array[String] = ["position", "pos", "at", "via", "point", "points", "centre", "center",
	"look_at", "from", "to", "where", "spot", "path"]

var _moved: Dictionary = {}


func after_each() -> void:
	for id in _moved:
		ContentDB.get_or_empty(id)["position"] = _moved[id]
	_moved.clear()
	SaveSystem.pending.erase("player")


## Moves a place the way a redrawn map does, until the test ends. A place is moved once a test.
func _move(id: String, by: Vector2) -> void:
	var def := ContentDB.get_or_empty(id)
	if _moved.has(id) or not def.has("position"):
		return
	_moved[id] = (def["position"] as Array).duplicate()
	var p: Array = def["position"]
	def["position"] = [float(p[0]) + by.x, float(p[1]) + by.y]


## Moves whichever place a pin was kept beside: on a map as full as the atlas's that is not
## always the town the test stood it in.
func _move_pinned(pin: Dictionary) -> void:
	_move(str(pin.get("place", "")), MOVE)


func _xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


# --- specs ---------------------------------------------------------------------------------------

func test_a_bearing_is_a_compass_bearing_as_the_cinematic_has_it() -> void:
	var town := PlaceRef.xz(MERROWBY)
	assert_ne(town, Vector2.INF, "Merrowby says where it is")
	var north := PlaceRef.point_xz({"place": MERROWBY, "bearing": 0.0, "distance": 100.0})
	assert_true(north.is_equal_approx(town + Vector2(0.0, -100.0)), "0 is north, -z: %s" % str(north - town))
	var east := PlaceRef.point_xz({"place": MERROWBY, "bearing": 90.0, "distance": 100.0})
	assert_true(east.is_equal_approx(town + Vector2(100.0, 0.0)), "90 is east, +x: %s" % str(east - town))
	var ground := func(_x: float, _z: float) -> float: return 0.0
	var place := func(id: String) -> Vector3: return Vector3(PlaceRef.xz(id).x, 0.0, PlaceRef.xz(id).y)
	var spec := {"place": MERROWBY, "bearing": 137.0, "distance": 240.0, "height": 3.0}
	var cine := CinematicPath.point_of(spec, ground, place)
	assert_true(_xz(cine).is_equal_approx(PlaceRef.point_xz(spec)), "and the cinematic reads the same spec to the same point")


func test_an_offset_is_metres_east_and_south() -> void:
	var town := PlaceRef.xz(MERROWBY)
	var p := PlaceRef.point_xz({"place": MERROWBY, "offset": [80.0, -70.0]})
	assert_true(p.is_equal_approx(town + Vector2(80.0, -70.0)))


func test_a_spec_follows_its_place() -> void:
	var before := PlaceRef.point_xz({"place": MERROWBY, "bearing": 40.0, "distance": 55.0})
	_move(MERROWBY, MOVE)
	var after := PlaceRef.point_xz({"place": MERROWBY, "bearing": 40.0, "distance": 55.0})
	assert_true((after - before).is_equal_approx(MOVE), "moved %s with the town" % str(after - before))


func test_a_spec_for_a_place_that_is_not_there_says_so() -> void:
	assert_eq(PlaceRef.point_xz({"place": "core:place/nowhere_at_all"}), Vector2.INF)
	assert_eq(PlaceRef.point({"place": ""}), Vector3.INF)
	assert_false(PlaceRef.is_spec([900.0, 2350.0]), "coordinates are not a spec")


# --- a way between two places --------------------------------------------------------------------

func test_a_shape_comes_back_as_the_points_it_was_drawn_from() -> void:
	var a := PlaceRef.xz(STAIR_HEAD)
	var b := PlaceRef.xz(CHOIR)
	var drawn: Array[Vector2] = [a.lerp(b, 0.25) + Vector2(12.0, -3.0), a.lerp(b, 0.7) + Vector2(-20.0, 8.0)]
	var shape: Array = []
	for p in drawn:
		var s := PlaceRef.shape_of(p, a, b)
		shape.append([s.x, s.y])
	var back := PlaceRef.along(STAIR_HEAD, CHOIR, shape)
	for i in drawn.size():
		assert_true(back[i].distance_to(drawn[i]) < 0.001, "point %d came back %.4f m off" % [i, back[i].distance_to(drawn[i])])


func test_the_stair_head_way_goes_where_its_ends_go() -> void:
	var def := ContentDB.get_or_empty(STAIR_HEAD)
	var way: Dictionary = def.get("path", {})
	assert_true(way.has("shape"), "the Stair Head's way is a shape between its ends, not coordinates")
	assert_false(way.has("via"), "and it no longer carries the coordinates as well")
	# the drawn way, not a road the world may have built along it (way_points prefers that)
	var here := PoiDressing.way_points(STAIR_HEAD, def, false)
	assert_gt(here.size(), 5)
	var span := PlaceRef.xz(STAIR_HEAD).distance_to(PlaceRef.xz(CHOIR))
	var end_here := here[here.size() - 1].distance_to(PlaceRef.xz(CHOIR)) / span
	# the camp moves one way and the Choir another, as a redrawn map would have them
	_move(STAIR_HEAD, MOVE)
	_move(CHOIR, MOVE + Vector2(300.0, 150.0))
	var there := PoiDressing.way_points(STAIR_HEAD, def, false)
	assert_eq(there.size(), here.size())
	assert_true(there[0].distance_to(PlaceRef.xz(STAIR_HEAD)) < 30.0, "it still starts at the camp")
	var end_there := there[there.size() - 1].distance_to(PlaceRef.xz(CHOIR)) / PlaceRef.xz(STAIR_HEAD).distance_to(PlaceRef.xz(CHOIR))
	assert_near(end_there, end_here, 0.0001, "and it still ends as near the Choir, for the length of the way")


# --- what a save remembers ---------------------------------------------------------------------------

func test_a_pin_on_an_unmoved_map_gives_back_exactly_what_was_saved() -> void:
	var at := at_place(MERROWBY, 31.25, Vector2(37.0, -12.5))
	var pin := PlaceRef.pin(at)
	assert_eq(str(pin.get("place", "")), PlaceRef.nearest(Vector2(at.x, at.z)), "pinned to the place nearest it")
	assert_eq(PlaceRef.follow(at, pin), at, "nothing moved, so nothing moves")


func test_a_pin_follows_its_place_and_keeps_its_height_above_the_ground() -> void:
	var at := at_place(MERROWBY, 31.25, Vector2(37.0, -12.5))
	var pin := PlaceRef.pin(at)
	_move_pinned(pin)
	var now := PlaceRef.follow(at, pin)
	assert_true((_xz(now) - _xz(at)).is_equal_approx(MOVE), "beside the town where it is now: %s" % str(_xz(now) - _xz(at)))
	var rise := at.y - WorldProbe.get_height(at.x, at.z, at.y)
	assert_near(now.y - WorldProbe.get_height(now.x, now.z, now.y), rise, 0.02, "at the same height above the ground")


func test_a_pocket_is_not_pinned_and_a_missing_place_keeps_the_position() -> void:
	var pocket: Vector3 = Interiors.POCKET_ORIGIN + Vector3(3.0, 1.0, 2.0)
	assert_true(PlaceRef.pin(pocket).is_empty(), "an interior's pocket is off the map; no place moves it")
	var at := Vector3(12.0, 4.0, -30.0)
	assert_eq(PlaceRef.follow(at, {"place": "core:place/nowhere_at_all", "at": [0.0, 0.0], "rise": 1.0}), at)
	assert_eq(PlaceRef.follow(at, null), at, "an old save with no pin loads where it was")


func test_a_saved_body_loads_beside_its_place_on_a_redrawn_map() -> void:
	var at := at_place(MERROWBY, 2.0, Vector2(20.0, 5.0))
	SaveSystem.pending["player"] = {"position": [at.x, at.y, at.z], "near": PlaceRef.pin(at)}
	var spawn := PlayerSpawn.new()
	assert_eq(spawn._saved_position(), at, "unmoved, it loads where it was saved")
	_move_pinned(SaveSystem.pending["player"]["near"])
	var moved: Vector3 = spawn._saved_position()
	assert_true((_xz(moved) - _xz(at)).is_equal_approx(MOVE), "moved, it loads beside the town: %s" % str(_xz(moved) - _xz(at)))
	spawn.free()


func test_the_hearth_keeps_its_stone_and_its_echo_beside_their_places() -> void:
	var saved_state := Hearth.to_save()
	var stone := at_place(MERROWBY, 0.1, Vector2(-6.0, 9.0))
	var fell := at_place(MERROWBY, 0.0, Vector2(140.0, 60.0))
	Hearth.last_hearthstone_id = "test_stone"
	Hearth.respawn_position = stone
	Hearth.echo = {"position": fell, "marks": 12, "region": "core:region/hearthvale"}
	var d := Hearth.to_save()
	_move_pinned(d["respawn_near"])
	_move_pinned(d["echo"]["near"])
	Hearth.from_save(d)
	assert_true((_xz(Hearth.respawn_position) - _xz(stone)).is_equal_approx(MOVE), "the stone's landing moved with the town")
	assert_true((_xz(Hearth.echo["position"]) - _xz(fell)).is_equal_approx(MOVE), "and so did the Echo")
	Hearth.from_save(saved_state)


func test_somebody_walking_with_you_is_saved_beside_a_place() -> void:
	var registry := NpcRegistry.ensure()
	registry.despawn_all()
	registry.states.clear()
	registry.rebuild()
	var who := "core:npc/aud_fennick"
	var on_road := at_place(MERROWBY, 1.0, Vector2(60.0, -40.0))
	registry.begin_escort(who, "core:quest/test_escort", on_road)
	var d: Variant = JSON.parse_string(JSON.stringify(registry.to_save()))
	_move_pinned(d["states"][who]["escort_near"])
	registry.from_save(d)
	var now := registry.escort_position(who)
	assert_true((_xz(now) - _xz(on_road)).is_equal_approx(MOVE), "on the road beside the town where it is now: %s" % str(_xz(now) - _xz(on_road)))
	assert_false(registry.state(who).has("escort_near"), "the pin is a save's, not the roster's")
	registry.despawn_all()
	registry.states.clear()
	registry.rebuild()


func test_the_way_out_of_an_interior_follows_its_place() -> void:
	var out := at_place(MERROWBY, 0.5, Vector2(18.0, 0.0))
	var d := {"current_id": "", "return_point": [out.x, out.y, out.z], "return_yaw": 0.0,
		"return_near": PlaceRef.pin(out)}
	_move_pinned(d["return_near"])
	Interiors.from_save(d)
	assert_true((_xz(Interiors.return_point) - _xz(out)).is_equal_approx(MOVE), "the door's step moved with the town")
	Interiors.return_point = Vector3.ZERO


# --- the content ------------------------------------------------------------------------------------

func test_a_door_plan_names_its_place_and_nothing_else() -> void:
	var doors := WorldDoors.new()
	for plan in ContentDB.all("table"):
		if str(plan.get("role", "")) != WorldDoors.PLAN_ROLE:
			continue
		assert_false(plan.has("position"), "%s copies its place's position, which stays behind when the place moves" % plan["id"])
		var place := str(plan.get("place", ""))
		var centre := doors._centre_of(place, plan)
		assert_eq(Vector2(centre.x, centre.z), PlaceRef.xz(place), "%s stands its doors round %s" % [plan["id"], place])
	doors.free()


## No definition writes a point on the map where it could name a place. The places' and POIs' own
## `position` is where the map is written down (the atlas writes it), and a region's `map` block
## is its no-world fallback; everything else says what it is beside.
func test_no_definition_holds_coordinates_where_a_place_belongs() -> void:
	var found: Array[String] = []
	for id in ContentDB._defs:
		var def: Dictionary = ContentDB._defs[id]
		var type := Ids.type_of(str(id))
		for key in def:
			if key == "position" and type in ["place", "poi"]:
				continue
			if key == "map" and type == "region":
				continue
			_coordinates_in(def[key], str(key), str(id), found)
	assert_empty(found, "coordinates where a place belongs: " + ", ".join(found.slice(0, 12)))


func _coordinates_in(v: Variant, key: String, id: String, found: Array[String]) -> void:
	if v is Array:
		var a: Array = v
		if key in POINT_KEYS and _is_point(a):
			found.append("%s %s" % [id, key])
			return
		if key in POINT_KEYS and not a.is_empty() and a.all(func(e: Variant) -> bool: return e is Array and _is_point(e)):
			found.append("%s %s[]" % [id, key])
			return
		for e in a:
			_coordinates_in(e, key, id, found)
	elif v is Dictionary:
		for k in v:
			_coordinates_in(v[k], str(k), id, found)


## Two or three numbers, one of them far enough out to be metres on the map rather than a range.
static func _is_point(a: Array) -> bool:
	if a.size() < 2 or a.size() > 3:
		return false
	var far := false
	for e in a:
		if not (e is float or e is int):
			return false
		far = far or absf(float(e)) >= 60.0
	return far
