extends Node
## QuestLog: every quest the player has started, which stage it is on, how far each objective has
## got, and the journal text that records it. Save section "quests". Joins the group "quest_log".
##
## Data: content type "quest" (docs/CONTRACTS.md §7):
##   {id, name, layer (main|faction|side|radiant), stages[{id, journal, objectives[{type, target,
##    count}], on_enter[], on_complete[]}], rewards}
## Radiant quests are generated at runtime (systems/quests/radiant.gd) and registered with
## register_runtime(), which keeps their whole definition in the save file so a loaded game still
## knows what the board asked for.
##
## Objective types (CONTRACTS §7 plus this stream's list):
##   talk      target = npc id            EventBus.dialogue_ended
##   reach     target = place/poi id      position provider, or EventBus.place_discovered
##   kill      target = enemy id (or "" for any, or a tag:) EventBus.entity_killed
##   collect   target = item id           EventBus.item_acquired (and the inventory's current count)
##   deliver   target = npc id, item = item id   completed by dialogue effects or deliver()
##   escort    target = npc id, place = place id EventBus.escort_arrived
##   choice    target = option id         choose()
##   use_item  target = item id           EventBus.item_used
##   rest_at   target = hearthstone id    EventBus.hearthstone_rested
##   read_book target = book id           EventBus.book_opened
##
## Markers are approximate areas, never pins: {place_id, radius, quest_id, text} (DESIGN §5.10).
##
## **How content names a stage.** By its id, or by its *number*, counted from one: the first
## stage is 1. Every quest in the pack that writes numbers says so in its own `notes` ("Stage
## numbers in quest_at and quest_stage are 1-based"), and until this was written down in code
## the code read them as indices from nought, so every numbered reference in the pack landed on
## the stage after the one its writer meant, or on none. `stage_index()` is the one place that
## turns what content wrote into an index; `stage_of()` is that index and content never writes it.
##
## Emits: EventBus.quest_started(id), quest_stage_changed(id, stage), quest_completed(id, outcome).

const OBJECTIVE_TYPES := ["talk", "reach", "kill", "collect", "deliver", "escort", "choice", "use_item", "rest_at", "read_book"]

## How close counts as "reached" when nothing says otherwise, and how wide a marker is drawn.
const REACH_RADIUS_M := 45.0
const MARKER_RADIUS_M := 140.0
const REGION_MARKER_RADIUS_M := 600.0
## How often the position provider is asked about reach objectives (seconds).
const REACH_POLL_S := 0.5

## Quest record: {id, stage, stage_id, counts{}, journal[], started_day, state, outcome, choices{}, runtime{}}
var quests: Dictionary = {}

## Injected by Social: a SocialContext for on_enter/on_complete effect lists.
var ctx: SocialContext = null
## Where the player is, for `reach` objectives: anything with a position() method or a Node3D.
var position_provider: Object = null
## The board generator, whose board cooldowns ride along in this system's save section.
var radiant: RadiantGenerator = null

var _poll := 0.0


func _ready() -> void:
	add_to_group("quest_log")
	SaveSystem.register("quests", self)
	EventBus.entity_killed.connect(_on_entity_killed)
	EventBus.item_acquired.connect(_on_item_acquired)
	EventBus.place_discovered.connect(_on_place_discovered)
	EventBus.dialogue_ended.connect(_on_dialogue_ended)
	EventBus.hearthstone_rested.connect(_on_hearthstone_rested)
	EventBus.book_opened.connect(_on_book_opened)
	EventBus.item_used.connect(_on_item_used)
	EventBus.escort_arrived.connect(_on_escort_arrived)


func _process(delta: float) -> void:
	if _locator() == null:
		return
	_poll += delta
	if _poll < REACH_POLL_S:
		return
	_poll = 0.0
	check_reach()


# --- definitions -----------------------------------------------------------------------------

## The quest definition: a runtime (radiant) one if registered, otherwise the content pack's.
func definition(quest_id: String) -> Dictionary:
	var q: Dictionary = quests.get(quest_id, {})
	var runtime: Variant = q.get("runtime")
	if typeof(runtime) == TYPE_DICTIONARY and not (runtime as Dictionary).is_empty():
		return runtime
	return ContentDB.get_or_empty(quest_id)


## Registers a generated quest (radiant) so it can be started like any other.
func register_runtime(def: Dictionary) -> bool:
	var id := str(def.get("id", ""))
	if id == "" or not def.has("stages"):
		Log.warn("Quests", "register_runtime: definition without id or stages")
		return false
	if not quests.has(id):
		quests[id] = _blank_record(id)
	quests[id]["runtime"] = def.duplicate(true)
	return true


func stages_of(quest_id: String) -> Array:
	var s: Variant = definition(quest_id).get("stages", [])
	return s if typeof(s) == TYPE_ARRAY else []


func stage_def(quest_id: String, index: int) -> Dictionary:
	var stages := stages_of(quest_id)
	if index < 0 or index >= stages.size():
		return {}
	var s: Variant = stages[index]
	return s if typeof(s) == TYPE_DICTIONARY else {}


func stage_index_of_id(quest_id: String, stage_id: String) -> int:
	var stages := stages_of(quest_id)
	for i in stages.size():
		if str((stages[i] as Dictionary).get("id", "")) == stage_id:
			return i
	return -1


## The index of a stage as content names it: a stage id, or a stage number counted from one.
## -1 when it names no stage of this quest.
func stage_index(quest_id: String, stage: Variant) -> int:
	return stage_index_in(stages_of(quest_id), stage)


## `stage_index` over a stage list, for anything that holds a definition rather than a log: the
## content tests, the tools. A string that is all digits is a number, because that is how one
## arrives from the debug console.
static func stage_index_in(stages: Array, stage: Variant) -> int:
	match typeof(stage):
		TYPE_INT, TYPE_FLOAT:
			var n := int(stage)
			return n - 1 if n >= 1 and n <= stages.size() else -1
		TYPE_STRING, TYPE_STRING_NAME:
			var s := str(stage)
			for i in stages.size():
				if typeof(stages[i]) == TYPE_DICTIONARY and str((stages[i] as Dictionary).get("id", "")) == s:
					return i
			if s.is_valid_int():
				return stage_index_in(stages, int(s))
	return -1


# --- life cycle -------------------------------------------------------------------------------

func start(quest_id: String) -> bool:
	if is_active(quest_id) or is_completed(quest_id):
		return false
	var def := definition(quest_id)
	if def.is_empty() or not def.has("stages"):
		Log.warn("Quests", "cannot start unknown quest '%s' (content problem)" % quest_id)
		return false
	if not QuestConditions.can_start(def, ctx, self):
		Log.info("Quests", "%s is not available yet (its requirements are unmet)" % quest_id)
		return false
	if not quests.has(quest_id):
		quests[quest_id] = _blank_record(quest_id)
	var rec: Dictionary = quests[quest_id]
	rec["state"] = "active"
	rec["stage"] = -1
	rec["started_day"] = WorldClock.day
	EventBus.quest_started.emit(quest_id)
	Log.info("Quests", "started %s (%s)" % [quest_id, str(def.get("name", "?"))])
	_enter_stage(quest_id, 0)
	return true


## Moves a quest to a stage, named as content names it: a stage id, or a stage number counted
## from one. Runs the effects of the stage entered.
func set_stage(quest_id: String, stage: Variant) -> void:
	if not quests.has(quest_id) or str(quests[quest_id].get("state", "")) != "active":
		if not is_completed(quest_id) and not start(quest_id):
			return
		if str(quests[quest_id].get("state", "")) != "active":
			return
	var index := stage_index(quest_id, stage)
	if index < 0:
		Log.warn("Quests", "%s: unknown stage '%s' (content problem)" % [quest_id, str(stage)])
		return
	_enter_stage(quest_id, index)


## Advances to the next stage, completing the quest after the last one.
##
## A stage's `on_complete` may say where to go instead — a branch stage rejoins the main line
## that way (`{"quest_stage": [quest, "tell_osric"]}`). This used to run those effects, land on
## the stage they named, and then carry on as though they had said nothing, entering
## `current + 1` over the top: every branch of the six branching side quests fell through into
## the next branch in the list rather than rejoining. When the effects have moved the quest,
## or finished it, that is the answer.
func advance(quest_id: String) -> void:
	if not is_active(quest_id):
		return
	var current := stage_of(quest_id)
	var stage := stage_def(quest_id, current)
	_run_effects(quest_id, stage.get("on_complete", []), "quest_complete_stage")
	if not is_active(quest_id) or stage_of(quest_id) != current:
		return
	if current + 1 >= stages_of(quest_id).size():
		complete(quest_id, str(stage.get("outcome", quests[quest_id].get("outcome", ""))))
	else:
		_enter_stage(quest_id, current + 1)


func _enter_stage(quest_id: String, index: int) -> void:
	var rec: Dictionary = quests[quest_id]
	var stage := stage_def(quest_id, index)
	if stage.is_empty():
		Log.warn("Quests", "%s: stage %d does not exist (content problem)" % [quest_id, index])
		return
	rec["stage"] = index
	rec["stage_id"] = str(stage.get("id", str(index)))
	var journal := str(stage.get("journal", ""))
	if journal != "":
		var line: String = ctx.substitute(journal) if ctx != null else journal
		var entries: Array = rec["journal"]
		if not entries.has(line):
			entries.append(line)
	EventBus.quest_stage_changed.emit(quest_id, index)
	_run_effects(quest_id, stage.get("on_enter", []), "quest_enter_stage")
	# Objectives already satisfied when the stage opens (an item you are carrying, a place you
	# already know) should not leave the stage stuck.
	_sync_stage(quest_id)
	_check_stage_complete(quest_id)


func complete(quest_id: String, outcome: String = "") -> void:
	if not quests.has(quest_id):
		return
	var rec: Dictionary = quests[quest_id]
	if str(rec.get("state", "")) == "completed":
		return
	rec["state"] = "completed"
	rec["outcome"] = outcome
	rec["completed_day"] = WorldClock.day
	_grant_rewards(quest_id)
	EventBus.quest_completed.emit(quest_id, outcome)
	Log.info("Quests", "completed %s%s" % [quest_id, (" (%s)" % outcome) if outcome != "" else ""])


func fail(quest_id: String, reason: String = "") -> void:
	if not is_active(quest_id):
		return
	var rec: Dictionary = quests[quest_id]
	rec["state"] = "failed"
	rec["outcome"] = reason
	var entries: Array = rec["journal"]
	entries.append("Left undone. %s" % reason if reason != "" else "Left undone.")
	EventBus.quest_completed.emit(quest_id, "failed")
	Log.info("Quests", "failed %s (%s)" % [quest_id, reason])


func abandon(quest_id: String) -> void:
	fail(quest_id, "abandoned")


func _grant_rewards(quest_id: String) -> void:
	var rewards: Variant = definition(quest_id).get("rewards", {})
	if typeof(rewards) != TYPE_DICTIONARY or ctx == null:
		return
	var r: Dictionary = rewards
	if int(r.get("marks", 0)) != 0:
		ctx.add_marks(int(r["marks"]))
	if int(r.get("renown", 0)) != 0:
		ctx.add_renown(int(r["renown"]), "quest:" + quest_id)
	if int(r.get("morality", 0)) != 0:
		ctx.add_morality(int(r["morality"]), "quest:" + quest_id)
	for entry in r.get("items", []):
		if typeof(entry) == TYPE_ARRAY and entry.size() >= 2:
			ctx.give_item(str(entry[0]), int(entry[1]))
		elif typeof(entry) == TYPE_STRING:
			ctx.give_item(str(entry), 1)
	for entry in r.get("rep", []):
		if typeof(entry) == TYPE_ARRAY and entry.size() >= 2:
			ctx.add_reputation(str(entry[0]), int(entry[1]), "quest:" + quest_id)
	var deed := str(r.get("deed", ""))
	if deed == "":
		deed = _layer_deed(str(definition(quest_id).get("layer", "side")))
	if deed != "":
		ctx.apply_deed(deed, r.get("witnesses", []))
	Effects.apply_all(r.get("effects", []), ctx, "quest_reward")


static func _layer_deed(layer: String) -> String:
	match layer:
		"main":
			return "quest_complete_main"
		"faction":
			return "quest_complete_faction"
		"radiant":
			return "quest_complete_radiant"
		"side":
			return "quest_complete_side"
		_:
			return ""


func _run_effects(quest_id: String, effects: Variant, reason: String) -> void:
	if ctx == null:
		if typeof(effects) == TYPE_ARRAY and not (effects as Array).is_empty():
			Log.warn("Quests", "%s: effects lost, no context bound" % quest_id)
		return
	Effects.apply_all(effects, ctx, reason)


# --- queries ------------------------------------------------------------------------------------

func is_active(quest_id: String) -> bool:
	return str(quests.get(quest_id, {}).get("state", "")) == "active"


func is_completed(quest_id: String) -> bool:
	return str(quests.get(quest_id, {}).get("state", "")) == "completed"


func is_failed(quest_id: String) -> bool:
	return str(quests.get(quest_id, {}).get("state", "")) == "failed"


func is_known(quest_id: String) -> bool:
	return quests.has(quest_id) and str(quests[quest_id].get("state", "")) != ""


func stage_of(quest_id: String) -> int:
	return int(quests.get(quest_id, {}).get("stage", -1))


func stage_id_of(quest_id: String) -> String:
	return str(quests.get(quest_id, {}).get("stage_id", ""))


func outcome_of(quest_id: String) -> String:
	return str(quests.get(quest_id, {}).get("outcome", ""))


func choice_of(quest_id: String) -> String:
	return str(quests.get(quest_id, {}).get("choices", {}).get(stage_id_of(quest_id), ""))


## [{id, name, layer, journal, objectives:[{text, done, count, needed}], stage, stage_id}]
func active_quests() -> Array[Dictionary]:
	return _list("active")


func completed_quests() -> Array[Dictionary]:
	return _list("completed")


func failed_quests() -> Array[Dictionary]:
	return _list("failed")


func _list(state: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for quest_id in quests:
		if str(quests[quest_id].get("state", "")) != state:
			continue
		out.append(entry(quest_id))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["layer"]) + str(a["name"]) < str(b["layer"]) + str(b["name"]))
	return out


func entry(quest_id: String) -> Dictionary:
	var def := definition(quest_id)
	var rec: Dictionary = quests.get(quest_id, {})
	return {
		"id": quest_id,
		"name": str(def.get("name", quest_id)),
		"layer": str(def.get("layer", "side")),
		"state": str(rec.get("state", "")),
		"stage": int(rec.get("stage", -1)),
		"stage_id": str(rec.get("stage_id", "")),
		"journal": (rec.get("journal", []) as Array).duplicate(),
		"objectives": objectives_of(quest_id),
		"outcome": str(rec.get("outcome", "")),
		"giver": str(def.get("giver", "")),
	}


## The current stage's objectives with progress: [{text, done, count, needed, type, target}].
func objectives_of(quest_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not is_active(quest_id):
		return out
	var index := stage_of(quest_id)
	var stage := stage_def(quest_id, index)
	var objs: Array = stage.get("objectives", [])
	for i in objs.size():
		var o: Dictionary = objs[i]
		if o.get("hidden", false):
			continue
		var needed: int = maxi(1, int(o.get("count", 1)))
		var have := _count_for(quest_id, index, i)
		out.append({
			"text": objective_text(o, quest_id),
			"type": str(o.get("type", "")),
			"target": str(o.get("target", "")),
			"count": mini(have, needed), "needed": needed, "done": have >= needed,
			"optional": bool(o.get("optional", false)),
		})
	return out


## Authored objective text wins; otherwise a plain sentence built from the objective, so a
## generated quest never shows a placeholder.
func objective_text(o: Dictionary, quest_id: String = "") -> String:
	var authored := str(o.get("text", ""))
	if authored != "":
		return ctx.substitute(authored) if ctx != null else authored
	var target := str(o.get("target", ""))
	var count := int(o.get("count", 1))
	var label := _name_of(target)
	match str(o.get("type", "")):
		"talk":
			return "Speak to %s" % label
		"reach":
			return "Go to %s" % label
		"kill":
			return "Kill %s%s" % [label, (" (%d)" % count) if count > 1 else ""]
		"collect":
			return "Gather %s%s" % [label, (" (%d)" % count) if count > 1 else ""]
		"deliver":
			return "Take %s to %s" % [_name_of(str(o.get("item", ""))), label]
		"escort":
			return "See %s safely to %s" % [label, _name_of(str(o.get("place", "")))]
		"choice":
			return "Decide: %s" % label.capitalize()
		"use_item":
			return "Use %s" % label
		"rest_at":
			return "Rest at %s" % label
		"read_book":
			return "Read %s" % label
		_:
			return label if label != "" else str(o.get("type", "do the thing"))


static func _name_of(id: String) -> String:
	if id == "":
		return ""
	var def := ContentDB.get_or_empty(id)
	if def.has("name"):
		return str(def["name"])
	if def.has("title"):
		return str(def["title"])
	return id.get_slice("/", 1).replace("_", " ")


## Approximate areas of interest for the map and compass: never exact pins.
func active_markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for quest_id in quests:
		if not is_active(quest_id):
			continue
		var index := stage_of(quest_id)
		var stage := stage_def(quest_id, index)
		var objs: Array = stage.get("objectives", [])
		for i in objs.size():
			var o: Dictionary = objs[i]
			if _count_for(quest_id, index, i) >= maxi(1, int(o.get("count", 1))):
				continue
			var marker := marker_for(o)
			if marker.is_empty():
				continue
			marker["quest_id"] = quest_id
			marker["text"] = objective_text(o, quest_id)
			out.append(marker)
		var stage_marker: Variant = stage.get("marker")
		if typeof(stage_marker) == TYPE_DICTIONARY:
			var m: Dictionary = (stage_marker as Dictionary).duplicate()
			m["quest_id"] = quest_id
			if not m.has("radius"):
				m["radius"] = MARKER_RADIUS_M
			m["text"] = str(stage.get("journal", ""))
			out.append(m)
	return out


## {place_id, radius} for an objective, or {} when the world should not help you.
func marker_for(o: Dictionary) -> Dictionary:
	var explicit: Variant = o.get("marker")
	if typeof(explicit) == TYPE_DICTIONARY:
		var m: Dictionary = (explicit as Dictionary).duplicate()
		if not m.has("radius"):
			m["radius"] = MARKER_RADIUS_M
		return m
	var candidates: Array[String] = []
	for key in ["place", "target"]:
		var v := str(o.get(key, ""))
		if v != "":
			candidates.append(v)
	for id in candidates:
		var type := Ids.type_of(id)
		if type == "place" or type == "poi":
			return {"place_id": id, "radius": float(o.get("radius", MARKER_RADIUS_M))}
		if type == "npc":
			var home := str(ContentDB.get_or_empty(id).get("home_place", ""))
			if home != "":
				return {"place_id": home, "radius": MARKER_RADIUS_M}
	var region := str(o.get("region", ""))
	if region != "":
		return {"region_id": region, "radius": REGION_MARKER_RADIUS_M}
	return {}


# --- progress -------------------------------------------------------------------------------------

func _key(stage_index: int, obj_index: int) -> String:
	return "%d:%d" % [stage_index, obj_index]


func _count_for(quest_id: String, stage_index: int, obj_index: int) -> int:
	return int(quests.get(quest_id, {}).get("counts", {}).get(_key(stage_index, obj_index), 0))


## Adds progress to one objective of the quest's current stage.
func _progress(quest_id: String, obj_index: int, amount: int = 1, absolute := false) -> void:
	if not is_active(quest_id) or amount == 0:
		return
	var rec: Dictionary = quests[quest_id]
	var index := int(rec["stage"])
	var counts: Dictionary = rec["counts"]
	var key := _key(index, obj_index)
	var before := int(counts.get(key, 0))
	var after: int = amount if absolute else before + amount
	var o := _objective(quest_id, index, obj_index)
	var needed: int = maxi(1, int(o.get("count", 1)))
	after = clampi(after, 0, needed)
	if after == before:
		return
	counts[key] = after
	if after >= needed:
		Log.info("Quests", "%s: objective '%s' done" % [quest_id, objective_text(o, quest_id)])
		_run_effects(quest_id, o.get("on_complete", []), "objective_complete")
	_check_stage_complete(quest_id)


func _objective(quest_id: String, stage_index: int, obj_index: int) -> Dictionary:
	var objs: Array = stage_def(quest_id, stage_index).get("objectives", [])
	if obj_index < 0 or obj_index >= objs.size():
		return {}
	return objs[obj_index]


## Completes an objective by index, by type:target, or by its `key` field. Used by dialogue
## effects: {"complete_objective": [quest_id, "talk:core:npc/hesk"]} or [quest_id, 0].
func complete_objective(quest_id: String, key: Variant) -> void:
	if not is_active(quest_id):
		return
	var index := stage_of(quest_id)
	var objs: Array = stage_def(quest_id, index).get("objectives", [])
	if typeof(key) == TYPE_INT or typeof(key) == TYPE_FLOAT:
		_progress(quest_id, int(key), maxi(1, int(_objective(quest_id, index, int(key)).get("count", 1))), true)
		return
	var wanted := str(key)
	for i in objs.size():
		var o: Dictionary = objs[i]
		var id_match: bool = str(o.get("key", "")) == wanted or str(o.get("target", "")) == wanted
		var type_match: bool = ("%s:%s" % [str(o.get("type", "")), str(o.get("target", ""))]) == wanted
		if id_match or type_match:
			_progress(quest_id, i, maxi(1, int(o.get("count", 1))), true)
			return
	Log.warn("Quests", "%s: no objective matching '%s' in stage %d (content problem)" % [quest_id, wanted, index])


## Forgets a finished quest so a repeatable one can be taken again (boards re-post work).
func forget(quest_id: String) -> void:
	quests.erase(quest_id)


## Records a choice (the `choice` objective type) and completes the matching objective.
##
## An option is authored either as a plain id, with its consequences in the objective's
## `effects_by_option`, or as an object carrying its own `text`, `conditions` and `effects`.
## Both shapes are answered here. Only the first was, which meant a quest whose options were
## written the second way could never be decided at all: `["a", "b"].has(option)` is false for
## a list of objects, so the objective never closed and the option's own effects never ran.
func choose(quest_id: String, option: String) -> void:
	if not is_active(quest_id):
		return
	var index := stage_of(quest_id)
	var objs: Array = stage_def(quest_id, index).get("objectives", [])
	for i in objs.size():
		var o: Dictionary = objs[i]
		if str(o.get("type", "")) != "choice":
			continue
		if not offers_option(o, option):
			continue
		var chosen := option_def(o, option)
		if ctx != null and not Conditions.all_of(chosen.get("conditions", []), ctx):
			Log.info("Quests", "%s: option '%s' is not open (its conditions are unmet)" % [quest_id, option])
			return
		var rec: Dictionary = quests[quest_id]
		(rec["choices"] as Dictionary)[stage_id_of(quest_id)] = option
		rec["outcome"] = option
		# The option's own effects run before the objective closes, because a branching quest
		# says where to go next in them, and a stage that has already advanced cannot be sent.
		_run_effects(quest_id, chosen.get("effects", []), "quest_choice")
		var per_option: Variant = o.get("effects_by_option", {})
		if typeof(per_option) == TYPE_DICTIONARY and (per_option as Dictionary).has(option):
			_run_effects(quest_id, per_option[option], "quest_choice")
		if stage_of(quest_id) == index:
			_progress(quest_id, i, 1, true)
		return
	Log.warn("Quests", "%s: no choice objective in stage %d offers '%s' (content problem)" % [quest_id, index, option])


## Does this choice objective offer that option? True for a plain-id list, for a list of option
## objects whose `id` matches, and for an objective that names the option as its own `target`.
static func offers_option(objective: Dictionary, option: String) -> bool:
	var options: Variant = objective.get("options", [])
	if typeof(options) != TYPE_ARRAY or (options as Array).is_empty():
		return true
	if str(objective.get("target", "")) == option:
		return true
	for entry in options as Array:
		if typeof(entry) == TYPE_DICTIONARY:
			if str((entry as Dictionary).get("id", "")) == option:
				return true
		elif str(entry) == option:
			return true
	return false


## The option object for an id, or {} when the options are authored as plain ids.
static func option_def(objective: Dictionary, option: String) -> Dictionary:
	for entry in objective.get("options", []):
		if typeof(entry) == TYPE_DICTIONARY and str((entry as Dictionary).get("id", "")) == option:
			return entry
	return {}


## The options of this stage's choice objective that are open right now, in authored order:
## [{id, text}]. What a dialogue or the journal should offer, rather than every option written.
func open_options(quest_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for o in stage_def(quest_id, stage_of(quest_id)).get("objectives", []):
		if str((o as Dictionary).get("type", "")) != "choice":
			continue
		for entry in (o as Dictionary).get("options", []):
			if typeof(entry) != TYPE_DICTIONARY:
				out.append({"id": str(entry), "text": str(entry)})
				continue
			var option: Dictionary = entry
			if ctx != null and not Conditions.all_of(option.get("conditions", []), ctx):
				continue
			out.append({"id": str(option.get("id", "")), "text": str(option.get("text", ""))})
	return out


## Marks a delivery made (dialogue usually does this through complete_objective).
func deliver(quest_id: String, npc_id: String) -> void:
	complete_objective(quest_id, "deliver:%s" % npc_id)


## A line in a quest's journal that no stage wrote: something that happened on the way (Escorts
## writes who was left behind where). The same line twice running is written once.
func note(quest_id: String, line: String) -> void:
	if not quests.has(quest_id) or line.strip_edges() == "":
		return
	var entries: Array = quests[quest_id]["journal"]
	if entries.is_empty() or str(entries[entries.size() - 1]) != line:
		entries.append(line)


## Is objective `index` of this quest's current stage done?
func objective_done(quest_id: String, index: int) -> bool:
	if not is_active(quest_id):
		return false
	var at := stage_of(quest_id)
	return _count_for(quest_id, at, index) >= maxi(1, int(_objective(quest_id, at, index).get("count", 1)))


## The objectives of every active quest's current stage, of one type or of all:
## [{quest_id, stage, index, objective, done}]. What another system reads to see what the
## journal is waiting for, without reaching into the records.
func current_objectives(type := "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for quest_id in quests.keys():
		if not is_active(quest_id):
			continue
		var at := stage_of(quest_id)
		var objectives: Array = stage_def(quest_id, at).get("objectives", [])
		for i in objectives.size():
			var o: Dictionary = objectives[i]
			if type != "" and str(o.get("type", "")) != type:
				continue
			out.append({"quest_id": str(quest_id), "stage": at, "index": i, "objective": o,
					"done": _count_for(quest_id, at, i) >= maxi(1, int(o.get("count", 1)))})
	return out


## The open options of every choice this NPC hosts and nobody wrote a button for, as
## [{quest_id, id, text}] — what the dialogue runner offers at their hub (see QuestRoutes).
func unwritten_choices_for(npc_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if npc_id == "":
		return out
	for entry in current_objectives("choice"):
		if bool(entry["done"]):
			continue
		var quest_id: String = entry["quest_id"]
		var stage := stage_def(quest_id, int(entry["stage"]))
		var objective: Dictionary = entry["objective"]
		if QuestRoutes.dialogue_offers(quest_id, objective):
			continue
		if QuestRoutes.host_of(definition(quest_id), stage, objective) != npc_id:
			continue
		for option in open_options(quest_id):
			out.append({"quest_id": quest_id, "id": str(option["id"]), "text": str(option["text"])})
	return out


func _check_stage_complete(quest_id: String) -> void:
	if not is_active(quest_id):
		return
	var index := stage_of(quest_id)
	var stage := stage_def(quest_id, index)
	var objs: Array = stage.get("objectives", [])
	if objs.is_empty():
		# An empty stage waits for a dialogue or a script to move it on, unless it is marked
		# "auto": a closing stage whose only job is to say what happened.
		if bool(stage.get("auto", false)):
			advance(quest_id)
		return
	for i in objs.size():
		var o: Dictionary = objs[i]
		if bool(o.get("optional", false)):
			continue
		if _count_for(quest_id, index, i) < maxi(1, int(o.get("count", 1))):
			return
	if bool(stage.get("manual_advance", false)):
		return
	advance(quest_id)


## Re-reads objectives that can be satisfied by state rather than by an event (collect, reach,
## read_book), so entering a stage with the goods already in your pack completes it.
func _sync_stage(quest_id: String) -> void:
	if not is_active(quest_id):
		return
	var index := stage_of(quest_id)
	var objs: Array = stage_def(quest_id, index).get("objectives", [])
	for i in objs.size():
		var o: Dictionary = objs[i]
		match str(o.get("type", "")):
			"collect":
				if ctx != null and ctx.has_inventory():
					var have := ctx.item_count(str(o.get("target", "")))
					if have > 0:
						_progress(quest_id, i, have, true)
			"read_book":
				if ctx != null and ctx.has_read(str(o.get("target", ""))):
					_progress(quest_id, i, 1, true)
			"reach":
				if ctx != null and ctx.is_discovered(str(o.get("target", ""))):
					_progress(quest_id, i, 1, true)
			_:
				pass
	check_reach()


# --- event tracking ---------------------------------------------------------------------------------

func _for_each_objective(type: String, fn: Callable) -> void:
	for quest_id in quests.keys():
		if not is_active(quest_id):
			continue
		var index := stage_of(quest_id)
		var objs: Array = stage_def(quest_id, index).get("objectives", [])
		for i in objs.size():
			var o: Dictionary = objs[i]
			if str(o.get("type", "")) != type:
				continue
			if _count_for(quest_id, index, i) >= maxi(1, int(o.get("count", 1))):
				continue
			fn.call(quest_id, i, o)


## True when an objective's target matches an id: "" matches anything, "tag:x" matches a def's
## tags, otherwise ids must be equal.
static func _matches(target: String, id: String, def: Dictionary = {}) -> bool:
	if target == "" or target == "any":
		return true
	if target.begins_with("tag:"):
		var tag := target.substr(4)
		var tags: Variant = def.get("tags", [])
		return typeof(tags) == TYPE_ARRAY and (tags as Array).has(tag)
	return target == id


func _on_entity_killed(_victim: Node, _killer: Node, enemy_id: String) -> void:
	var def := ContentDB.get_or_empty(enemy_id)
	_for_each_objective("kill", func(quest_id: String, i: int, o: Dictionary) -> void:
		if _matches(str(o.get("target", "")), enemy_id, def):
			_progress(quest_id, i, 1))


func _on_item_acquired(item_id: String, count: int) -> void:
	var def := ContentDB.get_or_empty(item_id)
	_for_each_objective("collect", func(quest_id: String, i: int, o: Dictionary) -> void:
		if _matches(str(o.get("target", "")), item_id, def):
			_progress(quest_id, i, maxi(1, count)))


func _on_place_discovered(place_id: String) -> void:
	_for_each_objective("reach", func(quest_id: String, i: int, o: Dictionary) -> void:
		if str(o.get("target", "")) == place_id:
			_progress(quest_id, i, 1))


func _on_dialogue_ended(npc_id: String) -> void:
	_for_each_objective("talk", func(quest_id: String, i: int, o: Dictionary) -> void:
		if _matches(str(o.get("target", "")), npc_id):
			_progress(quest_id, i, 1))
	_hand_over(npc_id)


## A delivery closes when you have spoken to the person it is for while carrying what they are
## owed; the goods change hands then. Five of the pack's deliveries had no line anywhere to hand
## the thing over on — the letter to the Circle, Aud's bell to Cadwen, the Fennick bell, the press
## screw, the three loaves — so they could never close. Where an author did write the hand-over
## (Nan Greyfold's basket, Tessane's lantern on the lectern) this stands aside for it.
func _hand_over(npc_id: String) -> void:
	if npc_id == "":
		return
	for entry in current_objectives("deliver"):
		if bool(entry["done"]):
			continue
		var quest_id: String = entry["quest_id"]
		var o: Dictionary = entry["objective"]
		if str(o.get("target", "")) != npc_id or not is_active(quest_id) or stage_of(quest_id) != int(entry["stage"]):
			continue
		if QuestRoutes.dialogue_closes(quest_id, stage_def(quest_id, int(entry["stage"])), int(entry["index"])):
			continue
		var needed: int = maxi(1, int(o.get("count", 1)))
		var item := str(o.get("item", ""))
		if item != "":
			if ctx == null or ctx.item_count(item) < needed:
				continue
			ctx.take_item(item, needed)
		Log.info("Quests", "%s: handed over to %s" % [quest_id, npc_id])
		_progress(quest_id, int(entry["index"]), needed, true)


func _on_hearthstone_rested(hearthstone_id: String) -> void:
	_for_each_objective("rest_at", func(quest_id: String, i: int, o: Dictionary) -> void:
		if _matches(str(o.get("target", "")), hearthstone_id):
			_progress(quest_id, i, 1))


func _on_book_opened(book_id: String) -> void:
	_for_each_objective("read_book", func(quest_id: String, i: int, o: Dictionary) -> void:
		if _matches(str(o.get("target", "")), book_id):
			_progress(quest_id, i, 1))


func _on_item_used(item_id: String, _effects: Array = []) -> void:
	_for_each_objective("use_item", func(quest_id: String, i: int, o: Dictionary) -> void:
		if _matches(str(o.get("target", "")), item_id):
			_progress(quest_id, i, 1))


func _on_escort_arrived(npc_id: String, place_id: String) -> void:
	_for_each_objective("escort", func(quest_id: String, i: int, o: Dictionary) -> void:
		if _matches(str(o.get("target", "")), npc_id):
			var want := str(o.get("place", ""))
			if want == "" or want == place_id:
				_progress(quest_id, i, 1))


## Where the player is, or nothing at all when what was bound has gone. A body that died and
## was freed, or a scene that changed, leaves this holding a dead reference -- and handing one to
## `can_locate` is a script error, once per stage synced, which is where a hundred and nine of a
## test run's errors came from. A provider that no longer exists is dropped the moment it is
## noticed, so nothing calls through it twice.
func _locator() -> Object:
	if position_provider != null and not is_instance_valid(position_provider):
		position_provider = null
	return position_provider


## Asks the position provider where the player is and completes `reach` objectives in range.
## Also callable directly with a position (tests, teleports).
func check_reach(at: Variant = null) -> void:
	var pos: Vector3
	var provider := _locator()
	if typeof(at) == TYPE_VECTOR3:
		pos = at
	elif provider != null and SocialContext.can_locate(provider):
		pos = SocialContext.position_of(provider)
	else:
		return
	_for_each_objective("reach", func(quest_id: String, i: int, o: Dictionary) -> void:
		var target := str(o.get("target", ""))
		var place := ContentDB.get_or_empty(target)
		var p: Array = place.get("position", [])
		if p.size() < 2:
			return
		var radius := float(o.get("radius", REACH_RADIUS_M))
		if Vector2(float(p[0]), float(p[1])).distance_to(Vector2(pos.x, pos.z)) <= radius:
			_progress(quest_id, i, 1))


# --- housekeeping -------------------------------------------------------------------------------

static func _blank_record(quest_id: String) -> Dictionary:
	return {
		"id": quest_id, "stage": -1, "stage_id": "", "counts": {}, "journal": [],
		"started_day": 0, "state": "", "outcome": "", "choices": {}, "runtime": {},
	}


func reset_for_new_game() -> void:
	quests.clear()
	# The generated quests live here; the boards that generated them live there. Clearing one
	# and not the other left boards holding notices this log had never heard of.
	if radiant != null and radiant.has_method("reset_for_new_game"):
		radiant.reset_for_new_game()


# --- save --------------------------------------------------------------------------------------

func to_save() -> Dictionary:
	var out: Dictionary = {"quests": quests.duplicate(true)}
	if radiant != null:
		out["radiant"] = radiant.to_save()
	return out


func from_save(d: Dictionary) -> void:
	quests.clear()
	if radiant != null:
		radiant.from_save(d.get("radiant", {}))
	var saved: Dictionary = d.get("quests", {})
	for quest_id in saved:
		var rec: Dictionary = _blank_record(str(quest_id))
		rec.merge(saved[quest_id] as Dictionary, true)
		rec["counts"] = (rec.get("counts", {}) as Dictionary).duplicate(true)
		rec["journal"] = (rec.get("journal", []) as Array).duplicate()
		rec["choices"] = (rec.get("choices", {}) as Dictionary).duplicate(true)
		rec["runtime"] = (rec.get("runtime", {}) as Dictionary).duplicate(true)
		quests[str(quest_id)] = rec
