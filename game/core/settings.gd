extends Node
## Settings: persisted user settings (user://settings.cfg) and the input map, including rebinding.
## Default bindings come from res://core/default_bindings.json so the rebinding UI is data-driven.

signal changed(section: String, key: String, value: Variant)
signal bindings_changed

const PATH := "user://settings.cfg"
const DEFAULTS := {
	# volumetric_fog and sdfgi are Forward+ only and off unless asked for; color_grade is the
	# region LUT; night_lights is how many real lamps the night-light pool may light at once
	"video": {"fullscreen": false, "vsync": true, "fov": 75.0, "render_scale": 1.0, "shadows": 2, "msaa": 1, "ssao": true, "glow": true, "brightness": 1.0,
		"volumetric_fog": false, "sdfgi": false, "color_grade": true, "night_lights": 8},
	"audio": {"master": 0.9, "music": 0.7, "sfx": 0.9, "ambience": 0.8, "ui": 0.8, "voice": 1.0},
	"controls": {"mouse_sensitivity": 0.25, "gamepad_sensitivity": 2.6, "invert_y": false, "camera_side": 1, "vibration": true, "toggle_sprint": false},
	"gameplay": {"day_length_minutes": 48.0, "subtitles": true, "difficulty": 1, "hud_opacity": 1.0, "show_hints": true, "compass": true, "play_opening": true},
	"accessibility": {"colourblind": 0, "ui_scale": 1.0, "reduce_flashing": false},
}

var data: Dictionary = {}
var binding_defs: Array = []
var bindings: Dictionary = {}   # action -> Array[String] of event strings


func _ready() -> void:
	load_settings()
	apply_all()


func load_settings() -> void:
	data = DEFAULTS.duplicate(true)
	_load_binding_defs()
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		for section in cf.get_sections():
			if section == "bindings":
				for action in cf.get_section_keys(section):
					bindings[action] = Array(cf.get_value(section, action))
				continue
			if not data.has(section):
				data[section] = {}
			for key in cf.get_section_keys(section):
				data[section][key] = cf.get_value(section, key)


func save_settings() -> void:
	var cf := ConfigFile.new()
	for section in data:
		for key in data[section]:
			cf.set_value(section, key, data[section][key])
	for action in bindings:
		cf.set_value("bindings", action, bindings[action])
	cf.save(PATH)


func get_value(section: String, key: String, default: Variant = null) -> Variant:
	return data.get(section, {}).get(key, default)


func set_value(section: String, key: String, value: Variant, apply := true) -> void:
	if not data.has(section):
		data[section] = {}
	data[section][key] = value
	changed.emit(section, key, value)
	if apply:
		_apply_section(section)


func apply_all() -> void:
	for section in data:
		_apply_section(section)
	apply_bindings()


func _apply_section(section: String) -> void:
	match section:
		"video":
			var fs: bool = data.video.fullscreen
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fs else DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if data.video.vsync else DisplayServer.VSYNC_DISABLED)
			var vp := get_viewport()
			if vp:
				vp.scaling_3d_scale = clampf(float(data.video.render_scale), 0.5, 1.0)
				vp.msaa_3d = clampi(int(data.video.msaa), 0, 3) as Viewport.MSAA
		"audio":
			for bus_name: String in ["Master", "Music", "SFX", "Ambience", "UI", "Voice"]:
				var idx := AudioServer.get_bus_index(bus_name)
				if idx >= 0:
					var key: String = bus_name.to_lower()
					AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(float(data.audio.get(key, 1.0)), 0.0, 1.0)))
		_:
			pass


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
