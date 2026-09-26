extends TestCase
## Content checks for everything the writers author against this stream: every dialogue graph
## links up and is reachable, every condition and effect is one the evaluator implements, every
## quest's stages close, and every journal line is written rather than a template. These run over
## the whole pack, so a new quest or conversation is checked the moment it lands.

const OBJECTIVE_TYPES := ["talk", "reach", "kill", "collect", "deliver", "escort", "choice", "use_item", "rest_at", "read_book", "act"]
## Keys inside a condition or effect object that are arguments, not vocabulary.
const CONDITION_CONTAINERS := ["conditions", "requires", "hidden_until", "fails_if"]
const EFFECT_CONTAINERS := ["effects", "on_enter", "on_complete"]


# --- dialogue graphs --------------------------------------------------------------------------

func test_every_dialogue_has_a_start_node() -> void:
	for def in ContentDB.all("dialogue"):
		var nodes: Dictionary = def.get("nodes", {})
		assert_gt(nodes.size(), 0, "%s has no nodes" % def["id"])
		var start := str(def.get("start", "start"))
		assert_true(nodes.has(start), "%s: start node '%s' is missing" % [def["id"], start])


func test_every_link_points_somewhere_real() -> void:
	for def in ContentDB.all("dialogue"):
		var nodes: Dictionary = def.get("nodes", {})
		for node_id in nodes:
			var node: Dictionary = nodes[node_id]
			for target in _targets_of(node):
				var to := str(target["to"])
				if to == "" or to == "end":
					continue
				assert_true(nodes.has(to), "%s.%s %s points at missing node '%s'" % [def["id"], node_id, str(target["what"]), to])


func test_every_node_can_be_reached() -> void:
	for def in ContentDB.all("dialogue"):
		var nodes: Dictionary = def.get("nodes", {})
		var start := str(def.get("start", "start"))
		if not nodes.has(start):
			continue
		var seen: Dictionary = {start: true}
		var stack: Array[String] = [start]
		while not stack.is_empty():
			var current: String = stack.pop_back()
			for target in _targets_of(nodes.get(current, {})):
				var to := str(target["to"])
				if nodes.has(to) and not seen.has(to):
					seen[to] = true
					stack.append(to)
		for node_id in nodes:
			assert_true(seen.has(node_id), "%s.%s cannot be reached from '%s'" % [def["id"], node_id, start])


func test_every_node_says_or_asks_something() -> void:
	for def in ContentDB.all("dialogue"):
		for node_id in def.get("nodes", {}):
			var node: Dictionary = def["nodes"][node_id]
			var has_text := str(node.get("text", "")) != ""
			var has_choices: bool = not (node.get("choices", []) as Array).is_empty()
			assert_true(has_text or has_choices, "%s.%s is empty" % [def["id"], node_id])


func test_npc_dialogue_links_both_ways() -> void:
	for npc in ContentDB.all("npc"):
		var dialogue := str(npc.get("dialogue", ""))
		if dialogue == "":
			continue
		assert_true(ContentDB.has(dialogue), "%s points at missing dialogue %s" % [npc["id"], dialogue])
	for def in ContentDB.all("dialogue"):
		var npc := str(def.get("npc", ""))
		if npc != "":
			assert_true(ContentDB.has(npc), "%s names missing npc %s" % [def["id"], npc])


# --- the vocabulary is binding -------------------------------------------------------------------

func test_every_authored_condition_is_implemented() -> void:
	var unknown: Dictionary = {}
	for type in ["dialogue", "quest"]:
		for def in ContentDB.all(type):
			for key in _keys_in(def, CONDITION_CONTAINERS):
				if not Conditions.KNOWN.has(key):
					unknown[key] = str(def["id"])
	assert_empty(unknown, "conditions used in content that the evaluator does not implement: %s" % str(unknown))


func test_every_authored_effect_is_implemented() -> void:
	var unknown: Dictionary = {}
	for type in ["dialogue", "quest"]:
		for def in ContentDB.all(type):
			for key in _keys_in(def, EFFECT_CONTAINERS):
				if not Effects.KNOWN.has(key):
					unknown[key] = str(def["id"])
	assert_empty(unknown, "effects used in content that the applier does not implement: %s" % str(unknown))


# --- quests ---------------------------------------------------------------------------------------

func test_every_quest_stage_is_shaped_right() -> void:
	for def in _authored_quests():
		var stages: Array = def.get("stages", [])
		assert_gt(stages.size(), 0, "%s has no stages" % def["id"])
		var ids: Dictionary = {}
		for i in stages.size():
			var stage: Dictionary = stages[i]
			var sid := str(stage.get("id", ""))
			assert_ne(sid, "", "%s: stage %d has no id" % [def["id"], i])
			assert_false(ids.has(sid), "%s: two stages called '%s'" % [def["id"], sid])
			ids[sid] = true
			for o in stage.get("objectives", []):
				var type := str((o as Dictionary).get("type", ""))
				assert_true(OBJECTIVE_TYPES.has(type), "%s.%s: unknown objective type '%s'" % [def["id"], sid, type])


func test_every_quest_can_close() -> void:
	for def in _authored_quests():
		var stages: Array = def.get("stages", [])
		var last: Dictionary = stages[stages.size() - 1]
		var closes: bool = not (last.get("objectives", []) as Array).is_empty() or bool(last.get("auto", false))
		assert_true(closes, "%s ends on a stage with nothing to do and no `auto`, so it can never finish" % def["id"])


func test_every_journal_line_is_written() -> void:
	for def in _authored_quests():
		for stage in def.get("stages", []):
			var journal := str((stage as Dictionary).get("journal", ""))
			assert_ne(journal, "", "%s.%s has no journal line" % [def["id"], str((stage as Dictionary).get("id", "?"))])
			assert_false(journal.contains("{"), "%s.%s journal still has a token: %s" % [def["id"], str((stage as Dictionary).get("id", "?")), journal])


func test_every_objective_target_exists() -> void:
	for def in _authored_quests():
		for stage in def.get("stages", []):
			for o in (stage as Dictionary).get("objectives", []):
				for key in ["target", "place", "item"]:
					var value := str((o as Dictionary).get(key, ""))
					if Ids.looks_like_id(value):
						assert_true(ContentDB.has(value), "%s: objective %s '%s' does not exist" % [def["id"], key, value])


func test_markers_name_real_places() -> void:
	for def in _authored_quests():
		for stage in def.get("stages", []):
			var marker: Variant = (stage as Dictionary).get("marker")
			if typeof(marker) != TYPE_DICTIONARY:
				continue
			var place := str((marker as Dictionary).get("place_id", ""))
			if place != "":
				assert_true(ContentDB.has(place), "%s marks missing place %s" % [def["id"], place])
			assert_gt(float((marker as Dictionary).get("radius", 0.0)), 0.0, "%s has a marker with no radius" % def["id"])


func test_quest_givers_and_factions_exist() -> void:
	for def in _authored_quests():
		for key in ["giver", "faction", "region"]:
			var value := str(def.get(key, ""))
			if value != "":
				assert_true(ContentDB.has(value), "%s: %s '%s' does not exist" % [def["id"], key, value])


func test_every_authored_quest_starts_and_walks_its_stages() -> void:
	# Not a simulation of play: it proves each stage can be entered, its effects applied and its
	# journal recorded without a content problem, which is what a quest is made of.
	var log_node: Node = Social.quests
	var bag := SocialFakes.FakeInventory.new()
	Social.bind("inventory", bag)
	# Opening a line's gate finishes the quests before it, and a finished quest pays its
	# rewards, several of which teach a saying. An effect with nowhere to land is a content
	# problem, and it would be this test's own doing.
	Social.bind("sayings", SocialFakes.Sayings.new())
	var problems_before: int = Social.ctx.problems.size()
	for def in _authored_quests():
		log_node.reset_for_new_game()
		Social.standing.reset_for_new_game()
		Social.factions.reset_for_new_game()
		var quest_id := str(def["id"])
		open_the_gate(def)
		assert_true(log_node.start(quest_id), "%s cannot be started, and its own `requires` do not say why" % quest_id)
		for stage in def.get("stages", []):
			var sid := str((stage as Dictionary).get("id", ""))
			if not log_node.is_active(quest_id):
				break
			log_node.set_stage(quest_id, sid)
			var entry: Dictionary = log_node.entry(quest_id)
			for o in entry["objectives"]:
				assert_ne(str((o as Dictionary)["text"]), "", "%s.%s has an objective with no text" % [quest_id, sid])
				assert_false(str((o as Dictionary)["text"]).contains("{"), "%s.%s objective text has a token" % [quest_id, sid])
	log_node.reset_for_new_game()
	Social.standing.reset_for_new_game()
	Social.factions.reset_for_new_game()
	Social.bind("inventory", null)
	Social.bind("sayings", null)
	Social.refresh_providers()
	assert_eq(Social.ctx.problems.size(), problems_before, "walking the authored quests raised content problems: %s" % str(Social.ctx.problems.slice(problems_before)))


## Makes a quest's own `requires` true, so that a quest which waits for the one before it in a
## faction line can still be walked here. Only the conditions a quest may state as a gate are
## honoured; anything else is left alone, and the start below fails and says so.
func open_the_gate(def: Dictionary) -> void:
	for cond_v in def.get("requires", []):
		if typeof(cond_v) != TYPE_DICTIONARY:
			continue
		var cond: Dictionary = cond_v
		if cond.has("quest_done"):
			# A line's third quest waits on its second, which waits on its first.
			var earlier := str(cond["quest_done"])
			if not Social.quests.is_completed(earlier):
				open_the_gate(ContentDB.get_or_empty(earlier))
				if Social.quests.start(earlier):
					Social.quests.complete(earlier)
		if cond.has("rep_min"):
			var pair: Array = cond["rep_min"]
			Social.factions.set_reputation(str(pair[0]), int(pair[1]))
		if cond.has("faction_rank_min") or cond.has("member_of"):
			var faction: Variant = cond.get("member_of", (cond.get("faction_rank_min", ["", 0]) as Array)[0])
			Social.factions.join(str(faction))
		if cond.has("flag"):
			GameState.set_flag(str(cond["flag"]))
		if cond.has("renown_min"):
			Social.standing.add_renown(int(cond["renown_min"]), "test")


# --- helpers ------------------------------------------------------------------------------------

func _authored_quests() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for def in ContentDB.all("quest"):
		if typeof(def.get("template")) == TYPE_DICTIONARY:
			continue        # a radiant template is a shape, not a quest
		out.append(def)
	return out


func _targets_of(node: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if node.has("next"):
		out.append({"what": "next", "to": str(node["next"])})
	if node.has("else"):
		out.append({"what": "else", "to": str(node["else"])})
	var choices: Variant = node.get("choices", [])
	if typeof(choices) == TYPE_ARRAY:
		for i in (choices as Array).size():
			var c: Variant = (choices as Array)[i]
			if typeof(c) == TYPE_DICTIONARY and (c as Dictionary).has("next"):
				out.append({"what": "choice %d" % i, "to": str((c as Dictionary)["next"])})
	return out


## Every key used inside the named condition/effect containers, anywhere in a definition.
func _keys_in(value: Variant, containers: Array) -> Array[String]:
	var out: Array[String] = []
	_collect(value, containers, out)
	return out


func _collect(value: Variant, containers: Array, out: Array[String]) -> void:
	match typeof(value):
		TYPE_DICTIONARY:
			for key in (value as Dictionary):
				var child: Variant = (value as Dictionary)[key]
				if containers.has(str(key)):
					_collect_entries(child, out)
				elif str(key) == "effects_by_option" and containers.has("effects") and typeof(child) == TYPE_DICTIONARY:
					for option in (child as Dictionary):
						_collect_entries((child as Dictionary)[option], out)
				else:
					_collect(child, containers, out)
		TYPE_ARRAY:
			for v in value:
				_collect(v, containers, out)
		_:
			pass


func _collect_entries(list: Variant, out: Array[String]) -> void:
	var entries: Array = list if typeof(list) == TYPE_ARRAY else [list]
	for e in entries:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		for key in (e as Dictionary):
			if not out.has(str(key)):
				out.append(str(key))
		# `not`, `any` and `all` carry nested conditions.
		for key in ["not", "any", "all"]:
			if (e as Dictionary).has(key):
				_collect_entries((e as Dictionary)[key], out)
