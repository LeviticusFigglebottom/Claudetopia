class_name Crafting
extends Node
## The node that owns Smithing, Alchemy and Enchanting for one actor: which recipes and
## enchantments are known, which ingredient effects have been discovered, and the save section
## "crafting".
##
## Add one beside the player's Inventory. It joins the "crafting" group, so the UI and the world's
## stations find it without a node path:
##     var c := get_tree().get_first_node_in_group("crafting")
##     c.recipes_for("forge"); c.craft(id); c.combine([a, b]); c.enchant(stack, effect, motes)
##
## Skill levels and modifiers come from the Progression node in the "progression" group when one
## exists, and crafting XP is awarded back to it. Everything works headless without one.

signal known_changed
signal crafted(recipe_id: String, item_id: String, count: int)
signal brewed(item_id: String, effects: Array)
signal enchanted(item_id: String, effect_id: String)

const GROUP := "crafting"
const SAVE_SECTION := "crafting"
const STATIONS := ["forge", "alembic", "name_table", "tanning_rack", "grindstone"]

@export var inventory_path: NodePath = NodePath("")

var alchemy := Alchemy.new()
var known_recipes: Array[String] = []
var known_enchantments: Array[String] = []
var inventory: Inventory = null


func _ready() -> void:
	add_to_group(GROUP)
	if inventory == null:
		_find_inventory()
	if known_recipes.is_empty():
		learn_default_recipes()
	SaveSystem.register(SAVE_SECTION, self)


func _exit_tree() -> void:
	if SaveSystem.participants.get(SAVE_SECTION) == self:
		SaveSystem.unregister(SAVE_SECTION)


func _find_inventory() -> void:
	if inventory_path != NodePath(""):
		inventory = get_node_or_null(inventory_path) as Inventory
		if inventory != null:
			return
	var parent := get_parent()
	if parent != null:
		for c in parent.get_children():
			if c is Inventory:
				inventory = c
				return
	if is_inside_tree():
		inventory = Inventory.player_bag(get_tree())


func bag() -> Inventory:
	if inventory == null:
		_find_inventory()
	return inventory


func progression() -> Progression:
	return Progression.of(get_tree()) if is_inside_tree() else null


func mods() -> Modifiers:
	var p := progression()
	return p.mods if p != null else null


func skill_level(skill: String) -> int:
	var p := progression()
	return p.skill_level(skill) if p != null else 0


func _award(skill: String, xp: float) -> void:
	if xp <= 0.0:
		return
	EventBus.skill_used.emit(Skills.normalise(skill), xp)


# --- known recipes and enchantments ------------------------------------------------------

func learn_default_recipes() -> void:
	for id in Smithing.recipes_known_by_default():
		if not known_recipes.has(id):
			known_recipes.append(id)
	known_recipes.sort()


## Learns a recipe (a quest reward, a book, a trainer). False when already known or unknown id.
func learn_recipe(recipe_id: String) -> bool:
	if known_recipes.has(recipe_id) or not ContentDB.has(recipe_id):
		return false
	known_recipes.append(recipe_id)
	known_recipes.sort()
	known_changed.emit()
	EventBus.recipe_learned.emit(recipe_id)
	return true


func knows_recipe(recipe_id: String) -> bool:
	return known_recipes.has(recipe_id)


func learn_enchantment(effect_id: String) -> bool:
	if known_enchantments.has(effect_id) or not Enchanting.is_enchantment(effect_id):
		return false
	known_enchantments.append(effect_id)
	known_enchantments.sort()
	known_changed.emit()
	EventBus.enchantment_learned.emit(effect_id)
	return true


func knows_enchantment(effect_id: String) -> bool:
	return known_enchantments.has(effect_id)


# --- smithing ----------------------------------------------------------------------------

## [{id, name, inputs, output, can_craft, missing, ...}] for a station's screen; known recipes first.
func recipes_for(station: String) -> Array[Dictionary]:
	var ids := Smithing.recipes_at(station)
	var summaries := Smithing.summaries(ids, bag(), skill_level("smithing"), station, known_recipes, mods())
	summaries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ka := known_recipes.has(str(a["id"]))
		var kb := known_recipes.has(str(b["id"]))
		if ka != kb:
			return ka
		if a["requires_level"] != b["requires_level"]:
			return int(a["requires_level"]) < int(b["requires_level"])
		return str(a["name"]) < str(b["name"]))
	return summaries


func can_craft(recipe_id: String) -> bool:
	return Smithing.blocker(recipe_id, bag(), skill_level("smithing"), "", knows_recipe(recipe_id), mods()) == ""


## Crafts a known recipe at its own station. Returns true on success.
func craft(recipe_id: String) -> bool:
	var d := Smithing.def(recipe_id)
	var skill := str(d.get("skill", "smithing"))
	var r := Smithing.craft(recipe_id, bag(), skill_level(skill), "", knows_recipe(recipe_id), mods())
	if not r["ok"]:
		return false
	_award(skill, float(r["xp"]))
	crafted.emit(recipe_id, str(r["item"]), int(r["count"]))
	EventBus.item_crafted.emit(recipe_id, str(r["item"]), int(r["count"]))
	return true


## Raises an item's temper tier (+10% per tier, more with the Red Door perk).
## `item` is an item id, a stack uid or an ItemStack. Returns {ok, reason, tier}.
func temper(item: Variant) -> Dictionary:
	var inv := bag()
	var stack := inv.resolve(item) if inv != null else null
	var r := Smithing.temper(stack, inv, skill_level("smithing"), mods())
	if r["ok"]:
		_award("smithing", float(r["xp"]))
	return {"ok": r["ok"], "reason": r["reason"], "tier": r["tier"], "stack": r["stack"]}


func temper_preview(item: Variant) -> Dictionary:
	var inv := bag()
	var stack := inv.resolve(item) if inv != null else null
	if stack == null:
		return {"ok": false, "reason": "no_item"}
	var why := Smithing.temper_blocker(stack, inv, skill_level("smithing"), mods())
	return {
		"ok": why == "", "reason": why, "tier": stack.temper_tier(), "next_tier": stack.temper_tier() + 1,
		"max_tier": Smithing.max_tier_for_level(skill_level("smithing")),
		"material": Smithing.temper_material(stack), "cost": Smithing.temper_cost(stack, mods()),
		"bonus_per_tier": Smithing.bonus_per_tier(mods()),
	}


# --- alchemy -----------------------------------------------------------------------------

## Effect ids known for an ingredient (the first is always known).
func known_effects(item_id: String) -> Array[String]:
	return alchemy.known_effects(item_id)


## Every ingredient in the bag with what is known about it, for the alchemy screen.
func ingredients() -> Array[Dictionary]:
	return alchemy.summaries(bag())


## Eats an ingredient: applies its first effect, may discover the next one. Returns the eat record.
func eat_ingredient(item_id: String) -> Dictionary:
	var inv := bag()
	if inv == null or not inv.has(item_id):
		return {"ok": false, "index": -1, "effect": "", "effects": [], "xp": 0.0}
	var r := alchemy.eat(item_id)
	if not r["ok"]:
		return r
	inv.remove(item_id, 1)
	EventBus.item_used.emit(item_id, r["effects"])
	if int(r["index"]) > 0:
		EventBus.ingredient_effect_discovered.emit(item_id, int(r["index"]))
		known_changed.emit()
	_award("alchemy", float(r["xp"]))
	return r


## Combines 2–3 ingredients into a potion. Returns {ok, item_id, effects, discovered, reason}.
func combine(ingredient_ids: Array) -> Dictionary:
	var r := alchemy.combine(ingredient_ids, bag(), skill_level("alchemy"), mods())
	for d in r["discovered"]:
		EventBus.ingredient_effect_discovered.emit(str(d["item"]), int(d["index"]))
	if not r["discovered"].is_empty():
		known_changed.emit()
	_award("alchemy", float(r["xp"]))
	if r["ok"]:
		brewed.emit(str(r["item_id"]), r["effects"])
		EventBus.item_crafted.emit("", str(r["item_id"]), 1)
	return {"ok": r["ok"], "reason": r["reason"], "item_id": r["item_id"], "effects": r["effects"], "discovered": r["discovered"]}


# --- enchanting --------------------------------------------------------------------------

## Enchantments for the Name-table screen, with `known` on each.
func enchantments() -> Array[Dictionary]:
	return Enchanting.summaries(known_enchantments)


## Destroys an enchanted item to learn its note. `item` is an item id, uid or ItemStack.
func disenchant(item: Variant) -> bool:
	var inv := bag()
	var stack := inv.resolve(item) if inv != null else null
	var r := Enchanting.disenchant(stack, inv, known_enchantments)
	if not r["ok"]:
		return false
	learn_enchantment(str(r["effect"]))
	_award("enchanting", float(r["xp"]))
	return true


## Writes a known note into an item, spending Ember Motes.
func enchant(item: Variant, effect_id: String, motes: int = 2) -> bool:
	var inv := bag()
	var stack := inv.resolve(item) if inv != null else null
	var item_id := stack.id if stack != null else ""
	var r := Enchanting.enchant(stack, effect_id, motes, inv, known_enchantments, skill_level("enchanting"), mods())
	if not r["ok"]:
		return false
	_award("enchanting", float(r["xp"]))
	enchanted.emit(item_id, effect_id)
	EventBus.item_enchanted.emit(item_id, effect_id)
	return true


func enchant_preview(effect_id: String, motes: int = 2) -> Dictionary:
	return Enchanting.preview(effect_id, motes, skill_level("enchanting"), mods())


## Whether a note can be written into an item with this many motes, and if not, why, in words:
## {ok, reason, why}. The Name-table asks before the button is pressed, the way the forge asks
## `temper_preview` -- `Enchanting.enchant_blocker` had seven passing tests and no caller, so a
## refused writing was a button that did nothing.
func enchant_check(item: Variant, effect_id: String, motes: int = 2) -> Dictionary:
	var inv := bag()
	var stack := inv.resolve(item) if inv != null and item != null else null
	var reason := Enchanting.enchant_blocker(stack, effect_id, motes, inv, known_enchantments)
	return {"ok": reason == "", "reason": reason, "why": Enchanting.blocker_text(reason, stack, effect_id, motes, inv)}


## Refills an item's enchantment charge from motes (-1 = as many as it takes).
func recharge(item: Variant, motes: int = -1) -> bool:
	var inv := bag()
	var stack := inv.resolve(item) if inv != null else null
	var n := motes if motes > 0 else (inv.count(Enchanting.MOTE_ITEM) if inv != null else 0)
	var r := Enchanting.recharge(stack, n, inv, mods())
	if not r["ok"]:
		return false
	_award("enchanting", float(r["xp"]))
	return true


## Spends one use of an item's enchantment; false when the note is silent. Combat calls this.
func consume_charge(item: Variant, amount: float = -1.0) -> bool:
	var inv := bag()
	var stack := inv.resolve(item) if inv != null else null
	return Enchanting.consume_charge(stack, amount, inv)


static func of(tree: SceneTree) -> Crafting:
	if tree == null:
		return null
	return tree.get_first_node_in_group(GROUP) as Crafting


# --- save --------------------------------------------------------------------------------

func to_save() -> Dictionary:
	return {
		"known_recipes": known_recipes.duplicate(), "known_enchantments": known_enchantments.duplicate(),
		"alchemy": alchemy.to_save(),
	}


func from_save(d: Dictionary) -> void:
	known_recipes.clear()
	for id in d.get("known_recipes", []):
		var s := str(id)
		if ContentDB.has(s) and not known_recipes.has(s):
			known_recipes.append(s)
	known_recipes.sort()
	known_enchantments.clear()
	for id in d.get("known_enchantments", []):
		var s := str(id)
		if Enchanting.is_enchantment(s) and not known_enchantments.has(s):
			known_enchantments.append(s)
	known_enchantments.sort()
	alchemy.from_save(d.get("alchemy", {}))
	known_changed.emit()
