class_name Inventory
extends Node
## A bag of ItemStacks plus the marks (coin) it carries. Used by the player, containers,
## merchants and corpses alike. Only the player's bag (`is_player = true`) joins the
## "inventory" group and mirrors its events onto EventBus (item_acquired, item_removed,
## item_used, marks_changed); every other bag stays local.
##
## Weight: Load = sum of stack weights (equipped gear stays in the bag, so it counts once).
## Capacity comes from the progression node (Endurance and perks) for the player, from
## `capacity_override` when set, else DEFAULT_CAPACITY. Adding never fails for weight;
## `is_overloaded()` is for the movement code to read.

signal changed
signal stack_added(stack: ItemStack, amount: int)
signal stack_removed(stack: ItemStack, amount: int)   # stack.count is already reduced (may be 0)
signal stack_changed(stack: ItemStack)                 # instance data changed in place (temper, enchant)
signal marks_changed(total: int, delta: int)
signal item_used(item_id: String, effects: Array)

const GROUP := "inventory"
const DEFAULT_CAPACITY := 90.0
const SORT_MODES := ["category", "name", "weight", "value"]
const CATEGORY_ORDER := ["weapon", "armour", "consumable", "ingredient", "material", "tool", "book", "key", "misc"]
const WORLD_ITEM_SCENE := "res://systems/inventory/world_item.tscn"

## The player's bag. Only this one joins the "inventory" group and mirrors its events onto
## EventBus, so the Hearth, the HUD and the crime stream always find the right bag. A bag whose
## parent (or grandparent) is in the "player" group sets this itself when it enters the tree.
@export var is_player: bool = false:
	set(value):
		is_player = value
		_update_group()
## When > 0 this fixes the capacity (containers use a large value).
@export var capacity_override: float = 0.0

var marks: int = 0:
	set(value):
		var delta := value - marks
		marks = value
		if delta != 0:
			marks_changed.emit(marks, delta)
			if is_player:
				EventBus.marks_changed.emit(marks, delta)

var _stacks: Array[ItemStack] = []
var _next_uid: int = 1


func _ready() -> void:
	if not is_player and _carried_by_player():
		is_player = true
	_update_group()


## True when an ancestor is in the "player" group (the player stream tags its own actor).
func _carried_by_player() -> bool:
	var n: Node = get_parent()
	var hops := 0
	while n != null and hops < 3:
		if n.is_in_group("player"):
			return true
		n = n.get_parent()
		hops += 1
	return false


func _update_group() -> void:
	if is_player:
		if not is_in_group(GROUP):
			add_to_group(GROUP)
	elif is_in_group(GROUP):
		remove_from_group(GROUP)


## The inventory an actor carries: `get_inventory()`, an `inventory` property, or a child Inventory.
static func for_actor(actor: Object) -> Inventory:
	if actor == null or not is_instance_valid(actor):
		return null
	if actor is Inventory:
		return actor
	if actor.has_method("get_inventory"):
		var got: Variant = actor.call("get_inventory")
		if got is Inventory:
			return got
	var prop: Variant = actor.get("inventory")
	if prop is Inventory:
		return prop
	if actor is Node:
		for c in (actor as Node).get_children():
			if c is Inventory:
				return c
	return null


## The player's bag, found through the "inventory" group (null before the player exists).
static func player_bag(tree: SceneTree) -> Inventory:
	if tree == null:
		return null
	var n := tree.get_first_node_in_group(GROUP)
	return n as Inventory


# --- adding and removing -----------------------------------------------------------------

## Adds `amount` of an item, merging into stacks with identical `data` up to the item's stack
## size. Returns the stack the last units landed in, or null for an unknown item.
func add(item_id: String, amount: int = 1, data: Dictionary = {}) -> ItemStack:
	if amount <= 0:
		return null
	if not ContentDB.has(item_id):
		Log.error("Inventory", "add: unknown item '%s'" % item_id)
		return null
	var probe := ItemStack.new(item_id, 1, data)
	var max_stack := probe.max_stack()
	var remaining := amount
	var last: ItemStack = null
	if max_stack > 1:
		for s in _stacks:
			if remaining <= 0:
				break
			if s.id == item_id and s.count < max_stack and s.data == probe.data:
				var n := mini(remaining, max_stack - s.count)
				s.count += n
				remaining -= n
				last = s
				stack_added.emit(s, n)
	while remaining > 0:
		var n := mini(remaining, max_stack)
		var s := ItemStack.new(item_id, n, data)
		s.uid = _next_uid
		_next_uid += 1
		_stacks.append(s)
		remaining -= n
		last = s
		stack_added.emit(s, n)
	changed.emit()
	if is_player:
		EventBus.item_acquired.emit(item_id, amount)
	return last


## Takes ownership of a stack object (from a split or another bag). Returns the holding stack.
func add_stack(stack: ItemStack) -> ItemStack:
	if stack == null or stack.count <= 0:
		return null
	return add(stack.id, stack.count, stack.data)


## Removes up to `amount` units of an item (optionally only from stacks whose data matches
## `data_filter`). Returns how many were removed.
func remove(item_id: String, amount: int = 1, data_filter: Dictionary = {}) -> int:
	var remaining := amount
	var removed := 0
	for s in _stacks.duplicate():
		if remaining <= 0:
			break
		if s.id != item_id:
			continue
		if not data_filter.is_empty() and not s.matches(data_filter):
			continue
		var n := mini(remaining, s.count)
		s.count -= n
		remaining -= n
		removed += n
		if s.count <= 0:
			_stacks.erase(s)
		stack_removed.emit(s, n)
	if removed > 0:
		changed.emit()
		if is_player:
			EventBus.item_removed.emit(item_id, removed)
	return removed


## Removes `amount` units from one specific stack (-1 = the whole stack). Returns the amount removed.
func remove_stack(stack: ItemStack, amount: int = -1) -> int:
	if stack == null or not _stacks.has(stack):
		return 0
	var n := stack.count if amount < 0 else mini(amount, stack.count)
	if n <= 0:
		return 0
	stack.count -= n
	if stack.count <= 0:
		_stacks.erase(stack)
	stack_removed.emit(stack, n)
	changed.emit()
	if is_player:
		EventBus.item_removed.emit(stack.id, n)
	return n


func clear() -> void:
	_stacks.clear()
	changed.emit()


## Call after mutating a stack's `data` in place (temper, enchant, recharge).
func notify_changed(stack: ItemStack) -> void:
	stack_changed.emit(stack)
	changed.emit()


# --- queries -----------------------------------------------------------------------------

func has(item_id: String, amount: int = 1) -> bool:
	return count(item_id) >= amount


func count(item_id: String) -> int:
	var total := 0
	for s in _stacks:
		if s.id == item_id:
			total += s.count
	return total


func is_empty() -> bool:
	return _stacks.is_empty()


func size() -> int:
	return _stacks.size()


## Copy of the stack list (the ItemStack objects themselves are shared).
func stacks() -> Array[ItemStack]:
	return _stacks.duplicate()


## Flat records for menus and other streams: [{item_id, count, uid, name, category, weight, value, data, ...}].
func items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in _stacks:
		out.append(s.summary())
	return out


func find(uid: int) -> ItemStack:
	if uid <= 0:
		return null
	for s in _stacks:
		if s.uid == uid:
			return s
	return null


func find_first(item_id: String, data_filter: Dictionary = {}) -> ItemStack:
	for s in _stacks:
		if s.id == item_id and (data_filter.is_empty() or s.matches(data_filter)):
			return s
	return null


func holds(stack: ItemStack) -> bool:
	return stack != null and _stacks.has(stack)


## Resolves a String (item id), int (uid) or ItemStack to a stack in this bag, else null.
func resolve(item: Variant) -> ItemStack:
	if item is ItemStack:
		return item if _stacks.has(item) else null
	if item is String:
		return find_first(item)
	if item is int:
		return find(item)
	return null


## Filter keys: id, category (String or Array), tag, tags_any, tags_all, equippable (bool),
## consumable (bool), weapon_class, armour_slot, name_contains.
func query(filter: Dictionary) -> Array[ItemStack]:
	var out: Array[ItemStack] = []
	for s in _stacks:
		if filter.has("id") and s.id != str(filter["id"]):
			continue
		if filter.has("category"):
			var c: Variant = filter["category"]
			if typeof(c) == TYPE_ARRAY:
				if not c.has(s.category()):
					continue
			elif s.category() != str(c):
				continue
		if filter.has("tag") and not s.has_tag(str(filter["tag"])):
			continue
		if filter.has("tags_any"):
			var any := false
			for t in filter["tags_any"]:
				if s.has_tag(str(t)):
					any = true
					break
			if not any:
				continue
		if filter.has("tags_all"):
			var all := true
			for t in filter["tags_all"]:
				if not s.has_tag(str(t)):
					all = false
					break
			if not all:
				continue
		if filter.has("equippable") and s.is_equippable() != bool(filter["equippable"]):
			continue
		if filter.has("consumable") and s.is_consumable() != bool(filter["consumable"]):
			continue
		if filter.has("weapon_class") and str(s.weapon().get("class", "")) != str(filter["weapon_class"]):
			continue
		if filter.has("armour_slot") and str(s.armour().get("slot", "")) != str(filter["armour_slot"]):
			continue
		if filter.has("name_contains") and not s.display_name().to_lower().contains(str(filter["name_contains"]).to_lower()):
			continue
		out.append(s)
	return out


func by_category(category: String) -> Array[ItemStack]:
	return query({"category": category})


## The arrow a bow draws from this bag, for `Player.ammo_provider`: the kind the bow names
## (`preferred`) when there is one, else any item tagged `tag` ("arrow", "bolt"). With `take` one
## of it leaves the bag. Returns its id, or "" when the quiver is empty. Before this was assigned
## the player loosed from a counter of twenty that no pickup ever refilled, and the thirty arrows
## a Wayfarer starts with could not be shot.
func ammo_for(tag: String, preferred: String = "", take: bool = false) -> String:
	var id := ""
	if not preferred.is_empty() and count(preferred) > 0:
		id = preferred
	else:
		for s in by_tag(tag):
			if s.count > 0:
				id = s.id
				break
	if not id.is_empty() and take:
		remove(id, 1)
	return id


func by_tag(tag: String) -> Array[ItemStack]:
	return query({"tag": tag})


func sort(mode: String = "category") -> void:
	match mode:
		"name":
			_stacks.sort_custom(func(a: ItemStack, b: ItemStack) -> bool: return _cmp_name(a, b))
		"weight":
			_stacks.sort_custom(func(a: ItemStack, b: ItemStack) -> bool:
				if a.weight() != b.weight():
					return a.weight() > b.weight()
				return _cmp_name(a, b))
		"value":
			_stacks.sort_custom(func(a: ItemStack, b: ItemStack) -> bool:
				if a.value() != b.value():
					return a.value() > b.value()
				return _cmp_name(a, b))
		_:
			_stacks.sort_custom(func(a: ItemStack, b: ItemStack) -> bool:
				var ca := _category_rank(a.category())
				var cb := _category_rank(b.category())
				if ca != cb:
					return ca < cb
				return _cmp_name(a, b))
	changed.emit()


static func _category_rank(category: String) -> int:
	var i := CATEGORY_ORDER.find(category)
	return i if i >= 0 else CATEGORY_ORDER.size()


static func _cmp_name(a: ItemStack, b: ItemStack) -> bool:
	var c := a.display_name().naturalnocasecmp_to(b.display_name())
	if c != 0:
		return c < 0
	return a.uid < b.uid


# --- weight ------------------------------------------------------------------------------

func weight() -> float:
	var total := 0.0
	for s in _stacks:
		total += s.weight()
	return total


func capacity() -> float:
	if capacity_override > 0.0:
		return capacity_override
	if is_player and is_inside_tree():
		var prog := get_tree().get_first_node_in_group("progression")
		if prog != null and prog.has_method("load_capacity"):
			return float(prog.call("load_capacity"))
	return DEFAULT_CAPACITY


func load_fraction() -> float:
	var cap := capacity()
	return weight() / cap if cap > 0.0 else 0.0


func is_overloaded() -> bool:
	return weight() > capacity()


func can_carry(item_id: String, amount: int = 1) -> bool:
	return weight() + float(ContentDB.get_or_empty(item_id).get("weight", 0.0)) * amount <= capacity()


func total_value() -> int:
	var total := 0
	for s in _stacks:
		total += s.value()
	return total


# --- marks -------------------------------------------------------------------------------

func add_marks(n: int) -> void:
	if n > 0:
		marks += n


## Removes up to n marks; returns how many were actually removed.
func remove_marks(n: int) -> int:
	var taken := mini(maxi(n, 0), marks)
	if taken > 0:
		marks -= taken
	return taken


func take_all_marks() -> int:
	return remove_marks(marks)


func can_afford(n: int) -> bool:
	return marks >= n


# --- using, dropping, transferring -------------------------------------------------------

## Uses one unit: consumables and ingredients are eaten (their effects are emitted through
## `item_used`, and EventBus.item_used for the player, for the status system to apply);
## equippable items are equipped through the matching Equipment node. Returns false if nothing happened.
func use(item: Variant) -> bool:
	var s := resolve(item)
	if s == null:
		return false
	if s.is_readable():
		return read(s)
	if s.is_equippable():
		var eq := _equipment_node()
		if eq != null and eq.has_method("equip"):
			return bool(eq.call("equip", s))
		return false
	if s.is_readable():
		return read(s)
	if not s.is_consumable():
		return false
	if s.is_ingredient():
		# eating an ingredient can teach an effect, which is the crafting node's business
		var crafting := _crafting_node()
		if crafting != null and crafting.has_method("eat_ingredient"):
			return bool(crafting.call("eat_ingredient", s.id)["ok"])
	var effects := use_effects(s)
	var item_id := s.id
	remove_stack(s, 1)
	item_used.emit(item_id, effects)
	if is_player:
		EventBus.item_used.emit(item_id, effects)
	return true


## Opens a book that is being carried. The book is not used up: what it teaches — a skill, a
## saying — is the progression node's business, hung off EventBus.book_opened so that reading
## one off a shelf and reading one out of the bag teach exactly the same thing.
func read(item: Variant) -> bool:
	var s := resolve(item)
	if s == null:
		return false
	var book := s.reads_book()
	if book == "":
		return false
	EventBus.book_opened.emit(book)
	return true


## The effect entries applying when a stack is eaten: potions and food carry their own;
## a raw ingredient yields its first effect at half strength.
static func use_effects(stack: ItemStack) -> Array:
	if stack.is_ingredient():
		var ids: Array = stack.def()["alchemy"].get("effects", [])
		if ids.is_empty():
			return []
		var eff := ContentDB.get_or_empty(str(ids[0]))
		return [{"effect": str(ids[0]), "magnitude": float(eff.get("magnitude_base", 0)) * 0.5, "duration": float(eff.get("duration_base", 0)) * 0.5, "raw": true}]
	var out: Array = []
	for e in stack.effect_entries():
		if not e.get("enchant", false):
			out.append(e)
	return out


## Removes `amount` units and places them in the world as a WorldItem in front of the carrier.
## Returns the spawned node (null when not in a 3D scene; the items are still removed).
func drop(item: Variant, amount: int = 1) -> Node:
	var s := resolve(item)
	if s == null:
		return null
	amount = mini(maxi(amount, 1), s.count)
	var item_id := s.id
	var data := s.data.duplicate(true)
	remove_stack(s, amount)
	if not is_inside_tree():
		return null
	var scene := load(WORLD_ITEM_SCENE) as PackedScene
	if scene == null:
		return null
	var wi := scene.instantiate()
	wi.set("item_id", item_id)
	wi.set("count", amount)
	wi.set("data", data)
	wi.set("from_bag", true)
	var origin := _carrier_3d()
	var parent: Node = origin.get_parent() if origin != null else get_tree().current_scene
	if parent == null:
		parent = get_tree().root
	var pos := Vector3.ZERO
	if origin != null:
		pos = origin.global_position - origin.global_transform.basis.z * 0.8 + Vector3.UP * 0.3
	parent.add_child.call_deferred(wi)
	wi.set_deferred("global_position", pos)
	return wi


## Moves `amount` units (-1 = all) of a stack into another bag, keeping instance data. Returns the amount moved.
func transfer_to(other: Inventory, item: Variant, amount: int = -1) -> int:
	var s := resolve(item)
	if s == null or other == null or other == self:
		return 0
	var n := s.count if amount < 0 else mini(amount, s.count)
	if n <= 0:
		return 0
	var item_id := s.id
	var data := s.data.duplicate(true)
	remove_stack(s, n)
	other.add(item_id, n, data)
	return n


## Moves every stack and all marks into another bag. Returns the number of units moved.
func transfer_all_to(other: Inventory) -> int:
	if other == null or other == self:
		return 0
	var moved := 0
	for s in _stacks.duplicate():
		moved += transfer_to(other, s, -1)
	other.add_marks(take_all_marks())
	return moved


func _equipment_node() -> Node:
	if not is_inside_tree():
		return null
	for n in get_tree().get_nodes_in_group("equipment"):
		if n.get("inventory") == self:
			return n
	return null


## The crafting node working out of this bag, if there is one.
func _crafting_node() -> Node:
	if not is_inside_tree():
		return null
	for n in get_tree().get_nodes_in_group("crafting"):
		if n.has_method("bag") and n.call("bag") == self:
			return n
	return null


func _carrier_3d() -> Node3D:
	var n: Node = get_parent()
	while n != null:
		if n is Node3D:
			return n
		n = n.get_parent()
	return null


# --- save --------------------------------------------------------------------------------

func to_save() -> Dictionary:
	var list: Array = []
	for s in _stacks:
		list.append(s.to_dict())
	return {"marks": marks, "next_uid": _next_uid, "capacity_override": capacity_override, "stacks": list}


func from_save(d: Dictionary) -> void:
	_stacks.clear()
	var max_uid := 0
	for sd in d.get("stacks", []):
		if typeof(sd) != TYPE_DICTIONARY:
			continue
		var s := ItemStack.from_dict(sd)
		if not s.is_valid():
			Log.warn("Inventory", "dropping unknown item '%s' from save" % s.id)
			continue
		if s.count <= 0:
			continue
		_stacks.append(s)
		max_uid = maxi(max_uid, s.uid)
	_next_uid = maxi(int(d.get("next_uid", 1)), max_uid + 1)
	# stacks saved before uids existed get one now
	for s in _stacks:
		if s.uid <= 0:
			s.uid = _next_uid
			_next_uid += 1
	capacity_override = float(d.get("capacity_override", capacity_override))
	marks = int(d.get("marks", 0))
	changed.emit()
