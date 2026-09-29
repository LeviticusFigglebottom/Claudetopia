class_name Lockpicking
extends RefCounted
## One try at a lock, whoever's it is: a door's DoorLock or a locked WorldContainer (a chest, the
## tithe strongbox at Moreva). The UI's lockpick screen (ui/inventory/lockpick_screen.gd) sweeps a
## needle and calls the lock's `attempt(actor, timing_accuracy)`, which comes here: Stealth's rule
## (the window widens with Sneak and narrows with the lock), a pick snapped on a bad miss, Sneak
## practised, the crime committed when the thing is somebody else's, and the lesson told
## (`pick_lock`, EventBus.act_done). The lock itself unlocks on success; this does not.

const DEFAULT_XP_PER_LEVEL := 3.0

static var _default_pick := ""


## The pick the lock takes: the first item tagged "lockpick".
static func pick_id() -> String:
	if _default_pick.is_empty() and ContentDB.is_loaded:
		_default_pick = ContentQuery.id_of_first_with_tag("item", "lockpick")
	return _default_pick


static func has_pick(actor: Object) -> bool:
	var pick := pick_id()
	return not pick.is_empty() and Peers.item_count(actor, pick) > 0


## {success, broke, window, margin}. `target` is what is being opened (for the crime and the act).
static func attempt(target: Node, actor: Node, lock_level: int, timing_accuracy: float, pick := "",
		xp_per_level := DEFAULT_XP_PER_LEVEL) -> Dictionary:
	var r := Stealth.lockpick_attempt(Peers.skill_level("sneak"), lock_level, timing_accuracy)
	Foley.play("lockpick_break" if r["broke"] else "lockpick_click")
	if r["broke"]:
		var used := pick if not pick.is_empty() else pick_id()
		if not used.is_empty():
			Peers.take_item(actor, used, 1)
		EventBus.notify.emit("Your pick snaps.", "info")
	if r["success"]:
		EventBus.skill_used.emit("sneak", 5.0 + xp_per_level * lock_level)
		var ledger := Bounty.ensure()
		if target != null and ledger != null and Ownership.is_owned_by_other(target):
			var pos := (target as Node3D).global_position if target is Node3D else Vector3.ZERO
			ledger.commit("lockpicking", pos, {"target": str(target.get_path()) if target.is_inside_tree() else str(target.name)})
		EventBus.act_done.emit("pick_lock", actor, target, "")
	return r
