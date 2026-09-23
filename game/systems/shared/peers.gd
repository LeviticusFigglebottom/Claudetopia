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


## The social façade (`Social`), for the two things it owns that no child node does: the work
## a board generates and the accepting of it. Found by name off the tree root rather than by
## the autoload identifier, so this file still has no dependency on the social stream and a
## test can put a stand-in in `overrides["social"]`.
static func social() -> Object:
	if overrides.has("social"):
		var o: Variant = overrides["social"]
		return o if o is Object and is_instance_valid(o) else null
	var tree := _tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Social")


static func progression() -> Object:
	return participant("progression")


## The character's modifier table (Progression.mods): perks, draughts, worn enchantments.
static func stat_mods() -> Modifiers:
	var p := progression()
	if p == null:
		return null
	var table: Variant = p.get("mods")
	return table as Modifiers if table is Modifiers else null


## The character's multiplier on a stat (Fair Dealing's `prices_buy` 0.9); 1 with no character.
static func stat_mult(stat: String) -> float:
	var m := stat_mods()
	return m.get_mult(stat) if m != null else 1.0


## The character's addition to a stat; 0 with no character.
static func stat_add(stat: String) -> float:
	var m := stat_mods()
	return m.get_add(stat) if m != null else 0.0


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


## The bag belonging to `actor`. Inventory API: add(item_id, count),
## remove(item_id, count), count(item_id). Resolved in order: an `inventory` property, the
## actor itself, a child node offering the API (the usual shape — an Inventory node under
## the actor). Only for the player, or when no actor is given, does this fall back to the
## registered "inventory" group node: an NPC without a bag must never resolve to the
## player's, or a pickpocket would rob the thief.
static func inventory_of(actor: Object) -> Object:
	if actor != null and is_instance_valid(actor):
		var inv: Variant = actor.get("inventory")
		if inv is Object and _has_inventory_api(inv):
			return inv
		if _has_inventory_api(actor):
			return actor
		if actor is Node:
			var child := _child_inventory(actor as Node)
			if child != null:
				return child
			if not (actor as Node).is_in_group("player"):
				return null
	var reg := inventory()
	if reg != null and _has_inventory_api(reg):
		return reg
	return null


## A direct child (or grandchild) offering the inventory API.
static func _child_inventory(node: Node, depth: int = 2) -> Object:
	for c in node.get_children():
		if _has_inventory_api(c):
			return c
	if depth > 1:
		for c in node.get_children():
			var found := _child_inventory(c, depth - 1)
			if found != null:
				return found
	return null


static func _has_inventory_api(o: Object) -> bool:
	return o.has_method("add") and o.has_method("remove") and o.has_method("count")


static func item_count(actor: Object, item_id: String) -> int:
	var inv := inventory_of(actor)
	return int(inv.call("count", item_id)) if inv != null else 0


## Adds items and reports whether they arrived. Inventories differ in what `add` returns —
## an ItemStack, a bool, an Error, or nothing, and `Inventory.add` returns null for an
## unknown item — so the result is judged by what the bag holds afterwards. An explicit
## `false` or a non-OK error is honoured directly.
static func give_item(actor: Object, item_id: String, count: int) -> bool:
	if count <= 0:
		return true
	var inv := inventory_of(actor)
	if inv == null:
		return false
	var before := int(inv.call("count", item_id))
	var r: Variant = inv.call("add", item_id, count)
	if typeof(r) == TYPE_BOOL:
		return r
	# An int may be an Error (0 = OK) or a units-added count (0 = nothing added), so the
	# bag itself decides.
	return int(inv.call("count", item_id)) > before


## Takes items and reports whether they left, judged the same way.
static func take_item(actor: Object, item_id: String, count: int) -> bool:
	if count <= 0:
		return true
	var inv := inventory_of(actor)
	if inv == null:
		return false
	var before := int(inv.call("count", item_id))
	if before < count:
		return false
	var r: Variant = inv.call("remove", item_id, count)
	match typeof(r):
		TYPE_BOOL:
			return r
		TYPE_INT:
			return int(r) >= count
	return int(inv.call("count", item_id)) <= before - count


## Items held, as [{item_id, count}] when the inventory offers items(); else [].
static func items_of(actor: Object) -> Array:
	var inv := inventory_of(actor)
	if inv != null and inv.has_method("items"):
		var r: Variant = inv.call("items")
		if typeof(r) == TYPE_ARRAY:
			return r
	return []
