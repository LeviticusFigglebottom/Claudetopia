class_name DialogueSteer
extends RefCounted
## Steers a conversation through the game's own dialogue runner the way a player picks lines.
##
## The quest walker (tests/quests/quest_walker.gd) says where it wants a conversation to go: to a
## line (a `talk` objective's `topic`), to a choice or line whose effects do something (start a
## quest, put a decision, hand something over, move a stage on), or through whatever the lines a
## quest is waiting on are, and then away. This drives `Social.dialogue` a line at a time: it
## presses on through lines with nothing to ask, and where there are choices it takes the one
## that gets closest to the goal, looking ahead through the graph the author wrote. The choices it
## weighs are the ones the runner actually shows, so a line whose conditions do not hold, a `once`
## already taken, and the choices the runner puts itself (a giver's work, a decision nobody wrote a
## button for) are exactly what a player would see.
##
## A goal is a Dictionary:
##   {"node": id}                 reach that line (entering it is what a topic waits for)
##   {"effect": {key: arg}}       take a choice, or enter a line, whose effects include it; `arg`
##                                of null matches any argument, an Array matches element by element
##                                (null elements match anything)
##   {"quest": quest_id, "flags": [..]}
##                                the lines a quest is waiting on: choices whose conditions or
##                                effects name the quest, or set one of `flags`, each taken once
## and any of them with "leave": false to stay in the conversation after the goal (the caller stops).

const MAX_STEPS := 90
const LOOK_DEPTH := 14

## Quest-keyed effects and conditions: what makes a line "about" a quest.
const QUEST_EFFECTS := ["start_quest", "quest_stage", "quest_choice", "complete_objective", "complete_quest", "fail_quest"]
const QUEST_CONDITIONS := ["quest_at", "quest_active", "quest_done", "quest_not_done", "quest_min_stage", "quest_outcome"]


## Runs a conversation with `npc_id` toward `goal`. Returns {ok, reached, lines: [what was said
## and chosen], why}. `ok` is whether the goal was met; a `quest` goal is met by having had the
## conversation at all.
static func drive(npc_id: String, goal: Dictionary, place := "") -> Dictionary:
	var runner: Node = Social.talk(npc_id, "", place)
	return steer(runner, goal, npc_id)


## Steers a conversation already running (a light to decide at, a scripted scene) toward `goal`.
static func steer(runner: Node, goal: Dictionary, npc_id := "") -> Dictionary:
	var out := {"ok": false, "reached": false, "lines": [], "why": ""}
	var taken: Dictionary = {}
	var steps := 0
	var after_goal := 0
	var leave := bool(goal.get("leave", true))
	var exploring := goal.has("quest")
	while runner.is_running() and steps < MAX_STEPS:
		steps += 1
		var node_id := str(runner.current_node_id)
		if not bool(out["reached"]) and node_id != "" and _node_meets(runner, node_id, goal):
			out["reached"] = true
			(out["lines"] as Array).append("reached '%s'" % node_id)
			if not leave:
				break
		var choices: Array = runner.current_choices
		if choices.is_empty():
			runner.advance()
			continue
		if bool(out["reached"]):
			# the goal is met: whatever the lines after it do has been done by now, and a player
			# walks away at the next question
			after_goal += 1
			break
		var pick := -1
		# a choice that does it, shown now
		if goal.has("effect"):
			for i in choices.size():
				if _effects_match((choices[i] as Dictionary).get("effects", []), goal["effect"]):
					pick = i
					break
		if pick >= 0:
			(out["lines"] as Array).append("chose \"%s\"" % _short(str((choices[pick] as Dictionary).get("text", ""))))
			out["reached"] = true
			runner.choose(pick)
			if not leave:
				break
			continue
		if exploring:
			pick = _relevant_choice(runner, choices, goal, taken)
			if pick < 0:
				# nothing about the quest is shown here: go on toward where something is
				pick = _closest_choice(runner, choices, goal, taken)
		else:
			pick = _closest_choice(runner, choices, goal, taken)
		if pick < 0:
			break
		var c: Dictionary = choices[pick]
		taken["%s|%s" % [node_id, str(c.get("text", ""))]] = true
		(out["lines"] as Array).append("chose \"%s\"" % _short(str(c.get("text", ""))))
		runner.choose(pick)
	if exploring:
		out["reached"] = true
	out["ok"] = bool(out["reached"])
	if not bool(out["ok"]):
		out["why"] = "no way through %s's lines to %s" % [Ids.name_of(npc_id) if npc_id != "" else "the", _goal_text(goal)]
	if runner.is_running() and leave:
		runner.stop()
	return out


## Whether entering this line meets the goal.
static func _node_meets(runner: Node, node_id: String, goal: Dictionary) -> bool:
	if goal.has("node") and str(goal["node"]) == node_id:
		return true
	if goal.has("effect"):
		var node: Dictionary = _nodes(runner).get(node_id, {})
		if _effects_match(node.get("effects", []), goal["effect"]):
			return true
	return false


static func _nodes(runner: Node) -> Dictionary:
	var def: Variant = runner.get("_def")
	if typeof(def) != TYPE_DICTIONARY:
		return {}
	var nodes: Variant = (def as Dictionary).get("nodes", {})
	return nodes if typeof(nodes) == TYPE_DICTIONARY else {}


## Does an effects list include the wanted effect? `want` is {key: arg}.
static func _effects_match(effects: Variant, want: Variant) -> bool:
	if typeof(want) != TYPE_DICTIONARY or typeof(effects) != TYPE_ARRAY:
		return false
	for e in effects as Array:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		for key in (want as Dictionary).keys():
			if not (e as Dictionary).has(key):
				continue
			if _arg_matches((e as Dictionary)[key], (want as Dictionary)[key]):
				return true
	return false


static func _arg_matches(have: Variant, want: Variant) -> bool:
	if want == null:
		return true
	if typeof(want) == TYPE_ARRAY:
		if typeof(have) != TYPE_ARRAY:
			# {"give_item": "core:item/x"} against ["core:item/x", null]
			return (want as Array).size() > 0 and str(have) == str((want as Array)[0])
		for i in (want as Array).size():
			if (want as Array)[i] == null:
				continue
			if i >= (have as Array).size() or str((have as Array)[i]) != str((want as Array)[i]):
				return false
		return true
	return str(have) == str(want)


## The shown choice with the shortest way to the goal through the written graph; -1 when none
## leads there.
static func _closest_choice(runner: Node, choices: Array, goal: Dictionary, taken: Dictionary) -> int:
	var nodes := _nodes(runner)
	var here := str(runner.current_node_id)
	var best := -1
	var best_len := 1 << 20
	for i in choices.size():
		var c: Dictionary = choices[i]
		# what the runner puts itself (gossip, the shop, somebody's work, a decision) is taken only
		# when it is the goal, which the caller has already looked for
		if bool(c.get("talk", false)) or int(c.get("source_index", 0)) < 0:
			continue
		if taken.has("%s|%s" % [here, str(c.get("text", ""))]):
			continue
		# on the way to something else, no decision is made, nothing is ended, and nobody else's
		# work is taken on
		if _decides(c.get("effects", [])) or _starts_other(c.get("effects", []), goal):
			continue
		var sets := _flags_set_by(c.get("effects", []))
		var next := str(c.get("next", ""))
		if next == "":
			next = str((nodes.get(here, {}) as Dictionary).get("next", ""))
		if next == "" or next == "end":
			continue
		if next == here:
			# a choice that comes back here is a way on only when it changes what a line ahead tests
			var changes := false
			for f in sets:
				if not Social.ctx.has_flag(str(f)):
					changes = true
			if not changes:
				continue
		var n := _distance(nodes, next, goal, sets, taken)
		if n >= 0 and n < best_len:
			best_len = n
			best = i
	return best


## How many lines from `from` to the goal, looking only through the author's graph: -1 when it
## is not there within LOOK_DEPTH.
static func _distance(nodes: Dictionary, from: String, goal: Dictionary, flags: Dictionary, taken: Dictionary = {}) -> int:
	var seen: Dictionary = {}
	var frontier: Array = [[from, 0, flags]]
	while not frontier.is_empty():
		var item: Array = frontier.pop_front()
		var id := str(item[0])
		var depth := int(item[1])
		var set_flags: Dictionary = item[2]
		if id == "" or id == "end" or seen.has(id) or depth > LOOK_DEPTH:
			continue
		seen[id] = true
		var node: Dictionary = nodes.get(id, {})
		if node.is_empty():
			continue
		if not _could_hold(node.get("conditions", []), set_flags):
			var alt := str(node.get("else", ""))
			if alt != "":
				frontier.append([alt, depth, set_flags])
			continue
		if goal.has("node") and str(goal["node"]) == id:
			return depth
		if goal.has("effect") and _effects_match(node.get("effects", []), goal["effect"]):
			return depth
		var now := set_flags.duplicate()
		now.merge(_flags_set_by(node.get("effects", [])), true)
		var choices: Variant = node.get("choices", [])
		if typeof(choices) == TYPE_ARRAY and not (choices as Array).is_empty():
			for c_v in choices as Array:
				if typeof(c_v) != TYPE_DICTIONARY:
					continue
				var c: Dictionary = c_v
				if not _could_hold(c.get("conditions", []), now):
					continue
				if goal.has("effect") and _effects_match(c.get("effects", []), goal["effect"]):
					return depth + 1
				if goal.has("quest") and not taken.has("%s|%s" % [id, str(c.get("text", ""))]) \
						and not _decides(c.get("effects", [])) and not _names_other_quest(c.get("effects", []), str(goal["quest"])) \
						and _about(c, str(goal["quest"]), goal.get("flags", [])):
					return depth + 1
				if _decides(c.get("effects", [])) or _starts_other(c.get("effects", []), goal):
					continue
				var next := str(c.get("next", node.get("next", "")))
				var then := now.duplicate()
				then.merge(_flags_set_by(c.get("effects", [])), true)
				frontier.append([next, depth + 1, then])
		else:
			frontier.append([str(node.get("next", "")), depth + 1, now])
	return -1


## Conditions that hold now, or would once the flags set on the way here are set.
static func _could_hold(conds: Variant, set_flags: Dictionary) -> bool:
	if typeof(conds) != TYPE_ARRAY:
		return true
	for c in conds as Array:
		if typeof(c) == TYPE_DICTIONARY and (c as Dictionary).has("flag") and set_flags.has(str((c as Dictionary)["flag"])):
			continue
		if not Conditions.all_of([c], Social.ctx):
			return false
	return true


static func _flags_set_by(effects: Variant) -> Dictionary:
	var out: Dictionary = {}
	if typeof(effects) != TYPE_ARRAY:
		return out
	for e in effects as Array:
		if typeof(e) == TYPE_DICTIONARY and (e as Dictionary).has("set_flag"):
			var arg: Variant = (e as Dictionary)["set_flag"]
			out[str(arg[0]) if typeof(arg) == TYPE_ARRAY else str(arg)] = true
	return out


## A shown choice about the quest the conversation is for, not taken yet; -1 when none is left.
## Nothing that starts somebody else's work, makes a decision for another quest, opens the shop or
## asks for gossip: those are a player's own business, and the walker does them on purpose.
static func _relevant_choice(runner: Node, choices: Array, goal: Dictionary, taken: Dictionary) -> int:
	var quest := str(goal.get("quest", ""))
	var flags: Array = goal.get("flags", [])
	var here := str(runner.current_node_id)
	for i in choices.size():
		var c: Dictionary = choices[i]
		if bool(c.get("talk", false)) or taken.has("%s|%s" % [here, str(c.get("text", ""))]):
			continue
		if _names_other_quest(c.get("effects", []), quest) or _decides(c.get("effects", [])):
			continue
		if _about(c, quest, flags):
			return i
	return -1


## A quest started that is not the one the goal is about.
static func _starts_other(effects: Variant, goal: Dictionary) -> bool:
	if typeof(effects) != TYPE_ARRAY:
		return false
	var own := str(goal.get("quest", ""))
	if own == "" and goal.has("effect") and typeof(goal["effect"]) == TYPE_DICTIONARY:
		for key in (goal["effect"] as Dictionary).keys():
			var arg: Variant = (goal["effect"] as Dictionary)[key]
			own = str((arg as Array)[0]) if typeof(arg) == TYPE_ARRAY and (arg as Array).size() > 0 else str(arg)
	for e in effects as Array:
		if typeof(e) == TYPE_DICTIONARY and (e as Dictionary).has("start_quest") and str((e as Dictionary)["start_quest"]) != own:
			return true
	return false


## A decision, or an ending, which the walker makes on purpose and never on the way past.
static func _decides(effects: Variant) -> bool:
	if typeof(effects) != TYPE_ARRAY:
		return false
	for e in effects as Array:
		if typeof(e) == TYPE_DICTIONARY:
			for key in ["quest_choice", "fail_quest", "complete_quest", "bounty"]:
				if (e as Dictionary).has(key):
					return true
	return false


static func _about(c: Dictionary, quest: String, flags: Array) -> bool:
	for cond in _flatten(c.get("conditions", [])):
		for key in QUEST_CONDITIONS:
			if cond.has(key) and _mentions(cond[key], quest):
				return true
	var effects: Variant = c.get("effects", [])
	if typeof(effects) == TYPE_ARRAY:
		for e in effects as Array:
			if typeof(e) != TYPE_DICTIONARY:
				continue
			for key in QUEST_EFFECTS:
				if (e as Dictionary).has(key) and _mentions((e as Dictionary)[key], quest):
					return true
			if (e as Dictionary).has("set_flag"):
				var arg: Variant = (e as Dictionary)["set_flag"]
				if flags.has(str(arg[0]) if typeof(arg) == TYPE_ARRAY else str(arg)):
					return true
	return false


static func _names_other_quest(effects: Variant, quest: String) -> bool:
	if typeof(effects) != TYPE_ARRAY:
		return false
	for e in effects as Array:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		for key in QUEST_EFFECTS:
			if (e as Dictionary).has(key) and not _mentions((e as Dictionary)[key], quest):
				return true
	return false


static func _mentions(arg: Variant, quest: String) -> bool:
	if typeof(arg) == TYPE_ARRAY:
		return (arg as Array).size() > 0 and str((arg as Array)[0]) == quest
	return str(arg) == quest


static func _flatten(conds: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if typeof(conds) == TYPE_DICTIONARY:
		conds = [conds]
	if typeof(conds) != TYPE_ARRAY:
		return out
	for c in conds as Array:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		out.append(c)
		for key in ["not", "any", "all"]:
			if (c as Dictionary).has(key):
				out.append_array(_flatten((c as Dictionary)[key]))
	return out


static func _goal_text(goal: Dictionary) -> String:
	if goal.has("node"):
		return "the line '%s'" % str(goal["node"])
	if goal.has("effect"):
		return JSON.stringify(goal["effect"])
	return "the lines of %s" % Ids.name_of(str(goal.get("quest", "")))


static func _short(text: String) -> String:
	return text if text.length() <= 60 else text.substr(0, 57) + "..."


# --- the pack, read for routes ---------------------------------------------------------------------

## Who can say what: [{npc, dialogue, node, choice (index or -1), effects, conditions}] for every
## line or choice in the pack whose effects include `want` ({key: arg}, as in a goal's `effect`).
static func speakers_of(want: Dictionary) -> Array[Dictionary]:
	var owner: Dictionary = {}
	for npc in ContentDB.all("npc"):
		var d := str((npc as Dictionary).get("dialogue", ""))
		if d != "":
			owner[d] = str((npc as Dictionary).get("id", ""))
	var out: Array[Dictionary] = []
	for def_v in ContentDB.all("dialogue"):
		var def: Dictionary = def_v
		var npc := str(owner.get(str(def.get("id", "")), ""))
		if npc == "":
			continue
		var nodes: Variant = def.get("nodes", {})
		if typeof(nodes) != TYPE_DICTIONARY:
			continue
		for node_id in (nodes as Dictionary).keys():
			var node: Dictionary = (nodes as Dictionary)[node_id]
			if _effects_match(node.get("effects", []), want):
				out.append({"npc": npc, "dialogue": str(def["id"]), "node": str(node_id), "choice": -1,
						"conditions": node.get("conditions", [])})
			var choices: Variant = node.get("choices", [])
			if typeof(choices) != TYPE_ARRAY:
				continue
			for i in (choices as Array).size():
				var c: Variant = (choices as Array)[i]
				if typeof(c) == TYPE_DICTIONARY and _effects_match((c as Dictionary).get("effects", []), want):
					out.append({"npc": npc, "dialogue": str(def["id"]), "node": str(node_id), "choice": i,
							"conditions": (c as Dictionary).get("conditions", [])})
	return out
