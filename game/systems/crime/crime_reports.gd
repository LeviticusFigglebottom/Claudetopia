class_name CrimeReports
extends Node
## The join between doing a wrong thing and the law hearing about it.
##
## `Bounty.commit()` makes the crime, works out who saw it, schedules their reports, raises the
## bounty and moves the morality needle. Two things in the game called it: picking a lock, and
## picking a pocket. Emptying a stranger's chest did not, and neither did killing a villager in
## their own kitchen — you could walk out of Merrowby with the steward's strongbox and his life
## and no guard in the region would ever hear of either.
##
## What is here is call sites, not new rules. The severities, the witness model, the reporting
## delay and the morality deltas all belong to `Crimes` and `Bounty` already; this only notices
## the moment and hands it over. Lockpicking and pickpocketing stay where they are, in
## `door_lock.gd` and `stealth.gd`, because the code that knows the attempt succeeded is the
## right code to report it — and reporting them twice would be worse than not at all.
##
## Two shapes of call site:
##   * the explicit one — a container emptied, an owned thing taken — where only the caller
##     knows what was taken and what it was worth;
##   * the listening one — a death on the event bus, where the victim having a name in the
##     roster is the whole difference between a hunt and a murder.

const GROUP := "crime_reports"
const PLAYER_GROUP := "player"


static func ensure() -> CrimeReports:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var found := tree.get_first_node_in_group(GROUP)
	if found is CrimeReports:
		return found as CrimeReports
	var made := CrimeReports.new()
	made.name = "CrimeReports"
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	host.add_child(made)
	return made


func _ready() -> void:
	add_to_group(GROUP)
	EventBus.entity_killed.connect(_on_killed)


func _exit_tree() -> void:
	if EventBus.entity_killed.is_connected(_on_killed):
		EventBus.entity_killed.disconnect(_on_killed)


# --- the moments ------------------------------------------------------------------------------

## Taking what is not yours. `value` is what it is worth, which is what decides the bounty;
## `target` is the thing taken from, so a witness's account names the chest and not just a day.
static func theft(actor: Node, at: Vector3, value: int, owner_npc: String,
		owner_faction: String, target: String = "") -> void:
	if not _is_the_player(actor) or not _owned_by_somebody_else(owner_npc, owner_faction):
		return
	_commit("theft", at, {"value": maxi(value, 0), "victim": owner_npc,
			"target": target, "faction_victim": owner_faction})


# --- the listening one ------------------------------------------------------------------------

## A death. A wolf is a hunt; a villager is a murder, and the difference is whether the thing
## that died had a name in the roster. The killer has to be the player: a guard cutting down a
## bandit is not the player's crime, and a villager killed by a drake is a tragedy, not a case.
func _on_killed(victim: Node, killer: Node, _content_id: String) -> void:
	if victim == null or not _is_the_player(killer):
		return
	var npc_id := _npc_id_of(victim)
	if npc_id == "":
		return
	var at := (victim as Node3D).global_position if victim is Node3D else Vector3.ZERO
	_commit("murder", at, {"victim": npc_id, "target": npc_id})


# --- plumbing ---------------------------------------------------------------------------------

static func _commit(kind: String, at: Vector3, opts: Dictionary) -> void:
	var bounty := Bounty.instance
	if bounty == null:
		# No law installed (a bare test host, the arena). Doing nothing is right; saying
		# nothing is not, because a crime that silently evaporates is how this got missed.
		Log.warn("CrimeReports", "%s at %s with no Bounty installed" % [kind, at])
		return
	bounty.commit(kind, at, opts)


static func _is_the_player(node: Node) -> bool:
	return node != null and is_instance_valid(node) and node.is_in_group(PLAYER_GROUP)


## Somebody else's, and somebody in particular. An unowned chest in a cave is nobody's loss.
static func _owned_by_somebody_else(owner_npc: String, owner_faction: String) -> bool:
	if owner_npc == "" and owner_faction == "":
		return false
	if owner_npc == Ownership.PLAYER:
		return false
	if owner_npc == "" and owner_faction != "" and Peers.is_player_member(owner_faction):
		return false
	return true


## The roster id of whatever just died, if it has one. An `Npc` carries it directly; anything
## else that knows its own name answers through `content_id()`.
static func _npc_id_of(victim: Node) -> String:
	var direct: Variant = victim.get("npc_id") if "npc_id" in victim else null
	if typeof(direct) == TYPE_STRING and str(direct) != "":
		return str(direct)
	if victim.has_method("content_id"):
		var id := str(victim.call("content_id"))
		if id.begins_with("core:npc/") or (ContentDB.has(id) and Ids.type_of(id) == "npc"):
			return id
	return ""
