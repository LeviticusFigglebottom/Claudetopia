class_name ItemStack
extends RefCounted
## One stack of an item: an item id, a count and per-instance `data`.
##
## `data` is what makes two stacks of the same item different (they never merge):
##   temper: int                                    tier set by Smithing.temper (+10% per tier to damage/armour)
##   enchant: {effect, magnitude, duration, charge, charge_max}   written at a Name-table by Enchanting
##   effects: [{effect, magnitude, duration}]       a brewed potion's effects (override the template's)
##   name: String                                   display-name override (brewed potions)
##   quality: float                                 potency a potion was brewed at (scales value)
## Stacks are plain data: they know nothing about the Inventory holding them beyond `uid`.

const TEMPER_SUFFIXES := ["", "(Fine)", "(Honed)", "(Tempered)", "(Rung)", "(Named)"]
const TEMPER_BONUS_PER_TIER := 0.10
const TWO_HANDED_CLIP_SETS := ["2H", "bow", "staff"]

var uid: int = 0          # unique inside its inventory; 0 until added to one
var id: String = ""
var count: int = 1
var data: Dictionary = {}


func _init(item_id: String = "", item_count: int = 1, item_data: Dictionary = {}) -> void:
	id = item_id
	count = item_count
	data = item_data.duplicate(true)


# --- definition access -------------------------------------------------------------------

func def() -> Dictionary:
	return ContentDB.get_or_empty(id)


func is_valid() -> bool:
	return ContentDB.has(id)


func category() -> String:
	return str(def().get("category", ""))


func tags() -> Array:
	return def().get("tags", [])


func has_tag(tag: String) -> bool:
	return tags().has(tag)


func base_name() -> String:
	return str(def().get("name", id))


## Name shown in menus: a brewed potion's own name, plus the temper suffix.
func display_name() -> String:
	var shown := str(data.get("name", base_name()))
	var tier := temper_tier()
	if tier > 0 and tier < TEMPER_SUFFIXES.size():
		shown += " " + TEMPER_SUFFIXES[tier]
	return shown


func description() -> String:
	return str(def().get("description", ""))


func max_stack() -> int:
	return maxi(1, int(def().get("stack", 1)))


func is_stackable() -> bool:
	return max_stack() > 1


# --- weight and value --------------------------------------------------------------------

func unit_weight() -> float:
	return float(def().get("weight", 0.0))


func weight() -> float:
	return unit_weight() * count


## Value of one unit: base value raised by temper, potion quality and any enchantment.
func unit_value() -> int:
	var v := float(def().get("value", 0))
	v *= 1.0 + 0.25 * temper_tier()
	v *= float(data.get("quality", 1.0))
	var ench := enchantment()
	if not ench.is_empty():
		v = v * 2.0 + 60.0 + 2.0 * float(ench.get("charge_max", 0))
	return int(round(v))


func value() -> int:
	return unit_value() * count


# --- instance state ----------------------------------------------------------------------

func temper_tier() -> int:
	return int(data.get("temper", 0))


func enchantment() -> Dictionary:
	var e: Variant = data.get("enchant", {})
	return e if typeof(e) == TYPE_DICTIONARY else {}


func is_enchanted() -> bool:
	return not enchantment().is_empty()


func weapon() -> Dictionary:
	var w: Variant = def().get("weapon", {})
	return w if typeof(w) == TYPE_DICTIONARY else {}


func armour() -> Dictionary:
	var a: Variant = def().get("armour", {})
	return a if typeof(a) == TYPE_DICTIONARY else {}


func is_weapon() -> bool:
	return not weapon().is_empty()


func is_armour() -> bool:
	return not armour().is_empty()


func is_shield() -> bool:
	return str(weapon().get("class", "")) == "shield"


func is_ranged() -> bool:
	return def().has("ranged")


## Greatswords, spears, bows, crossbows and staves occupy both hands.
func is_two_handed() -> bool:
	var w := weapon()
	if w.is_empty() or is_shield():
		return false
	if def().has("two_handed"):
		return bool(def()["two_handed"])
	return TWO_HANDED_CLIP_SETS.has(str(w.get("clips_set", "")))


func is_equippable() -> bool:
	return is_weapon() or is_armour() or has_tag("offhand")


func is_consumable() -> bool:
	return category() == "consumable" or category() == "ingredient"


## The book this item opens ("" when it is not something to read). An item says so with
## `reads`; a `book`-category item whose short name matches a book id says so by its name.
func reads_book() -> String:
	var named := str(def().get("reads", ""))
	if named != "":
		return named
	if category() != "book":
		return ""
	var guess := Ids.make(Ids.pack_of(id), "book", Ids.name_of(id))
	return guess if ContentDB.has(guess) else ""


func is_readable() -> bool:
	return reads_book() != ""


func is_ingredient() -> bool:
	return category() == "ingredient" and def().has("alchemy")


## Effects this stack carries: the template's (or a brewed potion's own) plus its enchantment.
## Each entry: {effect, magnitude, duration} and "enchant": true for the enchantment entry.
func effect_entries() -> Array:
	var out: Array = []
	var own: Variant = data.get("effects", def().get("effects", []))
	if typeof(own) == TYPE_ARRAY:
		for e in own:
			if typeof(e) == TYPE_DICTIONARY:
				out.append(e.duplicate(true))
	var ench := enchantment()
	if not ench.is_empty():
		out.append({"effect": str(ench.get("effect", "")), "magnitude": ench.get("magnitude", 0), "duration": ench.get("duration", 0), "enchant": true})
	return out


func temper_multiplier(bonus_per_tier: float = TEMPER_BONUS_PER_TIER) -> float:
	return 1.0 + bonus_per_tier * temper_tier()


## The weapon block with temper applied (damage and poise_damage scaled). Empty for non-weapons.
func effective_weapon(bonus_per_tier: float = TEMPER_BONUS_PER_TIER) -> Dictionary:
	var w := weapon().duplicate(true)
	if w.is_empty():
		return w
	var m := temper_multiplier(bonus_per_tier)
	w["damage"] = float(w.get("damage", 0)) * m
	w["poise_damage"] = float(w.get("poise_damage", 0)) * m
	w["temper"] = temper_tier()
	return w


## The armour block with temper applied. Empty for non-armour.
func effective_armour(bonus_per_tier: float = TEMPER_BONUS_PER_TIER) -> Dictionary:
	var a := armour().duplicate(true)
	if a.is_empty():
		return a
	a["armour"] = float(a.get("armour", 0)) * temper_multiplier(bonus_per_tier)
	a["temper"] = temper_tier()
	return a


# --- stack mechanics ---------------------------------------------------------------------

## True when every key in `filter` equals the same key in `data`.
func matches(filter: Dictionary) -> bool:
	for k in filter:
		if not data.has(k) or data[k] != filter[k]:
			return false
	return true


func same_kind(other: ItemStack) -> bool:
	return other != null and id == other.id and data == other.data


## Removes `n` units from this stack and returns them as a new (uid-less) stack; null if n >= count.
func split(n: int) -> ItemStack:
	if n <= 0 or n >= count:
		return null
	count -= n
	return ItemStack.new(id, n, data)


func duplicate_stack() -> ItemStack:
	var s := ItemStack.new(id, count, data)
	s.uid = uid
	return s


func to_dict() -> Dictionary:
	return {"uid": uid, "id": id, "count": count, "data": data.duplicate(true)}


static func from_dict(d: Dictionary) -> ItemStack:
	var raw: Variant = d.get("data", {})
	var s := ItemStack.new(str(d.get("id", "")), int(d.get("count", 1)), raw if typeof(raw) == TYPE_DICTIONARY else {})
	s.uid = int(d.get("uid", 0))
	return s


## Flat record for menus and other streams.
func summary() -> Dictionary:
	return {
		"uid": uid, "item_id": id, "name": display_name(), "count": count, "category": category(),
		"weight": weight(), "unit_weight": unit_weight(), "value": value(), "unit_value": unit_value(),
		"tags": tags().duplicate(), "description": description(), "data": data.duplicate(true),
		"equippable": is_equippable(), "consumable": is_consumable(), "two_handed": is_two_handed(),
		"readable": is_readable(), "reads": reads_book(),
	}
