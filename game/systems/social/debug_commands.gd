class_name SocialDebugCommands
extends RefCounted
## Debug console commands for the social systems, so writers and designers can drive dialogue,
## quests, standing and gossip by hand without a UI. Registered by Social on the first frame if
## the `Debug` autoload is present (it is optional; nothing here is needed to play).
##
##   talk <npc_id> [dialogue_id]   start a conversation and print the line and the choices
##   next                          advance past a line with no choices
##   say <index>                   take a choice
##   greet <npc_id>                print the greeting this NPC would give right now
##   gesture <gesture_id> [npc_id] make a gesture and print the answer
##   standing                      renown, Hearth/Hollow, tiers and title
##   deed <deed_id> [witnesses]    apply a deed with N anonymous witnesses (default 1)
##   rep <faction_id> [delta]      show or change reputation
##   join <faction_id>             join a faction
##   quests                        list active quests with their objectives
##   quest <quest_id> [stage]      start a quest, or move it to a stage
##   board <place_id> [count]      generate a job board's notices
##   rumours [place_id]            what a place is saying


static func register_all(social: Node, console: Object) -> void:
	console.register("talk", func(args: Array) -> String: return _talk(social, args), "talk <npc_id> [dialogue_id]")
	console.register("next", func(_args: Array) -> String: return _next(social), "next: advance the conversation")
	console.register("say", func(args: Array) -> String: return _say(social, args), "say <index>: take a choice")
	console.register("greet", func(args: Array) -> String: return _greet(social, args), "greet <npc_id>")
	console.register("gesture", func(args: Array) -> String: return _gesture(social, args), "gesture <gesture_id> [npc_id]")
	console.register("standing", func(_args: Array) -> String: return _standing(social), "standing: renown and Hearth/Hollow")
	console.register("deed", func(args: Array) -> String: return _deed(social, args), "deed <deed_id> [witnesses]")
	console.register("rep", func(args: Array) -> String: return _rep(social, args), "rep <faction_id> [delta]")
	console.register("join", func(args: Array) -> String: return _join(social, args), "join <faction_id>")
	console.register("quests", func(_args: Array) -> String: return _quests(social), "quests: the active journal")
	console.register("quest", func(args: Array) -> String: return _quest(social, args), "quest <quest_id> [stage]")
	console.register("board", func(args: Array) -> String: return _board(social, args), "board <place_id> [count]")
	console.register("rumours", func(args: Array) -> String: return _rumours(social, args), "rumours [place_id]")


static func _talk(social: Node, args: Array) -> String:
	if args.is_empty():
		return "talk <npc_id> [dialogue_id]"
	var npc_id := _id(str(args[0]), "npc")
	var dialogue_id: String = _id(str(args[1]), "dialogue") if args.size() > 1 else ""
	var runner: Node = social.talk(npc_id, dialogue_id)
	return _state(runner)


static func _next(social: Node) -> String:
	social.dialogue.advance()
	return _state(social.dialogue)


static func _say(social: Node, args: Array) -> String:
	if args.is_empty():
		return "say <index>"
	social.dialogue.choose(int(args[0]))
	return _state(social.dialogue)


static func _state(runner: Node) -> String:
	if not runner.is_running():
		return "(the conversation is over)"
	var out: Array[String] = []
	for c in runner.current_choices.size():
		out.append("  [%d] %s" % [c, str(runner.current_choices[c].get("text", ""))])
	if out.is_empty():
		return "at node '%s' (type `next`)" % runner.current_node_id
	return "at node '%s':\n%s" % [runner.current_node_id, "\n".join(out)]


static func _greet(social: Node, args: Array) -> String:
	if args.is_empty():
		return "greet <npc_id>"
	var npc_id := _id(str(args[0]), "npc")
	var row: Dictionary = Greetings.select_row(npc_id, social.ctx)
	return "%s\n  (row: %s)" % [social.greet(npc_id), str(row.get("id", "?"))]


static func _gesture(social: Node, args: Array) -> String:
	if args.is_empty():
		return "gesture <gesture_id> [npc_id]"
	var gesture_id := _id(str(args[0]), "gesture")
	var npc_id: String = _id(str(args[1]), "npc") if args.size() > 1 else social.dialogue.npc_id
	var r: Dictionary = social.do_gesture(gesture_id, npc_id)
	if r.is_empty():
		return "no such gesture"
	return "disposition %+d (now %d): \"%s\"" % [int(r["delta"]), int(r["disposition"]), str(r["line"])]


static func _standing(social: Node) -> String:
	var p: Dictionary = social.reaction_profile()
	var lines: Array[String] = [
		"renown %d (tier %d, %s)" % [int(p["renown"]), int(p["renown_tier"]), str(p["renown_title"]) if str(p["renown_title"]) != "" else "no title yet"],
		"hearth/hollow %d (tier %d, %s)" % [int(p["morality"]), int(p["morality_tier"]), str(p["morality_title"]) if str(p["morality_title"]) != "" else "unremarkable"],
		"at %s" % (social.place_id() if social.place_id() != "" else "nowhere in particular"),
	]
	for id in social.factions.members():
		lines.append("%s: %s (%d)" % [id, str(social.factions.rank_name(id)), int(social.factions.reputation(id))])
	return "\n".join(lines)


static func _deed(social: Node, args: Array) -> String:
	if args.is_empty():
		return "deed <deed_id> [witnesses]"
	var witnesses: int = int(args[1]) if args.size() > 1 else 1
	var r: Dictionary = social.apply_deed(str(args[0]), witnesses)
	if r.is_empty():
		return "no such deed (see core:table/deeds)"
	return "hearth %+d, renown %+d, %d witnesses, rumour %s at %s" % [int(r["hearth"]), int(r["renown"]), int(r["witnesses"]), str(r["rumour"]) if str(r["rumour"]) != "" else "none", str(r["place"]) if str(r["place"]) != "" else "nowhere"]


static func _rep(social: Node, args: Array) -> String:
	if args.is_empty():
		return "rep <faction_id> [delta]"
	var faction := _id(str(args[0]), "faction")
	if args.size() > 1:
		social.factions.add_reputation(faction, int(args[1]), "debug")
	return "%s: %d, rank %s%s" % [faction, int(social.factions.reputation(faction)),
		str(social.factions.rank_name(faction)) if str(social.factions.rank_name(faction)) != "" else "none",
		" (member)" if bool(social.factions.is_member(faction)) else ""]


static func _join(social: Node, args: Array) -> String:
	if args.is_empty():
		return "join <faction_id>"
	var faction := _id(str(args[0]), "faction")
	if not social.factions.join(faction):
		return "they will not have you"
	return "joined %s as %s" % [faction, str(social.factions.rank_name(faction))]


static func _quests(social: Node) -> String:
	var active: Array = social.quests.active_quests()
	if active.is_empty():
		return "(nothing in the journal)"
	var out: Array[String] = []
	for q in active:
		out.append("%s [%s] stage %s" % [str(q["name"]), str(q["layer"]), str(q["stage_id"])])
		for o in q["objectives"]:
			out.append("   %s %s (%d/%d)" % ["x" if bool(o["done"]) else "-", str(o["text"]), int(o["count"]), int(o["needed"])])
	return "\n".join(out)


static func _quest(social: Node, args: Array) -> String:
	if args.is_empty():
		return "quest <quest_id> [stage]"
	var quest_id := _id(str(args[0]), "quest")
	if args.size() > 1:
		var stage: Variant = int(args[1]) if str(args[1]).is_valid_int() else str(args[1])
		social.quests.set_stage(quest_id, stage)
	elif not social.quests.start(quest_id):
		return "could not start %s (unknown, already taken, or its requirements are unmet)" % quest_id
	return "%s: stage %s" % [quest_id, str(social.quests.stage_id_of(quest_id))]


static func _board(social: Node, args: Array) -> String:
	if args.is_empty():
		return "board <place_id> [count]"
	var place := _id(str(args[0]), "place")
	var count: int = int(args[1]) if args.size() > 1 else 3
	var jobs: Array = social.board_jobs(place, "", count)
	if jobs.is_empty():
		return "the board is bare (no content for those targets in this region yet)"
	var out: Array[String] = []
	for j in jobs:
		out.append("%s — %s (%d marks)\n   %s" % [str(j["name"]), str(j["id"]), int((j["rewards"] as Dictionary).get("marks", 0)), str(j.get("board_line", ""))])
	return "\n".join(out)


static func _rumours(social: Node, args: Array) -> String:
	var place: String = _id(str(args[0]), "place") if not args.is_empty() else social.place_id()
	if place == "":
		return "nowhere in particular"
	var pool: Array = social.gossip.pool_of(place, {"player": social.ctx.player_name(), "title": social.ctx.title()})
	if pool.is_empty():
		return "%s has nothing to say about you" % place
	var out: Array[String] = []
	for r in pool:
		out.append("%.2f  %s" % [float(r["heat"]), str(r["text"])])
	return "\n".join(out)


## Lets the console take "hesk" for "core:npc/hesk" and "core:npc/hesk" for itself.
static func _id(value: String, type: String) -> String:
	if Ids.is_valid(value):
		return value
	var guess := "core:%s/%s" % [type, value]
	if ContentDB.has(guess):
		return guess
	for id in ContentDB.ids_of(type):
		if Ids.name_of(id).ends_with(value) or Ids.name_of(id).contains(value):
			return id
	return guess
