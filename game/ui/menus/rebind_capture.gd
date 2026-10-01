class_name RebindCapture
extends RefCounted
## The "press the thing you want" state for the Controls tab, kept apart from the screen so
## it can be checked with synthetic events (tests/unit/test_rebind_capture.gd).
##
##   capture.start("attack_light", RebindCapture.PAD)
##   var r := capture.consume(event)
##   if r["state"] == "bound": Settings.rebind(r["action"], r["event"], r["slot"])

## KEYBOARD is an action's first keyboard-and-mouse binding, SECOND its second (a key as well as the
## middle mouse button for the lock-on, triage 80), PAD its gamepad binding.
enum { KEYBOARD = 0, PAD = 1, SECOND = 2 }

const IGNORED_ACTIONS := ["ui_cancel"]
const AXIS_DEADZONE := 0.6

var active := false
var action := ""
var slot: int = KEYBOARD


func start(for_action: String, in_slot: int) -> void:
	action = for_action
	slot = in_slot
	active = true


func cancel() -> void:
	active = false
	action = ""


## Looks at one event while capturing. Returns:
##   {"state": "idle"}      not capturing
##   {"state": "waiting"}   this event is not something we can bind (motion, release, echo)
##   {"state": "cancelled"} the player backed out
##   {"state": "bound", action, slot, event, string}
func consume(event: InputEvent) -> Dictionary:
	if not active:
		return {"state": "idle"}
	if event is InputEventMouseMotion:
		return {"state": "waiting"}
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return {"state": "waiting"}
		if key.physical_keycode == KEY_ESCAPE or key.keycode == KEY_ESCAPE:
			cancel()
			return {"state": "cancelled"}
	elif event is InputEventMouseButton:
		if not (event as InputEventMouseButton).pressed:
			return {"state": "waiting"}
	elif event is InputEventJoypadButton:
		if not (event as InputEventJoypadButton).pressed:
			return {"state": "waiting"}
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) < AXIS_DEADZONE:
			return {"state": "waiting"}
	else:
		return {"state": "waiting"}

	# a slot only takes its own kind of device, so a gamepad column never fills with keys
	var is_pad: bool = event is InputEventJoypadButton or event is InputEventJoypadMotion
	if (slot == PAD) != is_pad:
		return {"state": "waiting"}

	@warning_ignore("static_called_on_instance")
	var text := Settings.event_to_string(event)
	if text.is_empty():
		return {"state": "waiting"}
	var bound := {"state": "bound", "action": action, "slot": slot, "event": event, "string": text}
	cancel()
	return bound


## What a binding row shows: the pretty name of this action's binding for that slot.
static func label_for(action_name: String, in_slot: int) -> String:
	var list: Array = Settings.bindings.get(action_name, [])
	var nth := 1 if in_slot == SECOND else 0
	for s: String in list:
		var is_pad := s.begins_with("joy")
		if is_pad == (in_slot == PAD):
			if nth > 0:
				nth -= 1
				continue
			@warning_ignore("static_called_on_instance")
			return Settings._pretty(s)
	return "—"
