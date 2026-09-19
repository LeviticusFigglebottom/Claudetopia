class_name Peers
## Duck-typed lookups for systems owned by other streams (standing, factions, inventory,
## quests, progression, the player). Nothing here references another stream's class by name,
## so this compiles whether or not those systems exist yet. Lookups go through the autoload
## registries only: SaveSystem.participants (every system registers a save section) and the
## "player" scene group. Tests inject fakes with Peers.overrides[section] = fake.

static var overrides: Dictionary = {}

const DEFAULT_PROFILE := {"renown_tier": 0, "morality_tier": 0, "title": ""}


static func participant(section: String) -> Object:
	if overrides.has(section):
		var o: Variant = overrides[section]
		if o is Object and is_instance_valid(o):
			return o
		return null
	var p: Variant = SaveSystem.participants.get(section)
	if p is Object and is_instance_valid(p):
		return p
	return null


static func player() -> Node:
	if overrides.has("player"):
		var o: Variant = overrides["player"]
		return o if (o is Node and is_instance_valid(o)) else null
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return null
	return loop.get_first_node_in_group("player")


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


## {renown_tier: int 0..4, morality_tier: int -3..3 (negative = Hollow), title: String}.
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
	for m in ["rank_of", "rank", "get_rank"]:
		if f.has_method(m):
			return int(f.call(m, faction_id))
	return 0


static func faction_rep(faction_id: String) -> int:
	var f := factions()
	if f == null:
		return 0
	for m in ["rep_of", "reputation", "rep", "get_reputation"]:
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


## Gossip: does the rumour pool of `place_id` know `deed`? False when no gossip system exists.
static func knows_deed(place_id: String, deed: String) -> bool:
	for section in ["standing", "factions", "gossip"]:
		var o := participant(section)
		if o != null and o.has_method("knows_deed"):
			return bool(o.call("knows_deed", place_id, deed))
	return false


## Inventory API per ARCHITECTURE §5: add(item_id, count), remove(item_id, count), count(item_id).
## Resolves, in order: an `inventory` property on the actor, the actor itself, the registered
## inventory section. Returns null when nothing offers the API.
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
	return _ok(inv.call("add", item_id, count))


static func take_item(actor: Object, item_id: String, count: int) -> bool:
	var inv := inventory_of(actor)
	if inv == null or item_count(actor, item_id) < count:
		return false
	return _ok(inv.call("remove", item_id, count))


## Inventory calls may return nothing, a bool, or an Error code; all of these mean success
## except an explicit false or a non-OK error.
static func _ok(r: Variant) -> bool:
	match typeof(r):
		TYPE_NIL:
			return true
		TYPE_BOOL:
			return r
		TYPE_INT:
			return int(r) == OK
		_:
			return true
