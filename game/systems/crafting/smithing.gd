class_name Smithing
extends RefCounted
## Forge work: recipes (core:recipe/*) and tempering.
##
## A recipe is {station, inputs: [{item, count}], output: {item, count}, skill, requires_level,
## xp, known_by_default}. Crafting consumes the inputs from an Inventory, adds the output and
## returns the XP earned. `Modifiers` (from Progression) trims material cost
## (smithing_material_cost) and widens the temper step (temper_bonus).
##
## Tempering raises a specific ItemStack's `temper` tier: +10% to damage and armour per tier
## (ItemStack.effective_weapon/effective_armour apply it). A tier costs one unit of the item's
## `material` per tier reached, and the smithing level gates how far anything can be tempered.
## Pure logic over an Inventory: no nodes, no signals. Crafting owns an instance.

const RECIPE_TYPE := "recipe"
const MAX_TEMPER := 5
const TEMPER_LEVEL_PER_TIER := 15   # smithing level needed per temper tier
const TEMPER_XP := 15.0
const DEFAULT_TEMPER_MATERIAL := "core:item/iron_ingot"


static func all_recipes() -> Array:
	return ContentDB.all(RECIPE_TYPE)


static func def(recipe_id: String) -> Dictionary:
	return ContentDB.get_or_empty(recipe_id)


## Recipes for a station ("forge", "alembic", "name_table", "tanning_rack"...).
static func recipes_at(station: String) -> Array[String]:
	var out: Array[String] = []
	for d in ContentDB.where(RECIPE_TYPE, "station", station):
		out.append(str(d["id"]))
	out.sort()
	return out


static func recipes_known_by_default() -> Array[String]:
	var out: Array[String] = []
	for d in all_recipes():
		if bool(d.get("known_by_default", false)):
			out.append(str(d["id"]))
	out.sort()
	return out


# --- material cost ----------------------------------------------------------------------

## A recipe's inputs after the smithing_material_cost modifier (never below one of each).
static func inputs_for(recipe_id: String, mods: Modifiers = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var scale := 1.0 if mods == null else mods.get_mult("smithing_material_cost")
	for i in def(recipe_id).get("inputs", []):
		if typeof(i) != TYPE_DICTIONARY:
			continue
		var n := int(ceil(float(i.get("count", 1)) * scale))
		out.append({"item": str(i.get("item", "")), "count": maxi(1, n)})
	return out


## Inputs missing from an inventory: [{item, count, have}] (empty when everything is there).
static func missing_inputs(recipe_id: String, inventory: Inventory, mods: Modifiers = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if inventory == null:
		return out
	for i in inputs_for(recipe_id, mods):
		var have := inventory.count(str(i["item"]))
		if have < int(i["count"]):
			out.append({"item": i["item"], "count": int(i["count"]), "have": have})
	return out


## Why a recipe cannot be crafted: "" when it can. Reasons: unknown_recipe, unknown_recipe_output,
## wrong_station, not_known, skill_too_low, missing_materials, no_inventory.
static func blocker(recipe_id: String, inventory: Inventory, skill_level: int, station: String = "", known: bool = true, mods: Modifiers = null) -> String:
	var d := def(recipe_id)
	if d.is_empty():
		return "unknown_recipe"
	if not ContentDB.has(str(d.get("output", {}).get("item", ""))):
		return "unknown_recipe_output"
	if station != "" and str(d.get("station", "")) != station:
		return "wrong_station"
	if not known:
		return "not_known"
	if skill_level < int(d.get("requires_level", 0)):
		return "skill_too_low"
	if inventory == null:
		return "no_inventory"
	if not missing_inputs(recipe_id, inventory, mods).is_empty():
		return "missing_materials"
	return ""


## Consumes the inputs and adds the output. Returns {ok, item, count, xp, reason}.
static func craft(recipe_id: String, inventory: Inventory, skill_level: int, station: String = "", known: bool = true, mods: Modifiers = null) -> Dictionary:
	var why := blocker(recipe_id, inventory, skill_level, station, known, mods)
	if why != "":
		return {"ok": false, "reason": why, "item": "", "count": 0, "xp": 0.0}
	var d := def(recipe_id)
	for i in inputs_for(recipe_id, mods):
		inventory.remove(str(i["item"]), int(i["count"]))
	var out: Dictionary = d.get("output", {})
	var item := str(out.get("item", ""))
	var count := int(out.get("count", 1))
	var data: Dictionary = out.get("data", {}) if typeof(out.get("data", {})) == TYPE_DICTIONARY else {}
	inventory.add(item, count, data)
	return {"ok": true, "reason": "", "item": item, "count": count, "xp": float(d.get("xp", 10.0))}


# --- tempering ---------------------------------------------------------------------------

## Highest temper tier a smithing level allows.
static func max_tier_for_level(skill_level: int) -> int:
	return clampi(1 + int(skill_level / TEMPER_LEVEL_PER_TIER), 0, MAX_TEMPER)


## Improvement per temper tier: 10%, raised by the temper_bonus modifier (the Red Door perk).
static func bonus_per_tier(mods: Modifiers = null) -> float:
	return ItemStack.TEMPER_BONUS_PER_TIER + (0.0 if mods == null else mods.get_add("temper_bonus"))


## The material a stack is tempered with: its def's `material`, else iron.
static func temper_material(stack: ItemStack) -> String:
	var m := str(stack.def().get("material", ""))
	return m if ContentDB.has(m) else DEFAULT_TEMPER_MATERIAL


## Units of material to reach the next tier (one per tier reached, trimmed by the thrift perk).
static func temper_cost(stack: ItemStack, mods: Modifiers = null) -> int:
	var tier := stack.temper_tier() + 1
	var scale := 1.0 if mods == null else mods.get_mult("smithing_material_cost")
	return maxi(1, int(ceil(float(tier) * scale)))


## Why a stack cannot be tempered: "" when it can. Reasons: no_item, not_temperable,
## max_temper, skill_too_low, missing_materials, no_inventory.
static func temper_blocker(stack: ItemStack, inventory: Inventory, skill_level: int, mods: Modifiers = null) -> String:
	if stack == null:
		return "no_item"
	if not stack.is_weapon() and not stack.is_armour():
		return "not_temperable"
	if stack.temper_tier() >= MAX_TEMPER:
		return "max_temper"
	if stack.temper_tier() + 1 > max_tier_for_level(skill_level):
		return "skill_too_low"
	if inventory == null:
		return "no_inventory"
	if inventory.count(temper_material(stack)) < temper_cost(stack, mods):
		return "missing_materials"
	return ""


## Raises a stack's temper tier by one, consuming material. Tempering splits a stacked item so
## only the tempered unit changes. Returns {ok, reason, stack, tier, xp}.
static func temper(stack: ItemStack, inventory: Inventory, skill_level: int, mods: Modifiers = null) -> Dictionary:
	var why := temper_blocker(stack, inventory, skill_level, mods)
	if why != "":
		return {"ok": false, "reason": why, "stack": null, "tier": 0, "xp": 0.0}
	var material := temper_material(stack)
	inventory.remove(material, temper_cost(stack, mods))
	var target := stack
	if stack.count > 1:
		var split := stack.split(1)
		inventory.notify_changed(stack)
		target = inventory.add(split.id, 1, split.data)
	var tier := target.temper_tier() + 1
	target.data["temper"] = tier
	inventory.notify_changed(target)
	return {"ok": true, "reason": "", "stack": target, "tier": tier, "xp": TEMPER_XP * tier}


## [{id, name, station, inputs, output, output_name, requires_level, can_craft, missing, blocker}]
## for the forge screen.
static func summaries(recipe_ids: Array, inventory: Inventory, skill_level: int, station: String = "", known_ids: Array = [], mods: Modifiers = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw in recipe_ids:
		var id := str(raw)
		var d := def(id)
		if d.is_empty():
			continue
		var known := known_ids.is_empty() or known_ids.has(id)
		var why := blocker(id, inventory, skill_level, station, known, mods)
		var output: Dictionary = d.get("output", {})
		out.append({
			"id": id, "name": str(d.get("name", id)), "station": str(d.get("station", "")),
			"inputs": inputs_for(id, mods), "output": output.duplicate(true),
			"output_name": str(ContentDB.get_or_empty(str(output.get("item", ""))).get("name", "")),
			"requires_level": int(d.get("requires_level", 0)), "skill": str(d.get("skill", "smithing")),
			"can_craft": why == "", "blocker": why, "missing": missing_inputs(id, inventory, mods),
		})
	return out
