class_name WorldContainer
extends StaticBody3D
## A chest, barrel, corpse-pack or cupboard in the world: an Inventory with an owner, a loot
## table rolled on first opening, and optional respawn. State (contents, opened count, lock)
## persists across streaming and saves through a shared store registered as the "containers"
## save section, keyed by `container_id`.
##
## Ownership (`owner_faction`, `owner_npc`) is read by the crime stream: taking from an owned
## container is theft unless the actor belongs there. Locks are opened by the stealth stream's
## lockpicking (call unlock()) or by carrying `key_item`.

signal opened(container: WorldContainer, actor: Node)
signal looted(container: WorldContainer, actor: Node)

const SAVE_SECTION := "containers"
const INTERACT_LAYER := 1 << 4   # 3d_physics/layer_5 "interactable"

## Persistent id; empty derives one from the node name and rounded position (stable per placement).
@export var container_id: String = ""
@export var display_name: String = "Chest"
@export var loot_table: String = ""
@export var owner_faction: String = ""
@export var owner_npc: String = ""
@export var respawn: bool = false
@export var respawn_hours: float = 72.0
@export var locked: bool = false
@export var lock_level: int = 0
@export var key_item: String = ""

var inventory: Inventory = null
var opened_count: int = 0
var last_opened_hours: float = -1.0


## Shared persistent state for every container, registered once with SaveSystem.
class Store:
	extends RefCounted
	var states: Dictionary = {}   # container_id -> {opened_count, last_opened_hours, locked, inventory}

	func to_save() -> Dictionary:
		return {"states": states.duplicate(true)}

	func from_save(d: Dictionary) -> void:
		var s: Variant = d.get("states", {})
		states = s.duplicate(true) if typeof(s) == TYPE_DICTIONARY else {}

	func clear() -> void:
		states.clear()


static var store: Store = Store.new()
static var _store_registered := false


func _ready() -> void:
	add_to_group("interactable")
	collision_layer = INTERACT_LAYER
	collision_mask = 0
	if container_id == "":
		container_id = _derive_id()
	if inventory == null:
		inventory = get_node_or_null("Inventory") as Inventory
	if inventory == null:
		inventory = Inventory.new()
		inventory.name = "Inventory"
		inventory.capacity_override = 10000.0
		add_child(inventory)
	# A body with no shape is a body the ray goes through. `house_interior.gd` gives its
	# chests a shape the size of the prop, which is better than anything this can guess — but
	# a caller that does not know to is left with a chest you cannot open, and that is the
	# same failure as being on the wrong physics layer. A default is better than nothing.
	if find_children("*", "CollisionShape3D", true, false).is_empty():
		var shape := CollisionShape3D.new()
		var form := BoxShape3D.new()
		form.size = Vector3(0.9, 0.6, 0.55)
		shape.shape = form
		shape.position.y = form.size.y * 0.5
		add_child(shape)
	register_store()
	restore_state()
	inventory.changed.connect(_persist)
	if not EventBus.game_loaded.is_connected(_on_game_loaded):
		EventBus.game_loaded.connect(_on_game_loaded)


func _exit_tree() -> void:
	if EventBus.game_loaded.is_connected(_on_game_loaded):
		EventBus.game_loaded.disconnect(_on_game_loaded)


static func register_store() -> void:
	if not _store_registered:
		SaveSystem.register(SAVE_SECTION, store)
		_store_registered = true


func _derive_id() -> String:
	var p := global_position if is_inside_tree() else position
	return "%s@%d_%d_%d" % [name, roundi(p.x), roundi(p.y), roundi(p.z)]


# --- interaction -------------------------------------------------------------------------

func prompt_text() -> String:
	var label := display_name
	if locked:
		label += " (Locked)"
	elif is_owned():
		label += " (Owned)"
	return "Open %s" % label


## What has been taken out of here since it was opened, in marks, and not yet reported.
var _stolen := 0
## Whether this container's loot table has already been rolled. Persisted, because it is the
## difference between a chest you have already looked in and one that is about to mint a
## second haul on top of the first.
var rolled := false


func is_owned() -> bool:
	return owner_faction != "" or owner_npc != ""


## True when the actor's inventory holds the key.
func actor_has_key(actor: Node) -> bool:
	if key_item == "":
		return false
	var inv := Inventory.for_actor(actor)
	return inv != null and inv.has(key_item)


## Opens the container: rolls loot the first time (or after a respawn), then emits `opened`
## and EventBus.container_opened for the UI to show the transfer screen. Locked containers
## open only with the key; returns false otherwise.
func interact(actor: Node) -> bool:
	if locked:
		if actor_has_key(actor):
			unlock()
		else:
			return false
	ensure_loot()
	opened_count += 1
	last_opened_hours = now_hours()
	_persist()
	opened.emit(self, actor)
	EventBus.container_opened.emit(self, actor)
	return true


func unlock() -> void:
	if locked:
		locked = false
		_persist()


## Moves everything into the actor's inventory. Returns units moved (marks not counted).
func take_all(actor: Node) -> int:
	var inv := Inventory.for_actor(actor)
	if inv == null:
		return 0
	var worth := _worth_of_contents()
	var moved := inventory.transfer_all_to(inv)
	_stolen += worth
	looted.emit(self, actor)
	close_up(actor)
	return moved


## Moves one stack into the actor's bag. Returns false when it will not fit or is not here.
func take(stack: Variant, actor: Node) -> bool:
	var inv := Inventory.for_actor(actor)
	if inv == null:
		return false
	var s: ItemStack = inventory.resolve(stack)
	if s == null or not inventory.holds(s):
		return false
	var worth := int(s.value())
	# Read the stack before removing it: `remove_stack` empties it, and an emptied stack adds
	# nothing to the bag on the other side.
	var id := s.id
	var how_many := s.count
	var extra := s.data.duplicate(true)
	inventory.remove_stack(s)
	if inv.add(id, how_many, extra) == null:
		inventory.add(id, how_many, extra)      # it would not fit; put it back
		return false
	_stolen += worth
	looted.emit(self, actor)
	return true


## Takes the money. Kept apart from the stacks because marks are not an item.
func take_marks(actor: Node) -> int:
	var inv := Inventory.for_actor(actor)
	if inv == null or inventory.marks <= 0:
		return 0
	var taken := inventory.remove_marks(inventory.marks)
	inv.add_marks(taken)
	_stolen += taken
	looted.emit(self, actor)
	return taken


## Called when the player is finished with the chest. Emptying somebody's strongbox item by
## item is one theft, not nine: the law hears about the visit, not each handful, or a chest
## with nine things in it would put nine separate accounts in front of the same witness.
func close_up(actor: Node) -> void:
	if _stolen <= 0:
		_stolen = 0
		return
	var worth := _stolen
	_stolen = 0
	CrimeReports.theft(actor, global_position, worth, owner_npc, owner_faction, container_id)


## What is in here, in marks. The bounty for a theft is a fraction of what was taken, so an
## empty crate in a stranger's byre is not the same crime as their strongbox.
func _worth_of_contents() -> int:
	return int(inventory.total_value()) + int(inventory.marks)


# --- loot --------------------------------------------------------------------------------

## Rolls the loot table once, and again only if this container respawns and enough hours have
## passed since it was last opened. Deterministic per container and opening.
##
## The test is `rolled`, not `opened_count == 0`. A container can hold its haul without ever
## having been opened — a chest whose contents were rolled and then saved — and reading the
## count would roll a second haul on top of the restored one the first time anybody looked.
func ensure_loot() -> void:
	var needs := not rolled
	if not needs and respawn and last_opened_hours >= 0.0 and now_hours() - last_opened_hours >= respawn_hours:
		inventory.clear()
		needs = true
	if not needs or loot_table == "" or not ContentDB.has(loot_table):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(container_id) ^ GameState.seed ^ (opened_count * 7919)
	for r in LootTable.roll_merged(loot_table, rng, loot_context()):
		if r.has("marks"):
			inventory.add_marks(int(r["marks"]))
		else:
			inventory.add(str(r["item"]), int(r["count"]), r.get("data", {}))
	rolled = true
	_persist()


func loot_context() -> Dictionary:
	return LootTable.default_context()


static func now_hours() -> float:
	return float(WorldClock.day - 1) * 24.0 + WorldClock.time_hours


# --- persistence -------------------------------------------------------------------------

func _persist() -> void:
	store.states[container_id] = {
		"opened_count": opened_count, "last_opened_hours": last_opened_hours, "locked": locked,
		"rolled": rolled, "inventory": inventory.to_save(),
	}


## Re-reads this container's state from the store (after a load).
func restore_state() -> void:
	if not store.states.has(container_id):
		return
	var st: Dictionary = store.states[container_id]
	opened_count = int(st.get("opened_count", 0))
	# An old save has no `rolled`; a container it recorded as opened had certainly rolled.
	rolled = bool(st.get("rolled", opened_count > 0))
	last_opened_hours = float(st.get("last_opened_hours", -1.0))
	locked = bool(st.get("locked", locked))
	var inv: Variant = st.get("inventory", {})
	if typeof(inv) == TYPE_DICTIONARY:
		if inventory.changed.is_connected(_persist):
			inventory.changed.disconnect(_persist)
		inventory.from_save(inv)
		inventory.changed.connect(_persist)


func _on_game_loaded(_slot: String) -> void:
	restore_state()


## Forgets this container's persisted state (tests, debug).
func forget_state() -> void:
	store.states.erase(container_id)
	opened_count = 0
	last_opened_hours = -1.0
	inventory.clear()
