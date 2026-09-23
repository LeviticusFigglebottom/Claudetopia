class_name AnimationDriver
extends Node
## Thin animation façade (ARCHITECTURE §8). Gameplay code only ever calls play_intent(clip)
## and set_locomotion(); clip names and events follow CONTRACTS §3.
##
## **The driver keeps the time.** Every clip it plays has a timeline -- the caller's timing when
## one is given (a weapon's hit window, an enemy's authored telegraph), otherwise the clip's own
## off the rig's `.clips.json` sidecar -- and the gameplay events on it (`hit_start`, `hit_end`,
## `cancel_ok`, `charge_go`, `channel_start` ...) fire from here on the physics clock, whether the
## body is the forged humanoid (res://actors/shared/humanoid_model.tscn) or a PlaceholderBody.
## The humanoid is then only a picture of the timeline: it plays the clip at whatever speed makes
## its own blow land on the timeline's, and holds still while the timeline is held.
##
## It used to hand the rig the clip and forward the rig's own events, which meant that anything
## with a real body ignored the timing it was given. A hedge wight's authored one-second wind-up
## came out at the clip's 0.43 s; a charger's `charge_go` was never said, so a humanoid charger
## swung where it stood; a held note never held; a poacher's arrow was never loosed, because
## `Bow_Draw` has no `hit_start`; and a heavy could not be charged, because the hold was a speed
## the rig did not have.

signal clip_started(clip: String)
signal clip_event(event_name: String)
signal clip_finished(clip: String)

const MODEL_SCENE := "res://actors/shared/humanoid_model.tscn"
## Ground speed (m/s) at which a placeholder body swings its limbs fully.
const PLACEHOLDER_FULL_SPEED := 5.0
const LOOPING: Array[String] = ["Idle", "Idle_Combat", "Walk", "Walk_Back", "Run", "Strafe_L", "Strafe_R", "Sneak_Idle", "Sneak_Walk", "Jump_Loop", "Fall_Loop", "Block_Idle", "Cast_Loop", "Bow_Aim", "Sit_Idle", "Sleep_Idle"]
## Clips that keep their final pose after finishing (until another clip plays).
const HELD_POSE: Array[String] = ["Death_A", "Death_B", "Death", "Knockdown", "Sleep_Idle", "Sit_Idle"]
## The moment a clip's body connects, looked for in this order on either timeline: the rig's clip
## is stretched so its anchor meets the gameplay timeline's.
const ANCHORS: Array[String] = ["hit_start", "charge_go", "channel_start", "release", "cast_release"]
## How far the rig may be sped up or slowed down to meet a timeline. Past these a stretched swing
## stops reading as the same swing; it simply lands late or early and says so by looking wrong.
const MODEL_SPEED_MIN := 0.25
const MODEL_SPEED_MAX := 4.0
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
var hold_at: float = -1.0              # >= 0: freeze the timeline at this time (heavy charge)
var locomotion: Vector2 = Vector2.ZERO # ground velocity in the body's frame, m/s: x right, y ahead
var sneaking: bool = false
var held: bool = false                 # finished clip keeps its last pose
var event_times: Dictionary = {}       # name -> t for the current clip's timeline

var _events: Array = []                # [{t, name, fired}]
var _rig_timing: Dictionary = {}       # the rig's own {length, events} for the clip playing
var _rig_times: Dictionary = {}        # name -> t off _rig_timing


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
		# The rig's own clip_event and clip_finished are deliberately not listened to: the
		# timeline here is the one the game keeps, and the rig is a picture of it.
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


## The timeline a clip keeps when the caller gave none: the rig's own, when this body is a rig that
## has the clip, and otherwise the placeholder table.
func timing_of(clip: String) -> Dictionary:
	var t := _rig_clip_timing(clip)
	if not t.is_empty():
		return t
	return default_timing(clip)


func _rig_clip_timing(clip: String) -> Dictionary:
	if model == null or not model.has_method("clip_timing"):
		return {}
	var t: Dictionary = model.call("clip_timing", clip)
	return t if float(t.get("length", 0.0)) > 0.0 else {}


## Plays a clip. `timing` ({"length": s, "events": [{"t", "name"}]}) is the timeline the gameplay
## events fire on; without one, the clip keeps its own.
func play_intent(clip: String, timing: Dictionary = {}) -> void:
	held = false
	hold_at = -1.0
	# A loop the caller has given a length to is a held action with an end -- a boss's hymn on
	# Cast_Loop is six seconds of it -- and it has to finish, or whatever is waiting on its end
	# waits for ever. Only a loop played without a timing loops.
	looping = LOOPING.has(clip) and timing.is_empty()
	var t := timing if not timing.is_empty() else timing_of(clip)
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
	if model != null:
		_rig_timing = _rig_clip_timing(clip)
		_rig_times.clear()
		for e in _rig_timing.get("events", []):
			_rig_times[str(e["name"])] = float(e["t"])
		model.play_intent(clip)
		_sync_model_speed()
	elif placeholder != null:
		placeholder.begin(clip, event_times, current_length)
	clip_started.emit(clip)


## `v` is the body's ground velocity in its own frame, in m/s (x to its right, y ahead). The
## forge's model turns that into a gait played at the rate that keeps its feet planted.
func set_locomotion(v: Vector2, is_sneaking: bool) -> void:
	locomotion = v
	sneaking = is_sneaking
	if model != null:
		model.set_locomotion(v, is_sneaking)


## Freezes the timeline at time t (a heavy being charged) once it gets there; the rig holds its
## pose from the same moment. release_hold() lets both run on.
func hold(t: float) -> void:
	hold_at = maxf(t, 0.0)


func release_hold() -> void:
	hold_at = -1.0
	_sync_model_speed()


## Cancels the current non-looping clip without emitting its remaining events.
func stop() -> void:
	busy = false
	held = false
	hold_at = -1.0
	current_clip = ""
	_events.clear()
	event_times.clear()
	_rig_timing = {}
	_rig_times.clear()
	if model != null:
		if model.has_method("stop_intent"):
			model.stop_intent()
		elif model.has_method("stop"):
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


## Seconds until a named event fires in the current clip's timeline (-1 if none/past).
func time_to_event(event_name: String) -> float:
	for e in _events:
		if e["name"] == event_name and not e["fired"]:
			return maxf(float(e["t"]) - elapsed, 0.0)
	return -1.0


func _physics_process(delta: float) -> void:
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
					_let_the_rig_go(finished)
				clip_finished.emit(finished)
	if model != null:
		_sync_model_speed()
	elif placeholder != null:
		# the capsule's swing is scaled 0..1, full at a jog
		placeholder.update(delta, current_clip, progress(), locomotion / PLACEHOLDER_FULL_SPEED, sneaking)


## The timeline is done with a clip the rig may still be playing (a swing stretched past its
## limit): send the rig back to locomotion rather than let it finish a blow nobody is scoring.
func _let_the_rig_go(clip: String) -> void:
	if model == null or not model.has_method("current_intent"):
		return
	if str(model.call("current_intent")) == clip and model.has_method("stop_intent"):
		model.stop_intent()


func _sync_model_speed() -> void:
	if model == null or not ("speed_scale" in model):
		return
	model.set("speed_scale", model_speed())


## How fast the rig should play the current clip: so that its anchor (the frame its blow lands)
## meets the timeline's, and after that so that it ends when the timeline ends. 0 while held.
func model_speed() -> float:
	if hold_at >= 0.0 and elapsed >= hold_at - 0.00001:
		return 0.0
	if looping or LOOPING.has(current_clip) or current_clip.is_empty() or _rig_timing.is_empty():
		return 1.0
	var rig_length := float(_rig_timing.get("length", 0.0))
	if rig_length <= 0.0 or current_length <= 0.0:
		return 1.0
	var ours := _anchor(event_times)
	var theirs := _anchor(_rig_times)
	if ours > 0.0 and theirs > 0.0 and ours < current_length and theirs < rig_length:
		if elapsed < ours:
			return clampf(theirs / ours, MODEL_SPEED_MIN, MODEL_SPEED_MAX)
		return clampf((rig_length - theirs) / maxf(current_length - ours, 0.01), MODEL_SPEED_MIN, MODEL_SPEED_MAX)
	return clampf(rig_length / current_length, MODEL_SPEED_MIN, MODEL_SPEED_MAX)


static func _anchor(times: Dictionary) -> float:
	for name in ANCHORS:
		if times.has(name):
			return float(times[name])
	return -1.0
