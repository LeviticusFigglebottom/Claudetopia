class_name Gestures
extends RefCounted
## Gestures: the player's non-verbal half of the conversation (DESIGN §5.9). A gesture moves an
## NPC's disposition by their personality, gets a line and sometimes a gesture back, and if it is
## a loud one done in company it becomes a deed the village can talk about.
##
## Data: content type "gesture" (game/content/packs/core/gestures/gestures.json):
##   {id, name, animation, animation_fallback, description, base, loud, deed, forgives,
##    reactions{trait: delta}, replies{trait: [lines], default: [lines]},
##    reply_gestures{trait: gesture_id, default: gesture_id}}
##
## The reaction is base + the sum of the deltas for every trait the NPC has, so a proud pious
## villager takes a bow better than a cynical one, and a timid villager remembers a threat far
## longer than a brave one does.
##
## Emits (through the runner or directly): EventBus.gesture_performed(gesture_id, npc_id) and
## EventBus.npc_gesture(npc_id, reply_gesture_id).

## Doing the same gesture at the same person over and over stops meaning anything.
const REPEAT_DECAY := 0.5
const REPEAT_WINDOW := 4

static var _recent: Dictionary = {}     # npc_id -> Array[String] of recent gesture ids


static func definition(gesture_id: String) -> Dictionary:
	var def := ContentDB.get_or_empty(gesture_id)
	if def.is_empty():
		Log.warn("Gestures", "unknown gesture '%s' (content problem)" % gesture_id)
	return def


static func all_ids() -> Array[String]:
	return ContentDB.ids_of("gesture")


## The animation clip to play, falling back to one that exists in the shipped clip set.
static func animation_for(gesture_id: String, available: Array = []) -> String:
	var def := definition(gesture_id)
	var clip := str(def.get("animation", ""))
	if available.is_empty() or available.has(clip):
		return clip
	var fallback := str(def.get("animation_fallback", ""))
	return fallback if fallback != "" else clip


## Disposition delta this gesture would cause for an NPC with these traits, before repetition.
static func reaction_for(gesture_def: Dictionary, traits: Array) -> int:
	var total := int(gesture_def.get("base", 0))
	var reactions: Dictionary = gesture_def.get("reactions", {})
	for t in traits:
		if reactions.has(str(t)):
			total += int(reactions[str(t)])
	return total


## The line an NPC with these traits answers with. Deterministic per NPC and gesture so the same
## villager keeps their voice, not so random that a market sounds like a dice cup.
static func reply_for(gesture_def: Dictionary, traits: Array, npc_id: String, rng: RandomNumberGenerator = null) -> String:
	var replies: Dictionary = gesture_def.get("replies", {})
	var pool: Array = []
	for t in traits:
		if replies.has(str(t)):
			pool = replies[str(t)]
			break
	if pool.is_empty():
		pool = replies.get("default", [])
	if pool.is_empty():
		return ""
	var index: int
	if rng != null:
		index = rng.randi() % pool.size()
	else:
		index = absi(hash(npc_id + str(gesture_def.get("id", "")))) % pool.size()
	return str(pool[index])


## The gesture an NPC gives back, or "" for none.
static func reply_gesture_for(gesture_def: Dictionary, traits: Array) -> String:
	var map: Dictionary = gesture_def.get("reply_gestures", {})
	for t in traits:
		if map.has(str(t)):
			return str(map[str(t)])
	return str(map.get("default", ""))


## Performs a gesture at an NPC. `witnesses` are the other people close enough to see it; loud
## gestures in company become deeds, which is how a reputation for dancing badly gets about.
## Returns {gesture, npc, delta, disposition, line, reply_gesture, deed}.
static func perform(gesture_id: String, npc_id: String, ctx: SocialContext, witnesses: Array = []) -> Dictionary:
	var def := definition(gesture_id)
	if def.is_empty():
		return {}
	var traits := _traits_for(npc_id, ctx)
	var delta := reaction_for(def, traits)
	delta = int(round(float(delta) * _repetition_factor(npc_id, gesture_id)))
	_remember(npc_id, gesture_id)

	if npc_id != "":
		ctx.add_disposition(npc_id, delta)
	EventBus.gesture_performed.emit(gesture_id, npc_id)

	var line := ctx.substitute(reply_for(def, traits, npc_id, ctx.rng))
	var reply_gesture := reply_gesture_for(def, traits)
	if reply_gesture != "" and npc_id != "":
		EventBus.npc_gesture.emit(npc_id, reply_gesture)

	var deed := str(def.get("deed", ""))
	var audience: Array = witnesses.duplicate()
	if npc_id != "" and not audience.has(npc_id):
		audience.append(npc_id)
	if deed != "" and (bool(def.get("loud", false)) or delta < 0) and not audience.is_empty():
		ctx.apply_deed(deed, audience)
	else:
		deed = ""

	# An apology taken well clears what this NPC saw you do.
	if bool(def.get("forgives", false)) and delta > 0:
		var standing := ctx.provider("standing")
		if standing != null and standing.has_method("forget_witness"):
			standing.call("forget_witness", npc_id)

	return {
		"gesture": gesture_id, "npc": npc_id, "delta": delta,
		"disposition": ctx.disposition(npc_id), "line": line,
		"reply_gesture": reply_gesture, "deed": deed,
	}


static func _traits_for(npc_id: String, ctx: SocialContext) -> Array:
	if ctx.npc_id == npc_id and not ctx.npc.is_empty():
		return ctx.npc_traits()
	var def := ContentDB.get_or_empty(npc_id)
	var pers: Variant = def.get("personality", {})
	if typeof(pers) == TYPE_DICTIONARY:
		var t: Variant = (pers as Dictionary).get("traits", [])
		return t if typeof(t) == TYPE_ARRAY else []
	if typeof(pers) == TYPE_ARRAY:
		return pers
	return []


static func _repetition_factor(npc_id: String, gesture_id: String) -> float:
	var recent: Array = _recent.get(npc_id, [])
	var repeats := 0
	for g in recent:
		if str(g) == gesture_id:
			repeats += 1
	return pow(REPEAT_DECAY, float(repeats))


static func _remember(npc_id: String, gesture_id: String) -> void:
	if npc_id == "":
		return
	var recent: Array = _recent.get(npc_id, [])
	recent.append(gesture_id)
	while recent.size() > REPEAT_WINDOW:
		recent.pop_front()
	_recent[npc_id] = recent


## Forgets the recent-gesture memory (new game, or long enough away).
static func clear_memory(npc_id: String = "") -> void:
	if npc_id == "":
		_recent.clear()
	else:
		_recent.erase(npc_id)
