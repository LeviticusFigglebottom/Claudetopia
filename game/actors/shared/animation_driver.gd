class_name AnimationDriver
extends Node
## Thin animation façade (ARCHITECTURE §8). Gameplay code only ever calls play_intent(clip)
## and set_locomotion(); clip names and events follow CONTRACTS §3.
##
## When the forge's humanoid model (res://actors/shared/humanoid_model.tscn, exposing
## play_intent(clip), set_locomotion(Vector2, sneaking), signals clip_event(name) and
## clip_finished(name)) exists it is instanced under the Model pivot and driven directly.
## Until then a PlaceholderBody is posed procedurally and the same events are emitted from
## timers, using per-attack timing passed in by the caller (weapon data / enemy attack data),
## so combat is fully testable now and switches to the real rig without code changes.

signal clip_started(clip: String)
signal clip_event(event_name: String)
signal clip_finished(clip: String)

const MODEL_SCENE := "res://actors/shared/humanoid_model.tscn"
const LOOPING: Array[String] = ["Idle", "Idle_Combat", "Walk", "Walk_Back", "Run", "Strafe_L", "Strafe_R", "Sneak_Idle", "Sneak_Walk", "Jump_Loop", "Fall_Loop", "Block_Idle", "Cast_Loop", "Bow_Aim", "Sit_Idle", "Sleep_Idle"]
## Clips that keep their final pose after finishing (until another clip plays).
const HELD_POSE: Array[String] = ["Death_A", "Death_B", "Death", "Knockdown", "Sleep_Idle", "Sit_Idle"]
## Placeholder timing for clips whose length does not come from weapon/attack data.
const DEFAULT_TIMING := {
	"Dodge_F": {"length": 0.6}, "Dodge_B": {"length": 0.6}, "Dodge_L": {"length": 0.6}, "Dodge_R": {"length": 0.6},
	"Hit_Light": {"length": 0.35}, "Hit_Heavy": {"length": 0.7}, "Hit": {"length": 0.35}, "Block_Hit": {"length": 0.3}, "Parry": {"length": 0.45},
	"Stagger": {"length": 0.8}, "Knockdown": {"length": 1.6}, "Get_Up": {"length": 0.8},
	"Death_A": {"length": 1.2}, "Death_B": {"length": 1.2}, "Death": {"length": 1.2},
	"Riposte": {"length": 1.3, "events": [{"t": 0.65, "name": "hit_start"}, {"t": 0.91, "name": "hit_end"}, {"t": 1.1, "name": "cancel_ok"}]},
	"Backstab": {"length": 1.3, "events": [{"t": 0.65, "name": "hit_start"}, {"t": 0.91, "name": "hit_end"}, {"t": 1.1, "name": "cancel_ok"}]},
	"Cast_Quick": {"length": 0.6}, "Cast_Long": {"length": 1.2}, "Bow_Draw": {"length": 0.7}, "Bow_Release": {"length": 0.3}, "Throw": {"length": 0.6},
	"Interact": {"length": 0.8}, "Pick_Up": {"length": 0.9}, "Jump_Start": {"length": 0.2}, "Jump_Land": {"length": 0.25},
	"Attack_1": {"length": 1.0, "events": [{"t": 0.5, "name": "hit_start"}, {"t": 0.7, "name": "hit_end"}, {"t": 0.85, "name": "cancel_ok"}]},
	"Attack_2": {"length": 1.0, "events": [{"t": 0.5, "name": "hit_start"}, {"t": 0.7, "name": "hit_end"}, {"t": 0.85, "name": "cancel_ok"}]},
	"Wave": {"length": 1.4}, "Bow_Gesture": {"length": 1.4}, "Laugh": {"length": 1.4}, "Rude": {"length": 1.0}, "Dance": {"length": 2.4}, "Cheer": {"length": 1.2}, "Cower": {"length": 1.2}, "Point": {"length": 1.0},
	"Drink": {"length": 1.2}, "Eat": {"length": 1.2}, "Read": {"length": 1.6}, "Talk_1": {"length": 1.6}, "Talk_2": {"length": 1.6},
	"Sit_Down": {"length": 0.8}, "Stand_Up": {"length": 0.8}, "Work_Hammer": {"length": 1.0}, "Work_Chop": {"length": 1.2}, "Work_Stir": {"length": 1.6}, "Work_Dig": {"length": 1.4},
}

var model: Node = null                 # the real model when present
var placeholder: PlaceholderBody = null
var pivot: Node3D = null
var current_clip: String = ""
var current_length: float = 0.0
var elapsed: float = 0.0
var looping: bool = false
var busy: bool = false                 # a non-looping clip is in progress
var hold_at: float = -1.0              # >= 0: freeze the placeholder at this time (heavy charge)
var locomotion: Vector2 = Vector2.ZERO # x = strafe, y = forward, in units of run speed
var sneaking: bool = false
var held: bool = false                 # finished clip keeps its last pose
var event_times: Dictionary = {}       # name -> t for the current clip (placeholder)

var _events: Array = []                # [{t, name, fired}]


func setup(model_pivot: Node3D, body_kind: String, tint: Color, body_scale: float = 1.0, body_variant: String = "") -> void:
	pivot = model_pivot
	model = null
	for c in pivot.get_children():
		if c.has_method("play_intent") and c.has_signal("clip_event"):
			model = c
			break
	if model == null and body_kind == "humanoid" and ResourceLoader.exists(MODEL_SCENE):
		var scene := load(MODEL_SCENE) as PackedScene
		if scene != null:
			var inst := scene.instantiate()
			if inst.has_method("play_intent") and inst.has_signal("clip_event"):
				pivot.add_child(inst)
				model = inst
			else:
				inst.free()
	if model != null:
		model.clip_event.connect(_on_model_event)
		model.clip_finished.connect(_on_model_finished)
		if "tint" in model:
			model.set("tint", tint)
	else:
		placeholder = PlaceholderBody.build(body_kind, tint, body_scale, body_variant)
		pivot.add_child(placeholder)


func has_real_model() -> bool:
	return model != null


static func default_timing(clip: String) -> Dictionary:
	if DEFAULT_TIMING.has(clip):
		return DEFAULT_TIMING[clip]
	if clip.begins_with("Attack"):
		return {"length": 0.9, "events": [{"t": 0.34, "name": "hit_start"}, {"t": 0.52, "name": "hit_end"}, {"t": 0.63, "name": "cancel_ok"}]}
	return {"length": 0.8}


## Plays a clip. `timing` ({"length": s, "events": [{"t", "name"}]}) drives the placeholder's
## event timers; the real model ignores it except for an optional "speed_scale".
func play_intent(clip: String, timing: Dictionary = {}) -> void:
	held = false
	hold_at = -1.0
	looping = LOOPING.has(clip)
	if model != null:
		if timing.has("speed_scale") and "speed_scale" in model:
			model.set("speed_scale", float(timing["speed_scale"]))
		elif "speed_scale" in model:
			model.set("speed_scale", 1.0)
		model.play_intent(clip)
		current_clip = clip
		busy = not looping
		clip_started.emit(clip)
		return
	var t := timing if not timing.is_empty() else default_timing(clip)
	current_clip = clip
	current_length = maxf(float(t.get("length", 0.8)), 0.05)
	elapsed = 0.0
	_events.clear()
	event_times.clear()
	for e in t.get("events", []):
		_events.append({"t": float(e["t"]), "name": str(e["name"]), "fired": false})
		event_times[str(e["name"])] = float(e["t"])
	_events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))
	busy = not looping
	if placeholder != null:
		placeholder.begin(clip, event_times, current_length)
	clip_started.emit(clip)


func set_locomotion(v: Vector2, is_sneaking: bool) -> void:
	locomotion = v
	sneaking = is_sneaking
	if model != null:
		model.set_locomotion(v, is_sneaking)


## Freezes the placeholder clip at time t (heavy-attack charge). release_hold() resumes.
func hold(t: float) -> void:
	hold_at = maxf(t, 0.0)
	if model != null and "speed_scale" in model:
		model.set("speed_scale", 0.0)


func release_hold() -> void:
	hold_at = -1.0
	if model != null and "speed_scale" in model:
		model.set("speed_scale", 1.0)


## Cancels the current non-looping clip without emitting its remaining events.
func stop() -> void:
	busy = false
	held = false
	hold_at = -1.0
	current_clip = ""
	_events.clear()
	event_times.clear()
	if model != null:
		if model.has_method("stop"):
			model.stop()
		else:
			model.play_intent("Idle")
	elif placeholder != null:
		placeholder.begin("", {}, 0.0)


func is_busy() -> bool:
	return busy


func is_playing(clip: String) -> bool:
	return current_clip == clip and (busy or looping or held)


func progress() -> float:
	return clampf(elapsed / current_length, 0.0, 1.0) if current_length > 0.0 else 0.0


## Seconds until a named event fires in the current placeholder clip (-1 if none/past).
func time_to_event(event_name: String) -> float:
	for e in _events:
		if e["name"] == event_name and not e["fired"]:
			return maxf(float(e["t"]) - elapsed, 0.0)
	return -1.0


func _physics_process(delta: float) -> void:
	if model != null:
		return
	if busy or looping:
		var next := elapsed + delta
		if hold_at >= 0.0 and next >= hold_at:
			next = hold_at
		elapsed = next
		for e in _events:
			if not e["fired"] and elapsed >= float(e["t"]) - 0.00001:
				e["fired"] = true
				clip_event.emit(e["name"])
		if elapsed >= current_length - 0.00001 and not (hold_at >= 0.0 and hold_at >= current_length):
			var finished := current_clip
			if looping:
				elapsed -= current_length
				for e in _events:
					e["fired"] = false
			else:
				busy = false
				held = HELD_POSE.has(finished)
				elapsed = current_length
				if not held:
					current_clip = ""
				clip_finished.emit(finished)
	if placeholder != null:
		placeholder.update(delta, current_clip, progress(), locomotion, sneaking)


func _on_model_event(event_name: String) -> void:
	clip_event.emit(event_name)


func _on_model_finished(clip: String) -> void:
	if clip == current_clip:
		busy = false
		held = HELD_POSE.has(clip)
		if not held:
			current_clip = ""
	clip_finished.emit(clip)
