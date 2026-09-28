extends Node
## Settings: persisted user settings (user://settings.cfg) and the input map, including rebinding.
## Default bindings come from res://core/default_bindings.json so the rebinding UI is data-driven.
##
## The `graphics` section is every knob of the picture's fidelity: `Graphics` (core/graphics.gd)
## says what each one means and puts it into the engine, and the presets live there too. A value
## set here is applied at once and written to settings.cfg at the end of the frame -- except while
## `persist` is off, which the unit tests and the measuring tools turn off so that neither ever
## writes the player's file.

signal changed(section: String, key: String, value: Variant)
signal bindings_changed

const PATH := "user://settings.cfg"
const DEFAULTS := {
	# fov_first_person is the view through the eyes' own (CameraRig.FP_FOV)
	"video": {"fullscreen": false, "fov": 75.0, "fov_first_person": 70.0, "brightness": 1.0},
	"graphics": Graphics.DEFAULTS,
	"audio": {"master": 0.9, "music": 0.7, "sfx": 0.9, "ambience": 0.8, "ui": 0.8, "voice": 1.0},
	"controls": {"mouse_sensitivity": 0.25, "gamepad_sensitivity": 2.6, "invert_y": false, "camera_side": 1, "vibration": true, "toggle_sprint": false, "sprint_tap_rolls": true},
	"gameplay": {"day_length_minutes": 48.0, "subtitles": true, "difficulty": 1, "hud_opacity": 1.0, "show_hints": true, "compass": true, "hints_learned": [], "play_opening": true, "blood": true, "pickup_glint": true},
	# camera_shake scales the camera's kick when a blow lands (0 is none); hit_pause is the few
	# frames a landed blow holds the picture still; head_bob is how much of the head's own motion the
	# first-person view takes (0 only a slow average of it)
	"accessibility": {"colourblind": 0, "ui_scale": 1.0, "reduce_flashing": false, "camera_shake": 1.0, "hit_pause": true,
		"head_bob": 1.0},
}

## The `video` keys that became `graphics` keys when the graphics settings arrived: the six the
## Video tab always had, and the painted look's own (volumetric fog, SDFGI, the colour grade, the
## vignette and film grain, the lamps lit at night, the water's reflections). A file written
## before then still carries them under `video`, and what the player chose there is carried
## over once.
const MOVED_TO_GRAPHICS := ["vsync", "render_scale", "msaa", "ssao", "glow", "shadows",
		"volumetric_fog", "sdfgi", "color_grade", "vignette", "film_grain", "night_lights",
		"water_reflections"]

var data: Dictionary = {}
var binding_defs: Array = []
var bindings: Dictionary = {}   # action -> Array[String] of event strings
## Off while the unit tests run and while a tool measures a preset: they change settings in memory
## and must never write them into the player's settings.cfg.
var persist := true
## The file itself; a test that checks what is written points this somewhere of its own.
var path := PATH
var _save_queued := false


func _ready() -> void:
	load_settings()
	apply_all()
	# Lights and environments are adopted as they enter the tree, wherever they come from -- the
	# world's atmosphere, an interior, a review stage -- so a setting reaches them without any of
	# them having to know about it.
	get_tree().node_added.connect(_on_node_added)


## Bindings that were the defaults before the pad layout was put right (DECISIONS: "One pad
## button, one thing"). A saved binding still exactly one of these was never changed by its
## player, and takes the default it has now; one they changed is theirs and is kept.
const RETIRED_DEFAULTS := {
	"sprint": ["key:Shift", "joy_button:7"],
	"dodge": ["key:Ctrl", "joy_button:1"],
	"sneak": ["key:C", "joy_button:9"],
	"cast": ["key:F", "joy_button:11"],
	"toggle_camera": ["key:V", "joy_button:8"],
	"inventory": ["key:I", "joy_button:4"],
	"map": ["key:M", "joy_button:5"],
}


func load_settings() -> void:
	data = DEFAULTS.duplicate(true)
	_load_binding_defs()
	var cf := ConfigFile.new()
	if cf.load(path) == OK:
		for section in cf.get_sections():
			if section == "bindings":
				for action in cf.get_section_keys(section):
					bindings[action] = migrated_binding(action, Array(cf.get_value(section, action)))
				continue
			if not data.has(section):
				data[section] = {}
			for key in cf.get_section_keys(section):
				data[section][key] = cf.get_value(section, key)
		_migrate_video_keys(cf)


## Every setting in `values` (Settings.data's shape) that is not its shipped default, as
## "section.key=value". The flow and the test runner ask it of what they start with: a run measured
## on a settings.cfg some earlier run left behind is not measuring the game as shipped.
static func off_default(values: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for section: String in DEFAULTS:
		var shipped: Dictionary = DEFAULTS[section]
		var have: Variant = values.get(section, {})
		if not have is Dictionary:
			continue
		for key: String in shipped:
			if (have as Dictionary).has(key) and not _same(have[key], shipped[key]):
				out.append("%s.%s=%s" % [section, key, str(have[key])])
	return out


static func _same(a: Variant, b: Variant) -> bool:
	var numbers := [TYPE_INT, TYPE_FLOAT]
	if typeof(a) in numbers and typeof(b) in numbers:
		return is_equal_approx(float(a), float(b))
	return typeof(a) == typeof(b) and a == b


## A file from before the graphics section: what was chosen under `video` moves across, unless the
## file already has its own graphics value for it. `shadows` was a four-step quality that nothing
## ever read; all that survives of it is whether it was off.
func _migrate_video_keys(cf: ConfigFile) -> void:
	var moved := false
	for key: String in MOVED_TO_GRAPHICS:
		if not cf.has_section_key("video", key):
			continue
		(data["video"] as Dictionary).erase(key)
		if cf.has_section_key("graphics", key):
			continue
		var v: Variant = cf.get_value("video", key)
		if key == "shadows":
			data["graphics"]["shadows"] = int(v) > 0
		else:
			data["graphics"][key] = v
		moved = true
	if moved and not cf.has_section_key("graphics", "preset"):
		data["graphics"]["preset"] = Graphics.matching_preset(data["graphics"])


## A saved binding still exactly as one of RETIRED_DEFAULTS shipped takes the default it has now.
func migrated_binding(action: String, saved: Array) -> Array:
	if RETIRED_DEFAULTS.get(action, []) == saved:
		return default_events(action)
	return saved


func save_settings() -> void:
	if not persist:
		return
	var cf := ConfigFile.new()
	for section in data:
		for key in data[section]:
			cf.set_value(section, key, data[section][key])
	for action in bindings:
		cf.set_value("bindings", action, bindings[action])
	cf.save(path)


func get_value(section: String, key: String, default: Variant = null) -> Variant:
	return data.get(section, {}).get(key, default)


func set_value(section: String, key: String, value: Variant, apply := true) -> void:
	if not data.has(section):
		data[section] = {}
	data[section][key] = value
	changed.emit(section, key, value)
	if section == "graphics" and key != "preset":
		# a knob moved on its own: the section is a preset only if it still matches one exactly
		_set_preset_name(Graphics.matching_preset(data["graphics"]))
	if apply:
		_apply_section(section)
	_queue_save()


## Every fidelity knob to a preset's values at once, applied once and saved once.
func apply_graphics_preset(preset: String) -> void:
	if not Graphics.PRESETS.has(preset):
		return
	var values := Graphics.preset_values(preset)
	for key: String in values:
		data["graphics"][key] = values[key]
		changed.emit("graphics", key, values[key])
	_set_preset_name(preset)
	_apply_section("graphics")
	_queue_save()


func _set_preset_name(preset: String) -> void:
	if str(data["graphics"].get("preset", "")) == preset:
		return
	data["graphics"]["preset"] = preset
	changed.emit("graphics", "preset", preset)


func _queue_save() -> void:
	if not persist or _save_queued:
		return
	_save_queued = true
	_save_now.call_deferred()


func _save_now() -> void:
	_save_queued = false
	save_settings()


func apply_all() -> void:
	for section in data:
		_apply_section(section)
	apply_bindings()


func _on_node_added(node: Node) -> void:
	if node is DirectionalLight3D or node is WorldEnvironment:
		# deferred, so whatever built the node has finished configuring it before its author's
		# settings are remembered
		_adopt.call_deferred(node)


func _adopt(node) -> void:
	if is_instance_valid(node):
		Graphics.adopt(node, data.get("graphics", {}))


func _apply_section(section: String) -> void:
	match section:
		"video":
			var fs: bool = data.video.fullscreen
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fs else DisplayServer.WINDOW_MODE_WINDOWED)
		"graphics":
			if is_inside_tree():
				Graphics.apply(data["graphics"], get_tree())
		"accessibility":
			apply_ui_scale()
		"audio":
			for bus_name: String in ["Master", "Music", "SFX", "Ambience", "UI", "Voice"]:
				var idx := AudioServer.get_bus_index(bus_name)
				if idx >= 0:
					var key: String = bus_name.to_lower()
					AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(float(data.audio.get(key, 1.0)), 0.0, 1.0)))
		_:
			pass


## The "Size of the UI" (accessibility/ui_scale, 0.8-1.4) is the whole UI's size: every menu,
## the HUD, the Naming, conversations, toasts, the chart, prompts and the films' words (triage 28:
## it used to reach only the films' subtitles). The project stretches canvas_items from 1280x720
## keeping the aspect ("expand"), and the window's content_scale_factor multiplies that stretch, so
## at 1.4 a 1280x720 window lays its screens out on 914x514 and draws them 1.4 times as large. The
## 3D picture is not touched (canvas_items scales only the canvas). Every screen has to fit that
## smaller canvas: tests/unit/test_ui_fits_at_every_scale.gd lays the main ones out there.
const UI_SCALE_MIN := 0.8
const UI_SCALE_MAX := 1.4


static func ui_scale_of(value: Variant) -> float:
	return clampf(float(value) if value != null else 1.0, UI_SCALE_MIN, UI_SCALE_MAX)


func ui_scale() -> float:
	return ui_scale_of(get_value("accessibility", "ui_scale", 1.0))


func apply_ui_scale() -> void:
	if not is_inside_tree():
		return
	var root := get_tree().root
	var s := ui_scale()
	if not is_equal_approx(root.content_scale_factor, s):
		root.content_scale_factor = s


# --- input bindings -----------------------------------------------------------------

func _load_binding_defs() -> void:
	var text := FileAccess.get_file_as_string("res://core/default_bindings.json")
	var parsed: Variant = JSON.parse_string(text)
	binding_defs = parsed.get("actions", []) if typeof(parsed) == TYPE_DICTIONARY else []
	bindings.clear()
	for def in binding_defs:
		bindings[def["action"]] = Array(def["events"]).duplicate()


func default_events(action: String) -> Array:
	for def in binding_defs:
		if def["action"] == action:
			return Array(def["events"]).duplicate()
	return []


func apply_bindings() -> void:
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		InputMap.action_erase_events(action)
		for s in bindings[action]:
			var ev := string_to_event(s)
			if ev:
				InputMap.action_add_event(action, ev)
	bindings_changed.emit()


## Rebind an action's event in a slot (0 = primary keyboard/mouse, 1 = gamepad). Returns the
## action that previously used this event (now cleared) or "".
func rebind(action: String, event: InputEvent, slot: int = 0) -> String:
	var s := event_to_string(event)
	if s.is_empty():
		return ""
	var conflict := ""
	for other in bindings:
		if other != action and bindings[other].has(s):
			bindings[other].erase(s)
			conflict = other
	var list: Array = bindings.get(action, [])
	while list.size() <= slot:
		list.append("")
	list[slot] = s
	bindings[action] = list.filter(func(x): return x != "")
	apply_bindings()
	save_settings()
	return conflict


func reset_bindings() -> void:
	for def in binding_defs:
		bindings[def["action"]] = Array(def["events"]).duplicate()
	apply_bindings()
	save_settings()


static func event_to_string(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k: Key = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
		return "key:" + OS.get_keycode_string(k)
	if ev is InputEventMouseButton:
		return "mouse:%d" % ev.button_index
	if ev is InputEventJoypadButton:
		return "joy_button:%d" % ev.button_index
	if ev is InputEventJoypadMotion:
		if absf(ev.axis_value) < 0.5:
			return ""
		return "joy_axis:%d:%d" % [ev.axis, 1 if ev.axis_value > 0 else -1]
	return ""


static func string_to_event(s: String) -> InputEvent:
	var parts := s.split(":")
	match parts[0]:
		"key":
			var ev := InputEventKey.new()
			ev.physical_keycode = OS.find_keycode_from_string(parts[1])
			return ev
		"mouse":
			var ev := InputEventMouseButton.new()
			ev.button_index = int(parts[1]) as MouseButton
			return ev
		"joy_button":
			var ev := InputEventJoypadButton.new()
			ev.button_index = int(parts[1]) as JoyButton
			return ev
		"joy_axis":
			var ev := InputEventJoypadMotion.new()
			ev.axis = int(parts[1]) as JoyAxis
			ev.axis_value = float(parts[2])
			return ev
	return null


## Human-readable label for the first binding of an action, used by prompts ("[E] Take").
func prompt_for(action: String, gamepad := false) -> String:
	var list: Array = bindings.get(action, [])
	for s: String in list:
		var is_pad: bool = s.begins_with("joy")
		if is_pad == gamepad:
			return _pretty(s)
	return _pretty(list[0]) if list.size() > 0 else "?"


static func _pretty(s: String) -> String:
	var parts := s.split(":")
	match parts[0]:
		"key": return parts[1]
		"mouse": return ["", "LMB", "RMB", "MMB", "WheelUp", "WheelDown"][int(parts[1])] if int(parts[1]) < 6 else "Mouse%s" % parts[1]
		"joy_button": return ["A", "B", "X", "Y", "Back", "Guide", "Start", "LS", "RS", "LB", "RB", "DUp", "DDown", "DLeft", "DRight", "Misc"][int(parts[1])] if int(parts[1]) < 16 else "Btn%s" % parts[1]
		"joy_axis": return ["LX", "LY", "RX", "RY", "LT", "RT"][int(parts[1])] if int(parts[1]) < 6 else "Axis%s" % parts[1]
	return s
