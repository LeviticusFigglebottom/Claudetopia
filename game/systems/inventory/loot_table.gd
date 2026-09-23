class_name LootTable
extends RefCounted
## Pure loot rolls. Given a table (a core:loot/* id or an inline Dictionary), a
## RandomNumberGenerator and a context, returns [{item, count}] and [{marks}] results.
## The same seed, table and context always give the same results.
##
## Table: {rolls: int | [min, max] (default 1), entries: [entry], guaranteed: [entry]}
## Entry (weighted pick, one per roll):
##   {item: id, count: int | [min, max], weight (default 1), weight_per_luck (default 0), conditions: [...]}
##   {table: loot id, ...}   nested table, rolled in full
##   {marks: int | [min, max], ...}
##   {nothing: true, weight}
## Guaranteed entries roll independently of the weighted picks, each with an optional
## `chance` (0..1) and `conditions`.
## Conditions (all must pass): {region: id}, {min_level: n}, {max_level: n}, {luck_min: x},
##   {flag: name}, {flag_not: name}, {quest_at: [quest_id, stage]}, {quest_min: [quest_id, stage]}.
##   A stage is named the pack's way: its id, or its number counted from one.
## Context: {region: id, level: int, luck: float, flags: {name: value}, quests: {quest_id: stage
##   index from nought}, quests_done: [quest_id]}; `world_context()` reads it off the world.

const MAX_DEPTH := 6
const QUEST_LOG := preload("res://systems/quests/quest_log.gd")


## Rolls a table; results are not merged (call merge() for one entry per item).
static func roll(table: Variant, rng: RandomNumberGenerator, context: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_roll_into(table, rng, context, out, 0)
	return out


## Rolls and merges: one {item, count} per item id and at most one {marks}.
static func roll_merged(table: Variant, rng: RandomNumberGenerator, context: Dictionary = {}) -> Array[Dictionary]:
	return merge(roll(table, rng, context))


static func _roll_into(table: Variant, rng: RandomNumberGenerator, context: Dictionary, out: Array[Dictionary], depth: int) -> void:
	if depth > MAX_DEPTH:
		Log.warn("LootTable", "nested tables deeper than %d; stopping" % MAX_DEPTH)
		return
	var def := resolve(table)
	if def.is_empty():
		return
	var entries: Array = def.get("entries", [])
	var eligible: Array = []
	var weights: Array[float] = []
	var total := 0.0
	for e in entries:
		if typeof(e) != TYPE_DICTIONARY or not conditions_pass(e.get("conditions", []), context):
			continue
		var w := effective_weight(e, context)
		if w <= 0.0:
			continue
		eligible.append(e)
		weights.append(w)
		total += w
	var rolls := range_value(def.get("rolls", 1), rng)
	for _i in rolls:
		if total <= 0.0:
			break
		var r := rng.randf() * total
		var acc := 0.0
		var picked: Dictionary = {}
		for j in eligible.size():
			acc += weights[j]
			if r < acc:
				picked = eligible[j]
				break
		if picked.is_empty():
			picked = eligible[eligible.size() - 1]
		_apply_entry(picked, rng, context, out, depth)
	for g in def.get("guaranteed", []):
		if typeof(g) != TYPE_DICTIONARY or not conditions_pass(g.get("conditions", []), context):
			continue
		var chance := float(g.get("chance", 1.0))
		if chance < 1.0 and rng.randf() >= chance:
			continue
		_apply_entry(g, rng, context, out, depth)


static func _apply_entry(e: Dictionary, rng: RandomNumberGenerator, context: Dictionary, out: Array[Dictionary], depth: int) -> void:
	if e.get("nothing", false):
		return
	if e.has("table"):
		_roll_into(e["table"], rng, context, out, depth + 1)
		return
	if e.has("marks"):
		var n := range_value(e["marks"], rng)
		if n > 0:
			out.append({"marks": n})
		return
	if e.has("item"):
		var id := str(e["item"])
		if not ContentDB.has(id):
			Log.warn("LootTable", "entry references unknown item '%s'" % id)
			return
		var n := range_value(e.get("count", 1), rng)
		if n > 0:
			var r := {"item": id, "count": n}
			if e.has("data") and typeof(e["data"]) == TYPE_DICTIONARY:
				r["data"] = e["data"].duplicate(true)
			out.append(r)


## A loot id is looked up in ContentDB; a Dictionary is used as-is.
static func resolve(table: Variant) -> Dictionary:
	if typeof(table) == TYPE_DICTIONARY:
		return table
	if typeof(table) == TYPE_STRING:
		var def := ContentDB.get_or_empty(table)
		if def.is_empty():
			Log.warn("LootTable", "unknown loot table '%s'" % table)
		return def
	return {}


static func effective_weight(e: Dictionary, context: Dictionary) -> float:
	var w := float(e.get("weight", 1.0))
	w += float(context.get("luck", 0.0)) * float(e.get("weight_per_luck", 0.0))
	return w


## int, or [min, max] inclusive drawn from rng. Anything else counts as 1.
static func range_value(v: Variant, rng: RandomNumberGenerator) -> int:
	match typeof(v):
		TYPE_INT:
			return v
		TYPE_FLOAT:
			return int(v)
		TYPE_ARRAY:
			if v.size() >= 2:
				var lo := int(v[0])
				var hi := int(v[1])
				if hi < lo:
					var t := lo
					lo = hi
					hi = t
				return rng.randi_range(lo, hi)
			elif v.size() == 1:
				return int(v[0])
	return 1


static func conditions_pass(conds: Variant, context: Dictionary) -> bool:
	if typeof(conds) != TYPE_ARRAY:
		return true
	for c in conds:
		if typeof(c) == TYPE_DICTIONARY and not condition_passes(c, context):
			return false
	return true


static func condition_passes(cond: Dictionary, context: Dictionary) -> bool:
	for key in cond:
		var v: Variant = cond[key]
		match str(key):
			"region":
				if str(context.get("region", "")) != str(v):
					return false
			"min_level":
				if int(context.get("level", 1)) < int(v):
					return false
			"max_level":
				if int(context.get("level", 1)) > int(v):
					return false
			"luck_min":
				if float(context.get("luck", 0.0)) < float(v):
					return false
			"flag":
				if not _flag_set(context, str(v)):
					return false
			"flag_not":
				if _flag_set(context, str(v)):
					return false
			"quest_at":
				if typeof(v) != TYPE_ARRAY or v.size() < 2:
					return false
				var quests: Dictionary = context.get("quests", {})
				var at := _stage_named(str(v[0]), v[1])
				if at < 0 or not quests.has(str(v[0])) or int(quests[str(v[0])]) != at:
					return false
			"quest_min":
				if typeof(v) != TYPE_ARRAY or v.size() < 2:
					return false
				# a finished quest is past every one of its stages
				if not (context.get("quests_done", []) as Array).has(str(v[0])):
					var quests2: Dictionary = context.get("quests", {})
					var least := _stage_named(str(v[0]), v[1])
					if least < 0 or not quests2.has(str(v[0])) or int(quests2[str(v[0])]) < least:
						return false
			_:
				Log.warn("LootTable", "unknown loot condition '%s'" % key)
				return false
	return true


static func _flag_set(context: Dictionary, flag: String) -> bool:
	var flags: Dictionary = context.get("flags", {})
	if not flags.has(flag):
		return false
	var v: Variant = flags[flag]
	match typeof(v):
		TYPE_BOOL:
			return v
		TYPE_INT, TYPE_FLOAT:
			return v != 0
		TYPE_STRING:
			return not v.is_empty()
	return v != null


## Combines duplicate items and marks entries into one each (order of first appearance kept).
static func merge(results: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var by_key := {}
	for r in results:
		var key: String
		if r.has("marks"):
			key = "$marks"
		else:
			key = str(r.get("item", "")) + "|" + str(r.get("data", {}))
		if by_key.has(key):
			var existing: Dictionary = by_key[key]
			if r.has("marks"):
				existing["marks"] = int(existing["marks"]) + int(r["marks"])
			else:
				existing["count"] = int(existing["count"]) + int(r["count"])
		else:
			var copy := r.duplicate(true)
			by_key[key] = copy
			out.append(copy)
	return out


## Context from the shared game state: current region, GameState flags, level 1, luck 0.
## Callers add "level", "luck" (from Modifiers) and "quests" from their own systems.
static func default_context() -> Dictionary:
	return {"region": GameState.current_region_id, "level": 1, "luck": 0.0, "flags": GameState.flags.duplicate(),
			"quests": {}, "quests_done": []}


## The context a roll is made in, read off the world: where, the character's level and luck, the
## flags, and how far each quest has come (`quests`: an active quest's stage, as an index from
## nought; `quests_done`: the ones finished). A kill's drop (`GameServices.loot_context`, handed to
## `LootDrops`) and a chest's contents (`Container`) are rolled in the same one. A chest rolled in
## the default context was a level-1 character with no luck and no quests, whatever the player was.
static func world_context() -> Dictionary:
	var ctx := default_context()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return ctx
	var prog := tree.get_first_node_in_group("progression")
	if prog != null:
		ctx["level"] = int(prog.get("level"))
		var mods: Variant = prog.get("mods")
		if mods is Modifiers:
			ctx["luck"] = (mods as Modifiers).apply("luck", 0.0)
	var quest_log := tree.get_first_node_in_group("quest_log")
	if quest_log != null and quest_log.has_method("stage_of"):
		var quests := {}
		var done: Array = []
		var known: Variant = quest_log.get("quests")
		if known is Dictionary:
			for quest_id in known:
				var id := str(quest_id)
				if bool(quest_log.call("is_active", id)):
					quests[id] = int(quest_log.call("stage_of", id))
				elif bool(quest_log.call("is_completed", id)):
					done.append(id)
		ctx["quests"] = quests
		ctx["quests_done"] = done
	return ctx


## The stage a condition names, as an index from nought: content writes a stage's id or its number
## counted from one, the pack's rule everywhere else (QuestLog.stage_index). These conditions read
## the number as an index, which would have put every numbered one a stage late.
static func _stage_named(quest_id: String, stage: Variant) -> int:
	return QUEST_LOG.stage_index_in(ContentDB.get_or_empty(quest_id).get("stages", []), stage)
