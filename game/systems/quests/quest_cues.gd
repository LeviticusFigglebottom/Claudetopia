class_name QuestCues
extends RefCounted
## What a quest is to the player at a glance (triage 50): which answers in a conversation take a
## quest, move one on or hand one in, whether somebody has quest business with you, and what kind
## of quest it is. The user: "it's not obvious what dialog options relate to/progress quests (with
## distinction between turning in main/side quest, accepting a quest, etc)".
##
## Everything is read from what the content already says, never from a mark an author has to add:
##   start    an answer (or the lines it leads to) says `start_quest`, or a `quest_stage` on a
##            quest not yet taken;
##   advance  a `quest_stage`, `complete_objective` or `quest_choice` on a quest under way, or a
##            line that is the `topic` of an open `talk` objective with this person, or a
##            `take_item` a `deliver` to them is waiting on;
##   turn_in  `complete_quest`, or any of the above when it is the last thing the quest asks
##            (the stage's other steps done, no stage after it that asks anything);
##   about    no effect, but the answer is only offered while a quest is at some stage
##            (`quest_at`, `quest_active`, `quest_min_stage`): it is about that quest.
## The tier is the quest's `layer`: `main`, `faction`, `side` (and radiant work), and `intro` for a
## fighting style's first lessons and its tie-in (the style's `tutorial` and `tie_in`), or a quest
## whose layer says `intro`.
##
## A person's standing mark (QuestMark over their head, the dialogue's nameplate) is the strongest
## of: `turn_in` (speaking to them finishes a quest), `advance` (a step of a quest is theirs),
## `available` (they have a quest to give), `in_progress` (they gave a quest that is under way).

const KINDS := ["turn_in", "start", "advance", "about"]
## How the page says each kind, before the answer.
const TAGS := {"start": "New quest", "advance": "Quest", "turn_in": "Turn in", "about": ""}
const TIER_WORDS := {"main": "Main quest", "side": "Side quest", "faction": "Faction quest", "intro": "First lessons"}
## Colours that read on the dialogue page's dark oak and in the world at dusk: main gold, side a
## pale blue, faction a rose red, the first lessons a leaf green.
const TIER_COLOURS := {"main": Color(0.96, 0.75, 0.3), "side": Color(0.58, 0.78, 0.97),
		"faction": Color(0.94, 0.5, 0.45), "intro": Color(0.58, 0.87, 0.52)}
## The same, as ink on the page's parchment (the dialogue page, the journal): deep enough to read.
const TIER_INKS := {"main": Color(0.55, 0.34, 0.0), "side": Color(0.1, 0.28, 0.5),
		"faction": Color(0.52, 0.1, 0.08), "intro": Color(0.13, 0.4, 0.12)}
## The standing marks, strongest first.
const STATES := ["turn_in", "advance", "available", "in_progress"]
## How many lines a choice is followed through, looking for what it does.
const MAX_HOPS := 6
## How long a person's standing mark is kept before it is asked again (wall clock).
const STATE_TTL_MS := 900

static var _intros: Dictionary = {}
static var _intros_built := false
static var _states: Dictionary = {}     # npc id -> {at_ms, cue}


static func reset() -> void:
	_intros.clear()
	_intros_built = false
	_states.clear()


# --- tiers ---------------------------------------------------------------------------------------

static func tier_of(quest_id: String, def: Dictionary = {}) -> String:
	if def.is_empty():
		def = ContentDB.get_or_empty(quest_id)
	var layer := str(def.get("layer", "side"))
	if layer == "intro" or _is_intro(quest_id):
		return "intro"
	match layer:
		"main":
			return "main"
		"faction":
			return "faction"
	return "side"


static func tier_colour(tier: String) -> Color:
	return TIER_COLOURS.get(tier, TIER_COLOURS["side"])


static func tier_ink(tier: String) -> Color:
	return TIER_INKS.get(tier, TIER_INKS["side"])


static func tier_word(tier: String) -> String:
	return str(TIER_WORDS.get(tier, "Quest"))


static func _is_intro(quest_id: String) -> bool:
	if not _intros_built:
		_intros_built = true
		for style in ContentDB.all("style"):
			for key in ["tutorial", "tie_in"]:
				var q := str(style.get(key, ""))
				if q != "":
					_intros[q] = true
	return _intros.has(quest_id)


static func quest_name(quest_id: String, quests: Object = null) -> String:
	var def := _def(quest_id, quests)
	return str(def.get("name", Ids.name_of(quest_id).replace("_", " ").capitalize()))


static func _def(quest_id: String, quests: Object) -> Dictionary:
	if quests != null and quests.has_method("definition"):
		var d: Dictionary = quests.call("definition", quest_id)
		if not d.is_empty():
			return d
	return ContentDB.get_or_empty(quest_id)


## {kind, quest_id, name, tier, tag, tier_word} for one kind on one quest.
static func cue(kind: String, quest_id: String, quests: Object = null) -> Dictionary:
	var tier := tier_of(quest_id, _def(quest_id, quests))
	return {"kind": kind, "quest_id": quest_id, "name": quest_name(quest_id, quests), "tier": tier,
			"tag": str(TAGS.get(kind, "")), "tier_word": tier_word(tier)}


## The first line of a journal entry, and of a long one its first sentence or two, up to about
## `limit` characters: why a stage is asked (the HUD's notice), a past stage in the journal's log.
static func first_line(journal: String, limit := 170) -> String:
	var trimmed := journal.strip_edges()
	if trimmed == "":
		return ""
	var line := trimmed.split("\n", false)[0]
	if line.length() <= limit:
		return line
	var cut := -1
	for end in [". ", "! ", "? "]:
		var at := line.rfind(end, limit)
		if at > cut:
			cut = at
	return line.substr(0, cut + 1) if cut > 40 else line.substr(0, limit - 3).strip_edges() + "..."


# --- a choice ------------------------------------------------------------------------------------

## What taking a choice does to the player's quests, as a cue, or {} for nothing.
##   `lookup`   Callable(node_id) -> Dictionary: the node of the conversation's graph
##   `passes`   Callable(conditions: Array) -> bool: whether a node's conditions hold now
##   `quests`   the QuestLog (or anything with its reading methods); null reads effects alone
## The choice's effects are read, then the lines it leads to (through `next` and `else`) up to
## the next set of answers: the effect that takes a quest is often on the line after the answer.
static func for_choice(choice: Dictionary, npc_id: String, lookup: Callable, passes: Callable, quests: Object) -> Dictionary:
	var found: Array[Dictionary] = []
	found.append_array(_effect_cues(choice.get("effects", []), npc_id, quests))
	var next := str(choice.get("next", ""))
	var seen := {}
	var hops := 0
	while next != "" and next != "end" and hops < MAX_HOPS and not seen.has(next):
		seen[next] = true
		hops += 1
		var node: Dictionary = lookup.call(next)
		if node.is_empty():
			break
		if not bool(passes.call(node.get("conditions", []))):
			next = str(node.get("else", ""))
			continue
		found.append_array(_topic_cues(next, npc_id, quests))
		found.append_array(_effect_cues(node.get("effects", []), npc_id, quests))
		var choices: Variant = node.get("choices", [])
		if typeof(choices) == TYPE_ARRAY and not (choices as Array).is_empty():
			break
		next = str(node.get("next", ""))
	if found.is_empty():
		var about := _about(choice.get("conditions", []), quests)
		if about != "":
			return cue("about", about, quests)
		return {}
	return _strongest(found, quests)


static func _strongest(found: Array[Dictionary], quests: Object) -> Dictionary:
	for kind in KINDS:
		for f in found:
			if str(f["kind"]) == kind:
				return cue(kind, str(f["quest_id"]), quests)
	return {}


## What a list of effects does to quests: [{kind, quest_id}].
static func _effect_cues(effects: Variant, npc_id: String, quests: Object) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if typeof(effects) != TYPE_ARRAY:
		return out
	for e_v in effects:
		if typeof(e_v) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = e_v
		for key in e:
			var arg: Variant = e[key]
			match str(key):
				"start_quest":
					var q := str(arg[0]) if typeof(arg) == TYPE_ARRAY and not (arg as Array).is_empty() else str(arg)
					if not _known(q, quests):
						out.append({"kind": "start", "quest_id": q})
				"complete_quest":
					var q := str(arg[0]) if typeof(arg) == TYPE_ARRAY and not (arg as Array).is_empty() else str(arg)
					if not _done(q, quests):
						out.append({"kind": "turn_in", "quest_id": q})
				"quest_stage":
					if typeof(arg) == TYPE_ARRAY and (arg as Array).size() >= 2:
						var q := str(arg[0])
						if _done(q, quests):
							continue
						if not _known(q, quests):
							out.append({"kind": "start", "quest_id": q})
						elif _stage_ends(q, arg[1], quests):
							out.append({"kind": "turn_in", "quest_id": q})
						else:
							out.append({"kind": "advance", "quest_id": q})
				"complete_objective":
					if typeof(arg) == TYPE_ARRAY and (arg as Array).size() >= 2 and _active(str(arg[0]), quests):
						var q := str(arg[0])
						var i := _objective_index(q, arg[1], quests)
						out.append({"kind": "turn_in" if i >= 0 and _finishes(q, i, quests) else "advance", "quest_id": q})
				"quest_choice":
					if typeof(arg) == TYPE_ARRAY and (arg as Array).size() >= 1 and _active(str(arg[0]), quests):
						out.append({"kind": "advance", "quest_id": str(arg[0])})
				"take_item":
					var item := str(arg[0]) if typeof(arg) == TYPE_ARRAY and not (arg as Array).is_empty() else str(arg)
					for row in _open_objectives(quests, "deliver"):
						var o: Dictionary = row["objective"]
						if str(o.get("item", "")) == item and _matches(str(o.get("target", "")), npc_id):
							out.append({"kind": "turn_in" if _finishes(str(row["quest_id"]), int(row["index"]), quests) else "advance",
									"quest_id": str(row["quest_id"])})
	return out


## A line that is the topic an open `talk` objective with this person waits for.
static func _topic_cues(node_id: String, npc_id: String, quests: Object) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if npc_id == "":
		return out
	for row in _open_objectives(quests, "talk"):
		var o: Dictionary = row["objective"]
		if str(o.get("topic", "")) == node_id and _matches(str(o.get("target", "")), npc_id):
			var q := str(row["quest_id"])
			out.append({"kind": "turn_in" if _finishes(q, int(row["index"]), quests) else "advance", "quest_id": q})
	return out


## The quest an answer's conditions tie it to, while that quest is under way, or "".
static func _about(conds: Variant, quests: Object) -> String:
	if typeof(conds) != TYPE_ARRAY:
		return ""
	for c_v in conds:
		if typeof(c_v) != TYPE_DICTIONARY:
			continue
		for key in ["quest_at", "quest_active", "quest_min_stage", "quest_stage"]:
			if not (c_v as Dictionary).has(key):
				continue
			var arg: Variant = (c_v as Dictionary)[key]
			var q := str(arg[0]) if typeof(arg) == TYPE_ARRAY and not (arg as Array).is_empty() else str(arg)
			if _active(q, quests):
				return q
	return ""


# --- the quest log, read ---------------------------------------------------------------------------

## QuestLog's own reading of an objective's target against a person: "" and "any" are anyone,
## "tag:x" anyone whose def carries the tag.
static func _matches(target: String, id: String) -> bool:
	if target == "" or target == "any":
		return true
	if target.begins_with("tag:"):
		return (ContentDB.get_or_empty(id).get("tags", []) as Array).has(target.substr(4))
	return target == id


static func _known(q: String, quests: Object) -> bool:
	return quests != null and quests.has_method("is_known") and bool(quests.call("is_known", q))


static func _active(q: String, quests: Object) -> bool:
	return quests != null and quests.has_method("is_active") and bool(quests.call("is_active", q))


static func _done(q: String, quests: Object) -> bool:
	return quests != null and quests.has_method("is_completed") and bool(quests.call("is_completed", q))


## [{quest_id, stage, index, objective, done}] of every active quest's current stage, not done.
static func _open_objectives(quests: Object, type: String) -> Array:
	if quests == null or not quests.has_method("current_objectives"):
		return []
	return (quests.call("current_objectives", type) as Array).filter(func(r: Dictionary) -> bool: return not bool(r["done"]))


static func _objective_index(q: String, key: Variant, quests: Object) -> int:
	if typeof(key) == TYPE_INT or typeof(key) == TYPE_FLOAT:
		return int(key)
	for row in _open_objectives(quests, ""):
		if str(row["quest_id"]) != q:
			continue
		var o: Dictionary = row["objective"]
		var wanted := str(key)
		# QuestLog.complete_objective's own reading: its `key`, its target, or "type:target"
		if str(o.get("key", "")) == wanted or str(o.get("target", "")) == wanted \
				or "%s:%s" % [str(o.get("type", "")), str(o.get("target", ""))] == wanted:
			return int(row["index"])
	return -1


## Whether closing objective `index` of a quest's current stage would finish the quest: every other
## step the stage asks is done, and no stage after it asks anything.
static func _finishes(q: String, index: int, quests: Object) -> bool:
	if not _active(q, quests) or not quests.has_method("stage_of") or not quests.has_method("stages_of"):
		return false
	var at := int(quests.call("stage_of", q))
	if not _last_that_asks(q, at, quests):
		return false
	var stage: Dictionary = quests.call("stage_def", q, at)
	if bool(stage.get("manual_advance", false)):
		return false
	for row in quests.call("current_objectives", ""):
		var r: Dictionary = row
		if str(r["quest_id"]) != q or int(r["index"]) == index:
			continue
		if not bool(r["done"]) and not bool((r["objective"] as Dictionary).get("optional", false)):
			return false
	return true


## Whether moving a quest to `stage` puts it on its last stage that asks anything.
static func _stage_ends(q: String, stage: Variant, quests: Object) -> bool:
	if not quests.has_method("stage_index"):
		return false
	var i := int(quests.call("stage_index", q, stage))
	if i < 0:
		return false
	var s: Dictionary = quests.call("stage_def", q, i)
	return (s.get("objectives", []) as Array).is_empty() and bool(s.get("auto", false)) and _last_that_asks(q, i, quests)


## Whether no stage after `at` asks anything (the ones after are `auto` and empty, or none).
static func _last_that_asks(q: String, at: int, quests: Object) -> bool:
	var stages: Array = quests.call("stages_of", q)
	for i in range(at + 1, stages.size()):
		var s: Dictionary = stages[i]
		if not (s.get("objectives", []) as Array).is_empty() or not bool(s.get("auto", false)):
			return false
	return true


# --- a person's standing mark --------------------------------------------------------------------------

## What this person is to the player's quests now: {state, quest_id, name, tier} or {} (see the
## header). Kept for a moment (STATE_TTL_MS) so every head in a town can ask each frame.
static func npc_state(npc_id: String, quests: Object = null, ctx: SocialContext = null) -> Dictionary:
	if npc_id == "":
		return {}
	var now := Time.get_ticks_msec()
	var kept: Variant = _states.get(npc_id)
	if kept is Dictionary and now - int((kept as Dictionary)["at_ms"]) < STATE_TTL_MS:
		return (kept as Dictionary)["cue"]
	var found := state_now(npc_id, quests, ctx)
	_states[npc_id] = {"at_ms": now, "cue": found}
	return found


## Forgets every kept mark (a quest moved: the next look is fresh).
static func touch() -> void:
	_states.clear()


static func _mark(state: String, quest_id: String, quests: Object) -> Dictionary:
	var c := cue(state, quest_id, quests)
	c["state"] = state
	return c


## The same as `npc_state`, asked now.
static func state_now(npc_id: String, quests: Object = null, ctx: SocialContext = null) -> Dictionary:
	if quests == null:
		quests = Social.quests if Social != null else null
	if ctx == null and Social != null:
		ctx = Social.ctx
	if quests == null:
		return {}
	var advance := ""
	for type in ["talk", "deliver"]:
		for row in _open_objectives(quests, type):
			var o: Dictionary = row["objective"]
			if bool(o.get("optional", false)) or not _matches(str(o.get("target", "")), npc_id) \
					or str(o.get("target", "")) == "":
				continue
			var q := str(row["quest_id"])
			if type == "deliver" and ctx != null and ctx.has_inventory() and ctx.item_count(str(o.get("item", ""))) <= 0:
				continue
			if _finishes(q, int(row["index"]), quests):
				return _mark("turn_in", q, quests)
			if advance == "":
				advance = q
	if advance == "" and quests.has_method("unwritten_choices_for"):
		for offer in quests.call("unwritten_choices_for", npc_id):
			advance = str((offer as Dictionary).get("quest_id", ""))
			break
	if advance != "":
		return _mark("advance", advance, quests)
	var offer := _offer_of(npc_id, quests, ctx)
	if offer != "":
		return _mark("available", offer, quests)
	if quests.has_method("active_quests"):
		for e in quests.call("active_quests"):
			var d: Dictionary = e
			if str(d.get("giver", "")) == npc_id and str(d.get("layer", "")) != "radiant":
				return _mark("in_progress", str(d["id"]), quests)
	return {}


## A quest this person would give now: one they offer at their hub (QuestLog.giver_offers), or a
## `start_quest` in their own conversation on a line or an answer whose conditions hold now.
static func _offer_of(npc_id: String, quests: Object, ctx: SocialContext) -> String:
	if quests.has_method("giver_offers"):
		for offer in quests.call("giver_offers", npc_id):
			return str((offer as Dictionary).get("quest_id", ""))
	var dialogue := ContentDB.get_or_empty(str(ContentDB.get_or_empty(npc_id).get("dialogue", "")))
	var nodes: Variant = dialogue.get("nodes", {})
	if typeof(nodes) != TYPE_DICTIONARY or ctx == null:
		return ""
	var was_id := ctx.npc_id
	var was_def := ctx.npc
	ctx.npc_id = npc_id
	ctx.npc = ContentDB.get_or_empty(npc_id)
	var found := ""
	for node_id in nodes:
		var node: Dictionary = (nodes as Dictionary)[node_id]
		var here: Array = [[node.get("effects", []), node.get("conditions", [])]]
		for c in node.get("choices", []):
			if typeof(c) == TYPE_DICTIONARY:
				here.append([(c as Dictionary).get("effects", []), (c as Dictionary).get("conditions", [])])
		for pair in here:
			for f in _effect_cues(pair[0], npc_id, quests):
				if str(f["kind"]) != "start":
					continue
				var def := _def(str(f["quest_id"]), quests)
				if str(def.get("giver", "")) != npc_id and not def.is_empty() and str(def.get("giver", "")) != "":
					continue
				if Conditions.all_of(node.get("conditions", []), ctx) and Conditions.all_of(pair[1], ctx) \
						and QuestConditions.can_start(def, ctx, quests):
					found = str(f["quest_id"])
					break
			if found != "":
				break
		if found != "":
			break
	ctx.npc_id = was_id
	ctx.npc = was_def
	return found


## What the standing mark says, in words, for the nameplate: "New quest", "Turn in", "Quest".
static func state_word(state: String) -> String:
	match state:
		"turn_in":
			return "Turn in"
		"advance":
			return "Quest"
		"available":
			return "New quest"
		"in_progress":
			return "Under way"
	return ""


## The glyph over a head: "!" a quest to give, "?" a quest to go on with or hand in.
static func state_glyph(state: String) -> String:
	match state:
		"available":
			return "!"
		"turn_in", "advance", "in_progress":
			return "?"
	return ""
