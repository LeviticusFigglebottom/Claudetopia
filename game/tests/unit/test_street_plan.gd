extends TestCase
## Where a settlement's streets run and where its houses stand along them (world/exteriors/
## street_plan.gd). A town used to be a ring of houses looking in at a green, their doors turned
## to the middle and not to the roads; these pin the streets as the grain of the place: every
## house fronts a street with its door on it, nothing stands on a road or in the open middle,
## nothing stands in anything else, a house with an inside goes on the frontage nearest where
## its door plan wanted it, and the same place is planned the same way every time.

const CENTRE := Vector2(900.0, 2350.0)


## A straight road through `at` on `bearing_deg`, `reach` metres each way, as roads.json has it.
func _road(bearing_deg: float, reach := 120.0, at := CENTRE) -> Array:
	var a := deg_to_rad(bearing_deg)
	var dir := Vector2(sin(a), cos(a))
	var out: Array = []
	for i in range(-12, 13):
		var p := at + dir * (reach * float(i) / 12.0)
		out.append([p.x, p.y])
	return out


func _plan(kind := "village", roads: Array = [], id := "core:place/test_streets", radius := 64.0) -> StreetPlan:
	return StreetPlan.make(id, kind, CENTRE, radius, roads)


# --- the streets ------------------------------------------------------------------------------------

func test_a_road_through_the_middle_is_two_streets() -> void:
	var plan := _plan("village", [_road(30.0)])
	assert_eq(plan.arms.size(), 2, "a road through the middle is a street each way")
	var a := float(plan.arms[0]["bearing"])
	var b := float(plan.arms[1]["bearing"])
	assert_near(absf(fposmod(b - a, 360.0) - 180.0), 0.0, 3.0, "the two arms leave in opposite directions")


func test_a_crossroads_is_four_streets_and_two_roads_on_one_line_are_one() -> void:
	var plan := _plan("town", [_road(30.0), _road(120.0), _road(35.0)])
	assert_eq(plan.arms.size(), 4, "two roads crossing, and a third on the line of the first: %d arms" % plan.arms.size())


func test_a_place_no_road_crosses_still_has_a_street() -> void:
	var plan := _plan("village", [])
	assert_eq(plan.arms.size(), 2, "a village with no road through it was given no street")
	var again := _plan("village", [])
	assert_near(float(again.arms[0]["bearing"]), float(plan.arms[0]["bearing"]), 0.001,
			"and it is the same street every time")


# --- the plots --------------------------------------------------------------------------------------

func test_houses_front_the_street_with_their_doors_on_it() -> void:
	var plan := _plan("village", [_road(30.0), _road(115.0)])
	var n := plan.fill(20)
	assert_gt(n, 8, "a village on a crossroads found room for only %d houses" % n)
	var sb: Array = plan.layout()["setback"]
	for h in plan.houses:
		var door: Vector2 = h["door"]
		var facing: Vector2 = h["facing"]
		var off := plan.road_distance(door)
		assert_true(off >= StreetPlan.ROAD_HALF_M + float(sb[0]) - 0.2 and off <= StreetPlan.ROAD_HALF_M + float(sb[1]) + 0.2,
				"a front door %.1f m from the road's middle" % off)
		# a step out of the door toward the street is a step nearer the road
		assert_true(plan.road_distance(door + facing * 1.0) < off, "a house turns its back to the street")


func test_nothing_stands_on_a_road_or_in_the_open_middle() -> void:
	var plan := _plan("town", [_road(30.0), _road(115.0)])
	plan.fill(40)
	for h in plan.houses:
		for p in StreetPlan.corners(h["box"]):
			assert_true(plan.road_distance(p) > StreetPlan.ROAD_HALF_M, "a house corner on the road at %s" % p)
		assert_true(StreetPlan._nearest_distance(h["box"], CENTRE) >= plan.hub - 0.01, "a house in the market square")
		var g: Dictionary = h["garden"]
		if not g.is_empty():
			for p in StreetPlan.corners(g):
				assert_true(plan.road_distance(p) > StreetPlan.ROAD_HALF_M, "a garden across the road")


func test_no_house_or_garden_stands_in_another() -> void:
	var plan := _plan("town", [_road(30.0), _road(115.0)])
	plan.fill(40)
	var boxes: Array = []
	for h in plan.houses:
		boxes.append(h["box"])
		if not (h["garden"] as Dictionary).is_empty():
			boxes.append(h["garden"])
	for i in range(boxes.size()):
		for j in range(i + 1, boxes.size()):
			assert_false(StreetPlan.overlaps(boxes[i], boxes[j], 0.02), "plots %d and %d overlap" % [i, j])


func test_a_garden_runs_back_from_its_house() -> void:
	var plan := _plan("village", [_road(30.0)])
	plan.fill(16)
	var gardens := 0
	for h in plan.houses:
		var g: Dictionary = h["garden"]
		if g.is_empty():
			continue
		gardens += 1
		var b: Dictionary = h["box"]
		assert_gt(((g["c"] as Vector2) - (b["c"] as Vector2)).dot(b["v"]), 0.0, "a garden in front of its house")
	assert_gt(gardens, floori(plan.houses.size() / 2.0), "a village of %d houses with %d gardens" % [plan.houses.size(), gardens])


func test_a_house_on_either_side_of_the_street_is_the_same_way_round() -> void:
	# (u, up, v) must be a right-handed frame on both sides, or one side's houses are mirrored
	var plan := _plan("village", [_road(30.0)])
	plan.fill(16)
	var sides := {}
	for h in plan.houses:
		var b: Dictionary = h["box"]
		var u: Vector2 = b["u"]
		var v: Vector2 = b["v"]
		assert_near(Vector2(-u.y, u.x).dot(v), 1.0, 0.001, "a house built as its own mirror image")
		sides[float(h["side"])] = true
	assert_eq(sides.size(), 2, "houses on only one side of the street")


# --- the houses with an inside ---------------------------------------------------------------------

func test_a_house_with_an_inside_goes_on_the_frontage_nearest_its_plan() -> void:
	var plan := _plan("town", [_road(30.0), _road(115.0)])
	# a 9 x 8 m house whose door is 2.5 m from its left-hand wall, wanted 30 m out on bearing 70
	var foot := Rect2(-2.5, 0.3, 9.0, 8.0)
	var wanted := CENTRE + Vector2(sin(deg_to_rad(70.0)), cos(deg_to_rad(70.0))) * 30.0
	var plot := plan.place_real("core:interior/test", foot, wanted)
	assert_false(plot.is_empty(), "a town with two streets had no frontage for one house")
	var door: Vector2 = plot["door"]
	assert_true(door.distance_to(wanted) < 22.0, "the house went %.0f m from where it was wanted" % door.distance_to(wanted))
	assert_true(plan.road_distance(door) < StreetPlan.ROAD_HALF_M + 3.0, "its door is not on a street")
	assert_true(plan.road_distance(door + (plot["facing"] as Vector2)) < plan.road_distance(door), "and faces it")
	# the footprint's middle is 2 m to the house's right of the door (its own +x, the box's u)
	var b: Dictionary = plot["box"]
	var along := ((b["c"] as Vector2) - door).dot(b["u"])
	assert_near(along, 2.0, 0.01, "the house is not built round its own door")
	var second := plan.place_real("core:interior/test_two", foot, wanted)
	assert_false(second.is_empty(), "no room for a second house")
	assert_false(StreetPlan.overlaps(plot["box"], second["box"]), "two houses in one plot")


func test_the_fabric_fills_round_the_real_houses() -> void:
	var plan := _plan("town", [_road(30.0), _road(115.0)])
	var real := plan.place_real("core:interior/test", Rect2(-2.5, 0.3, 9.0, 8.0), CENTRE + Vector2(20.0, 20.0))
	plan.fill(40)
	for h in plan.houses:
		if h == real:
			continue
		assert_false(StreetPlan.overlaps(real["box"], h["box"]), "the fabric built through a house with an inside")


func test_the_same_place_is_planned_the_same_way_twice() -> void:
	var a := _plan("town", [_road(30.0), _road(115.0)], "core:place/test_twice")
	var b := _plan("town", [_road(30.0), _road(115.0)], "core:place/test_twice")
	a.fill(30)
	b.fill(30)
	assert_eq(a.houses.size(), b.houses.size())
	for i in range(a.houses.size()):
		assert_true((a.houses[i]["door"] as Vector2).distance_to(b.houses[i]["door"]) < 0.001, "house %d moved" % i)
	var c := _plan("town", [_road(30.0), _road(115.0)], "core:place/test_other")
	c.fill(30)
	var same := 0
	for i in range(mini(a.houses.size(), c.houses.size())):
		if (a.houses[i]["door"] as Vector2).distance_to(c.houses[i]["door"]) < 0.001:
			same += 1
	assert_true(same < a.houses.size(), "two places on the same roads were built as one town")


# --- the middle -------------------------------------------------------------------------------------

func test_the_open_middle_is_cut_into_the_gaps_between_the_streets() -> void:
	var plan := _plan("town", [_road(0.0), _road(90.0)])
	var wedges := plan.wedges()
	assert_eq(wedges.size(), 4)
	for w in wedges:
		assert_near(float(w["width"]), 90.0, 2.0)
		# the middle of a gap is as far from the roads as the gap allows
		var p := plan.hub_point(float(w["bearing"]), plan.hub * 0.6)
		assert_gt(plan.road_distance(p), StreetPlan.ROAD_HALF_M, "the middle of a gap is on a road")


# --- boxes ------------------------------------------------------------------------------------------

func test_boxes_overlap_only_when_they_do() -> void:
	var a := StreetPlan.box(Vector2.ZERO, Vector2.RIGHT, 2.0, 1.0)
	var near := StreetPlan.box(Vector2(3.5, 0.0), Vector2.RIGHT, 2.0, 1.0)
	var far := StreetPlan.box(Vector2(4.5, 0.0), Vector2.RIGHT, 2.0, 1.0)
	# turned 45 degrees, its corner reaching toward `a` but not into it
	var turned := StreetPlan.box(Vector2(3.9, 0.0), Vector2(1.0, 1.0), 1.0, 1.0)
	assert_true(StreetPlan.overlaps(a, near))
	assert_false(StreetPlan.overlaps(a, far))
	assert_false(StreetPlan.overlaps(a, turned), "a corner that stops short of the box was counted as inside it")
	assert_true(StreetPlan.segment_hits(a, Vector2(-5.0, 0.5), Vector2(5.0, 0.5), 0.0), "a road straight through")
	assert_false(StreetPlan.segment_hits(a, Vector2(-5.0, 2.0), Vector2(5.0, 2.0), 0.5), "a road that passes by")
	assert_true(StreetPlan.segment_hits(a, Vector2(-5.0, 2.0), Vector2(5.0, 2.0), 1.2), "a road that passes too close")
	assert_false(StreetPlan.segment_hits(a, Vector2(3.0, -5.0), Vector2(3.0, 5.0), 0.5), "a road beside it")


func test_lanes_go_back_between_the_gardens() -> void:
	var plan := _plan("town", [_road(30.0), _road(115.0)])
	plan.fill(40)
	assert_false(plan.lanes.is_empty(), "a town of forty houses with no way through to the back")
	for lane in plan.lanes:
		for h in plan.houses:
			assert_false(StreetPlan.overlaps(lane, h["box"]), "a lane through a house")
			var g: Dictionary = h["garden"]
			if not g.is_empty():
				assert_false(StreetPlan.overlaps(lane, g), "a lane through a garden")
		# it starts at the street: its near end is at the road's edge
		var near: Vector2 = (lane["c"] as Vector2) - (lane["v"] as Vector2) * float(lane["hd"])
		assert_true(plan.road_distance(near) < StreetPlan.ROAD_HALF_M + 0.5, "a lane that starts nowhere")
	var hamlet := _plan("hamlet", [_road(30.0)], "core:place/test_lane_hamlet")
	hamlet.fill(9)
	assert_true(hamlet.lanes.is_empty(), "a hamlet of nine houses with lanes between them")
