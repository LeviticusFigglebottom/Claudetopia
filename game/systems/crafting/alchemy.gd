class_name Alchemy
extends RefCounted
## Ingredient effects, their discovery, and brewing.
##
## Every ingredient item carries `alchemy.effects`: four effect ids (core:effect/*). The first is
## known as soon as you hold the ingredient; the rest are learned by eating it (each meal reveals
## the next unknown one) or by a successful combine (every ingredient that contributed the shared
## effect learns it).
##
## Combining two or three ingredients looks for effects they share. Every effect shared by at
## least two of them goes into the potion; a mixture with nothing in common is wasted.
## The result is an instance of that effect's content-defined potion template
## (`core:effect/x`.potion, e.g. core:item/potion_restore_health) whose `data` carries the brewed
## effects, the brewed name and the quality, so two brews of the same potion never merge into one
## stack unless they came out identical.
##
## Magnitude scales with the Alchemy skill: `base * (1 + skill/100)` before the potency modifier
## (potion_potency for buffs and restores, poison_potency for harm).
## Discovery state lives here and is saved by Crafting.

const INGREDIENT_EFFECT_COUNT := 4
const SKILL_MAGNITUDE_PER_LEVEL := 0.01
const SKILL_DURATION_PER_LEVEL := 0.005
const MIN_INGREDIENTS := 2
const MAX_INGREDIENTS := 3
const BREW_XP_BASE := 12.0
const EAT_XP := 3.0
const DISCOVERY_XP := 8.0

var discovered: Dictionary = {}   # ingredient item id -> Array[int] of known effect indices


# --- definitions -------------------------------------------------------------------------

static func is_ingredient(item_id: String) -> bool:
	return ContentDB.get_or_empty(item_id).has("alchemy")


## The four effect ids of an ingredient (empty for a non-ingredient).
static func effects_of(item_id: String) -> Array:
	var d := ContentDB.get_or_empty(item_id)
	if not d.has("alchemy"):
		return []
	var e: Variant = d["alchemy"].get("effects", [])
	return e if typeof(e) == TYPE_ARRAY else []


static func effect_def(effect_id: String) -> Dictionary:
	return ContentDB.get_or_empty(effect_id)


static func effect_name(effect_id: String) -> String:
	return str(effect_def(effect_id).get("name", effect_id))


static func is_harmful(effect_id: String) -> bool:
	return str(effect_def(effect_id).get("kind", "")) == "harm"


## The content-defined potion template an effect brews into ("" when it has none, e.g. an
## enchantment-only effect).
static func potion_template(effect_id: String) -> String:
	var id := str(effect_def(effect_id).get("potion", ""))
	return id if ContentDB.has(id) else ""


## Every ingredient in the packs that carries an effect, for a recipe-book screen.
static func ingredients_with(effect_id: String) -> Array[String]:
	var out: Array[String] = []
	for d in ContentDB.all("item"):
		if not d.has("alchemy"):
			continue
		if effects_of(str(d["id"])).has(effect_id):
			out.append(str(d["id"]))
	out.sort()
	return out


# --- discovery ---------------------------------------------------------------------------

## Known effect indices for an ingredient; index 0 is always known.
func known_indices(item_id: String) -> Array[int]:
	var out: Array[int] = [0]
	for i in discovered.get(item_id, []):
		var idx := int(i)
		if idx > 0 and not out.has(idx):
			out.append(idx)
	out.sort()
	return out


## Effect ids known for an ingredient, in slot order.
func known_effects(item_id: String) -> Array[String]:
	var all := effects_of(item_id)
	var out: Array[String] = []
	for i in known_indices(item_id):
		if i < all.size():
			out.append(str(all[i]))
	return out


func knows(item_id: String, effect_id: String) -> bool:
	return known_effects(item_id).has(effect_id)


func is_fully_known(item_id: String) -> bool:
	return known_indices(item_id).size() >= effects_of(item_id).size()


## Records an effect index as discovered. Returns false when it was already known.
func discover_index(item_id: String, index: int) -> bool:
	if index <= 0 or index >= effects_of(item_id).size():
		return false
	var list: Array = discovered.get(item_id, [])
	if list.has(index):
		return false
	list.append(index)
	list.sort()
	discovered[item_id] = list
	return true


## Records a specific effect as discovered. Returns false when unknown to the ingredient or
## already discovered.
func discover_effect(item_id: String, effect_id: String) -> bool:
	var idx := effects_of(item_id).find(effect_id)
	return discover_index(item_id, idx) if idx > 0 else false


## Eating an ingredient: reveals the next unknown effect and returns what happened:
## {ok, index, effect, effects (the ones now applying to the eater), xp}.
func eat(item_id: String) -> Dictionary:
	var all := effects_of(item_id)
	if all.is_empty():
		return {"ok": false, "index": -1, "effect": "", "effects": [], "xp": 0.0}
	var index := -1
	for i in all.size():
		if not known_indices(item_id).has(i):
			index = i
			break
	var learned := index > 0 and discover_index(item_id, index)
	var eff := str(all[0])
	var d := effect_def(eff)
	return {
		"ok": true, "index": index if learned else -1, "effect": str(all[index]) if learned else "",
		"effects": [{"effect": eff, "magnitude": float(d.get("magnitude_base", 0)) * 0.5, "duration": float(d.get("duration_base", 0)) * 0.5}],
		"xp": EAT_XP + (DISCOVERY_XP if learned else 0.0),
	}


# --- brewing -----------------------------------------------------------------------------

## Effects shared by at least two of the given ingredients, in the order they first appear.
static func shared_effects(item_ids: Array) -> Array[String]:
	var seen := {}
	var order: Array[String] = []
	for raw in item_ids:
		var id := str(raw)
		for e in effects_of(id):
			var eid := str(e)
			if not seen.has(eid):
				seen[eid] = []
				order.append(eid)
			if not seen[eid].has(id):
				seen[eid].append(id)
	var out: Array[String] = []
	for eid in order:
		if seen[eid].size() >= 2:
			out.append(eid)
	return out


## Magnitude and duration of one effect brewed at a skill level.
static func brewed_magnitude(effect_id: String, skill_level: int, mods: Modifiers = null) -> Dictionary:
	var d := effect_def(effect_id)
	var skill_scale := 1.0 + float(skill_level) * SKILL_MAGNITUDE_PER_LEVEL
	var potency := 1.0
	if mods != null:
		potency = mods.get_mult("poison_potency" if is_harmful(effect_id) else "potion_potency")
	var magnitude := float(d.get("magnitude_base", 0)) * skill_scale * potency
	var duration := float(d.get("duration_base", 0)) * (1.0 + float(skill_level) * SKILL_DURATION_PER_LEVEL)
	return {"effect": effect_id, "magnitude": snappedf(magnitude, 0.1), "duration": snappedf(duration, 0.1)}


## The name a brew gets: "Potion of X" from the template, plus the secondary effects.
static func brew_name(effects: Array) -> String:
	if effects.is_empty():
		return "Murky Brew"
	var primary := str(effects[0].get("effect", ""))
	var base := str(ContentDB.get_or_empty(potion_template(primary)).get("name", "Potion of " + effect_name(primary)))
	if effects.size() > 1:
		var extra: Array[String] = []
		for i in range(1, effects.size()):
			extra.append(effect_name(str(effects[i].get("effect", ""))))
		base += " (" + ", ".join(extra) + ")"
	return base


## Why a mixture cannot be brewed: "" when it can. Reasons: too_few, too_many, no_inventory,
## not_an_ingredient, missing_ingredient, no_shared_effect, no_potion_template.
func combine_blocker(item_ids: Array, inventory: Inventory) -> String:
	if item_ids.size() < MIN_INGREDIENTS:
		return "too_few"
	if item_ids.size() > MAX_INGREDIENTS:
		return "too_many"
	if inventory == null:
		return "no_inventory"
	var needed := {}
	for raw in item_ids:
		var id := str(raw)
		if not is_ingredient(id):
			return "not_an_ingredient"
		needed[id] = int(needed.get(id, 0)) + 1
	for id in needed:
		if inventory.count(str(id)) < int(needed[id]):
			return "missing_ingredient"
	var shared := shared_effects(item_ids)
	if shared.is_empty():
		return "no_shared_effect"
	if potion_template(shared[0]) == "":
		return "no_potion_template"
	return ""


## Brews a potion from 2–3 ingredients. Consumes them either way (a failed mixture is wasted),
## and on success adds one potion instance and discovers the shared effects in every ingredient
## that carries them.
## Returns {ok, reason, item_id, stack, effects, discovered: [{item, index, effect}], xp}.
func combine(item_ids: Array, inventory: Inventory, skill_level: int = 0, mods: Modifiers = null) -> Dictionary:
	var result := {"ok": false, "reason": "", "item_id": "", "stack": null, "effects": [], "discovered": [], "xp": 0.0}
	var why := combine_blocker(item_ids, inventory)
	if why != "" and why != "no_shared_effect" and why != "no_potion_template":
		result["reason"] = why
		return result
	for raw in item_ids:
		inventory.remove(str(raw), 1)
	if why != "":
		result["reason"] = why
		result["xp"] = BREW_XP_BASE * 0.25
		return result
	var shared := shared_effects(item_ids)
	var effects: Array = []
	for eid in shared:
		if potion_template(eid) != "":
			effects.append(brewed_magnitude(eid, skill_level, mods))
	if effects.is_empty():
		result["reason"] = "no_potion_template"
		return result
	var discoveries: Array = []
	for eid in shared:
		for raw in item_ids:
			var id := str(raw)
			if effects_of(id).has(eid) and discover_effect(id, eid):
				discoveries.append({"item": id, "index": effects_of(id).find(eid), "effect": eid})
	var template := potion_template(str(effects[0]["effect"]))
	var quality := 1.0 + float(skill_level) * SKILL_MAGNITUDE_PER_LEVEL + 0.35 * float(effects.size() - 1)
	var data := {"effects": effects, "name": brew_name(effects), "quality": snappedf(quality, 0.01), "brewed": true}
	var stack := inventory.add(template, 1, data)
	result["ok"] = true
	result["item_id"] = template
	result["stack"] = stack
	result["effects"] = effects
	result["discovered"] = discoveries
	result["xp"] = BREW_XP_BASE * float(effects.size()) + DISCOVERY_XP * float(discoveries.size())
	return result


## [{item_id, name, effects: [{effect, name, known, description}], fully_known}] for the alchemy
## screen: every ingredient in an inventory, with what is known about it.
func summaries(inventory: Inventory) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if inventory == null:
		return out
	var seen := {}
	for s in inventory.query({"category": "ingredient"}):
		if seen.has(s.id):
			continue
		seen[s.id] = true
		var known := known_effects(s.id)
		var effects: Array = []
		for e in effects_of(s.id):
			var eid := str(e)
			var d := effect_def(eid)
			var is_known := known.has(eid)
			effects.append({
				"effect": eid, "name": effect_name(eid) if is_known else "?", "known": is_known,
				"kind": str(d.get("kind", "")) if is_known else "",
				"description": str(d.get("description", "")) if is_known else "",
			})
		out.append({
			"item_id": s.id, "name": s.display_name(), "count": inventory.count(s.id),
			"effects": effects, "fully_known": is_fully_known(s.id),
		})
	return out


func to_save() -> Dictionary:
	return {"discovered": discovered.duplicate(true)}


func from_save(d: Dictionary) -> void:
	discovered.clear()
	var saved: Variant = d.get("discovered", {})
	if typeof(saved) != TYPE_DICTIONARY:
		return
	for item_id in saved:
		if not is_ingredient(str(item_id)):
			continue
		var list: Array = []
		for i in saved[item_id]:
			var idx := int(i)
			if idx > 0 and idx < effects_of(str(item_id)).size() and not list.has(idx):
				list.append(idx)
		list.sort()
		if not list.is_empty():
			discovered[str(item_id)] = list
