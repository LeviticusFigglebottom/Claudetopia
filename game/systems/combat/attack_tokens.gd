class_name AttackTokens
extends RefCounted
## Turn-taking among foes on one body (playtest 2026-09-27, 8: "fights against several enemies at
## once almost impossible"). Every foe that saw a blow ready threw it, so three bandits wound up
## together and landed together, and no guard, roll or parry answers three blows in one moment.
##
## A foe now asks for one of its target's tokens before it begins an attack (Enemy._tick_combat)
## and gives it back when the attack is over (_finish_attack, an interruption, its death). A body
## has MOST tokens, and a token is not given within GAP_S of the last one, so blows come by turns;
## the rest hold off on the edge of the fight, circling, until a token is free (Enemy._hold_off).
## A boss is never kept waiting, but its blow holds a token all the same, so its adds wait on it.
##
## Pure bookkeeping with no nodes of its own: the holders are kept per target instance id, and
## anything stale (a holder freed, dead, no longer attacking, or holding past HELD_MOST_S) is let
## go whenever the target's tokens are asked about.

## How many foes may be in an attack on one body at once.
const MOST := 2
## The least time between two foes' attacks beginning on one body (s).
const GAP_S := 0.45
## A token held this long is let go whatever its holder is doing (s): nothing swings for longer.
const HELD_MOST_S := 6.0

## target id -> {"holders": {holder id: [holder, since]}, "last": time a token was last given}
static var _by_target: Dictionary = {}


static func _now() -> float:
	return Actor.now()


## Whether `who` may begin an attack on `target` now, taking a token if so. A holder asking again
## keeps the one it has. `always` (a boss) takes one past MOST and GAP_S.
static func take(target: Node, who: Node, always := false) -> bool:
	if target == null or who == null or not is_instance_valid(target):
		return true
	var entry := _entry(target)
	var holders: Dictionary = entry["holders"]
	var id := who.get_instance_id()
	var t := _now()
	if holders.has(id):
		holders[id] = [who, t]
		return true
	if not always:
		if holders.size() >= MOST or t - float(entry["last"]) < GAP_S:
			return false
	holders[id] = [who, t]
	entry["last"] = t
	return true


## Whether a token would be given `who` now (without taking it).
static func could_take(target: Node, who: Node) -> bool:
	if target == null or who == null or not is_instance_valid(target):
		return true
	var entry := _entry(target)
	var holders: Dictionary = entry["holders"]
	if holders.has(who.get_instance_id()):
		return true
	return holders.size() < MOST and _now() - float(entry["last"]) >= GAP_S


## Gives back `who`'s token on `target` (or on every target, when `target` is null).
static func give_back(target: Node, who: Node) -> void:
	if who == null:
		return
	var id := who.get_instance_id()
	if target != null and is_instance_valid(target):
		var tid := target.get_instance_id()
		if _by_target.has(tid):
			(_by_target[tid]["holders"] as Dictionary).erase(id)
		return
	for tid in _by_target:
		(_by_target[tid]["holders"] as Dictionary).erase(id)


## How many foes hold a token on `target` now.
static func held_on(target: Node) -> int:
	if target == null or not is_instance_valid(target):
		return 0
	return (_entry(target)["holders"] as Dictionary).size()


static func clear() -> void:
	_by_target.clear()


static func _entry(target: Node) -> Dictionary:
	var tid := target.get_instance_id()
	if not _by_target.has(tid):
		_by_target[tid] = {"holders": {}, "last": -100.0}
	var entry: Dictionary = _by_target[tid]
	var holders: Dictionary = entry["holders"]
	var t := _now()
	for id in holders.keys():
		var h: Array = holders[id]
		var who: Variant = h[0]
		if not is_instance_valid(who) or t - float(h[1]) > HELD_MOST_S or not _still_attacking(who as Node):
			holders.erase(id)
	return entry


static func _still_attacking(who: Node) -> bool:
	if who.has_method("holds_attack_token"):
		return bool(who.call("holds_attack_token"))
	return true
