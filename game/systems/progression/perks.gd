class_name Perks
extends RefCounted
## Taken perks and the rules for taking them.
##
## A perk def (core:perk/*) is {name, skill, requires_level, effects: [modifier dicts],
## requires_perk?, ranks?}. A perk is available when its skill is at `requires_level` and its
## prerequisite perk (if any) is taken. Taking one costs a perk point (Leveling holds those).
## `modifiers()` returns every taken perk's effects for Modifiers.set_source("perks", ...).
## Pure logic: no nodes, no signals.

const PERK_TYPE := "perk"

var taken: Array[String] = []


func reset() -> void:
	taken.clear()


# --- definitions -------------------------------------------------------------------------

static func all_ids() -> Array[String]:
	return ContentDB.ids_of(PERK_TYPE)


static func def(perk_id: String) -> Dictionary:
	return ContentDB.get_or_empty(perk_id)


## Perk ids belonging to a skill, ordered by required level.
static func ids_for_skill(skill_id: String) -> Array[String]:
	var defs := ContentDB.where(PERK_TYPE, "skill", skill_id).duplicate()
	defs.sort_custom(func(a, b) -> bool:
		var la := int(a.get("requires_level", 0))
		var lb := int(b.get("requires_level", 0))
		if la != lb:
			return la < lb
		return str(a["id"]) < str(b["id"]))
	var out: Array[String] = []
	for d in defs:
		out.append(str(d["id"]))
	return out


# --- state -------------------------------------------------------------------------------

func has(perk_id: String) -> bool:
	return taken.has(perk_id)


func count() -> int:
	return taken.size()


## Why a perk cannot be taken: "" when it can. Reasons: unknown_perk, already_taken,
## skill_too_low, missing_prerequisite.
func blocker(perk_id: String, skills: Skills) -> String:
	var d := def(perk_id)
	if d.is_empty():
		return "unknown_perk"
	if has(perk_id):
		return "already_taken"
	var skill_id := str(d.get("skill", ""))
	if skills != null and skills.level(skill_id) < int(d.get("requires_level", 0)):
		return "skill_too_low"
	var prereq := str(d.get("requires_perk", ""))
	if prereq != "" and not has(prereq):
		return "missing_prerequisite"
	return ""


func can_take(perk_id: String, skills: Skills) -> bool:
	return blocker(perk_id, skills) == ""


## Records a perk as taken (the caller spends the point). Returns false if it may not be taken.
func take(perk_id: String, skills: Skills) -> bool:
	if not can_take(perk_id, skills):
		return false
	taken.append(perk_id)
	return true


## Removes a perk (respec, console). Perks depending on it are removed too; returns the ids removed.
func untake(perk_id: String) -> Array[String]:
	var removed: Array[String] = []
	if not has(perk_id):
		return removed
	taken.erase(perk_id)
	removed.append(perk_id)
	var again := true
	while again:
		again = false
		for t in taken.duplicate():
			var prereq := str(def(t).get("requires_perk", ""))
			if prereq != "" and not has(prereq):
				taken.erase(t)
				removed.append(t)
				again = true
	return removed


# --- output ----------------------------------------------------------------------------

## Modifier dicts from every taken perk, tagged with the perk's name as their source label.
func modifiers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in taken:
		var d := def(id)
		for e in d.get("effects", []):
			if typeof(e) != TYPE_DICTIONARY:
				continue
			var m: Dictionary = e.duplicate(true)
			m["source"] = str(d.get("name", id))
			out.append(m)
	return out


## [{id, name, description, skill, requires_level, requires_perk, effects, taken, available, blocker}]
## for one skill's perk tree, or for every perk when skill_id is empty.
func summaries(skill_id: String, skills: Skills) -> Array[Dictionary]:
	var ids := ids_for_skill(skill_id) if skill_id != "" else all_ids()
	var out: Array[Dictionary] = []
	for id in ids:
		var d := def(id)
		var why := blocker(id, skills)
		out.append({
			"id": id, "name": str(d.get("name", id)), "description": str(d.get("description", "")),
			"skill": str(d.get("skill", "")), "requires_level": int(d.get("requires_level", 0)),
			"requires_perk": str(d.get("requires_perk", "")), "effects": d.get("effects", []).duplicate(true),
			"taken": has(id), "available": why == "", "blocker": why,
		})
	return out


func to_save() -> Dictionary:
	return {"taken": taken.duplicate()}


func from_save(d: Dictionary) -> void:
	taken.clear()
	for id in d.get("taken", []):
		var s := str(id)
		if ContentDB.has(s) and not taken.has(s):
			taken.append(s)
		elif not ContentDB.has(s):
			Log.warn("Perks", "dropping unknown perk '%s' from save" % s)
