extends TestCase
## The loading caption's watch (UI.LOADING_QUIET_S): a caption that waits on something that never
## comes says what it is waiting on, reports it, and offers the way back to the title; one that is
## still moving is left alone. The owner's Continue after a change of settings sat on the caption for
## good (2026-10-02), and nothing on the screen or in the logs said what it waited for.


func after_each() -> void:
	UI.fade_from_black(0.0)
	GameState.clear_flag("_pending_load_slot")


func test_the_caption_says_what_it_is_waiting_on() -> void:
	assert_eq(UI.loading_wait(), "", "no caption, nothing waited on")
	UI.fade_to_black(0.0, "The Roll is read again, and your name is in it.")
	assert_true(UI.loading_wait().begins_with("the world's scene to come in"),
			"with no world yet it waits for the world's scene: %s" % UI.loading_wait())
	assert_false(UI.is_loading_stuck())


func test_a_load_that_stops_moving_is_reported_and_offered_the_way_back() -> void:
	UI.fade_to_black(0.0, "The Roll is read again, and your name is in it.")
	var t0 := Time.get_ticks_msec()
	UI._watch_loading(t0)
	UI._watch_loading(t0 + 30000)
	assert_false(UI.is_loading_stuck(), "half a minute on one thing is a slow machine, not a stuck one")
	var said: Array = []
	var heard := func(what: String, quiet_s: float) -> void: said.append([what, quiet_s])
	UI.loading_stuck.connect(heard)
	UI._watch_loading(t0 + int(UI.LOADING_QUIET_S * 1000.0) + 10)
	UI.loading_stuck.disconnect(heard)
	assert_true(UI.is_loading_stuck(), "a minute without moving is a load that has stopped")
	assert_eq(said.size(), 1, "said once")
	assert_true(str(UI.last_loading_stuck.get("what", "")).begins_with("the world's scene to come in"),
			"with what it waits on: %s" % str(UI.last_loading_stuck))
	var state: Dictionary = UI.last_loading_stuck.get("state", {})
	for key in ["scene", "paused", "reads", "read_limit", "safe_mode", "settings_off_default"]:
		assert_true(state.has(key), "the report carries %s" % key)
	var back := UI._loading_back
	var note := UI._loading_note
	assert_true(back.visible and note.visible, "the caption says so and offers the way back")
	assert_true(note.text.contains("the world's scene to come in"), note.text)
	# it goes on waiting: one report, not one a frame
	UI._watch_loading(t0 + int(UI.LOADING_QUIET_S * 1000.0) + 5000)
	assert_eq(said.size(), 1)


func test_a_load_that_moves_again_takes_the_note_down() -> void:
	UI.fade_to_black(0.0, "The Roll is read again, and your name is in it.")
	var t0 := Time.get_ticks_msec()
	UI._watch_loading(t0)
	UI._watch_loading(t0 + int(UI.LOADING_QUIET_S * 1000.0) + 10)
	assert_true(UI.is_loading_stuck())
	# what it waits on changes (a cell came, the world went on a step): it is moving
	UI._loading_wait = "something else"
	UI._watch_loading(t0 + int(UI.LOADING_QUIET_S * 1000.0) + 20)
	assert_false(UI.is_loading_stuck(), "moving again")
	assert_false(UI._loading_back.visible, "and the way back goes with the note")


func test_the_way_back_lets_go_of_the_load() -> void:
	GameState.set_flag("_pending_load_slot", "never_read")
	UI.fade_to_black(0.0, "The Roll is read again, and your name is in it.")
	var t0 := Time.get_ticks_msec()
	UI._watch_loading(t0)
	UI._watch_loading(t0 + int(UI.LOADING_QUIET_S * 1000.0) + 10)
	(Engine.get_main_loop() as SceneTree).paused = true
	# (the scene itself is not changed here: the suite's runner is the current scene)
	UI.back_to_title(false)
	assert_false((Engine.get_main_loop() as SceneTree).paused, "nothing is left paused")
	assert_false(GameState.has_flag("_pending_load_slot"), "the slot asked for is let go")
	assert_false(UI.is_loading_shown(), "the caption is down")
	assert_false(UI.is_loading_stuck())
