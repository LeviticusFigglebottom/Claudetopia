class_name Ownership
extends Node
## Ownership registry (DESIGN §5.13): who owns an item, container, door, bed, animal or
## interior. Scene nodes carry ownership as metadata (`owner_faction`, `owner_npc`, set by
## `tag()` or by the inventory stream's container fields of the same names); abstract things
## (interior ids, bed ids, place-scoped keys) live in the registry by string id.
## The player's own things are marked owner_npc == PLAYER. Saved inside the "crime" section
## by Bounty (to_dict/from_dict).

static var instance: Ownership

const META_FACTION := "owner_faction"
const META_NPC := "owner_npc"
const PLAYER := "player"

var registry: Dictionary = {}   # id -> {"faction": String, "npc": String}


static func ensure() -> Ownership:
	if instance != null and is_instance_valid(instance):
		return instance
	var found := Service.ensure(load("res://systems/crime/ownership.gd"), "Ownership") as Ownership
	# A copy of this service inside a world set `instance` as it entered the tree and cleared it as it
	# left; a copy under the root that entered earlier is then found here with `instance` still empty,
	# and everything that reads `instance` directly finds nothing. Point it at what was found.
	if found != null and (instance == null or not is_instance_valid(instance)):
		instance = found
	return found


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


## Tags a scene node (and nothing else) with its owner.
static func tag(node: Node, faction: String = "", npc: String = "") -> void:
	if node == null:
		return
	if faction.is_empty():
		if node.has_meta(META_FACTION):
			node.remove_meta(META_FACTION)
	else:
		node.set_meta(META_FACTION, faction)
	if npc.is_empty():
		if node.has_meta(META_NPC):
			node.remove_meta(META_NPC)
	else:
		node.set_meta(META_NPC, npc)


## {faction, npc} for a node (metadata, then properties of the same names, then its parents)
## or a string id (registry). Empty strings mean unowned.
static func owner_of(node_or_id: Variant) -> Dictionary:
	if node_or_id is Node:
		var n: Node = node_or_id
		while n != null:
			var f := _read(n, META_FACTION)
			var o := _read(n, META_NPC)
			if not f.is_empty() or not o.is_empty():
				return {"faction": f, "npc": o}
			if n.has_meta("owner_stop") or n is Window:
				break
			n = n.get_parent()
		return {"faction": "", "npc": ""}
	var id := str(node_or_id)
	if instance != null and instance.registry.has(id):
		var e: Dictionary = instance.registry[id]
		return {"faction": str(e.get("faction", "")), "npc": str(e.get("npc", ""))}
	return {"faction": "", "npc": ""}


static func _read(n: Node, key: String) -> String:
	if n.has_meta(key):
		return str(n.get_meta(key))
	if key in n:
		return str(n.get(key))
	return ""


static func is_owned(node_or_id: Variant) -> bool:
	var o := owner_of(node_or_id)
	return not o["faction"].is_empty() or not o["npc"].is_empty()


## True when the thing belongs to someone other than `actor_id` (default: the player) and
## not to a faction the actor belongs to. Player faction membership comes from the Factions
## system when present; `actor_factions` lets NPCs pass their own.
static func is_owned_by_other(node_or_id: Variant, actor_id: String = PLAYER, actor_factions: Array = []) -> bool:
	var o := owner_of(node_or_id)
	var faction: String = o["faction"]
	var npc: String = o["npc"]
	if faction.is_empty() and npc.is_empty():
		return false
	if not npc.is_empty() and npc == actor_id:
		return false
	if not faction.is_empty():
		if faction in actor_factions:
			return false
		if actor_id == PLAYER and Peers.is_player_member(faction):
			return false
		return npc.is_empty() or npc != actor_id
	return true


func assign_owner(id: String, faction: String = "", npc: String = "") -> void:
	if faction.is_empty() and npc.is_empty():
		registry.erase(id)
	else:
		registry[id] = {"faction": faction, "npc": npc}


func clear_owner(id: String) -> void:
	registry.erase(id)


func claim_for_player(id: String) -> void:
	assign_owner(id, "", PLAYER)


func is_player_owned(id: String) -> bool:
	return owner_of(id)["npc"] == PLAYER


func owned_by(npc_id: String) -> Array[String]:
	var out: Array[String] = []
	for id in registry:
		if str(registry[id].get("npc", "")) == npc_id:
			out.append(id)
	out.sort()
	return out


func to_dict() -> Dictionary:
	return {"registry": registry.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	registry = d.get("registry", {}).duplicate(true)
