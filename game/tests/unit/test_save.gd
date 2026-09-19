extends TestCase


func test_migrate_v1_fixture() -> void:
	var text := FileAccess.get_file_as_string("res://tests/fixtures/save_v1.json")
	var data: Dictionary = JSON.parse_string(text)
	assert_eq(int(data["schema_version"]), 1)
	var m := Migrations.migrate(data)
	assert_eq(int(m["schema_version"]), SaveSystem.SCHEMA_VERSION)
	assert_has(m["sections"]["player"], "marks")
	assert_false(m["sections"]["player"].has("gold"))
	assert_eq(int(m["sections"]["player"]["marks"]), 120)
	assert_eq(int(m["sections"]["clock"]["day"]), 3)
	assert_near(float(m["sections"]["clock"]["time_hours"]), 6.5, 0.01)
	assert_has(m["sections"]["world"], "weather")


func test_current_version_is_noop() -> void:
	var data := {"schema_version": SaveSystem.SCHEMA_VERSION, "sections": {"player": {"marks": 5}}}
	var m := Migrations.migrate(data.duplicate(true))
	assert_eq(m, data)


func test_round_trip_clock_and_state() -> void:
	WorldClock.set_time(13.25, 7)
	GameState.set_flag("met_wren", true)
	GameState.inc("kills", 3)
	GameState.discover("core:place/merrowby")
	var data := SaveSystem.serialize()
	assert_eq(int(data["schema_version"]), SaveSystem.SCHEMA_VERSION)
	var text := JSON.stringify(data)
	WorldClock.set_time(1.0, 1)
	GameState.reset_for_new_game(1)
	assert_false(GameState.has_flag("met_wren"), "reset must clear flags")
	SaveSystem.deserialize(JSON.parse_string(text))
	assert_near(WorldClock.time_hours, 13.25)
	assert_eq(WorldClock.day, 7)
	assert_true(GameState.has_flag("met_wren"))
	assert_eq(GameState.count("kills"), 3)
	assert_true(GameState.is_discovered("core:place/merrowby"))


func test_slot_write_read() -> void:
	SaveSystem.save_to_slot("_unit_test")
	assert_true(SaveSystem.slot_exists("_unit_test"))
	var slots := SaveSystem.list_slots()
	var found := false
	for s in slots:
		if s["slot"] == "_unit_test":
			found = true
	assert_true(found)
	assert_eq(SaveSystem.load_from_slot("_unit_test"), OK)
	SaveSystem.delete_slot("_unit_test")
	assert_false(SaveSystem.slot_exists("_unit_test"))


func test_late_joiner_pending() -> void:
	SaveSystem.deserialize({"schema_version": SaveSystem.SCHEMA_VERSION, "sections": {"ghost_section": {"x": 1}}})
	assert_eq(SaveSystem.take_pending("ghost_section"), {"x": 1})
	assert_eq(SaveSystem.take_pending("ghost_section"), {})
