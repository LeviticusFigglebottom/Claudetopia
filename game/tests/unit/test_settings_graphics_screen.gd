extends TestCase
## Pressing every control on the Graphics tab, the way `test_station_screen` presses the forge:
## find it on the screen, press it, and ask `Settings` and the engine -- not the screen -- whether
## anything happened. Then the presets, the greying out on a renderer that cannot do a thing, and
## the screen closing.

var _saved: Dictionary = {}


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	_saved = Settings.data.duplicate(true)
	Graphics.renderer_override = ""
	UI.gameplay_override = true


func after_each() -> void:
	UI.close_all()
	UI.gameplay_override = false
	_tree().paused = false
	Graphics.renderer_override = ""
	Settings.data = _saved.duplicate(true)
	Settings.apply_all()


func _open() -> Node:
	var screen := UI.open("settings", {"tab": "Graphics"})
	await _tree().process_frame
	return screen


## Every pressable control on the screen that is bound to a graphics key, by key.
func _controls(screen: Node) -> Dictionary:
	var out: Dictionary = {}
	for n in screen.find_children("*", "", true, false):
		if not n.has_meta("setting_key") or n.is_queued_for_deletion():
			continue
		if n is CheckBox or n is HSlider or n is OptionButton:
			out[str(n.get_meta("setting_key"))] = n
	return out


func _preset_button(screen: Node, preset: String) -> Button:
	for n in screen.find_children("*", "Button", true, false):
		if n.has_meta("preset") and str(n.get_meta("preset")) == preset and not n.is_queued_for_deletion():
			return n
	return null


## Press a control to a value other than the one it shows. Returns false if it could not be.
static func _press(control: Control) -> bool:
	if control is CheckBox:
		var box := control as CheckBox
		if box.disabled:
			return false
		box.button_pressed = not box.button_pressed
		return true
	if control is HSlider:
		var s := control as HSlider
		s.value = s.min_value if not is_equal_approx(s.value, s.min_value) else s.max_value
		return true
	if control is OptionButton:
		var o := control as OptionButton
		for i in o.item_count:
			if i != o.selected and not o.is_item_disabled(i):
				o.select(i)
				o.item_selected.emit(i)
				return true
	return false


func test_every_graphics_knob_is_on_the_screen_and_pressing_it_changes_the_setting() -> void:
	var screen := await _open()
	var controls := _controls(screen)
	var missing: Array[String] = []
	var unmoved: Array[String] = []
	for c in Graphics.CONTROLS:
		var key := str(c["key"])
		if not controls.has(key):
			missing.append(key)
			continue
		var before: Variant = Settings.get_value("graphics", key)
		if not _press(controls[key]):
			unmoved.append("%s (could not be pressed)" % key)
			continue
		if str(Settings.get_value("graphics", key)) == str(before):
			unmoved.append("%s (still %s)" % [key, str(before)])
	assert_empty(missing, "knobs with no control on the Graphics tab: %s" % ", ".join(missing))
	assert_empty(unmoved, "controls that did not move their setting: %s" % ", ".join(unmoved))
	assert_eq(Settings.get_value("graphics", "preset"), "custom", "a pressed knob makes the preset custom")


func test_a_pressed_control_reaches_the_engine() -> void:
	var screen := await _open()
	var controls := _controls(screen)
	var scale: HSlider = controls["render_scale"]
	scale.value = 0.55
	assert_near(_tree().root.scaling_3d_scale, 0.55, 0.001, "render scale reached the viewport")
	var msaa: OptionButton = controls["msaa"]
	msaa.select(2)
	msaa.item_selected.emit(2)
	assert_eq(_tree().root.msaa_3d, Viewport.MSAA_4X, "4x reached the viewport")
	var cap: OptionButton = controls["fps_cap"]
	cap.select(2)
	cap.item_selected.emit(2)
	assert_eq(Engine.max_fps, 60, "the third choice is a 60 frame cap")


func test_each_preset_button_sets_every_knob() -> void:
	for preset in Graphics.PRESET_ORDER:
		var screen := await _open()
		var b := _preset_button(screen, preset)
		assert_true(b != null, "no %s button" % preset)
		if b == null:
			continue
		b.pressed.emit()
		await _tree().process_frame
		var want := Graphics.preset_values(preset)
		for key in want:
			assert_eq(str(Settings.get_value("graphics", key)), str(want[key]),
					"%s: %s after pressing %s" % [preset, key, preset])
		assert_eq(Settings.get_value("graphics", "preset"), preset)
		# the rebuilt tab shows the preset's values, not the old ones
		var shown: HSlider = _controls(screen)["render_scale"]
		assert_near(shown.value, float(want["render_scale"]), 0.001, "%s shows its render scale" % preset)
		UI.close_all()
		await _tree().process_frame


func test_what_compatibility_cannot_do_is_greyed_out_with_the_reason() -> void:
	Graphics.renderer_override = Graphics.RENDERER_COMPATIBILITY
	var screen := await _open()
	var controls := _controls(screen)
	for key in ["fxaa", "taa", "volumetric_fog", "ssil", "sdfgi"]:
		var box: CheckBox = controls.get(key)
		assert_true(box != null and box.disabled, "%s should be greyed out on Compatibility" % key)
	var words := ""
	for l in screen.find_children("*", "Label", true, false):
		words += (l as Label).text + "\n"
	assert_true(words.contains("the Compatibility renderer has no SDFGI"), "the reason is on the screen")
	var up: OptionButton = controls["upscaler"]
	assert_false(up.disabled, "bilinear scaling is still offered")
	assert_false(up.is_item_disabled(0))
	assert_true(up.is_item_disabled(1) and up.is_item_disabled(2), "FSR is not")
	for key in ["msaa", "ssao", "glow", "shadows"]:
		var c: Control = controls[key]
		assert_false((c as BaseButton).disabled if c is BaseButton else false, "%s works on Compatibility" % key)


func test_the_graphics_tab_closes_on_the_pause_key_and_on_done() -> void:
	await _open()
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.physical_keycode = KEY_ESCAPE
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _tree().process_frame
	await _tree().process_frame
	assert_false(UI.is_menu_open("settings"), "Escape closes the Graphics tab")
	var screen := await _open()
	var done: Button = null
	for n in screen.find_children("*", "Button", true, false):
		if (n as Button).text == "Done":
			done = n
	assert_true(done != null, "a Done button")
	if done != null:
		done.pressed.emit()
		await _tree().process_frame
	assert_false(UI.is_menu_open("settings"), "Done closes it")


func test_a_tab_opens_by_name() -> void:
	var screen := UI.open("settings", {"tab": "Controls"})
	await _tree().process_frame
	assert_eq(int(screen.get("_tab")), 3, "Controls by name")
	assert_true(_controls(screen).is_empty(), "and the graphics knobs are not on it")
