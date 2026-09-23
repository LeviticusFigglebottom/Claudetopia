class_name DoorLock
extends Node
## Lock component for doors and containers. Add it as a child named exactly "DoorLock" of a
## Door (res://systems/interiors/door.tscn) or of a chest; the parent's `interact(actor)`
## forwards here through the contracted pair `is_locked()` / `try_open(actor)`. A key opens
## it outright; otherwise `try_open` starts the lockpick minigame (the UI stream shows the
## timing bar and calls `attempt(actor, timing_accuracy)` per try) and returns false so the
## door stays shut. Picking something owned by someone else is the crime "lockpicking".
## Ownership comes from this node's exports, or from the parent Door's own
## `owner_faction`/`owner_npc` fields when they are set there.

signal unlocked(by: Node)
signal lockpick_started(lock: DoorLock)
signal attempt_made(result: Dictionary)
signal pick_broken

@export_range(1, 5) var lock_level := 1
@export var locked := true
@export var key_item := ""          # item id that opens this lock
@export var lockpick_item := ""     # defaults to the first item tagged "lockpick"
@export var owner_faction := ""
@export var owner_npc := ""
@export var xp_per_level := 3.0

var picking := false
var attempts := 0

static var _default_pick := ""


func _ready() -> void:
	var parent := get_parent()
	if parent == null:
		return
	# A Door carries its own owner fields; adopt them when this node leaves them blank.
	if owner_faction.is_empty() and "owner_faction" in parent:
		owner_faction = str(parent.get("owner_faction"))
	if owner_npc.is_empty() and "owner_npc" in parent:
		owner_npc = str(parent.get("owner_npc"))
	if not owner_faction.is_empty() or not owner_npc.is_empty():
		Ownership.tag(parent, owner_faction, owner_npc)


func target() -> Node:
	return get_parent()


## --- Door contract -------------------------------------------------------------------------

func is_locked() -> bool:
	return locked


## True when the door may open now (unlocked, or unlocked by a key the actor carries).
## False leaves it shut and, when the actor has a pick, starts the lockpick minigame.
func try_open(actor: Node) -> bool:
	var r := interact(actor)
	return bool(r.get("ok", false))


func lockpick_item_id() -> String:
	if not lockpick_item.is_empty():
		return lockpick_item
	if _default_pick.is_empty() and ContentDB.is_loaded:
		_default_pick = ContentQuery.id_of_first_with_tag("item", "lockpick")
	return _default_pick


func has_key(actor: Object) -> bool:
	return not key_item.is_empty() and Peers.item_count(actor, key_item) > 0


func has_pick(actor: Object) -> bool:
	var pick := lockpick_item_id()
	return not pick.is_empty() and Peers.item_count(actor, pick) > 0


## {ok, state: open | unlocked_with_key | locked | no_pick, lock_level, window}
func interact(actor: Node) -> Dictionary:
	if not locked:
		return {"ok": true, "state": "open"}
	if has_key(actor):
		unlock(actor)
		return {"ok": true, "state": "unlocked_with_key"}
	var window := Stealth.lockpick_window(Peers.skill_level("sneak"), lock_level)
	if not has_pick(actor):
		EventBus.notify.emit("Locked. You have nothing to pick it with.", "info")
		return {"ok": false, "state": "no_pick", "lock_level": lock_level, "window": window}
	picking = true
	lockpick_started.emit(self)
	return {"ok": false, "state": "locked", "lock_level": lock_level, "window": window}


## One pick attempt. timing_accuracy 0 = perfect. Consumes a pick on a snap.
func attempt(actor: Node, timing_accuracy: float) -> Dictionary:
	if not locked:
		return {"success": true, "broke": false, "window": 1.0, "margin": 1.0}
	var skill := Peers.skill_level("sneak")
	var r := Stealth.lockpick_attempt(skill, lock_level, timing_accuracy)
	attempts += 1
	Foley.play("lockpick_break" if r["broke"] else "lockpick_click")
	if r["broke"]:
		var pick := lockpick_item_id()
		if not pick.is_empty():
			Peers.take_item(actor, pick, 1)
		pick_broken.emit()
		EventBus.notify.emit("Your pick snaps.", "info")
		if not has_pick(actor):
			picking = false
	if r["success"]:
		EventBus.skill_used.emit("sneak", 5.0 + xp_per_level * lock_level)
		var t := target()
		var ledger := Bounty.ensure()
		if t != null and ledger != null and Ownership.is_owned_by_other(t):
			var pos := (t as Node3D).global_position if t is Node3D else Vector3.ZERO
			ledger.commit("lockpicking", pos, {"target": str(t.get_path())})
		unlock(actor)
	attempt_made.emit(r)
	return r


func unlock(by: Node) -> void:
	locked = false
	picking = false
	var t := target()
	if t != null:
		t.set_meta("locked", false)
	unlocked.emit(by)


func lock() -> void:
	locked = true
	var t := target()
	if t != null:
		t.set_meta("locked", true)


func cancel() -> void:
	picking = false


func prompt_text(actor: Object = null) -> String:
	if not locked:
		return "Open"
	if actor != null and has_key(actor):
		return "Unlock"
	return "Pick lock (%s)" % Stealth.lock_level_name(lock_level)
