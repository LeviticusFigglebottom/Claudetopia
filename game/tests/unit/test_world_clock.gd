extends TestCase


func test_advance_wraps_days() -> void:
	WorldClock.set_time(23.0, 2)
	WorldClock.advance_hours(2.0)
	assert_eq(WorldClock.day, 3)
	assert_near(WorldClock.time_hours, 1.0)


func test_wait_until() -> void:
	WorldClock.set_time(22.0, 1)
	var waited := WorldClock.wait_until(6.0)
	assert_near(waited, 8.0)
	assert_eq(WorldClock.day, 2)
	assert_near(WorldClock.time_hours, 6.0)


func test_daylight_and_night() -> void:
	WorldClock.set_time(12.0)
	assert_near(WorldClock.daylight(), 1.0)
	assert_false(WorldClock.is_night())
	WorldClock.set_time(0.0)
	assert_near(WorldClock.daylight(), 0.0)
	assert_true(WorldClock.is_night())


func test_settings_bindings_roundtrip() -> void:
	var ev := Settings.string_to_event("key:W")
	assert_true(ev is InputEventKey)
	assert_eq(Settings.event_to_string(ev), "key:W")
	var j := Settings.string_to_event("joy_axis:1:-1")
	assert_true(j is InputEventJoypadMotion)
	assert_eq(Settings.event_to_string(j), "joy_axis:1:-1")
	assert_true(InputMap.has_action("attack_light"))
	assert_gt(InputMap.action_get_events("move_forward").size(), 1)
