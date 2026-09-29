class_name Conditions
extends RefCounted
## Conditions: the pure evaluator for the condition vocabulary in docs/CONTRACTS.md §7.
##
## A condition is a Dictionary with exactly one key (the test) whose value is its argument.
## Arrays of conditions are ANDed. Everything is read through a SocialContext, so this file
## touches no autoload and no scene, and tests drive it with fakes.
##
## Vocabulary (CONTRACTS §7):
##   {"flag": "met_wren"}                     flag set (truthy)
##   {"quest_at": [quest_id, stage]}          quest is active at exactly that stage: its stage id, or its
##                                            number counted from one (the first stage is 1), which is how
##                                            every quest in the pack that writes numbers says it counts
##   {"rep_min": [faction_id, n]}             reputation >= n
##   {"renown_min": n}                        renown >= n
##   {"morality_min": n}                      Hearth/Hollow >= n (negative n tests the Hollow side)
##   {"skill_min": [skill_id, n]}             skill level >= n
##   {"knows_spell": spell_id}                the character has been taught that saying
##   {"knows_recipe": recipe_id}              the character has been taught that recipe
##   {"has_item": [item_id, n]}               at least n in inventory
##   {"time_between": [from_hour, to_hour]}   game hour in [from, to), wrapping past midnight
## Extensions required by this stream:
##   {"not": cond} {"any": [conds]} {"all": [conds]}
##   {"personality": trait}                   the NPC in context has the trait
##   {"faction_rank_min": [faction_id, n]}    member and rank index >= n
##   {"bounty_min": [faction_id, n]}          bounty with that faction >= n
##   {"counter_min": [key, n]}                GameState counter >= n
##   {"discovered": place_id}                 place discovered
##   {"wearing_tag": tag}                     an equipped item carries the tag
##   {"random": p}                            true with probability p (context rng; deterministic in tests)
##   {"style": style_id}                      the character was named with that fighting style
##   {"has_mount": true}                      the character owns a horse (false: owns none)
## Further supported (documented in the README; the same shapes, mirrored):
##   flag_not, flag_equals, quest_active, quest_done, quest_not_done, quest_min_stage,
##   quest_outcome, rep_max, renown_max, morality_max, member_of, not_member_of, has_no_item,
##   marks_min, is_night, knows_deed, book_read, in_region, at_place, npc_is, witnessed_crime,
##   disposition_min, true, false
##
## Unknown keys never crash: they evaluate to false and are recorded as a content problem.

const KNOWN := [
	"flag", "quest_at", "rep_min", "renown_min", "morality_min", "skill_min", "has_item", "time_between",
	"not", "any", "all", "personality", "faction_rank_min", "bounty_min", "counter_min", "discovered",
	"wearing_tag", "random", "knows_spell", "knows_recipe",
	"flag_not", "flag_equals", "quest_active", "quest_done", "quest_not_done", "quest_min_stage",
	"quest_outcome", "rep_max", "renown_max", "morality_max", "member_of", "not_member_of",
	"has_no_item", "marks_min", "is_night", "knows_deed", "book_read", "in_region", "at_place",
	"npc_is", "witnessed_crime", "disposition_min", "true", "false", "style", "has_mount",
]


## Evaluates an array of conditions (AND). An empty or null list is true.
static func all_of(conds: Variant, ctx: SocialContext) -> bool:
	if conds == null:
		return true
	if typeof(conds) == TYPE_DICTIONARY:
		return check(conds, ctx)
	if typeof(conds) != TYPE_ARRAY:
		ctx.problem("conditions: expected an array, got %s" % type_string(typeof(conds)))
		return false
	for c in conds:
		if not check(c, ctx):
			return false
	return true


## Evaluates one condition object.
static func check(cond: Variant, ctx: SocialContext) -> bool:
	if typeof(cond) != TYPE_DICTIONARY:
		ctx.problem("condition: expected an object, got %s (%s)" % [type_string(typeof(cond)), str(cond)])
		return false
	if cond.is_empty():
		return true
	var result := true
	for key in cond.keys():
		if not _one(str(key), cond[key], ctx):
			result = false
			break
	return result


static func _one(key: String, arg: Variant, ctx: SocialContext) -> bool:
	match key:
		"true":
			return true
		"false":
			return false

		# --- logic ---
		"not":
			return not check(arg, ctx) if typeof(arg) == TYPE_DICTIONARY else not all_of(arg, ctx)
		"all":
			return all_of(arg, ctx)
		"any":
			if typeof(arg) != TYPE_ARRAY:
				ctx.problem("condition 'any' expects an array")
				return false
			for c in arg:
				if check(c, ctx):
					return true
			return false

		# --- flags & counters ---
		"flag":
			return ctx.has_flag(str(arg))
		"flag_not":
			return not ctx.has_flag(str(arg))
		"style":
			return str(ctx.get_flag(StyleDef.FLAG, "")) == str(arg)
		"has_mount":
			return ctx.owns_a_mount() == bool(arg)
		"flag_equals":
			var pair := _pair(arg, ctx, "flag_equals")
			if pair.is_empty():
				return false
			return ctx.get_flag(str(pair[0]), null) == pair[1]
		"counter_min":
			var p := _pair(arg, ctx, "counter_min")
			return false if p.is_empty() else ctx.count(str(p[0])) >= int(p[1])

		# --- quests ---
		"quest_at":
			var p := _pair(arg, ctx, "quest_at")
			if p.is_empty():
				return false
			var quest := str(p[0])
			if not ctx.quest_active(quest):
				return false
			if typeof(p[1]) == TYPE_STRING:
				return ctx.quest_stage_id(quest) == str(p[1])
			# a number counts from one; the log's own stage is an index from nought
			return ctx.quest_stage(quest) + 1 == int(p[1])
		"quest_min_stage":
			var p := _pair(arg, ctx, "quest_min_stage")
			if p.is_empty():
				return false
			var quest := str(p[0])
			if not ctx.quest_active(quest):
				return false
			if typeof(p[1]) == TYPE_STRING:
				var at := ctx.quest_stage_index(quest, str(p[1]))
				return at >= 0 and ctx.quest_stage(quest) >= at
			return ctx.quest_stage(quest) + 1 >= int(p[1])
		"quest_active":
			return ctx.quest_active(str(arg))
		"quest_done":
			return ctx.quest_completed(str(arg))
		"quest_not_done":
			return not ctx.quest_completed(str(arg))
		"quest_outcome":
			var p := _pair(arg, ctx, "quest_outcome")
			return false if p.is_empty() else ctx.quest_outcome(str(p[0])) == str(p[1])

		# --- factions ---
		"rep_min":
			var p := _pair(arg, ctx, "rep_min")
			return false if p.is_empty() else ctx.reputation(str(p[0])) >= int(p[1])
		"rep_max":
			var p := _pair(arg, ctx, "rep_max")
			return false if p.is_empty() else ctx.reputation(str(p[0])) <= int(p[1])
		"faction_rank_min":
			var p := _pair(arg, ctx, "faction_rank_min")
			if p.is_empty():
				return false
			return ctx.is_member(str(p[0])) and ctx.faction_rank(str(p[0])) >= int(p[1])
		"member_of":
			return ctx.is_member(str(arg))
		"not_member_of":
			return not ctx.is_member(str(arg))
		"bounty_min":
			var p := _pair(arg, ctx, "bounty_min")
			return false if p.is_empty() else ctx.bounty(str(p[0])) >= int(p[1])

		# --- standing ---
		"renown_min":
			return ctx.renown() >= int(arg)
		"renown_max":
			return ctx.renown() <= int(arg)
		"morality_min":
			return ctx.morality() >= int(arg)
		"morality_max":
			return ctx.morality() <= int(arg)
		"knows_deed":
			var p := _pair(arg, ctx, "knows_deed")
			if p.is_empty():
				return ctx.knows_deed(ctx.place_id, str(arg)) if typeof(arg) == TYPE_STRING else false
			return ctx.knows_deed(str(p[0]), str(p[1]))
		"witnessed_crime":
			return ctx.npc_witnessed(ctx.npc_id) != ""
		"disposition_min":
			if typeof(arg) == TYPE_ARRAY:
				var p := _pair(arg, ctx, "disposition_min")
				return false if p.is_empty() else ctx.disposition(str(p[0])) >= int(p[1])
			return ctx.disposition(ctx.npc_id) >= int(arg)

		# --- player, items, skills ---
		"skill_min":
			var p := _pair(arg, ctx, "skill_min")
			return false if p.is_empty() else ctx.skill_level(str(p[0])) >= int(p[1])
		"has_item":
			var p := _pair_or_single(arg, ctx, "has_item")
			return false if p.is_empty() else ctx.item_count(str(p[0])) >= int(p[1])
		"has_no_item":
			var p := _pair_or_single(arg, ctx, "has_no_item")
			return false if p.is_empty() else ctx.item_count(str(p[0])) < int(p[1])
		"wearing_tag":
			return ctx.wearing_tag(str(arg))
		"knows_spell":
			return ctx.knows_spell(str(arg))
		"knows_recipe":
			return ctx.knows_recipe(str(arg))
		"marks_min":
			return ctx.marks() >= int(arg)

		# --- world ---
		"discovered":
			return ctx.is_discovered(str(arg))
		"book_read":
			return ctx.has_read(str(arg))
		"in_region":
			return ctx.region_id() == str(arg)
		"at_place":
			return ctx.place_id == str(arg)
		"npc_is":
			return ctx.npc_id == str(arg)
		"personality":
			return str(arg) in ctx.npc_traits()
		"is_night":
			return ctx.is_night() == bool(arg)
		"time_between":
			var p := _pair(arg, ctx, "time_between")
			if p.is_empty():
				return false
			return in_hour_window(ctx.hour(), float(p[0]), float(p[1]))

		# --- chance ---
		"random":
			return ctx.rng.randf() < clampf(float(arg), 0.0, 1.0)

		_:
			ctx.problem("unknown condition '%s' (content problem, treated as false)" % key)
			return false


## Hour window test that wraps past midnight: [20, 6) covers 20,21,...,5.
static func in_hour_window(hour: float, from_hour: float, to_hour: float) -> bool:
	if is_equal_approx(from_hour, to_hour):
		return true
	if from_hour < to_hour:
		return hour >= from_hour and hour < to_hour
	return hour >= from_hour or hour < to_hour


static func _pair(arg: Variant, ctx: SocialContext, key: String) -> Array:
	if typeof(arg) == TYPE_ARRAY and arg.size() >= 2:
		return [arg[0], arg[1]]
	ctx.problem("condition '%s' expects [a, b], got %s" % [key, str(arg)])
	return []


## Accepts ["core:item/x", 2] or the bare "core:item/x" (meaning one).
static func _pair_or_single(arg: Variant, ctx: SocialContext, key: String) -> Array:
	if typeof(arg) == TYPE_STRING:
		return [arg, 1]
	return _pair(arg, ctx, key)
