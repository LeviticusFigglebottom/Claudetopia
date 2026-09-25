class_name Effects
extends RefCounted
## Effects: the pure applier for the effect vocabulary in docs/CONTRACTS.md §7.
##
## An effect is a Dictionary with one key (the action) whose value is its argument. Effects are
## applied in order through a SocialContext, so this file touches no autoload and no scene.
##
## Vocabulary (CONTRACTS §7):
##   {"set_flag": "met_wren"} | {"set_flag": ["key", value]}
##   {"give_item": ["core:item/x", 2]} | {"give_item": "core:item/x"}
##   {"quest_stage": [quest_id, stage]}      a stage id, or a stage number counted from one (QuestLog.stage_index)
##   {"rep": [faction_id, delta]}
##   {"morality": delta}
##   {"renown": delta}
##   {"marks": delta}                        positive gives, negative takes (inventory owns marks)
##   {"start_quest": quest_id}
##   {"teach_recipe": recipe_id}
##   {"teach_spell": spell_id}              a Sayer teaches a saying (progression owns the list)
##   {"arm": item_id}                       one of a weapon given and put in the main hand when
##                                          that hand is empty or holds a weaker one ("Sword up")
## Extensions required by this stream:
##   {"gesture_reply": gesture_id}           the NPC answers with a gesture (runner emits it)
##   {"rumour": rumour_id}                   seeds the current place's rumour pool
##   {"unlock_topic": topic_id}              opens a dialogue topic (a flag under "topic/")
##   {"end": true}                           ends the conversation after this node
##   {"bounty": "theft"}                     a decision that is a crime: committed here, seen by the
##   {"bounty": {"crime": "theft", "value": 120, "at": place_id, "seen_by": npc_id, "reaction": r}}
##                                           person spoken to (or `seen_by`), and reported by the crime
##                                           system's rules (SocialContext.commit_crime)
##   {"offer_work": true} | {"offer_work": place_id}
##                                           the work going in the place (the speaker's own when true):
##                                           its notice post, or what its people carry (JobBoard.for_place)
## Further supported (documented in the README):
##   clear_flag, inc_counter, take_item, deed, disposition, complete_quest, fail_quest,
##   quest_choice, complete_objective, join_faction, leave_faction, discover, notify, none
##
## Unknown keys never crash: they are skipped and recorded as a content problem.

const TOPIC_PREFIX := "topic/"

const KNOWN := [
	"set_flag", "give_item", "quest_stage", "rep", "morality", "renown", "marks", "start_quest",
	"teach_recipe", "teach_spell", "gesture_reply", "rumour", "unlock_topic", "end",
	"clear_flag", "inc_counter", "take_item", "deed", "disposition", "complete_quest", "fail_quest",
	"quest_choice", "complete_objective", "join_faction", "leave_faction", "discover", "notify", "none",
	"bounty", "offer_work", "arm",
]


## Applies a list of effects in order. Null or empty is a no-op.
static func apply_all(effects: Variant, ctx: SocialContext, reason: String = "dialogue") -> void:
	if effects == null:
		return
	if typeof(effects) == TYPE_DICTIONARY:
		apply(effects, ctx, reason)
		return
	if typeof(effects) != TYPE_ARRAY:
		ctx.problem("effects: expected an array, got %s" % type_string(typeof(effects)))
		return
	for e in effects:
		apply(e, ctx, reason)


## Applies one effect object (all of its keys, in insertion order).
static func apply(effect: Variant, ctx: SocialContext, reason: String = "dialogue") -> void:
	if typeof(effect) != TYPE_DICTIONARY:
		ctx.problem("effect: expected an object, got %s (%s)" % [type_string(typeof(effect)), str(effect)])
		return
	for key in effect.keys():
		_one(str(key), effect[key], ctx, reason)


static func _one(key: String, arg: Variant, ctx: SocialContext, reason: String) -> void:
	match key:
		"none":
			pass

		# --- flags, counters, discovery ---
		"set_flag":
			if typeof(arg) == TYPE_ARRAY and arg.size() >= 2:
				ctx.set_flag(str(arg[0]), arg[1])
			else:
				ctx.set_flag(str(arg), true)
		"clear_flag":
			ctx.clear_flag(str(arg))
		"inc_counter":
			if typeof(arg) == TYPE_ARRAY and arg.size() >= 2:
				ctx.inc(str(arg[0]), int(arg[1]))
			else:
				ctx.inc(str(arg), 1)
		"unlock_topic":
			ctx.set_flag(TOPIC_PREFIX + str(arg), true)
		"discover":
			ctx.discover(str(arg))

		# --- items and marks ---
		"give_item":
			var p := _item_pair(arg, ctx, "give_item")
			if not p.is_empty():
				ctx.give_item(str(p[0]), int(p[1]))
		"arm":
			var p := _item_pair(arg, ctx, "arm")
			if not p.is_empty():
				ctx.arm(str(p[0]))
		"take_item":
			var p := _item_pair(arg, ctx, "take_item")
			if not p.is_empty():
				ctx.take_item(str(p[0]), int(p[1]))
		"marks":
			ctx.add_marks(int(arg))
		"teach_recipe":
			ctx.teach_recipe(str(arg))
		"teach_spell":
			ctx.teach_spell(str(arg))

		# --- quests ---
		"start_quest":
			ctx.start_quest(str(arg))
		"quest_stage":
			var p := _pair(arg, ctx, "quest_stage")
			if not p.is_empty():
				ctx.set_quest_stage(str(p[0]), p[1])
		"quest_choice":
			var p := _pair(arg, ctx, "quest_choice")
			if not p.is_empty():
				ctx.quest_choose(str(p[0]), str(p[1]))
		"complete_objective":
			var p := _pair(arg, ctx, "complete_objective")
			if not p.is_empty():
				ctx.complete_objective(str(p[0]), p[1])
		"complete_quest":
			if typeof(arg) == TYPE_ARRAY and arg.size() >= 2:
				ctx.complete_quest(str(arg[0]), str(arg[1]))
			else:
				ctx.complete_quest(str(arg), "")
		"fail_quest":
			if typeof(arg) == TYPE_ARRAY and arg.size() >= 2:
				ctx.fail_quest(str(arg[0]), str(arg[1]))
			else:
				ctx.fail_quest(str(arg), reason)

		# --- factions ---
		"rep":
			var p := _pair(arg, ctx, "rep")
			if not p.is_empty():
				ctx.add_reputation(str(p[0]), int(p[1]), reason)
		"join_faction":
			ctx.join_faction(str(arg))
		"leave_faction":
			ctx.expel_faction(str(arg), reason)

		# --- standing and gossip ---
		"morality":
			ctx.add_morality(int(arg), reason)
		"renown":
			ctx.add_renown(int(arg), reason)
		"deed":
			if typeof(arg) == TYPE_ARRAY and arg.size() >= 2:
				ctx.apply_deed(str(arg[0]), _witness_list(arg[1], ctx))
			else:
				ctx.apply_deed(str(arg), _witness_list(null, ctx))
		"disposition":
			if typeof(arg) == TYPE_ARRAY and arg.size() >= 2:
				ctx.add_disposition(str(arg[0]), int(arg[1]))
			else:
				ctx.add_disposition(ctx.npc_id, int(arg))
		"bounty":
			if typeof(arg) == TYPE_DICTIONARY:
				var d: Dictionary = arg
				ctx.commit_crime(str(d.get("crime", "")), str(d.get("at", "")), str(d.get("seen_by", "")),
						int(d.get("value", 0)), str(d.get("reaction", "report")))
			else:
				ctx.commit_crime(str(arg))
		"offer_work":
			ctx.offer_work(str(arg) if typeof(arg) == TYPE_STRING else "")
		"rumour":
			var rid := ""
			var heat := 0.6
			if typeof(arg) == TYPE_ARRAY and arg.size() >= 1:
				rid = str(arg[0])
				if arg.size() >= 2:
					heat = float(arg[1])
			else:
				rid = str(arg)
			ctx.add_rumour(rid, ctx.place_id, heat)

		# --- conversation control ---
		"gesture_reply":
			ctx.gesture_replies.append(str(arg))
		"end":
			if typeof(arg) == TYPE_BOOL and not arg:
				return
			ctx.end_requested = true
		"notify":
			ctx.notifications.append(ctx.substitute(str(arg)))

		_:
			ctx.problem("unknown effect '%s' (content problem, skipped)" % key)


static func _pair(arg: Variant, ctx: SocialContext, key: String) -> Array:
	if typeof(arg) == TYPE_ARRAY and arg.size() >= 2:
		return [arg[0], arg[1]]
	ctx.problem("effect '%s' expects [a, b], got %s" % [key, str(arg)])
	return []


## Accepts ["core:item/x", 2] or the bare "core:item/x" (meaning one).
static func _item_pair(arg: Variant, ctx: SocialContext, key: String) -> Array:
	if typeof(arg) == TYPE_STRING:
		return [arg, 1]
	return _pair(arg, ctx, key)


static func _witness_list(arg: Variant, ctx: SocialContext) -> Array:
	if typeof(arg) == TYPE_ARRAY:
		return arg
	if typeof(arg) == TYPE_STRING and str(arg) != "":
		return [arg]
	if typeof(arg) == TYPE_INT or typeof(arg) == TYPE_FLOAT:
		var out: Array = []
		for i in int(arg):
			out.append("")
		return out
	return [ctx.npc_id] if ctx.npc_id != "" else []
