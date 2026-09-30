class_name Equipment
extends Node
## Paper-doll slots over an Inventory. Equipped items stay in the bag (so weight counts once and
## selling or dropping one unequips it); each gear slot holds the stack's uid. The belt's eight
## quick slots bind an item id (things used: draughts, food, the flask, a torch, tools) and resolve
## to the first matching stack when used. Weapons are not on the belt: they are in the weapon set,
## up to WEAPON_SET_SIZE weapons (each remembering the off-hand it was carried with) that the
## cycle key goes round (cycle_weapon).
##
## Rules: shields and off-hand tools (lanterns, torches) go in off_hand; daggers may go in
## either hand; other one-handed weapons in main_hand; two-handed weapons (2H, bow, staff clip
## sets, or "two_handed": true) take main_hand and clear off_hand, and equipping anything in
## off_hand clears a two-handed main weapon. Armour goes by armour.slot; rings in ring_1/ring_2.
## Emits EventBus.item_equipped(slot, item_id) ("" on unequip) for the player's equipment.

signal changed(slot: String)
## The weapon set changed (a weapon added, taken off, or the hand cycled to another).
signal weapon_set_changed

const GROUP := "equipment"
const SLOTS: Array[String] = ["main_hand", "off_hand", "head", "body", "hands", "feet", "ring_1", "ring_2", "amulet", "quick_1", "quick_2", "quick_3", "quick_4", "quick_5", "quick_6", "quick_7", "quick_8"]
const GEAR_SLOTS: Array[String] = ["main_hand", "off_hand", "head", "body", "hands", "feet", "ring_1", "ring_2", "amulet"]
const QUICK_SLOTS: Array[String] = ["quick_1", "quick_2", "quick_3", "quick_4", "quick_5", "quick_6", "quick_7", "quick_8"]
## What the belt holds: things used. Weapons, armour, books, keys and materials are not.
const BELT_CATEGORIES: Array[String] = ["consumable", "ingredient", "tool"]
## How many weapons the cycle key goes round.
const WEAPON_SET_SIZE := 4
const ARMOUR_SLOTS: Array[String] = ["head", "body", "hands", "feet"]
const WEIGHT_CLASSES: Array[String] = ["light", "medium", "heavy"]
const SLOT_WEIGHT := {"head": 1.0, "body": 2.0, "hands": 1.0, "feet": 1.0}

var inventory: Inventory = null:
	set = set_inventory

var _slots: Dictionary = {}     # gear slot -> uid (0 = empty)
var _quick: Dictionary = {}     # quick slot -> item id ("" = empty)
var _pending: Dictionary = {}   # gear slot -> uid waiting for the inventory to load
## The weapons the cycle key goes round, in order (item ids), and the off-hand each was last carried
## with (main id -> off-hand id, "" for none): a sword comes back with its shield.
var weapon_set: Array[String] = []
var _set_offhand: Dictionary = {}


func _init() -> void:
	for s in GEAR_SLOTS:
		_slots[s] = 0
	for q in QUICK_SLOTS:
		_quick[q] = ""


func _ready() -> void:
	if inventory == null:
		_find_inventory()
	_update_group()


func set_inventory(inv: Inventory) -> void:
	if inventory != null and inventory.changed.is_connected(_on_inventory_changed):
		inventory.changed.disconnect(_on_inventory_changed)
	inventory = inv
	if inventory != null:
		inventory.changed.connect(_on_inventory_changed)
		_resolve_pending(false)
	_update_group()


func _find_inventory() -> void:
	var parent := get_parent()
	if parent != null:
		for c in parent.get_children():
			if c is Inventory:
				set_inventory(c)
				return
	if is_inside_tree():
		var bag := Inventory.player_bag(get_tree())
		if bag != null:
			set_inventory(bag)


## Only the player's paper-doll joins the "equipment" group, so the HUD and the UI stream find
## exactly one. Membership follows the bag's `is_player`, or an ancestor in the "player" group.
func _update_group() -> void:
	var player := (inventory != null and inventory.is_player) or _carried_by_player()
	if player and not is_in_group(GROUP):
		add_to_group(GROUP)
	elif not player and is_in_group(GROUP):
		remove_from_group(GROUP)


func _carried_by_player() -> bool:
	if not is_inside_tree():
		return false
	var n: Node = get_parent()
	var hops := 0
	while n != null and hops < 3:
		if n.is_in_group("player"):
			return true
		n = n.get_parent()
		hops += 1
	return false


# --- slot rules --------------------------------------------------------------------------

## The slots a stack may occupy, in preference order (empty = not equippable).
static func slots_for(stack: ItemStack) -> Array[String]:
	var out: Array[String] = []
	if stack == null:
		return out
	if stack.is_weapon():
		if stack.is_shield():
			out.append("off_hand")
		elif stack.is_two_handed():
			out.append("main_hand")
		elif str(stack.weapon().get("clips_set", "")) == "dagger":
			out.append("main_hand")
			out.append("off_hand")
		else:
			out.append("main_hand")
	elif stack.is_armour():
		var slot := str(stack.armour().get("slot", ""))
		match slot:
			"ring":
				out.append("ring_1")
				out.append("ring_2")
			"amulet":
				out.append("amulet")
			"head", "body", "hands", "feet":
				out.append(slot)
			"off_hand":
				# A shield worn as armour (the round shield) says so in its `armour` block; the
				# rule above only knew a shield carried as a weapon, so this one was sold in shops
				# and could never be taken up.
				out.append("off_hand")
	elif stack.has_tag("offhand"):
		out.append("off_hand")
	if stack.is_consumable():
		out.append_array(QUICK_SLOTS)
	return out


func can_equip(stack: ItemStack, slot: String = "") -> Dictionary:
	if stack == null:
		return {"ok": false, "reason": "no_item"}
	var allowed := slots_for(stack)
	if allowed.is_empty():
		return {"ok": false, "reason": "not_equippable"}
	if slot != "" and not allowed.has(slot):
		return {"ok": false, "reason": "wrong_slot"}
	if slot in QUICK_SLOTS or (slot == "" and allowed[0] in QUICK_SLOTS):
		return {"ok": true, "reason": ""}
	if inventory == null or not inventory.holds(stack):
		return {"ok": false, "reason": "not_in_inventory"}
	return {"ok": true, "reason": ""}


## Equips an item (item id, uid or ItemStack) into `slot`, or the best allowed slot when empty.
func equip(item: Variant, slot: String = "") -> bool:
	var stack := _resolve(item)
	var check := can_equip(stack, slot)
	if not check["ok"]:
		return false
	var allowed := slots_for(stack)
	if slot == "":
		slot = allowed[0]
		for s in allowed:
			if is_slot_free(s):
				slot = s
				break
	if slot in QUICK_SLOTS:
		return bind_quick(slot, stack.id)
	var current := slot_of(stack)
	if current == slot:
		return true
	if current != "":
		_clear(current)
	if slot == "main_hand" and stack.is_two_handed() and _slots["off_hand"] != 0:
		_clear("off_hand")
	if slot == "off_hand":
		var main := get_slot("main_hand")
		if main != null and main.is_two_handed():
			_clear("main_hand")
	_slots[slot] = stack.uid
	changed.emit(slot)
	_broadcast(slot, stack.id)
	# a weapon taken in hand joins the weapon set while it has room
	if slot == "main_hand" and inventory != null and inventory.is_player:
		add_to_weapon_set(stack.id)
	return true


## Empties a slot; returns the stack that was there (it remains in the bag), or null.
func unequip(slot: String) -> ItemStack:
	if slot in QUICK_SLOTS:
		var q := quick_stack(slot)
		clear_quick(slot)
		return q
	if not _slots.has(slot) or _slots[slot] == 0:
		return null
	var s := get_slot(slot)
	_clear(slot)
	return s


func unequip_all() -> void:
	for slot in GEAR_SLOTS:
		if _slots[slot] != 0:
			_clear(slot)


func _clear(slot: String) -> void:
	_slots[slot] = 0
	changed.emit(slot)
	_broadcast(slot, "")


func _broadcast(slot: String, item: String) -> void:
	if inventory != null and inventory.is_player:
		EventBus.item_equipped.emit(slot, item)


func _resolve(item: Variant) -> ItemStack:
	if item is ItemStack:
		return item
	if inventory == null:
		return null
	return inventory.resolve(item)


# --- reading slots -----------------------------------------------------------------------

func get_slot(slot: String) -> ItemStack:
	if slot in QUICK_SLOTS:
		return quick_stack(slot)
	if inventory == null or not _slots.has(slot):
		return null
	return inventory.find(int(_slots[slot]))


func item_id(slot: String) -> String:
	var s := get_slot(slot)
	return s.id if s != null else ""


## slot -> item id ("" when empty), for every slot.
func slots() -> Dictionary:
	var out := {}
	for slot in SLOTS:
		out[slot] = item_id(slot)
	return out


## slot -> ItemStack or null, for every slot.
func slot_stacks() -> Dictionary:
	var out := {}
	for slot in SLOTS:
		out[slot] = get_slot(slot)
	return out


func is_slot_free(slot: String) -> bool:
	if slot in QUICK_SLOTS:
		return _quick.get(slot, "") == ""
	return _slots.get(slot, 0) == 0


func slot_of(stack: ItemStack) -> String:
	if stack == null:
		return ""
	for slot in GEAR_SLOTS:
		if _slots[slot] != 0 and _slots[slot] == stack.uid:
			return slot
	return ""


func is_equipped(stack: ItemStack) -> bool:
	return slot_of(stack) != ""


func is_equipped_id(item: String) -> bool:
	for slot in GEAR_SLOTS:
		var s := get_slot(slot)
		if s != null and s.id == item:
			return true
	return false


# --- quick slots -------------------------------------------------------------------------

func bind_quick(slot: String, item: String) -> bool:
	if not slot in QUICK_SLOTS:
		return false
	if not belt_takes(item):
		return false
	_quick[slot] = item
	changed.emit(slot)
	_broadcast(slot, item)
	return true


## Puts `item` on the belt's first free slot (or finds it there already). Returns the slot, or ""
## when the belt is full or does not take it.
func bind_free_quick(item: String) -> String:
	for slot in QUICK_SLOTS:
		if quick_item(slot) == item:
			return slot
	for slot in QUICK_SLOTS:
		if quick_item(slot) == "":
			return slot if bind_quick(slot, item) else ""
	return ""


## Whether the belt holds this item: a thing used (BELT_CATEGORIES), not a weapon. A weapon goes in
## the weapon set (add_to_weapon_set); the belt used to take a one-handed one, and so the ranger's
## knife sat where a draught should.
static func belt_takes(item: String) -> bool:
	var def := ContentDB.get_or_empty(item)
	if def.is_empty():
		return false
	return BELT_CATEGORIES.has(str(def.get("category", "")))


func clear_quick(slot: String) -> void:
	if slot in QUICK_SLOTS and _quick[slot] != "":
		_quick[slot] = ""
		changed.emit(slot)
		_broadcast(slot, "")


func quick_item(slot: String) -> String:
	return str(_quick.get(slot, ""))


func quick_stack(slot: String) -> ItemStack:
	var id := quick_item(slot)
	if id == "" or inventory == null:
		return null
	return inventory.find_first(id)


## How many uses the belt slot has left: the stack's count, or for the flask its swallows.
func quick_count(slot: String) -> int:
	var id := quick_item(slot)
	if id == "" or inventory == null:
		return 0
	if Flask.is_flask(id):
		return Flask.charges(inventory.find_first(id))
	return inventory.count(id)


func use_quick(slot: String) -> bool:
	var s := quick_stack(slot)
	if s == null:
		return false
	# a torch or a lantern on the belt is taken into the off hand, and put away again
	if s.is_equippable():
		if slot_of(s) != "":
			_clear(slot_of(s))
			return true
		return equip(s)
	return inventory.use(s)


# --- the weapon set ------------------------------------------------------------------------

## Whether `item` can be in the weapon set: a weapon held in the main hand (not a shield).
static func set_takes(item: String) -> bool:
	var def := ContentDB.get_or_empty(item)
	if str(def.get("category", "")) != "weapon":
		return false
	return not (def.get("tags", []) as Array).has("shield") \
			and str((def.get("weapon", {}) as Dictionary).get("class", "")) != "shield"


## Puts a weapon in the set (at the end; not at all when the set is full or it is there already).
func add_to_weapon_set(item: String) -> bool:
	if not set_takes(item):
		return false
	if weapon_set.has(item):
		return true
	if weapon_set.size() >= WEAPON_SET_SIZE:
		return false
	weapon_set.append(item)
	weapon_set_changed.emit()
	return true


func remove_from_weapon_set(item: String) -> void:
	if weapon_set.has(item):
		weapon_set.erase(item)
		_set_offhand.erase(item)
		weapon_set_changed.emit()


func in_weapon_set(item: String) -> bool:
	return weapon_set.has(item)


## The set as it can be cycled now: its weapons still in the bag, and the one in the hand put in
## first when it is not there (a weapon taken in hand from the bag with the set full).
func weapon_round() -> Array[String]:
	var out: Array[String] = []
	var held := item_id("main_hand")
	for id in weapon_set:
		if inventory != null and inventory.find_first(id) != null:
			out.append(id)
	if held != "" and not out.has(held) and set_takes(held):
		out.push_front(held)
	return out


## Takes the next weapon in the round into the hand (`step` 1 on, -1 back), with the off-hand it
## was carried with; the one put away remembers its own. Returns the id now in the hand, or "" when
## there is nothing to cycle to (fewer than two weapons in the round).
func cycle_weapon(step: int = 1) -> String:
	var order: Array[String] = weapon_round()
	if order.size() < 2:
		return ""
	var held := item_id("main_hand")
	var at: int = order.find(held)
	var next: String = order[posmod(at + signi(step), order.size())] if at >= 0 \
			else (order[0] if step > 0 else order[order.size() - 1])
	if next == held:
		return ""
	if held != "":
		_set_offhand[held] = item_id("off_hand")
	if not equip(next, "main_hand"):
		return ""
	var off := str(_set_offhand.get(next, ""))
	var main := get_slot("main_hand")
	if off != "" and main != null and not main.is_two_handed() and inventory.find_first(off) != null:
		equip(off, "off_hand")
	elif off == "" and _set_offhand.has(next) and _slots["off_hand"] != 0:
		_clear("off_hand")
	weapon_set_changed.emit()
	return next


## The belt's answer to a quick key, as `Player.quick_slot_handler` wants it: key `index` (0..7)
## uses whatever is bound to quick_<index + 1>. The doll owns the belt, so the doll answers.
func use_quick_index(index: int, _item_id: String = "") -> bool:
	if index < 0 or index >= QUICK_SLOTS.size():
		return false
	return use_quick(QUICK_SLOTS[index])


# --- aggregates --------------------------------------------------------------------------

## Sum of armour ratings (temper applied) over every gear slot.
func armour_total(bonus_per_tier: float = ItemStack.TEMPER_BONUS_PER_TIER) -> float:
	var total := 0.0
	for slot in GEAR_SLOTS:
		var s := get_slot(slot)
		if s != null and s.is_armour():
			total += float(s.effective_armour(bonus_per_tier).get("armour", 0.0))
	return total


## Guard stability 0..1: the off-hand shield's, else the main weapon's, plus armour stability.
func stability() -> float:
	var base := 0.0
	var off := get_slot("off_hand")
	var main := get_slot("main_hand")
	if off != null and off.is_weapon():
		base = float(off.weapon().get("stability", 0.0))
	elif main != null and main.is_weapon():
		base = float(main.weapon().get("stability", 0.0))
	for slot in ARMOUR_SLOTS:
		var s := get_slot(slot)
		if s != null and s.is_armour():
			base += float(s.armour().get("stability", 0.0))
	return clampf(base, 0.0, 1.0)


## light | medium | heavy: weighted average of worn head/body/hands/feet (body counts double).
func weight_class() -> String:
	var score := 0.0
	var weight_sum := 0.0
	for slot in ARMOUR_SLOTS:
		var s := get_slot(slot)
		if s == null or not s.is_armour():
			continue
		var cls := str(s.armour().get("weight_class", "light"))
		var idx := WEIGHT_CLASSES.find(cls)
		if idx < 0:
			idx = 0
		var w: float = SLOT_WEIGHT.get(slot, 1.0)
		score += idx * w
		weight_sum += w
	if weight_sum <= 0.0:
		return "light"
	return WEIGHT_CLASSES[clampi(int(round(score / weight_sum)), 0, 2)]


## Weight of everything worn or wielded.
func equipped_weight() -> float:
	var total := 0.0
	var seen := {}
	for slot in GEAR_SLOTS:
		var s := get_slot(slot)
		if s != null and not seen.has(s.uid):
			seen[s.uid] = true
			total += s.unit_weight()
	return total


## The main-hand weapon block with temper applied ({} when unarmed).
func main_weapon(bonus_per_tier: float = ItemStack.TEMPER_BONUS_PER_TIER) -> Dictionary:
	var s := get_slot("main_hand")
	return s.effective_weapon(bonus_per_tier) if s != null else {}


func off_hand_weapon(bonus_per_tier: float = ItemStack.TEMPER_BONUS_PER_TIER) -> Dictionary:
	var s := get_slot("off_hand")
	return s.effective_weapon(bonus_per_tier) if s != null else {}


## Passive modifiers from worn items and their enchantments, as {stat, add|mult, source} dicts
## ready for Modifiers.set_source(). Effects turn into modifiers through their def's `modifier`
## block; a weapon enchantment with no charge left contributes nothing.
func modifiers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	for slot in GEAR_SLOTS:
		var s := get_slot(slot)
		if s == null or seen.has(s.uid):
			continue
		seen[s.uid] = true
		for entry in s.effect_entries():
			var eff := ContentDB.get_or_empty(str(entry.get("effect", "")))
			if eff.is_empty() or not eff.has("modifier"):
				continue
			if bool(entry.get("enchant", false)) and int(eff.get("charge_cost", 0)) > 0 and int(s.enchantment().get("charge", 0)) <= 0:
				continue
			var mod: Dictionary = eff["modifier"]
			var magnitude := float(entry.get("magnitude", eff.get("magnitude_base", 0)))
			var scale := float(mod.get("scale", 1.0))
			var m := {"stat": str(mod.get("stat", "")), "source": s.display_name()}
			if str(mod.get("op", "add")) == "mult":
				m["mult"] = 1.0 + magnitude * scale
			else:
				m["add"] = magnitude * scale
			out.append(m)
	return out


## Everything a HUD or paper-doll needs in one call.
func summary() -> Dictionary:
	return {
		"slots": slots(), "armour": armour_total(), "stability": stability(), "weight_class": weight_class(),
		"weight": equipped_weight(), "modifiers": modifiers(), "main_weapon": main_weapon(), "off_hand": off_hand_weapon(),
	}


# --- inventory tracking ------------------------------------------------------------------

func _on_inventory_changed() -> void:
	_resolve_pending(true)
	for slot in GEAR_SLOTS:
		var uid: int = _slots[slot]
		if uid != 0 and inventory.find(uid) == null:
			_clear(slot)


func _resolve_pending(drop_missing: bool) -> void:
	if inventory == null or _pending.is_empty():
		return
	for slot in _pending.keys():
		var uid := int(_pending[slot])
		if inventory.find(uid) != null:
			_slots[slot] = uid
			_pending.erase(slot)
			changed.emit(slot)
		elif drop_missing:
			_pending.erase(slot)


# --- save --------------------------------------------------------------------------------

func to_save() -> Dictionary:
	return {"slots": _slots.duplicate(), "quick": _quick.duplicate(), "weapon_set": Array(weapon_set),
			"set_offhand": _set_offhand.duplicate()}


func from_save(d: Dictionary) -> void:
	for slot in GEAR_SLOTS:
		_slots[slot] = 0
	_pending.clear()
	var saved: Dictionary = d.get("slots", {})
	for slot in saved:
		var uid := int(saved[slot])
		if GEAR_SLOTS.has(str(slot)) and uid > 0:
			_pending[str(slot)] = uid
	var quick: Dictionary = d.get("quick", {})
	weapon_set.clear()
	_set_offhand.clear()
	for w in d.get("weapon_set", []):
		if set_takes(str(w)) and not weapon_set.has(str(w)) and weapon_set.size() < WEAPON_SET_SIZE:
			weapon_set.append(str(w))
	var offs: Dictionary = d.get("set_offhand", {})
	for k in offs:
		_set_offhand[str(k)] = str(offs[k])
	for q in QUICK_SLOTS:
		var id := str(quick.get(q, ""))
		# a weapon left on the belt by an older game goes to the weapon set (Migrations._v5_to_v6
		# moves them in the save file; this is the same rule for anything written in between)
		if set_takes(id):
			add_to_weapon_set(id)
			id = ""
		_quick[q] = id if belt_takes(id) else ""
	_resolve_pending(false)
	changed.emit("")
