extends Control
## Settings (DESIGN §5.19). Five tabs, everything bound to the Settings autoload and applied
## the moment it changes, because a settings screen that needs an "Apply" button is a settings
## screen that lies to you.
##
## The Controls tab is built from Settings.binding_defs, so adding an action to
## core/default_bindings.json puts it here with no code change.

const TABS := ["Video", "Audio", "Controls", "Gameplay", "Accessibility"]

var from_menu := false
var _tab := 0
var _tab_buttons: Array[Control] = []
var _content: VBoxContainer
var _notice: Label
var _capture := RebindCapture.new()
var _capture_button: Button = null
var _scroll: ScrollContainer
var _pending_scroll := 0.0
var _compact := false
var _grid: GridContainer = null


func setup(args: Dictionary) -> void:
	from_menu = bool(args.get("from_menu", false))
	_tab = int(args.get("tab", 0))
	_pending_scroll = float(args.get("scroll", 0.0))
	if is_inside_tree():
		_show_tab(_tab)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.dim())
	_build()
	_show_tab(_tab)


func _build() -> void:
	var page := UiKit.page("Settings")
	var frame: PanelContainer = page["frame"]
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 110.0
	frame.offset_top = 36.0
	frame.offset_right = -110.0
	frame.offset_bottom = -36.0
	add_child(frame)
	var body: VBoxContainer = page["body"]

	var tabs := UiKit.row(6)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(tabs)
	for i in TABS.size():
		var b := UiKit.button(TABS[i], "FlatButton")
		var index := i
		b.pressed.connect(func() -> void: _show_tab(index))
		tabs.add_child(b)
		_tab_buttons.append(b)
	UiKit.focus_chain(_tab_buttons, false)

	_content = UiKit.column(6)
	_scroll = UiKit.scroll(_content)
	body.add_child(_scroll)

	_notice = UiKit.label("", "Small", HORIZONTAL_ALIGNMENT_CENTER)
	_notice.modulate = Color(1, 1, 1, 0.0)
	body.add_child(_notice)

	var foot := UiKit.row(10)
	foot.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(foot)
	var close := UiKit.button("Done", "FlatButton")
	close.pressed.connect(func() -> void: UI.close("settings"))
	foot.add_child(close)
	UiKit.ink_in(frame, 0.0, 0.32)


func _show_tab(index: int) -> void:
	_tab = clampi(index, 0, TABS.size() - 1)
	for i in _tab_buttons.size():
		_tab_buttons[i].modulate = Color(1, 1, 1, 1.0 if i == _tab else 0.55)
	for child in _content.get_children():
		child.queue_free()
	match _tab:
		0: _build_video()
		1: _build_audio()
		2: _build_controls()
		3: _build_gameplay()
		_: _build_accessibility()
	UiKit.ink_in(_content, 0.0, 0.26)
	if not _tab_buttons.is_empty():
		_tab_buttons[_tab].grab_focus()
	if _pending_scroll > 0.0:
		var wanted := _pending_scroll
		_pending_scroll = 0.0
		await get_tree().process_frame
		await get_tree().process_frame
		if is_instance_valid(_scroll):
			_scroll.scroll_vertical = int(wanted)


# --- rows ---------------------------------------------------------------------------------

func _row(label: String, control: Control, note := "") -> HBoxContainer:
	var row := UiKit.row(14)
	row.custom_minimum_size = Vector2(0, 34 if _compact else 38)
	var name_label := UiKit.label(label, "Body")
	name_label.custom_minimum_size = Vector2(196 if _compact else 300, 0)
	name_label.tooltip_text = note
	row.add_child(name_label)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	if not note.is_empty() and not _compact:
		var hint := UiKit.label(note, "Tiny")
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(hint)
	_target().add_child(row)
	return row


## Rows are added here, so a tab can send them into a grid instead of down the page.
func _target() -> Node:
	return _grid if _grid != null else _content


func _check(section: String, key: String, label: String, note := "") -> void:
	var c := CheckBox.new()
	c.button_pressed = bool(Settings.get_value(section, key, false))
	c.toggled.connect(func(on: bool) -> void: Settings.set_value(section, key, on))
	_row(label, c, note)


func _slider(section: String, key: String, label: String, low: float, high: float,
		step := 0.05, suffix := "") -> void:
	var box := UiKit.row(10)
	var s := HSlider.new()
	s.min_value = low
	s.max_value = high
	s.step = step
	s.value = float(Settings.get_value(section, key, low))
	s.custom_minimum_size = Vector2(150 if _compact else 260, 20)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value_label := UiKit.label(_format(s.value, suffix), "Small")
	value_label.custom_minimum_size = Vector2(60 if _compact else 90, 0)
	s.value_changed.connect(func(v: float) -> void:
			Settings.set_value(section, key, v)
			value_label.text = _format(v, suffix))
	box.add_child(s)
	box.add_child(value_label)
	_row(label, box)


func _format(value: float, suffix: String) -> String:
	if suffix == "%":
		return "%d%%" % roundi(value * 100.0)
	if suffix != "":
		return "%d %s" % [roundi(value), suffix]
	return "%.2f" % value


func _option(section: String, key: String, label: String, choices: Array, note := "") -> void:
	var o := OptionButton.new()
	for c in choices:
		o.add_item(str(c))
	o.selected = clampi(int(Settings.get_value(section, key, 0)), 0, choices.size() - 1)
	o.item_selected.connect(func(index: int) -> void: Settings.set_value(section, key, index))
	_row(label, o, note)


# --- tabs ----------------------------------------------------------------------------------

func _build_video() -> void:
	_check("video", "fullscreen", "Fullscreen")
	_check("video", "vsync", "Wait for the frame (vsync)")
	_slider("video", "fov", "Field of view", 60.0, 110.0, 1.0, "°")
	_slider("video", "render_scale", "Render scale", 0.5, 1.0, 0.05, "%")
	_option("video", "shadows", "Shadows", ["Off", "Low", "Medium", "High"])
	_option("video", "msaa", "Edge smoothing", ["Off", "2×", "4×", "8×"])
	_check("video", "ssao", "Corner shadow (SSAO)", "Forward+ only")
	_check("video", "volumetric_fog", "Volumetric fog", "Forward+ only")
	_check("video", "sdfgi", "Bounced light (SDFGI)", "Forward+ only")
	_check("video", "color_grade", "Region colour grade")
	_check("video", "vignette", "Vignette")
	_check("video", "film_grain", "Film grain")
	_check("video", "water_reflections", "Reflections in the water")
	_slider("video", "night_lights", "Lamps lit at night", 0.0, 8.0, 1.0, "lamps")
	_check("video", "glow", "Glow")
	_slider("video", "brightness", "Brightness", 0.6, 1.6, 0.05)


func _build_audio() -> void:
	for pair in [["master", "Everything"], ["music", "Music"], ["sfx", "Sounds"],
			["ambience", "The world"], ["ui", "Paper and brass"], ["voice", "Voices"]]:
		_slider("audio", str(pair[0]), str(pair[1]), 0.0, 1.0, 0.05, "%")


func _build_gameplay() -> void:
	_slider("gameplay", "day_length_minutes", "Length of a day", 12.0, 120.0, 1.0, "min")
	_option("gameplay", "difficulty", "Difficulty", ["Kind", "Ordinary", "Hard", "Quiet"])
	_check("gameplay", "subtitles", "Subtitles")
	_check("gameplay", "show_hints", "Hints")
	_check("gameplay", "compass", "Compass")
	_slider("gameplay", "hud_opacity", "How loud the HUD is", 0.2, 1.0, 0.05, "%")


func _build_accessibility() -> void:
	_option("accessibility", "colourblind", "Colour-blind palette",
			["Off", "Red-green (protan)", "Red-green (deutan)", "Blue-yellow (tritan)"],
			"changes the bar colours only")
	_slider("accessibility", "ui_scale", "Size of the UI", 0.8, 1.4, 0.05, "%")
	_check("accessibility", "reduce_flashing", "Less flashing")
	_content.add_child(UiKit.divider())
	_content.add_child(UiKit.wrapped(
			"The UI scale applies the next time a screen is opened. Colour-blind palettes " +
			"change the bar fills and the map's region tints, never the words.", "Journal"))


# --- controls ---------------------------------------------------------------------------------

func _build_controls() -> void:
	_compact = true
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 30)
	_content.add_child(_grid)
	_slider("controls", "mouse_sensitivity", "Mouse sensitivity", 0.05, 1.0, 0.01)
	_slider("controls", "gamepad_sensitivity", "Stick sensitivity", 0.5, 6.0, 0.1)
	_check("controls", "invert_y", "Invert looking up and down")
	_option("controls", "camera_side", "Camera side", ["Left", "Right"])
	_check("controls", "vibration", "Vibration")
	_check("controls", "toggle_sprint", "Sprint is a toggle")
	_check("controls", "sprint_tap_rolls", "A tap of Sprint rolls")
	_grid = null
	_compact = false
	_content.add_child(UiKit.divider())

	var head := UiKit.row(14)
	var spacer := UiKit.label("", "Small")
	spacer.custom_minimum_size = Vector2(300, 0)
	head.add_child(spacer)
	var kb := UiKit.label("Keyboard and mouse", "Small", HORIZONTAL_ALIGNMENT_CENTER)
	kb.custom_minimum_size = Vector2(190, 0)
	head.add_child(kb)
	var pad := UiKit.label("Gamepad", "Small", HORIZONTAL_ALIGNMENT_CENTER)
	pad.custom_minimum_size = Vector2(190, 0)
	head.add_child(pad)
	_content.add_child(head)

	var category := ""
	for def in Settings.binding_defs:
		var this_category := str(def.get("category", ""))
		if this_category != category:
			category = this_category
			var title := UiKit.label(category, "Heading")
			_content.add_child(title)
		_content.add_child(_binding_row(def))

	_content.add_child(UiKit.divider())
	var reset := UiKit.button("Put every binding back")
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(func() -> void:
			Settings.reset_bindings()
			_show_tab(2)
			_say("Bindings are back as they were."))
	_content.add_child(reset)


func _binding_row(def: Dictionary) -> HBoxContainer:
	var action := str(def.get("action", ""))
	var row := UiKit.row(14)
	row.custom_minimum_size = Vector2(0, 36)
	var label := UiKit.label(str(def.get("label", action)), "Body")
	label.custom_minimum_size = Vector2(300, 0)
	row.add_child(label)
	for slot in [RebindCapture.KEYBOARD, RebindCapture.PAD]:
		var b := UiKit.button(RebindCapture.label_for(action, slot), "FlatButton")
		b.custom_minimum_size = Vector2(190, 0)
		b.set_meta("action", action)
		b.set_meta("slot", slot)
		b.pressed.connect(func() -> void: _begin_capture(b))
		row.add_child(b)
	return row


func _begin_capture(button: Button) -> void:
	if _capture_button and is_instance_valid(_capture_button):
		_refresh_button(_capture_button)
	_capture_button = button
	_capture.start(str(button.get_meta("action")), int(button.get_meta("slot")))
	button.text = "press…"
	button.modulate = ThemeBuilder.colour("accent", UI.theme_variant)
	_say("Press what you want. Escape to leave it alone.")


func _refresh_button(button: Button) -> void:
	button.text = RebindCapture.label_for(str(button.get_meta("action")), int(button.get_meta("slot")))
	button.modulate = Color(1, 1, 1, 1)


func _input(event: InputEvent) -> void:
	if not _capture.active:
		return
	var result := _capture.consume(event)
	match str(result["state"]):
		"waiting":
			get_viewport().set_input_as_handled()
		"cancelled":
			if _capture_button:
				_refresh_button(_capture_button)
			_capture_button = null
			_say("Left as it was.")
			get_viewport().set_input_as_handled()
		"bound":
			var conflict := Settings.rebind(str(result["action"]), result["event"] as InputEvent, int(result["slot"]))
			if _capture_button:
				_refresh_button(_capture_button)
			_capture_button = null
			if conflict.is_empty():
				_say("Bound.")
			else:
				_say("That was %s; it has nothing on that key now." % _label_of(conflict))
				_show_tab(2)
			get_viewport().set_input_as_handled()


func _label_of(action: String) -> String:
	for def in Settings.binding_defs:
		if str(def.get("action", "")) == action:
			return str(def.get("label", action))
	return action


func _say(text: String) -> void:
	_notice.text = text
	_notice.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(_notice, "modulate:a", 0.0, 0.8)
