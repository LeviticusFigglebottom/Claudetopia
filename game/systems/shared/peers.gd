class_name Peers
## Duck-typed lookups for systems owned by other streams (standing, factions, inventory,
## quests, progression, the player). Nothing here references another stream's class by name,
## so this compiles whether or not those systems exist yet. Lookup order per system:
## a test override, the scene group of the same name (contract: "inventory", "standing",
## "factions", "quests", "progression", "player"), then the SaveSystem participant of that
## section. Tests inject fakes with Peers.overrides[name] = fake.
##
## Contracted APIs (coordinator): Inventory node (group "inventory"): marks: int,
## add_marks(n), remove_marks(n) -> int, add(item_id, count), remove(item_id, count) -> int,
## count(item_id) -> int, items() -> Array[{item_id, count}]. Standing (group "standing"):
## reaction_profile() -> {renown, renown_tier, morality, morality_tier, title}. Factions
## (group "factions"): reputation(id), rank(id), is_member(id), law_faction_for_region(region_id).

static var overrides: Dictionary = {}

const DEFAULT_PROFILE := {"renown": 0, "renown_tier": 0, "morality": 0, "morality_tier": 0, "title": ""}


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func participant(name: String) -> Object:
	if overrides.has(name):
		var o: Variant = overrides[name]
		if o is Object and is_instance_valid(o):
			return o
		return null
	var tree := _tree()
	if tree != null:
		var n := tree.get_first_node_in_group(name)
		if n != null:
			return n
	var p: Variant = SaveSystem.participants.get(name)
	if p is Object and is_instance_valid(p):
		return p
	return null


static func player() -> Node:
	var p := participant("player")
	return p if p is Node else null


static func standing() -> Object:
	return participant("standing")


static func factions() -> Object:
	return participant("factions")


static func inventory() -> Object:
	return participant("inventory")


static func quests() -> Object:
	return participant("quests")


static func progression() -> Object:
	return participant("progression")


## {renown, renown_tier 0..4, morality, morality_tier -3..3 (negative = Hollow), title}.
static func reaction_profile() -> Dictionary:
	var s := standing()
	if s != null and s.has_method("reaction_profile"):
		var p: Variant = s.call("reaction_profile")
		if typeof(p) == TYPE_DICTIONARY:
			var out := DEFAULT_PROFILE.duplicate()
			out.merge(p, true)
			return out
	return DEFAULT_PROFILE.duplicate()


static func skill_level(skill_id: String) -> int:
	var p := progression()
	if p == null:
		return 0
	for m in ["skill_level", "level_of", "get_level", "level"]:
		if p.has_method(m):
			return int(p.call(m, skill_id))
	var skills: Variant = p.get("skills")
	if typeof(skills) == TYPE_DICTIONARY and skills.has(skill_id):
		var v: Variant = skills[skill_id]
		if typeof(v) == TYPE_DICTIONARY:
			return int(v.get("level", 0))
		return int(v)
	return 0


static func faction_rank(faction_id: String) -> int:
	var f := factions()
	if f == null:
		return 0
	for m in ["rank", "rank_of", "get_rank"]:
		if f.has_method(m):
			return int(f.call(m, faction_id))
	return 0


static func faction_rep(faction_id: String) -> int:
	var f := factions()
	if f == null:
		return 0
	for m in ["reputation", "rep_of", "rep", "get_reputation"]:
		if f.has_method(m):
			return int(f.call(m, faction_id))
	return 0


static func is_player_member(faction_id: String) -> bool:
	var f := factions()
	if f == null:
		return false
	for m in ["is_member", "joined"]:
		if f.has_method(m):
			return bool(f.call(m, faction_id))
	return faction_rank(faction_id) > 0


## Law faction of a region from the Factions system when it offers one; "" when none.
## Returns null when the Factions system is absent (callers fall back to region data).
static func law_faction_for_region(region_id: String) -> Variant:
	var f := factions()
	if f != null and f.has_method("law_faction_for_region"):
		var v: Variant = f.call("law_faction_for_region", region_id)
		return str(v) if v != null else ""
	return null


## Gossip: does the rumour pool of `place_id` know `deed`? False when no gossip system exists.
static func knows_deed(place_id: String, deed: String) -> bool:
	for name in ["gossip", "standing", "factions"]:
		var o := participant(name)
		if o != null and o.has_method("knows_deed"):
			return bool(o.call("knows_deed", place_id, deed))
	return false


## Inventory API: add(item_id, count), remove(item_id, count) -> int, count(item_id) -> int.
## Resolves, in order: an `inventory` property on the actor, the actor itself, the
## "inventory" group node / registered section. Returns null when nothing offers the API.
static func inventory_of(actor: Object) -> Object:
	if actor != null and is_instance_valid(actor):
		var inv: Variant = actor.get("inventory")
		if inv is Object and _has_inventory_api(inv):
			return inv
		if _has_inventory_api(actor):
			return actor
	var reg := inventory()
	if reg != null and _has_inventory_api(reg):
		return reg
	return null


static func _has_inventory_api(o: Object) -> bool:
	return o.has_method("add") and o.has_method("remove") and o.has_method("count")


static func item_count(actor: Object, item_id: String) -> int:
	var inv := inventory_of(actor)
	return int(inv.call("count", item_id)) if inv != null else 0


static func give_item(actor: Object, item_id: String, count: int) -> bool:
	var inv := inventory_of(actor)
	if inv == null:
		return false
	var r: Variant = inv.call("add", item_id, count)
	match typeof(r):
		TYPE_BOOL:
			return r
		TYPE_INT:
			return int(r) == OK or int(r) >= count
	return true


static func take_item(actor: Object, item_id: String, count: int) -> bool:
	var inv := inventory_of(actor)
	if inv == null or item_count(actor, item_id) < count:
		return false
	var r: Variant = inv.call("remove", item_id, count)
	match typeof(r):
		TYPE_BOOL:
			return r
		TYPE_INT:
			return int(r) >= count or int(r) == OK and item_count(actor, item_id) >= 0
	return true


## Items held, as [{item_id, count}] when the inventory offers items(); else [].
static func items_of(actor: Object) -> Array:
	var inv := inventory_of(actor)
	if inv != null and inv.has_method("items"):
		var r: Variant = inv.call("items")
		if typeof(r) == TYPE_ARRAY:
			return r
	return []
