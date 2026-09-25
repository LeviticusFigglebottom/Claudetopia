class_name Enchanting
extends RefCounted
## Name-table work: disenchanting to learn a note, writing one into gear with Ember Motes, and
## the charge those notes spend.
##
## An enchantment is an effect def with `"enchant": true`: it names the slots it can be written
## into (`enchant_slots`: weapon | armour | shield | jewellery), what one use costs
## (`charge_cost`, 0 for a passive note) and how many motes one point of magnitude takes
## (`mote_cost`).
##
## Disenchanting destroys an enchanted item and teaches its effect id. Enchanting writes
## {effect, magnitude, duration, charge, charge_max} into an ItemStack's `data`, spending motes
## (core:item/ember_mote). Charge is spent by `consume_charge()` when the item is used in anger;
## at zero the note is silent until recharged with more motes.
## Known enchantments live in Crafting, which saves them.

const MOTE_ITEM := "core:item/ember_mote"
const CHARGE_PER_MOTE := 25.0        # fallback when the mote item carries no `ember.charge`
const BASE_MAGNITUDE_MOTES := 2      # motes for one step of magnitude when the effect omits mote_cost
const MOTES_PER_WARMTH := 1          # caught from a foe a Kindling word killed (Mote Catcher: +1)
const MAGNITUDE_STEPS_MAX := 5
const SKILL_MAGNITUDE_PER_LEVEL := 0.01
const DISENCHANT_XP := 25.0
const ENCHANT_XP_BASE := 20.0
const RECHARGE_XP := 4.0


# --- definitions -------------------------------------------------------------------------

## Every effect def that can be written into gear.
static func all_enchantments() -> Array[String]:
	var out: Array[String] = []
	for d in ContentDB.where("effect", "enchant", true):
		out.append(str(d["id"]))
	out.sort()
	return out


static func def(effect_id: String) -> Dictionary:
	return ContentDB.get_or_empty(effect_id)


static func is_enchantment(effect_id: String) -> bool:
	return bool(def(effect_id).get("enchant", false))


static func slots_for(effect_id: String) -> Array:
	return def(effect_id).get("enchant_slots", [])


## The slot kind a stack counts as for enchanting: weapon | shield | armour | jewellery | "".
static func slot_kind(stack: ItemStack) -> String:
	if stack == null:
		return ""
	if stack.is_shield():
		return "shield"
	if stack.is_weapon():
		return "weapon"
	if stack.is_armour():
		var slot := str(stack.armour().get("slot", ""))
		return "jewellery" if (slot == "ring" or slot == "amulet") else "armour"
	return ""


static func fits(effect_id: String, stack: ItemStack) -> bool:
	var kind := slot_kind(stack)
	return kind != "" and slots_for(effect_id).has(kind)


## Ember Motes are "captured from slain foes with a Kindling spell" (DESIGN §5.8): a foe whose last
## blow was a Kindling saying gives its killer one, and Mote Catcher one more. Nothing did the
## catching, so the only motes in the world were the ones a loot table happened to roll. Returns
## how many went into the killer's bag. A called thing that is dismissed never dies, so it is
## never caught.
static func catch_last_warmth(victim: Node, killer: Node) -> int:
	if victim == null or killer == null or not is_instance_valid(victim) or not is_instance_valid(killer):
		return 0
	if str(victim.get("last_hit_skill")) != "kindling" or victim == killer:
		return 0
	var bag := Inventory.for_actor(killer)
	if bag == null or not ContentDB.has(MOTE_ITEM):
		return 0
	var extra := (killer as Actor).stat_add("mote_yield") if killer is Actor else 0.0
	var count := MOTES_PER_WARMTH + maxi(int(round(extra)), 0)
	if bag.add(MOTE_ITEM, count) == null:
		return 0
	EventBus.notify.emit("Caught %s." % ("an Ember Mote" if count == 1 else "%d Ember Motes" % count), "item")
	return count


## Charge one mote is worth.
static func charge_per_mote() -> float:
	var d := ContentDB.get_or_empty(MOTE_ITEM)
	if d.has("ember"):
		return float(d["ember"].get("charge", CHARGE_PER_MOTE))
	return CHARGE_PER_MOTE


static func motes_for_magnitude(effect_id: String) -> int:
	return maxi(1, int(def(effect_id).get("mote_cost", BASE_MAGNITUDE_MOTES)))


# --- disenchanting -----------------------------------------------------------------------

## Why a stack cannot be disenchanted: "" when it can. Reasons: no_item, not_enchanted,
## already_known, no_inventory.
static func disenchant_blocker(stack: ItemStack, inventory: Inventory, known: Array) -> String:
	if stack == null:
		return "no_item"
	if not stack.is_enchanted():
		return "not_enchanted"
	if inventory == null:
		return "no_inventory"
	if known.has(str(stack.enchantment().get("effect", ""))):
		return "already_known"
	return ""


## Destroys one unit of an enchanted item and returns its effect id to learn.
## Returns {ok, reason, effect, xp}.
static func disenchant(stack: ItemStack, inventory: Inventory, known: Array) -> Dictionary:
	var why := disenchant_blocker(stack, inventory, known)
	if why != "":
		return {"ok": false, "reason": why, "effect": "", "xp": 0.0}
	var effect := str(stack.enchantment().get("effect", ""))
	inventory.remove_stack(stack, 1)
	return {"ok": true, "reason": "", "effect": effect, "xp": DISENCHANT_XP}


# --- enchanting --------------------------------------------------------------------------

## The magnitude, duration and charge `motes` motes buy for an effect at a skill level.
static func preview(effect_id: String, motes: int, skill_level: int = 0, mods: Modifiers = null) -> Dictionary:
	var d := def(effect_id)
	var per_step := motes_for_magnitude(effect_id)
	@warning_ignore("integer_division")
	var steps := clampi(int(motes / per_step), 1, MAGNITUDE_STEPS_MAX)
	var skill_scale := 1.0 + float(skill_level) * SKILL_MAGNITUDE_PER_LEVEL
	var magnitude_mult := 1.0 if mods == null else mods.get_mult("enchant_magnitude")
	var charge_mult := 1.0 if mods == null else mods.get_mult("enchant_charge")
	var magnitude := float(d.get("magnitude_base", 0)) * float(steps) * skill_scale * magnitude_mult
	var charge := charge_per_mote() * float(motes) * charge_mult
	return {
		"effect": effect_id, "steps": steps, "motes_used": steps * per_step,
		"magnitude": snappedf(magnitude, 0.1), "duration": float(d.get("duration_base", 0)),
		"charge": snappedf(charge, 1.0), "charge_cost": float(d.get("charge_cost", 0)),
	}


## Why an item cannot be enchanted: "" when it can. Reasons: no_item, not_an_enchantment,
## not_known, wrong_item, already_enchanted, not_enough_motes, no_inventory.
static func enchant_blocker(stack: ItemStack, effect_id: String, motes: int, inventory: Inventory, known: Array) -> String:
	if stack == null:
		return "no_item"
	if not is_enchantment(effect_id):
		return "not_an_enchantment"
	if not known.has(effect_id):
		return "not_known"
	if not fits(effect_id, stack):
		return "wrong_item"
	if stack.is_enchanted():
		return "already_enchanted"
	if inventory == null:
		return "no_inventory"
	if motes < motes_for_magnitude(effect_id) or inventory.count(MOTE_ITEM) < motes:
		return "not_enough_motes"
	return ""


## What `enchant_blocker` means, said the way the Name-table says it. "" when nothing is in the way.
static func blocker_text(reason: String, stack: ItemStack, effect_id: String, motes: int, inventory: Inventory) -> String:
	var note := str(def(effect_id).get("name", "that note"))
	match reason:
		"":
			return ""
		"no_item":
			return "Choose something to write it on."
		"not_an_enchantment":
			return "That is not a note that can be written."
		"not_known":
			return "You have not learned %s." % note
		"wrong_item":
			var takes: Array = slots_for(effect_id)
			var into := " or ".join(takes.map(func(k: Variant) -> String: return {"weapon": "a blade", "shield": "a shield", "armour": "armour", "jewellery": "a ring or an amulet"}.get(str(k), str(k))))
			return "%s is written into %s, not into that." % [note, into if into != "" else "something else"]
		"already_enchanted":
			return "It already carries a note. Take that one out first."
		"no_inventory":
			return "There is nothing to write with."
		"not_enough_motes":
			var per_step := motes_for_magnitude(effect_id)
			var carried := inventory.count(MOTE_ITEM) if inventory != null else 0
			if motes < per_step:
				return "%s takes at least %d Ember Motes to say." % [note, per_step]
			return "That takes %d Ember Motes and you carry %d." % [motes, carried]
	return "It will not take."


## Writes an enchantment into one unit of a stack, spending motes. A stacked item is split so
## only the enchanted unit changes. Returns {ok, reason, stack, enchant, xp}.
static func enchant(stack: ItemStack, effect_id: String, motes: int, inventory: Inventory, known: Array, skill_level: int = 0, mods: Modifiers = null) -> Dictionary:
	var why := enchant_blocker(stack, effect_id, motes, inventory, known)
	if why != "":
		return {"ok": false, "reason": why, "stack": null, "enchant": {}, "xp": 0.0}
	var p := preview(effect_id, motes, skill_level, mods)
	inventory.remove(MOTE_ITEM, int(p["motes_used"]))
	var target := stack
	if stack.count > 1:
		var split := stack.split(1)
		inventory.notify_changed(stack)
		target = inventory.add(split.id, 1, split.data)
	var charge := float(p["charge"])
	target.data["enchant"] = {
		"effect": effect_id, "magnitude": float(p["magnitude"]), "duration": float(p["duration"]),
		"charge": charge, "charge_max": charge, "charge_cost": float(p["charge_cost"]),
	}
	inventory.notify_changed(target)
	return {"ok": true, "reason": "", "stack": target, "enchant": target.data["enchant"].duplicate(), "xp": ENCHANT_XP_BASE + 2.0 * float(p["motes_used"])}


# --- charge ------------------------------------------------------------------------------

static func charge_of(stack: ItemStack) -> float:
	return float(stack.enchantment().get("charge", 0.0)) if stack != null else 0.0


static func charge_max_of(stack: ItemStack) -> float:
	return float(stack.enchantment().get("charge_max", 0.0)) if stack != null else 0.0


static func charge_fraction(stack: ItemStack) -> float:
	var maximum := charge_max_of(stack)
	return charge_of(stack) / maximum if maximum > 0.0 else 0.0


## True when the note still has enough charge to speak (passive notes, cost 0, always do).
static func has_charge(stack: ItemStack) -> bool:
	if stack == null or not stack.is_enchanted():
		return false
	var cost := float(stack.enchantment().get("charge_cost", 0.0))
	return cost <= 0.0 or charge_of(stack) >= cost


## Spends one use of an enchantment (called by combat on a hit, or by a triggered item).
## `amount` defaults to the enchantment's charge_cost. Returns true when the note fired; false
## when it is silent. Pass the inventory to have the change broadcast to listening screens.
static func consume_charge(stack: ItemStack, amount: float = -1.0, inventory: Inventory = null) -> bool:
	if stack == null or not stack.is_enchanted():
		return false
	var ench: Dictionary = stack.data["enchant"]
	var cost := float(ench.get("charge_cost", 0.0)) if amount < 0.0 else amount
	if cost <= 0.0:
		return true
	var left := float(ench.get("charge", 0.0))
	if left < cost:
		return false
	ench["charge"] = left - cost
	if inventory != null:
		inventory.notify_changed(stack)
	return true


## Refills an enchantment's charge with motes. Returns {ok, reason, charge, motes_used, xp}.
## Reasons: no_item, not_enchanted, full, no_inventory, not_enough_motes.
static func recharge(stack: ItemStack, motes: int, inventory: Inventory, mods: Modifiers = null) -> Dictionary:
	if stack == null:
		return {"ok": false, "reason": "no_item", "charge": 0.0, "motes_used": 0, "xp": 0.0}
	if not stack.is_enchanted():
		return {"ok": false, "reason": "not_enchanted", "charge": 0.0, "motes_used": 0, "xp": 0.0}
	var ench: Dictionary = stack.data["enchant"]
	var maximum := float(ench.get("charge_max", 0.0))
	var left := float(ench.get("charge", 0.0))
	if left >= maximum:
		return {"ok": false, "reason": "full", "charge": left, "motes_used": 0, "xp": 0.0}
	if inventory == null:
		return {"ok": false, "reason": "no_inventory", "charge": left, "motes_used": 0, "xp": 0.0}
	var per_mote := charge_per_mote() * (1.0 if mods == null else mods.get_mult("enchant_charge"))
	var wanted := maxi(1, int(ceil((maximum - left) / maxf(per_mote, 1.0))))
	var used := mini(maxi(motes, 1), mini(wanted, inventory.count(MOTE_ITEM)))
	if used <= 0:
		return {"ok": false, "reason": "not_enough_motes", "charge": left, "motes_used": 0, "xp": 0.0}
	inventory.remove(MOTE_ITEM, used)
	ench["charge"] = minf(maximum, left + per_mote * float(used))
	inventory.notify_changed(stack)
	return {"ok": true, "reason": "", "charge": float(ench["charge"]), "motes_used": used, "xp": RECHARGE_XP * used}


## [{effect, name, description, slots, charge_cost, mote_cost, known}] for the Name-table screen.
static func summaries(known: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in all_enchantments():
		var d := def(id)
		out.append({
			"effect": id, "name": str(d.get("name", id)), "description": str(d.get("description", "")),
			"slots": slots_for(id).duplicate(), "charge_cost": float(d.get("charge_cost", 0)),
			"mote_cost": motes_for_magnitude(id), "magnitude_base": float(d.get("magnitude_base", 0)),
			"known": known.has(id),
		})
	return out
