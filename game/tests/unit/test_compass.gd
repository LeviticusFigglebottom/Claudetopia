extends TestCase
## The compass strip: bearings out of the world, offsets onto the strip.


func test_wrap_delta_folds_into_half_turns() -> void:
	assert_near(Compass.wrap_delta(0.0), 0.0)
	assert_near(Compass.wrap_delta(90.0), 90.0)
	assert_near(Compass.wrap_delta(350.0), -10.0)
	assert_near(Compass.wrap_delta(-350.0), 10.0)
	assert_near(absf(Compass.wrap_delta(540.0)), 180.0, 0.001, "half a turn is half a turn either way")


func test_bearings_follow_the_world_axes() -> void:
	# CONTRACTS §1: x east, z south, so north is -Z
	var here := Vector2(100.0, 200.0)
	assert_near(Compass.bearing_deg(here, here + Vector2(0.0, -50.0)), 0.0, 0.01, "north")
	assert_near(Compass.bearing_deg(here, here + Vector2(50.0, 0.0)), 90.0, 0.01, "east")
	assert_near(Compass.bearing_deg(here, here + Vector2(0.0, 50.0)), 180.0, 0.01, "south")
	assert_near(Compass.bearing_deg(here, here + Vector2(-50.0, 0.0)), 270.0, 0.01, "west")
	assert_near(Compass.bearing_deg(here, here + Vector2(50.0, -50.0)), 45.0, 0.01, "north-east")
	assert_near(Compass.bearing_deg(here, here), 0.0, 0.01, "a place you are standing on")


func test_heading_from_a_basis() -> void:
	assert_near(Compass.heading_from_basis(Basis.IDENTITY), 0.0, 0.01, "forward is -Z, so north")
	assert_near(Compass.heading_from_basis(Basis(Vector3.UP, deg_to_rad(-90.0))), 90.0, 0.01)
	assert_near(Compass.heading_from_basis(Basis(Vector3.UP, deg_to_rad(90.0))), 270.0, 0.01)


func test_strip_offset_puts_what_you_face_in_the_middle() -> void:
	var width := 500.0
	assert_near(Compass.strip_offset(0.0, 0.0, width), 250.0, 0.01)
	assert_near(Compass.strip_offset(90.0, 90.0, width), 250.0, 0.01)
	# the span covers 150 degrees end to end, so 75 degrees off is the edge
	assert_near(Compass.strip_offset(75.0, 0.0, width), 500.0, 0.01)
	assert_near(Compass.strip_offset(285.0, 0.0, width), 0.0, 0.01)
	# and it is linear in between
	assert_near(Compass.strip_offset(37.5, 0.0, width), 375.0, 0.01)
	# turning right slides everything left
	assert_gt(Compass.strip_offset(0.0, 0.0, width), Compass.strip_offset(0.0, 20.0, width))


func test_only_what_is_in_front_is_on_the_strip() -> void:
	assert_true(Compass.on_strip(0.0, 0.0))
	assert_true(Compass.on_strip(70.0, 0.0))
	assert_false(Compass.on_strip(120.0, 0.0))
	assert_false(Compass.on_strip(180.0, 0.0))
	assert_true(Compass.on_strip(350.0, 10.0), "wrapping past north still counts")


func test_glyphs_fade_toward_the_ends() -> void:
	assert_near(Compass.centre_weight(0.0, 0.0), 1.0, 0.001)
	assert_near(Compass.centre_weight(75.0, 0.0), 0.0, 0.001)
	assert_near(Compass.centre_weight(37.5, 0.0), 0.5, 0.001)
	assert_eq(Compass.centre_weight(180.0, 0.0), 0.0)


func test_a_place_due_north_lands_under_the_n() -> void:
	var player := Vector2(900.0, 2350.0)
	var place := Vector2(900.0, 1350.0)          # 1 km north
	var bearing := Compass.bearing_deg(player, place)
	assert_near(bearing, 0.0, 0.01)
	var heading := 0.0
	assert_near(Compass.strip_offset(bearing, heading, 520.0),
			Compass.strip_offset(0.0, heading, 520.0), 0.01, "it sits exactly on the N glyph")
