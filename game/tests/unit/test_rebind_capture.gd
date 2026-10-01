extends TestCase
## Press-to-rebind: what counts as "the thing you pressed" and what does not.

var capture: RebindCapture


func before_each() -> void:
	capture = RebindCapture.new()


func _key(keycode: Key, pressed := true, echo := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.keycode = keycode
	event.pressed = pressed
	event.echo = echo
	return event


func _pad(button: JoyButton, pressed := true) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	return event


func test_nothing_happens_before_it_starts() -> void:
	assert_eq(capture.consume(_key(KEY_K))["state"], "idle")
	assert_false(capture.active)


func test_a_key_press_binds_and_stops_capturing() -> void:
	capture.start("interact", RebindCapture.KEYBOARD)
	assert_true(capture.active)
	var result := capture.consume(_key(KEY_K))
	assert_eq(result["state"], "bound")
	assert_eq(result["action"], "interact")
	assert_eq(result["slot"], RebindCapture.KEYBOARD)
	assert_eq(result["string"], "key:K")
	assert_false(capture.active, "one press is one binding")


func test_releases_echoes_and_motion_are_not_presses() -> void:
	capture.start("interact", RebindCapture.KEYBOARD)
	assert_eq(capture.consume(_key(KEY_K, false))["state"], "waiting")
	assert_eq(capture.consume(_key(KEY_K, true, true))["state"], "waiting")
	assert_eq(capture.consume(InputEventMouseMotion.new())["state"], "waiting")
	assert_true(capture.active, "still waiting for a real press")
	assert_eq(capture.consume(_key(KEY_J))["state"], "bound")


func test_escape_backs_out() -> void:
	capture.start("interact", RebindCapture.KEYBOARD)
	var result := capture.consume(_key(KEY_ESCAPE))
	assert_eq(result["state"], "cancelled")
	assert_false(capture.active)


func test_a_column_only_takes_its_own_kind_of_device() -> void:
	capture.start("interact", RebindCapture.KEYBOARD)
	assert_eq(capture.consume(_pad(JOY_BUTTON_A))["state"], "waiting", "no pad button in the key column")
	assert_true(capture.active)
	capture.cancel()

	capture.start("interact", RebindCapture.PAD)
	assert_eq(capture.consume(_key(KEY_K))["state"], "waiting", "no key in the pad column")
	var result := capture.consume(_pad(JOY_BUTTON_A))
	assert_eq(result["state"], "bound")
	assert_eq(result["string"], "joy_button:0")


func test_a_stick_has_to_be_pushed_to_count() -> void:
	capture.start("move_forward", RebindCapture.PAD)
	var soft := InputEventJoypadMotion.new()
	soft.axis = JOY_AXIS_LEFT_Y
	soft.axis_value = -0.2
	assert_eq(capture.consume(soft)["state"], "waiting")
	var hard := InputEventJoypadMotion.new()
	hard.axis = JOY_AXIS_LEFT_Y
	hard.axis_value = -0.95
	var result := capture.consume(hard)
	assert_eq(result["state"], "bound")
	assert_eq(result["string"], "joy_axis:1:-1")


func test_a_mouse_button_binds() -> void:
	capture.start("attack_light", RebindCapture.KEYBOARD)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	var result := capture.consume(event)
	assert_eq(result["state"], "bound")
	assert_eq(result["string"], "mouse:2")


func test_labels_read_the_live_bindings() -> void:
	assert_eq(RebindCapture.label_for("move_forward", RebindCapture.KEYBOARD), "W")
	assert_eq(RebindCapture.label_for("move_forward", RebindCapture.PAD), "LY")
	assert_eq(RebindCapture.label_for("nothing_bound_here", RebindCapture.KEYBOARD), "—")


func test_rebinding_through_settings_reports_the_conflict() -> void:
	var before_jump: Array = Settings.bindings.get("jump", []).duplicate()
	var before_sneak: Array = Settings.bindings.get("sneak", []).duplicate()
	var event := _key(KEY_C)                       # C is Sneak by default
	var conflict := Settings.rebind("jump", event, RebindCapture.KEYBOARD)
	assert_eq(conflict, "sneak", "taking a key should say what lost it")
	assert_true(Settings.bindings["jump"].has("key:C"))
	assert_false(Settings.bindings["sneak"].has("key:C"))
	Settings.bindings["jump"] = before_jump
	Settings.bindings["sneak"] = before_sneak
	Settings.apply_bindings()
	Settings.save_settings()


## Triage 80: an action may have a second keyboard-and-mouse binding, in a column of its own (the
## lock-on's Z beside the middle mouse button); rebinding one slot leaves the others alone.
func test_a_second_key_is_bound_in_its_own_column() -> void:
	var before: Array = Settings.bindings.get("lock_on", []).duplicate()
	var before_jump: Array = Settings.bindings.get("jump", []).duplicate()
	assert_eq(RebindCapture.label_for("lock_on", RebindCapture.KEYBOARD), "MMB")
	assert_eq(RebindCapture.label_for("lock_on", RebindCapture.SECOND), "Z")
	assert_eq(RebindCapture.label_for("lock_on", RebindCapture.PAD), "RS")
	assert_eq(RebindCapture.label_for("jump", RebindCapture.SECOND), "—", "most actions have no second key")
	capture.start("lock_on", RebindCapture.SECOND)
	assert_eq(capture.consume(_pad(JOY_BUTTON_A))["state"], "waiting", "the second column takes keys, not buttons")
	var r := capture.consume(_key(KEY_X))
	assert_eq(r["state"], "bound")
	assert_eq(int(r["slot"]), RebindCapture.SECOND)
	assert_eq(Settings.rebind("lock_on", r["event"] as InputEvent, int(r["slot"])), "")
	assert_eq(Settings.prompts_for("lock_on", false), ["MMB", "X"] as Array[String], "the second key changed, the first stayed")
	assert_eq(Settings.bindings_for("lock_on", true), ["joy_button:8"] as Array[String], "and the pad's")
	Settings.rebind("lock_on", _key(KEY_T), RebindCapture.KEYBOARD)
	assert_eq(Settings.prompts_for("lock_on", false), ["T", "X"] as Array[String], "the first changed, the second stayed")
	Settings.rebind("lock_on", _key(KEY_X), RebindCapture.KEYBOARD)
	assert_eq(Settings.prompts_for("lock_on", false), ["X"] as Array[String], "one key is not both of an action's")
	Settings.rebind("jump", _key(KEY_Y), RebindCapture.SECOND)
	assert_eq(Settings.prompts_for("jump", false), ["Space", "Y"] as Array[String], "any action can have a second key")
	assert_eq(SocialContext.keys_in("Jump {key:jump}"), "Jump [Space] or [Y]", "and a lesson names both")
	Settings.bindings["lock_on"] = before
	Settings.bindings["jump"] = before_jump
	Settings.apply_bindings()
	Settings.save_settings()


## A settings file from before the lock-on had a key: its untouched lock-on takes Z as well, unless
## the player had put Z on something else, which keeps it.
func test_an_old_file_s_lock_on_takes_the_key_unless_it_is_the_player_s() -> void:
	assert_eq(Settings.migrated_binding("lock_on", ["mouse:3", "joy_button:8"]), ["mouse:3", "key:Z", "joy_button:8"])
	var test_path := "user://test_lock_on_key.cfg"
	var was_data := Settings.data.duplicate(true)
	var was_bindings := Settings.bindings.duplicate(true)
	for case_z_taken in [false, true]:
		var old := ConfigFile.new()
		old.set_value("bindings", "lock_on", ["mouse:3", "joy_button:8"])
		old.set_value("bindings", "toggle_lantern", ["key:Z"] if case_z_taken else ["key:L"])
		old.save(test_path)
		Settings.path = test_path
		Settings.load_settings()
		if case_z_taken:
			assert_eq(Settings.bindings["lock_on"], ["mouse:3", "joy_button:8"], "Z was the player's lantern: the lock-on does not take it")
			assert_eq(Settings.bindings["toggle_lantern"], ["key:Z"])
		else:
			assert_eq(Settings.bindings["lock_on"], ["mouse:3", "key:Z", "joy_button:8"], "the untouched lock-on takes Z as well")
	Settings.path = Settings.PATH
	Settings.data = was_data
	Settings.bindings = was_bindings
	Settings.apply_bindings()
	DirAccess.remove_absolute(test_path)
