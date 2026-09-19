class_name QuestConditions
extends RefCounted
## Quest conditions glue: the small layer between quest data and the dialogue condition
## vocabulary (systems/dialogue/conditions.gd), so a quest giver, a job board and a journal all
## ask the same question the same way.
##
## A quest definition may carry:
##   "requires": [conditions]    what must be true before it can start
##   "repeatable": true          may be started again after completion (radiant work is)
##   "fails_if": [conditions]    checked while active; true means the quest is lost
##   "hidden_until": [conditions] a giver will not mention it before this is true
## All condition objects are the CONTRACTS §7 vocabulary; unknown ones are content problems, not
## crashes (Conditions logs them through the context).

## Can this quest be started right now?
static func can_start(quest_def: Dictionary, ctx: SocialContext, log_obj: Object = null) -> bool:
	if quest_def.is_empty():
		return false
	if ctx == null:
		return true
	var quest_id := str(quest_def.get("id", ""))
	if log_obj != null and log_obj.has_method("is_completed") and log_obj.is_completed(quest_id):
		if not bool(quest_def.get("repeatable", false)):
			return false
	if log_obj != null and log_obj.has_method("is_active") and log_obj.is_active(quest_id):
		return false
	return Conditions.all_of(quest_def.get("requires", []), ctx)


## Should a giver even bring this up?
static func is_offerable(quest_def: Dictionary, ctx: SocialContext, log_obj: Object = null) -> bool:
	if not can_start(quest_def, ctx, log_obj):
		return false
	if ctx == null:
		return true
	return Conditions.all_of(quest_def.get("hidden_until", []), ctx)


## Has an active quest fallen through? (Checked when the world changes, not every frame.)
static func should_fail(quest_def: Dictionary, ctx: SocialContext) -> bool:
	if quest_def.is_empty() or ctx == null:
		return false
	var fails: Variant = quest_def.get("fails_if", [])
	if typeof(fails) != TYPE_ARRAY or (fails as Array).is_empty():
		return false
	return Conditions.all_of(fails, ctx)


## Quests a giver NPC can offer right now, by their `giver` field.
static func offers_of(npc_id: String, ctx: SocialContext, log_obj: Object = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for def in ContentDB.all("quest"):
		if str(def.get("giver", "")) != npc_id:
			continue
		if is_offerable(def, ctx, log_obj):
			out.append(def)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	return out


## Are the objectives of this stage all satisfied by state alone (no event needed)? Used by the
## log when it enters a stage, and by tests.
static func stage_satisfied(stage: Dictionary, counts: Dictionary, stage_index: int) -> bool:
	var objs: Array = stage.get("objectives", [])
	if objs.is_empty():
		return false
	for i in objs.size():
		var o: Dictionary = objs[i]
		if bool(o.get("optional", false)):
			continue
		var needed: int = maxi(1, int(o.get("count", 1)))
		if int(counts.get("%d:%d" % [stage_index, i], 0)) < needed:
			return false
	return true
