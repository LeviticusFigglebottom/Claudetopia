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
## True while the opening node (and any `else` it chains to) is being entered. If that whole
## chain fails its conditions, the conversation must not simply close in the player's face:
## a villager whose only lines are gated behind a quest you have not taken still owes you a
## hello, which is what `_show_bare_greeting` is for.
var _opening := false
var _visits: Dictionary = {}            # node_id -> times entered this conversation
var _taken: Dictionary = {}             # "node:index" -> true, for `once` choices this run
var _ended_frame := -100
var _ended_ms := -100000

## The node a conversation says goodbye on, and ends after, whatever it names as next. The dialogues'
## own notes say so ("the hub is 'hub'; topic nodes return to it; 'bye' ends"), but sixty of the
## seventy-two sent 'bye' back to the hub. Nothing noticed while nobody could start a conversation;
## once they could, a talk with the Warden could not be left.
const BYE_NODE := "bye"

## A conversation has one owner, this runner, and every way it can be left ends it here, so the one
## signal everything else keys on (EventBus.dialogue_ended: the camera's two-shot, the dialogue
## page, the body's held keys, the NPC's day) is always sent (triage 41: a trade left the camera
## on the shopkeeper and the page could stay up with nothing on it). Besides the graph's own ends:
## the player struck or a foe closing in, the player dying, a save loaded, and
## the person spoken to gone (unloaded, dead) or more than WALK_AWAY_M further off than when the
## talk began (they walked on, or the player was carried off: a fast travel, a knock-back).
const WALK_AWAY_M := 4.0
## Nobody further than this at the start is anybody the talk is held to (a quest's word from
## across the map, a Hearthstone, a test): the camera's reach (CameraRig.TALK_REACH).
const SPEAKER_REACH_M := 6.0
## A foe turning on the player nearer than this ends the talk.
const FOE_NEAR_M := 25.0
## How often the watch looks, in seconds.
const WATCH_S := 0.25
## A choice the runner adds where an author's every choice was closed off by its conditions and
## the node has nothing after it: the page is never left with nothing to press.
const LEAVE_CHOICE := "Leave."

## The body of the person being spoken to, when they stand near the player: what the camera frames
## and what the watch measures. Null for a voice with no body (a stone, a lectern, a test).
var speaker_actor: Node3D = null
## Who the next conversation is with, when the caller already has the body (set before start).
var _next_speaker: Node3D = null
var _held_at := 0.0
var _watch_t := 0.0


func _ready() -> void:
	add_to_group("dialogue_runner")
	if ctx == null:
		ctx = SocialContext.new()
	set_process(false)
	for pair in [[EventBus.damage_dealt, _on_damage_dealt], [EventBus.enemy_engaged, _on_enemy_engaged],
			[EventBus.player_died, _on_player_died], [EventBus.game_loaded, _on_game_loaded]]:
		var sig: Signal = pair[0]
		if not sig.is_connected(pair[1]):
			sig.connect(pair[1])


## The body the next conversation is held to (the camera frames it; walking away from it ends the
## talk). Otherwise the roster's actor for the npc id is used.
func set_next_speaker(body: Node3D) -> void:
	_next_speaker = body


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
	_hold_to_speaker()
	# Having spoken to somebody once is what puts them in the journal's People page.
	if npc_id != "" and ContentDB.has(npc_id):
		ctx.set_flag("met:" + npc_id, true)
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
	_opening = true
	_enter(first)
	_opening = false
	return true


func stop() -> void:
	if not _running:
		return
	_running = false
	_ended_frame = Engine.get_process_frames()
	_ended_ms = Time.get_ticks_msec()
	var who := npc_id
	current_choices.clear()
	current_node_id = ""
	speaker_actor = null
	set_process(false)
	EventBus.dialogue_ended.emit(who)
	ended.emit()


## Whether a conversation ended a moment ago: this frame or the next two, or the last quarter of a
## second on the wall. The key that goes on to the end of a conversation is the key that starts one,
## and the press the dialogue took to close itself must not open it again (Interactor.try_interact).
func just_ended() -> bool:
	return Engine.get_process_frames() - _ended_frame <= 2 or Time.get_ticks_msec() - _ended_ms < 250


# --- the watch: every other way a conversation is left ----------------------------------------

func _player_body() -> Node3D:
	var p := Peers.player() as Node3D
	if p == null and is_inside_tree():
		p = get_tree().get_first_node_in_group("player") as Node3D
	return p if p != null and is_instance_valid(p) and p.is_inside_tree() else null


func _hold_to_speaker() -> void:
	speaker_actor = null
	var body: Node3D = _next_speaker if _next_speaker != null and is_instance_valid(_next_speaker) else null
	_next_speaker = null
	if body == null and npc_id != "" and NpcRegistry.instance != null and is_instance_valid(NpcRegistry.instance):
		body = NpcRegistry.instance.actor(npc_id) as Node3D
	var player := _player_body()
	if body == null or player == null or not body.is_inside_tree():
		return
	var apart := _flat_distance(body, player)
	if apart > SPEAKER_REACH_M:
		return
	speaker_actor = body
	_held_at = apart
	_watch_t = 0.0
	set_process(true)


static func _flat_distance(a: Node3D, b: Node3D) -> float:
	var d := a.global_position - b.global_position
	return Vector2(d.x, d.z).length()


func _process(delta: float) -> void:
	if not _running:
		set_process(false)
		return
	_watch_t += delta
	if _watch_t < WATCH_S:
		return
	_watch_t = 0.0
	check_speaker()


## Ends the conversation when the person spoken to is gone or out of reach (see WALK_AWAY_M).
## Returns whether it is still running. The watch calls it; a test may call it at once.
func check_speaker() -> bool:
	if not _running or speaker_actor == null:
		return _running
	var body := speaker_actor
	if not is_instance_valid(body) or not body.is_inside_tree() or ("alive" in body and not bool(body.get("alive"))):
		stop()
		return false
	var player := _player_body()
	if player != null and _flat_distance(body, player) > maxf(_held_at, SPEAKER_REACH_M) + WALK_AWAY_M:
		stop()
		return false
	return true


func _is_player(n: Node) -> bool:
	return n != null and is_instance_valid(n) and n.is_in_group("player")


## Struck, the talk is over: the body is held while somebody is talking, and a held body cannot
## raise its guard.
func _on_damage_dealt(_attacker: Node, victim: Node, amount: float, _kind: String) -> void:
	if _running and amount > 0.0 and _is_player(victim):
		stop()


func _on_enemy_engaged(enemy: Node, engaged: bool) -> void:
	if not _running or not engaged or enemy == null or not is_instance_valid(enemy):
		return
	if not _is_player(enemy.get("target") as Node):
		return
	var player := _player_body()
	if player != null and enemy is Node3D and _flat_distance(enemy as Node3D, player) > FOE_NEAR_M:
		return
	stop()


func _on_player_died(_at: Vector3) -> void:
	stop()


func _on_game_loaded(_slot: String) -> void:
	stop()


# --- walking the graph ----------------------------------------------------------------------------

func _enter(node_id: String) -> void:
	if not _running:
		return
	if node_id == "" or node_id == "end":
		stop()
		return
	var nodes: Dictionary = _def.get("nodes", {})
	if not nodes.has(node_id) and node_id != TALK_NODE and node_id != TRADE_NODE and not node_id.begins_with(DEED_NODE):
		Log.warn("Dialogue", "%s: no node '%s' (content problem)" % [dialogue_id, node_id])
		stop()
		return
	# The talk is built when it is asked for, so it is not in the graph the author wrote.
	var node: Dictionary = _node(node_id)

	if not Conditions.all_of(node.get("conditions", []), ctx):
		var alt := str(node.get("else", ""))
		if alt != "" and alt != node_id:
			_enter(alt)
		elif _opening:
			_show_bare_greeting()
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
	_opening = false

	current_node_id = node_id
	history.append(node_id)
	EventBus.dialogue_node_entered.emit(npc_id, node_id)
	Effects.apply_all(node.get("effects", []), ctx, "dialogue:" + dialogue_id)
	_flush_side_effects()

	var text := _text_of(node)
	var speaker := _speaker_of(node)
	current_choices = _visible_choices(node)
	if current_choices.is_empty() and not node.has("next") and _has_authored_choices(node) and not ctx.end_requested:
		# every answer the author wrote is closed off here and nothing comes after: a way out
		current_choices.append({"text": LEAVE_CHOICE, "next": "end", "source_index": -7})
	if text.strip_edges().is_empty() and current_choices.is_empty():
		# a page with no line and nothing to press is never put up (triage 41)
		text = "..."

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
	if next == "" or current_node_id == BYE_NODE:
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
	if node_id == TRADE_NODE:
		return _trade_node()
	if node_id.begins_with(DEED_NODE):
		return _deed_node(node_id.substr(DEED_NODE.length()))
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
			# the bound person's own name written out is still them, and answers to their `known_as`
			if speaker == str(ctx.npc.get("name", "")):
				return _npc_name()
			var def := ContentDB.get_or_empty(speaker)
			return Npc.shown_name(def, ctx, speaker) if not def.is_empty() else speaker


## Who the nameplate says. The bound NPC's name when there is one; otherwise the dialogue's own
## `speaker_name`, which is how a conversation with somebody who is not a roster NPC — a voice
## through a door, a Sayer at a lectern — still has a name over it.
func _npc_name() -> String:
	var bound := Npc.shown_name(ctx.npc, ctx)
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
## The shop. An NPC with a `merchant` block carries a stock table, a float of marks and a
## price list, and until now there was no way to reach any of it: nothing in the game opened
## the trade screen, so every shopkeeper in Wickmere was a person you could only chat to.
## Offered at any hub that does not turn it down, like the talk of the place, so a merchant is
## reachable whether or not their author remembered to write the topic.
const TRADE_CHOICE := "Let me see what you have."
const TRADE_NODE := "__trade"
## A deed. An npc def that `sells_deeds` holds the deeds of the place it lives in; the key was
## written on Merrowby's steward and nothing read it, so he explained where the deeds were kept
## and could not hand one over. Each deed still for sale is offered at his hub, and taking one
## opens the deed screen, where the buying is done (`__deed:<deed id>`).
const DEED_NODE := "__deed:"
const TALK_FRAMING := {
	"warm": "%s",
	"neutral": "%s",
	"cold": "You did not hear this from me. — %s",
}


func _talk_choice() -> Dictionary:
	return {"text": TALK_CHOICE, "next": TALK_NODE, "talk": true}


func _trade_choice() -> Dictionary:
	return {"text": TRADE_CHOICE, "next": TRADE_NODE, "talk": true}


## Opening the shop is a thing that happens in the world, not a line of dialogue, so this asks
## for it and then puts the conversation back where it was. Whoever is listening -- the UI in
## the game, a test in the suite -- decides what a shop looks like.
func _trade_node() -> Dictionary:
	EventBus.trade_requested.emit(npc_id)
	return {"speaker": "npc", "text": _trade_line(), "next": _talk_return_to}


func _trade_line() -> String:
	var traits: Array = ctx.npc.get("personality", {}).get("traits", [])
	if traits.has("gruff") or traits.has("cynical"):
		return "Look, then. Do not handle what you are not buying."
	if traits.has("kind") or traits.has("warm"):
		return "Of course. Take your time over it, there is no one behind you."
	return "Everything is out. The prices are what they are."


## Whether this person keeps a shop at all.
func _sells_things() -> bool:
	return typeof(ctx.npc.get("merchant", null)) == TYPE_DICTIONARY


## The deeds this person holds and has not yet sold you, as choices: the houses of the place they
## live in, when their def `sells_deeds`.
func _deed_choices() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not bool(ctx.npc.get("sells_deeds", false)):
		return out
	var reg := PropertyRegistry.instance
	for d in PropertyRegistry.deeds_at(str(ctx.npc.get("home_place", ""))):
		var id := str(d.get("id", ""))
		if reg != null and reg.is_owned(id):
			continue
		var price := reg.asking_price(id) if reg != null else PropertyRegistry.price_of(id)
		out.append({"text": "The deed to %s. (%d marks)" % [PropertyRegistry.display_name(id), price],
				"next": DEED_NODE + id, "talk": true, "source_index": -6, "tag": "trade"})
	return out


## Taking a deed down: the screen that buys it is opened, and the conversation goes back to
## where it was, so the deed can be put back if the price is too dear.
func _deed_node(property_id: String) -> Dictionary:
	var reg := PropertyRegistry.instance
	var price := reg.asking_price(property_id) if reg != null else PropertyRegistry.price_of(property_id)
	EventBus.property_offered.emit(property_id, price)
	var house := PropertyRegistry.display_name(property_id)
	return {"speaker": "npc", "text": "%s%s. The price is on it, and it is the price." % [house.left(1).to_upper(), house.substr(1)],
			"next": _talk_return_to}


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


static func _has_authored_choices(node: Dictionary) -> bool:
	var choices: Variant = node.get("choices", [])
	return typeof(choices) == TYPE_ARRAY and not (choices as Array).is_empty()


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
	if not out.is_empty() and not bool(node.get("no_trade", false)) and _sells_things():
		var trade := _trade_choice()
		trade["source_index"] = -2
		out.insert(maxi(out.size() - 1, 0), trade)
	if not out.is_empty() and not bool(node.get("no_trade", false)):
		for deed in _deed_choices():
			out.insert(maxi(out.size() - 1, 0), deed)
	# A decision the journal is waiting on that no author wrote a button for is put to the person
	# who hosts it, at their hub (QuestRoutes): the main thread's five decisions had none, so none
	# of them could be made. After deciding, the conversation goes back to where it was.
	if not out.is_empty() and npc_id != "":
		for offer in ctx.quest_offers(npc_id):
			var decide := {"text": ctx.substitute(str(offer.get("text", ""))), "next": current_node_id,
					"effects": [{"quest_choice": [str(offer.get("quest_id", "")), str(offer.get("id", ""))]}],
					"source_index": -3, "tag": "quest"}
			out.insert(maxi(out.size() - 1, 0), decide)
		# and the work they are the giver of, where nothing else in the pack starts it
		for offer in _starts():
			out.insert(maxi(out.size() - 1, 0), offer)
	return out


## A giver's quests as choices that start them (QuestLog.giver_offers); the conversation carries on
## from where it was asked.
func _starts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if npc_id == "":
		return out
	for offer in ctx.quest_starts(npc_id):
		out.append({"text": ctx.substitute(str(offer.get("text", ""))), "next": current_node_id,
				"effects": [{"start_quest": str(offer.get("quest_id", ""))}], "source_index": -4, "tag": "quest"})
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
		var q := quest_cue(c)
		if not q.is_empty():
			entry["quest"] = q
		out.append(entry)
	return out


## What a choice does to the player's quests (QuestCues.for_choice): {kind, quest_id, name, tier,
## tag, tier_word}, or {} when it does nothing to any. Read from its effects and the lines it leads
## to; nothing an author writes on the choice.
func quest_cue(choice: Dictionary) -> Dictionary:
	if ctx == null:
		return {}
	return QuestCues.for_choice(choice, npc_id, _node,
			func(conds: Variant) -> bool: return Conditions.all_of(conds if typeof(conds) == TYPE_ARRAY else [], ctx),
			ctx.provider("quests"))


## What the person spoken to is to the player's quests now (QuestCues.state_now), for the page's
## nameplate: {} when nothing.
func speaker_quest_state() -> Dictionary:
	if npc_id == "" or ctx == null:
		return {}
	return QuestCues.state_now(npc_id, ctx.provider("quests"), ctx)


## Gesture replies and notifications produced by effects go out as soon as they are made.
func _flush_side_effects() -> void:
	for g in ctx.gesture_replies:
		EventBus.npc_gesture.emit(npc_id, str(g))
	ctx.gesture_replies.clear()
	for n in ctx.notifications:
		EventBus.emit_notify(str(n))
	ctx.notifications.clear()
	Barks.flush(ctx)
	# the work a resident offers is their place's board, read over the conversation the way a
	# notice post is read: the same screen, and the conversation is there when it closes
	for place in ctx.work_offered:
		var board := JobBoard.for_place(str(place))
		if board != null:
			EventBus.job_board_opened.emit(board, Peers.player())
	ctx.work_offered.clear()


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
	# somebody with nothing to say may still have work to give, and taking it ends the exchange
	var offers := _starts()
	if not offers.is_empty():
		for offer in offers:
			offer["next"] = ""
			current_choices.append(offer)
		current_choices.append({"text": "Goodbye.", "next": "", "source_index": -5})
		line_shown.emit(_npc_name(), line, _choice_payload())
		choice_needed.emit(_choice_payload())
		return
	line_shown.emit(_npc_name(), line, [])
