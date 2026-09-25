extends TestCase
## A ruined hall stands beside a road through its place, not across it.
##
## The hall is laid along the place's grain, which is the road's direction when a road passes, and
## it stood on the place's middle: a road through the place ran in at one gable and out at the
## other. The road walk on the batch-4 world was held at Bell Street's masonry on the Greyfold road
## for eighteen minutes of the game's time (245 snags, 734 of 2556 m walked). poi_builders.gd now stands
## the hall to the side (`_off_the_road`); `./run.sh roads --only=regressions` walks that road.

## by path: poi_builders.gd has no class_name (a cycle with PoiDressing, which names it by path)
const BUILDERS := preload("res://world/pois/poi_builders.gd")
const HALF := 3.5 + BUILDERS.RUIN_ROAD_CLEAR_M


func _kit(at: Vector2, road: Array) -> PoiKit:
	return PoiKit.new(null, Vector3(at.x, 0.0, at.y), 25.0, "cinderlea", false, "test", null, [road])


## How far the hall's middle stands from the road's line once shifted, across the road.
func _clearance(at: Vector2, road: Array, perp: Vector2) -> float:
	var k := _kit(at, road)
	var off := BUILDERS._off_the_road(k, HALF, perp)
	var a := Vector2(float(road[0][0]), float(road[0][1]))
	var b := Vector2(float(road[1][0]), float(road[1][1]))
	var d := (b - a).normalized()
	var mid := at + perp * off
	return absf((mid - a).cross(d))


func test_a_road_through_the_middle_puts_the_hall_beside_it() -> void:
	# Bell Street: the Greyfold road runs through the place's middle, west to east
	var road := [[-2100.0, 2980.0], [-2000.0, 2980.0]]
	var perp := Vector2(0.0, 1.0)      # across an east-west road
	assert_true(_clearance(Vector2(-2050.0, 2980.0), road, perp) >= HALF - 0.01,
		"the hall's side stands a verge off the road's middle")


func test_a_road_just_off_the_middle_pushes_the_hall_the_other_way() -> void:
	var road := [[-2100.0, 2982.0], [-2000.0, 2982.0]]
	var perp := Vector2(0.0, 1.0)
	var k := _kit(Vector2(-2050.0, 2980.0), road)
	var off := BUILDERS._off_the_road(k, HALF, perp)
	assert_true(off < 0.0, "the road is on the +perp side, so the hall goes to the other (%.2f)" % off)
	assert_true(_clearance(Vector2(-2050.0, 2980.0), road, perp) >= HALF - 0.01)


func test_a_road_well_clear_leaves_the_hall_where_it_was() -> void:
	var road := [[-2100.0, 3000.0], [-2000.0, 3000.0]]
	var k := _kit(Vector2(-2050.0, 2980.0), road)
	assert_eq(BUILDERS._off_the_road(k, HALF, Vector2(0.0, 1.0)), 0.0, "a road 20 m off does not move it")


func test_no_road_leaves_the_hall_where_it_was() -> void:
	var k := PoiKit.new(null, Vector3.ZERO, 25.0, "cinderlea", false, "test", null, [])
	assert_eq(BUILDERS._off_the_road(k, HALF, Vector2(1.0, 0.0)), 0.0)
