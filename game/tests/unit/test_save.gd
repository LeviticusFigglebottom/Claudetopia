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


# --- the bound keys ------------------------------------------------------------------------------

func test_quick_save_and_load_use_the_quick_slot() -> void:
	# F5/F9 are bound in default_bindings.json; before this they did nothing at all.
	var had := SaveSystem.slot_exists(SaveSystem.QUICK_SLOT)
	var kept := FileAccess.get_file_as_bytes(SaveSystem.slot_path(SaveSystem.QUICK_SLOT)) if had else PackedByteArray()
	GameState.set_flag("quick_save_probe", true)
	var heard: Array = []
	var handler := func(text: String, kind: String) -> void: heard.append([text, kind])
	EventBus.notify.connect(handler)
	UI.quick_save()
	assert_true(SaveSystem.slot_exists(SaveSystem.QUICK_SLOT))
	GameState.set_flag("quick_save_probe", false)
	UI.quick_load()
	EventBus.notify.disconnect(handler)
	assert_true(GameState.has_flag("quick_save_probe"), "the quick slot came back")
	assert_eq(heard.size(), 2, "the player is told both times")
	for entry in heard:
		assert_eq(str(entry[1]), "save")
	GameState.set_flag("quick_save_probe", false)
	if had:
		var f := FileAccess.open(SaveSystem.slot_path(SaveSystem.QUICK_SLOT), FileAccess.WRITE)
		f.store_buffer(kept)
		f.close()
	else:
		SaveSystem.delete_slot(SaveSystem.QUICK_SLOT)


func test_quick_load_with_nothing_saved_says_so() -> void:
	var had := SaveSystem.slot_exists(SaveSystem.QUICK_SLOT)
	var kept := FileAccess.get_file_as_bytes(SaveSystem.slot_path(SaveSystem.QUICK_SLOT)) if had else PackedByteArray()
	SaveSystem.delete_slot(SaveSystem.QUICK_SLOT)
	var heard: Array = []
	var handler := func(_text: String, kind: String) -> void: heard.append(kind)
	EventBus.notify.connect(handler)
	UI.quick_load()
	EventBus.notify.disconnect(handler)
	assert_eq(heard, ["warning"], "an empty slot warns instead of failing silently")
	if had:
		var f := FileAccess.open(SaveSystem.slot_path(SaveSystem.QUICK_SLOT), FileAccess.WRITE)
		f.store_buffer(kept)
		f.close()


func test_a_freed_participant_cannot_take_the_save_with_it() -> void:
	# A scene torn down without unregistering used to abort serialize() part-way through, so
	# the file was written missing every section after the dead one — including the world flags.
	var ghost := Node.new()
	ghost.set_script(load("res://core/game_state.gd"))
	SaveSystem.register("_ghost_section", ghost)
	ghost.free()
	GameState.set_flag("survives_a_ghost", true)
	var data := SaveSystem.serialize()
	var sections: Dictionary = data.get("sections", {})
	assert_false(sections.has("_ghost_section"), "the dead section is dropped")
	assert_true(sections.has("state"), "and everything else is still written")
	assert_true(bool(sections["state"]["flags"].get("survives_a_ghost", false)))
	assert_false(SaveSystem.participants.has("_ghost_section"), "and it is pruned on the way past")
	GameState.set_flag("survives_a_ghost", false)
