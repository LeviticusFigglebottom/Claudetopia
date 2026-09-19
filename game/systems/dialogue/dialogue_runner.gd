extends Node
## DialogueRunner: walks a dialogue graph. Filters choices by conditions, applies effects, and
## tells the UI what to show. Joins the group "dialogue_runner".
##
## Data: content type "dialogue" (docs/CONTRACTS.md §7):
##   {id, start, nodes{node_id: {speaker, text, conditions[], effects[], choices[{text, next,
##    conditions[], effects[], once}], next, else, once}}}
##
## Text may use {player}, {title}, {npc}, {place}, {region}, and the token "{greeting}", which is
## replaced by a line from the personality x standing matrix (systems/dialogue/greetings.gd).
##
## Signals (the UI contract):
##   line_shown(speaker: String, text: String, choices: Array)   choices are [{index, text}]
##   choice_needed(choices: Array)                               only when a choice is required
##   ended()
## Methods: start(dialogue_id, npc_id) -> bool, advance(), choose(index), gesture(gesture_id),
##          stop(), is_running(), greeting_for(npc_id).

signal line_shown(speaker: String, text: String, choices: Array)
signal choice_needed(choices: Array)
signal ended

## The context every condition reads and every effect writes through (injected by Social).
var ctx: SocialContext = null

var dialogue_id: String = ""
var npc_id: String = ""
var current_node_id: String = ""
var current_choices: Array[Dictionary] = []
var history: Array[String] = []

var _def: Dictionary = {}
## The hub the talk choice was asked from, so the conversation comes back to it.
var _talk_return_to: String = ""
var _running := false
var _visits: Dictionary = {}            # node_id -> times entered this conversation
var _taken: Dictionary = {}             # "node:index" -> true, for `once` choices this run


func _ready() -> void:
	add_to_group("dialogue_runner")
	if ctx == null:
		ctx = SocialContext.new()


func is_running() -> bool:
	return _running


# --- starting and stopping ----------------------------------------------------------------------

## Begins a conversation. A dialogue id of "" gives the bare greeting exchange, which is what a
## villager with nothing to say still owes you.
func start(new_dialogue_id: String, new_npc_id: String = "", place_id: String = "") -> bool:
	return _begin(new_dialogue_id, {}, new_npc_id, place_id)


## Runs a dialogue graph that is not in the content packs: a generated conversation, a debug
## graph, or a test fixture. The definition has the same shape as a `dialogue` def.
func start_def(def: Dictionary, new_npc_id: String = "", place_id: String = "") -> bool:
	return _begin(str(def.get("id", "")), def, new_npc_id, place_id)


func _begin(new_dialogue_id: String, def_override: Dictionary, new_npc_id: String, place_id: String) -> bool:
	if _running:
		stop()
	npc_id = new_npc_id
	dialogue_id = new_dialogue_id
	_visits.clear()
	_taken.clear()
	history.clear()
	current_choices.clear()
	ctx.reset_conversation()
	ctx.npc_id = npc_id
	ctx.npc = ContentDB.get_or_empty(npc_id)
	if place_id != "":
		ctx.place_id = place_id
	elif ctx.npc.has("home_place"):
		ctx.place_id = str(ctx.npc["home_place"])

	if dialogue_id == "" and ctx.npc.has("dialogue"):
		dialogue_id = str(ctx.npc["dialogue"])

	if not def_override.is_empty():
		_def = def_override
	else:
		_def = ContentDB.get_or_empty(dialogue_id) if dialogue_id != "" else {}
	if dialogue_id != "" and _def.is_empty():
		Log.warn("Dialogue", "unknown dialogue '%s' (content problem)" % dialogue_id)
	_running = true
	EventBus.dialogue_started.emit(npc_id)

	if _def.is_empty() or typeof(_def.get("nodes")) != TYPE_DICTIONARY:
		_show_bare_greeting()
		return true
	var first := str(_def.get("start", "start"))
	if not (_def["nodes"] as Dictionary).has(first):
		var keys: Array = (_def["nodes"] as Dictionary).keys()
		if keys.is_empty():
			_show_bare_greeting()
			return true
		Log.warn("Dialogue", "%s has no start node '%s' (content problem); using '%s'" % [dialogue_id, first, str(keys[0])])
		first = str(keys[0])
	_enter(first)
	return true


func stop() -> void:
	if not _running:
		return
	_running = false
	var who := npc_id
	current_choices.clear()
	current_node_id = ""
	EventBus.dialogue_ended.emit(who)
	ended.emit()


# --- walking the graph ----------------------------------------------------------------------------

func _enter(node_id: String) -> void:
	if not _running:
		return
	if node_id == "" or node_id == "end":
		stop()
		return
	var nodes: Dictionary = _def.get("nodes", {})
	if not nodes.has(node_id) and node_id != TALK_NODE:
		Log.warn("Dialogue", "%s: no node '%s' (content problem)" % [dialogue_id, node_id])
		stop()
		return
	# The talk is built when it is asked for, so it is not in the graph the author wrote.
	var node: Dictionary = _node(node_id)

	if not Conditions.all_of(node.get("conditions", []), ctx):
		var alt := str(node.get("else", ""))
		if alt != "" and alt != node_id:
			_enter(alt)
		else:
			stop()
		return

	var visits := int(_visits.get(node_id, 0))
	if bool(node.get("once", false)) and visits > 0:
		var after := str(node.get("next", ""))
		if after != "" and after != node_id:
			_enter(after)
		else:
			stop()
		return
	_visits[node_id] = visits + 1

	current_node_id = node_id
	history.append(node_id)
	Effects.apply_all(node.get("effects", []), ctx, "dialogue:" + dialogue_id)
	_flush_side_effects()

	var text := _text_of(node)
	var speaker := _speaker_of(node)
	current_choices = _visible_choices(node)

	line_shown.emit(speaker, text, _choice_payload())
	if not current_choices.is_empty():
		choice_needed.emit(_choice_payload())
		return
	if ctx.end_requested:
		ctx.end_requested = false
		stop()
		return
	if not node.has("next"):
		# A node with nothing after it and nothing to ask is the end of the conversation; the UI
		# still gets its line first.
		stop()


## Moves past a line that had no choices. The UI calls this when the player presses on.
func advance() -> void:
	if not _running:
		return
	if not current_choices.is_empty():
		return
	var node: Dictionary = _node(current_node_id)
	if ctx.end_requested:
		ctx.end_requested = false
		stop()
		return
	var next := str(node.get("next", ""))
	if next == "":
		stop()
		return
	_enter(next)


## Takes the choice the player picked (an index into the list the UI was given).
func choose(index: int) -> void:
	if not _running or current_choices.is_empty():
		return
	if index < 0 or index >= current_choices.size():
		Log.warn("Dialogue", "%s: choice %d out of range (%d shown)" % [dialogue_id, index, current_choices.size()])
		return
	var choice: Dictionary = current_choices[index]
	if bool(choice.get("talk", false)):
		_talk_return_to = current_node_id
	var source: int = int(choice.get("source_index", index))
	if source >= 0:
		_taken["%s:%d" % [current_node_id, source]] = true
	current_choices.clear()

	Effects.apply_all(choice.get("effects", []), ctx, "dialogue:" + dialogue_id)
	_flush_side_effects()
	if ctx.end_requested:
		ctx.end_requested = false
		stop()
		return
	var next := str(choice.get("next", ""))
	if next == "":
		var node: Dictionary = _node(current_node_id)
		next = str(node.get("next", ""))
	if next == "":
		stop()
		return
	_enter(next)


## A gesture made during the conversation: the NPC answers, and the answer is a line like any
## other, so the UI shows it the same way.
func gesture(gesture_id: String, witnesses: Array = []) -> Dictionary:
	var result := Gestures.perform(gesture_id, npc_id, ctx, witnesses)
	if result.is_empty():
		return result
	if _running and str(result.get("line", "")) != "":
		line_shown.emit(_npc_name(), str(result["line"]), _choice_payload())
	return result


# --- node helpers -----------------------------------------------------------------------------------

func _node(node_id: String) -> Dictionary:
	if node_id == TALK_NODE:
		return _talk_node()
	var nodes: Dictionary = _def.get("nodes", {})
	var n: Variant = nodes.get(node_id, {})
	return n if typeof(n) == TYPE_DICTIONARY else {}


func _text_of(node: Dictionary) -> String:
	var text := str(node.get("text", ""))
	if text.find("{greeting}") >= 0:
		text = text.replace("{greeting}", greeting_for(npc_id))
	return ctx.substitute(text)


func _speaker_of(node: Dictionary) -> String:
	var speaker := str(node.get("speaker", "npc"))
	match speaker:
		"npc", "":
			return _npc_name()
		"player", "you":
			return ctx.player_name()
		_:
			var def := ContentDB.get_or_empty(speaker)
			return str(def.get("name", speaker)) if not def.is_empty() else speaker


## Who the nameplate says. The bound NPC's name when there is one; otherwise the dialogue's own
## `speaker_name`, which is how a conversation with somebody who is not a roster NPC — a voice
## through a door, a Sayer at a lectern — still has a name over it.
func _npc_name() -> String:
	var bound := str(ctx.npc.get("name", ""))
	if not bound.is_empty():
		return bound
	var named := str(_def.get("speaker_name", ""))
	if not named.is_empty():
		return named
	return npc_id if npc_id != "" else "Somebody"


## Choices whose conditions pass and which have not been used up, in authored order.
## The talk of the place, offered at any hub that does not turn it down. Every villager can be
## asked what people are saying, so the gossip the world generates about your deeds actually
## reaches you instead of sitting in a pool nobody reads. Hearing it writes the rumour into the
## journal, which is what the rumour page has always keyed on.
const TALK_CHOICE := "What are people saying?"
const TALK_NODE := "__talk"
const TALK_FRAMING := {
	"warm": "%s",
	"neutral": "%s",
	"cold": "You did not hear this from me. — %s",
}


func _talk_choice() -> Dictionary:
	return {"text": TALK_CHOICE, "next": TALK_NODE, "talk": true}


## Builds the node the talk choice goes to, so the rumour is picked at the moment it is asked
## for rather than when the conversation opened.
func _talk_node() -> Dictionary:
	var news := ctx.hottest_rumour()
	if news.is_empty():
		return {"speaker": "npc", "text": "Nothing worth repeating. Which is its own kind of news, round here.", "next": current_node_id}
	var rumour_id := str(news.get("rumour", ""))
	if rumour_id != "":
		ctx.set_flag("rumour:" + rumour_id, true)
	var framing := str(TALK_FRAMING.get(str(news.get("tone", "neutral")), "%s"))
	return {"speaker": "npc", "text": framing % str(news.get("text", "")), "next": _talk_return_to}


func _visible_choices(node: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var choices: Variant = node.get("choices", [])
	if typeof(choices) != TYPE_ARRAY:
		return out
	for i in (choices as Array).size():
		var c: Variant = (choices as Array)[i]
		if typeof(c) != TYPE_DICTIONARY:
			ctx.problem("%s: choice %d of node '%s' is not an object" % [dialogue_id, i, current_node_id])
			continue
		var choice: Dictionary = (c as Dictionary).duplicate(true)
		if bool(choice.get("once", false)) and _taken.has("%s:%d" % [current_node_id, i]):
			continue
		if not Conditions.all_of(choice.get("conditions", []), ctx):
			continue
		choice["source_index"] = i
		choice["text"] = ctx.substitute(str(choice.get("text", "...")))
		out.append(choice)
	if not out.is_empty() and not bool(node.get("no_talk", false)) and not ctx.hottest_rumour().is_empty():
		var talk := _talk_choice()
		talk["source_index"] = -1
		out.insert(maxi(out.size() - 1, 0), talk)
	return out


## What the UI is handed: [{index, text}] plus any tag the author put on the choice.
func _choice_payload() -> Array:
	var out: Array = []
	for i in current_choices.size():
		var c: Dictionary = current_choices[i]
		var entry: Dictionary = {"index": i, "text": str(c.get("text", "..."))}
		if c.has("tag"):
			entry["tag"] = str(c["tag"])
		if c.has("skill"):
			entry["skill"] = str(c["skill"])
		out.append(entry)
	return out


## Gesture replies and notifications produced by effects go out as soon as they are made.
func _flush_side_effects() -> void:
	for g in ctx.gesture_replies:
		EventBus.npc_gesture.emit(npc_id, str(g))
	ctx.gesture_replies.clear()
	for n in ctx.notifications:
		EventBus.emit_notify(str(n))
	ctx.notifications.clear()


# --- greetings ------------------------------------------------------------------------------------

## The greeting this NPC would give right now, without starting a conversation (for barks and
## for the interaction prompt).
func greeting_for(for_npc_id: String) -> String:
	var previous_id := ctx.npc_id
	var previous_def := ctx.npc
	if for_npc_id != ctx.npc_id:
		ctx.npc_id = for_npc_id
		ctx.npc = ContentDB.get_or_empty(for_npc_id)
	var line := Greetings.greet(for_npc_id, ctx)
	ctx.npc_id = previous_id
	ctx.npc = previous_def
	return line


func _show_bare_greeting() -> void:
	current_node_id = ""
	current_choices.clear()
	var line := greeting_for(npc_id)
	if line == "":
		line = "..."
	line_shown.emit(_npc_name(), line, [])
