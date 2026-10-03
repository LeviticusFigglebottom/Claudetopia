extends Control
## Settings (DESIGN §5.19). Five tabs, everything bound to the Settings autoload and applied
## the moment it changes, because a settings screen that needs an "Apply" button is a settings
## screen that lies to you.
##
## The Controls tab is built from Settings.binding_defs, so adding an action to
## core/default_bindings.json puts it here with no code change.
##
## The Graphics tab is built from Graphics.CONTROLS the same way: four presets across the top,
## every knob below them, and a knob the running renderer cannot do greyed out with the one line
## that says why. Changing any knob makes the preset "Custom" unless the values still match one.

const TABS := ["Video", "Graphics", "Audio", "Controls", "Gameplay", "Accessibility"]
const GRAPHICS_TAB := 1
const CONTROLS_TAB := 3
## The Graphics tab's knobs in the groups it shows them under.
const GRAPHICS_GROUPS := [
	["The picture", ["render_scale", "upscaler", "msaa", "fxaa", "taa", "anisotropic", "ground_textures", "distant_ground"]],
	["Pacing", ["vsync", "fps_cap"]],
	["Shadows", ["shadows", "shadow_atlas", "shadow_cascades", "shadow_distance", "shadow_filter"]],
	["The country", ["scatter_density", "grass_instancer", "view_range", "lod_bias", "view_distance", "occlusion", "water_quality", "water_reflections", "wildlife"]],
	["Light and air", ["fog", "volumetric_fog", "ssao", "ao_quality", "ssil", "sdfgi", "glow", "night_lights"]],
	["The look", ["title_vista", "title_live", "color_grade", "vignette", "film_grain"]],
	["Starting safely", ["full_terrain"]],
]

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
	var tab: Variant = args.get("tab", 0)
	# a tab by name as well as by number, so adding one does not move everybody else's
	_tab = TABS.find(tab) if tab is String else int(tab)
	_tab = maxi(_tab, 0)
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
	add_child(frame)
	UiFit.inset(frame, 110.0, 36.0)
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
	# where this session's error log is written, for a player asked to send it
	var logs := UiKit.button("Open log folder", "FlatButton")
	logs.tooltip_text = "The folder with this session's error log, to send along with a report:\n%s" % ProjectSettings.globalize_path("user://logs")
	logs.pressed.connect(func() -> void: ErrorLog.open_folder())
	foot.add_child(logs)
	var close := UiKit.button("Done", "FlatButton")
	close.pressed.connect(func() -> void: UI.close("settings"))
	foot.add_child(close)
	UiKit.ink_in(frame, 0.0, 0.32)


## Everything here is applied the moment it changes and written down when the screen closes.
## Nothing wrote it down before, so every setting but the key bindings was forgotten when the game
## was quit -- including the one that says not to play the opening again.
func closing() -> void:
	Settings.save_settings()


func _show_tab(index: int) -> void:
	_tab = clampi(index, 0, TABS.size() - 1)
	for i in _tab_buttons.size():
		_tab_buttons[i].modulate = Color(1, 1, 1, 1.0 if i == _tab else 0.55)
	for child in _content.get_children():
		child.queue_free()
	match _tab:
		0: _build_video()
		1: _build_graphics()
		2: _build_audio()
		3: _build_controls()
		4: _build_gameplay()
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
	name_label.custom_minimum_size = Vector2(196 if _compact else (230 if _narrow() else 300), 0)
	name_label.tooltip_text = note
	row.add_child(name_label)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	if not note.is_empty() and not _compact:
		var hint := UiKit.label(note, "Tiny")
		# a note wraps rather than widening the page past the screen (a large UI, triage 28)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(120, 0)
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(hint)
	_target().add_child(row)
	return row


## Rows are added here, so a tab can send them into a grid instead of down the page.
func _target() -> Node:
	if _grid != null:
		return _grid
	return _content


## The canvas is narrower than the wide layout wants (the UI's size at 1.2 and up on 1280x720).
func _narrow() -> bool:
	return UiFit.narrow(self)


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
	if section == "accessibility" and key == "ui_scale":
		# The whole canvas is scaled by this one (Settings.apply_ui_scale), the slider with it: a
		# drag is applied when it is let go, or the handle would run away under the pointer. A key
		# or a pad's step is applied at once.
		s.drag_ended.connect(func(moved: bool) -> void:
				if moved:
					Settings.set_value(section, key, s.value))
		s.value_changed.connect(func(v: float) -> void:
				value_label.text = _format(v, suffix)
				if not s.has_meta("dragging"):
					Settings.set_value(section, key, v))
		s.drag_started.connect(func() -> void: s.set_meta("dragging", true))
		s.drag_ended.connect(func(_moved: bool) -> void: s.remove_meta("dragging"), CONNECT_DEFERRED)
	else:
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


## A drop-down for one setting. `values` is what each choice stores when it is not its index:
## the camera side is -1 or 1, and with the index stored, Left wrote 0, which the camera reads
## as the right shoulder.
func _option(section: String, key: String, label: String, choices: Array, note := "", values: Array = []) -> void:
	var o := OptionButton.new()
	for c in choices:
		o.add_item(str(c))
	var saved: Variant = Settings.get_value(section, key, values[0] if not values.is_empty() else 0)
	var index := _index_of(values, saved) if not values.is_empty() else int(saved)
	o.selected = clampi(index, 0, choices.size() - 1)
	o.item_selected.connect(func(i: int) -> void:
			Settings.set_value(section, key, values[i] if i < values.size() else i))
	# `option_key`, not `setting_key`: that one marks the Graphics tab's knobs
	o.set_meta("option_key", "%s/%s" % [section, key])
	if not values.is_empty():
		o.set_meta("setting_values", values)
	_row(label, o, note)


# --- tabs ----------------------------------------------------------------------------------

func _build_video() -> void:
	_check("video", "fullscreen", "Fullscreen")
	_slider("video", "fov", "Field of view", 60.0, 110.0, 1.0, "°")
	_slider("video", "fov_first_person", "Field of view, first person", 60.0, 110.0, 1.0, "°")
	_slider("video", "brightness", "Brightness", 0.6, 1.6, 0.05)
	_content.add_child(UiKit.divider())
	_content.add_child(UiKit.wrapped(
			"How much the picture holds -- shadows, distance, smoothing, the light in the air, the " +
			"lamps at night, the water, the colour grade -- is under Graphics.", "Journal"))


# --- graphics ------------------------------------------------------------------------------

func _build_graphics() -> void:
	var presets := UiKit.row(8)
	var now := str(Settings.get_value("graphics", "preset", Graphics.DEFAULT_PRESET))
	var heading := UiKit.label("Preset: %s" % str(Graphics.PRESET_LABELS.get(now, now.capitalize())), "Heading")
	heading.name = "PresetLabel"
	heading.custom_minimum_size = Vector2(300, 0)
	presets.add_child(heading)
	for p: String in Graphics.PRESET_ORDER:
		var b := UiKit.button(str(Graphics.PRESET_LABELS[p]), "FlatButton")
		b.set_meta("preset", p)
		b.modulate = Color(1, 1, 1, 1.0 if p == now else 0.6)
		var which := p
		b.pressed.connect(func() -> void: _choose_preset(which))
		presets.add_child(b)
	# the preset this machine's graphics adapter is recommended, as a first launch is given it
	var detect := UiKit.button("Detect recommended", "FlatButton")
	detect.name = "DetectRecommended"
	detect.tooltip_text = "Sets the preset for this machine's graphics, as the first launch did"
	detect.pressed.connect(_detect_recommended)
	_content.add_child(presets)
	var detect_row := UiKit.row(10)
	detect_row.add_child(detect)
	detect_row.add_child(UiKit.label(RenderingServer.get_video_adapter_name(), "Tiny"))
	_content.add_child(detect_row)
	_content.add_child(UiKit.wrapped(_renderer_line(), "Tiny"))
	for group in GRAPHICS_GROUPS:
		_content.add_child(UiKit.label(str(group[0]), "Heading"))
		for key: String in group[1]:
			_graphics_row(Graphics.control(key))


func _renderer_line() -> String:
	var r := Graphics.renderer()
	if r == Graphics.RENDERER_FORWARD_PLUS:
		return "Drawn with Forward+: everything below is available."
	return "Drawn with the Compatibility renderer: what it cannot do is greyed out, with the reason beside it."


func _choose_preset(preset: String) -> void:
	Settings.apply_graphics_preset(preset)
	_show_tab(GRAPHICS_TAB)
	_say("%s: every knob below is set to it." % str(Graphics.PRESET_LABELS.get(preset, preset)))


func _detect_recommended() -> void:
	var adapter := HardwareTier.adapter()
	var verdict := Settings.recommend_graphics(adapter)
	_show_tab(GRAPHICS_TAB)
	_say("%s for %s (%s)." % [str(Graphics.PRESET_LABELS.get(str(verdict["preset"]), verdict["preset"])),
			str(adapter.get("name", "this machine")), str(verdict["why"])])


## One knob, bound to Settings `graphics`, greyed out with its reason where this renderer cannot
## do it. Every control carries `setting_key` so a test can find the knob and press it.
func _graphics_row(c: Dictionary) -> void:
	if c.is_empty():
		return
	var key := str(c["key"])
	var value: Variant = Settings.get_value("graphics", key, Graphics.DEFAULTS.get(key))
	if key == "ground_textures":
		value = Graphics.ground_texture_quality({key: value})    # unchosen shows what this GPU gets
	# the row as a whole; a choice within it (FSR on Compatibility) is checked item by item below
	var reason := Graphics.unsupported_reason(key)
	var note := str(c.get("note", ""))
	var control: Control
	match str(c["kind"]):
		"check":
			var box := CheckBox.new()
			box.button_pressed = bool(value)
			box.toggled.connect(func(on: bool) -> void: _set_graphics(key, on))
			box.disabled = reason != ""
			control = box
		"slider":
			var holder := UiKit.row(10)
			var s := HSlider.new()
			s.min_value = float(c["min"])
			s.max_value = float(c["max"])
			s.step = float(c["step"])
			s.value = float(value)
			s.editable = reason == ""
			s.custom_minimum_size = Vector2(260, 20)
			s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var shown := UiKit.label(_format(s.value, str(c.get("suffix", ""))), "Small")
			shown.custom_minimum_size = Vector2(90, 0)
			var suffix := str(c.get("suffix", ""))
			s.value_changed.connect(func(v: float) -> void:
					_set_graphics(key, v)
					shown.text = _format(v, suffix))
			s.set_meta("setting_key", key)
			holder.add_child(s)
			holder.add_child(shown)
			control = holder
		_:
			var o := OptionButton.new()
			var values: Array = c.get("values", [])
			var choices: Array = c["choices"]
			for i in choices.size():
				o.add_item(str(choices[i]))
				# a choice this renderer cannot make (FSR on Compatibility) is there but not pickable
				var v: Variant = values[i] if i < values.size() else i
				if Graphics.unsupported_reason(key, v) != "":
					o.set_item_disabled(i, true)
					if reason == "":
						note = Graphics.unsupported_reason(key, v)
			var index := _index_of(values, value) if not values.is_empty() else int(value)
			o.selected = clampi(index, 0, choices.size() - 1)
			o.disabled = reason != ""
			o.item_selected.connect(func(i: int) -> void:
					_set_graphics(key, values[i] if i < values.size() else i))
			control = o
	control.set_meta("setting_key", key)
	var row := _row(str(c["label"]), control, reason if reason != "" else note)
	row.set_meta("setting_key", key)
	if reason != "":
		row.modulate = Color(1, 1, 1, 0.5)


## A value's place in a choice list, as a number: 4096 from the file and 4096.0 from a slider
## are the same choice.
static func _index_of(values: Array, value: Variant) -> int:
	for i in values.size():
		if is_equal_approx(float(values[i]), float(value)):
			return i
	return 0


func _set_graphics(key: String, value: Variant) -> void:
	var before := str(Settings.get_value("graphics", "preset", ""))
	Settings.set_value("graphics", key, value)
	var after := str(Settings.get_value("graphics", "preset", ""))
	if after != before:
		var label := _content.find_child("PresetLabel", true, false) as Label
		if label != null:
			label.text = "Preset: %s" % str(Graphics.PRESET_LABELS.get(after, after.capitalize()))


func _build_audio() -> void:
	for pair in [["master", "Everything"], ["music", "Music"], ["sfx", "Sounds"],
			["ambience", "The world"], ["ui", "Paper and brass"], ["voice", "Voices"]]:
		_slider("audio", str(pair[0]), str(pair[1]), 0.0, 1.0, 0.05, "%")


func _build_gameplay() -> void:
	_slider("gameplay", "day_length_minutes", "Length of a day", 12.0, 120.0, 1.0, "min")
	_option("gameplay", "difficulty", "Difficulty", ["Kind", "Ordinary", "Hard", "Quiet"])
	_check("gameplay", "subtitles", "Subtitles")
	_check("gameplay", "play_opening", "Play the opening on a new game",
			"the pause menu can still show it")
	_check("gameplay", "show_hints", "Hints")
	_check("gameplay", "compass", "Compass")
	_check("gameplay", "blood", "Blood", "on a blow that lands on flesh")
	_check("gameplay", "pickup_glint", "Things on the ground glint", "a soft glint now and then, so a dropped blade can be seen")
	_slider("gameplay", "hud_opacity", "How loud the HUD is", 0.2, 1.0, 0.05, "%")
	_option("gameplay", "quest_notice_time", "Quest news stays up", ["Shorter", "Ordinary", "Longer", "Longest"],
			"a quest taken, moved on or finished, under the compass", [0.75, 1.0, 1.5, 2.0])


func _build_accessibility() -> void:
	_option("accessibility", "colourblind", "Colour-blind palette",
			["Off", "Red-green (protan)", "Red-green (deutan)", "Blue-yellow (tritan)"],
			"changes the bar colours only")
	_slider("accessibility", "ui_scale", "Size of the UI", 0.8, 1.4, 0.05, "%")
	_check("accessibility", "reduce_flashing", "Less flashing")
	_slider("accessibility", "camera_shake", "Camera kick on a blow", 0.0, 1.0, 0.05, "%")
	_slider("accessibility", "head_bob", "Head bob in first person", 0.0, 1.0, 0.05, "%")
	_check("accessibility", "hit_pause", "Pause on a landed blow", "a few frames; the fight's timing is the same")
	_content.add_child(UiKit.divider())
	_content.add_child(UiKit.wrapped(
			"The size of the UI is every screen's, the HUD's and the films' words. Colour-blind palettes " +
			"change the bar fills and the map's region tints, never the words.", "Journal"))


# --- controls ---------------------------------------------------------------------------------

func _build_controls() -> void:
	_compact = true
	_grid = GridContainer.new()
	# one column when the UI is large enough that two would run off the screen
	_grid.columns = 1 if _narrow() else 2
	_grid.add_theme_constant_override("h_separation", 30)
	_content.add_child(_grid)
	_slider("controls", "mouse_sensitivity", "Mouse sensitivity", 0.05, 1.0, 0.01)
	_slider("controls", "gamepad_sensitivity", "Stick sensitivity", 0.5, 6.0, 0.1)
	_check("controls", "invert_y", "Invert looking up and down")
	_option("controls", "camera_side", "Camera side", ["Left", "Right"], "", [-1, 1])
	_check("controls", "vibration", "Vibration")
	_check("controls", "toggle_sprint", "Sprint is a toggle")
	_check("controls", "sprint_tap_rolls", "A tap of Sprint rolls")
	_grid = null
	_compact = false
	_content.add_child(UiKit.divider())

	var head := UiKit.row(14)
	var spacer := UiKit.label("", "Small")
	spacer.custom_minimum_size = Vector2(_binding_label_w(), 0)
	head.add_child(spacer)
	# two keyboard-and-mouse columns: a key as well as a mouse button (the lock-on's middle button
	# is one some players have not got, triage 80), then the pad's
	for words in ["Keyboard and mouse", "Or", "Gamepad"]:
		var col_head := UiKit.label(words, "Small", HORIZONTAL_ALIGNMENT_CENTER)
		col_head.custom_minimum_size = Vector2(_binding_button_w(), 0)
		head.add_child(col_head)
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
			_show_tab(CONTROLS_TAB)
			_say("Bindings are back as they were."))
	_content.add_child(reset)


func _binding_row(def: Dictionary) -> HBoxContainer:
	var action := str(def.get("action", ""))
	var row := UiKit.row(14)
	row.custom_minimum_size = Vector2(0, 36)
	var label := UiKit.label(str(def.get("label", action)), "Body")
	label.custom_minimum_size = Vector2(_binding_label_w(), 0)
	row.add_child(label)
	for slot in [RebindCapture.KEYBOARD, RebindCapture.SECOND, RebindCapture.PAD]:
		var b := UiKit.button(RebindCapture.label_for(action, slot), "FlatButton")
		b.custom_minimum_size = Vector2(_binding_button_w(), 0)
		b.set_meta("action", action)
		b.set_meta("slot", slot)
		b.pressed.connect(func() -> void: _begin_capture(b))
		row.add_child(b)
	return row


func _binding_label_w() -> float:
	return 230.0 if _narrow() else 280.0


func _binding_button_w() -> float:
	return 120.0 if _narrow() else 150.0


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
				_show_tab(CONTROLS_TAB)
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
