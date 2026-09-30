class_name SiteFallen
extends RefCounted
## Who of a large site's people is dead, remembered in the save: a fort's garrison and the foes in
## a site's inside stay dead when the place is raised again (walked away from and back to, entered
## again, the game loaded), until a Hearthstone rest brings them back, the rule the rest of the
## country keeps (Enemy.reset_to_spawn on `hearthstone_rested`).
##
## Each one who can fall has a stable key (`<site id>/<group>/<n>`, the same build to build). A death
## sets the flag `site_fallen/<key>` to the count of rests at that moment; the one stands again once
## a rest has been counted since. Rests are counted in `GameState.counters["hearth_rests"]` by
## HearthSystem, at the rest itself (and on coming back from death, which is a rest).

const FLAG := "site_fallen/"
const RESTS := "hearth_rests"

static var _listening := false


## Kept for whatever raises a site's people: the rests are counted by HearthSystem now, from the
## first rest of a session rather than from the first site raised in it.
static func listen() -> void:
	_listening = true


## A rest counted (what HearthSystem does at one; the tests call it directly).
static func _on_rested(_id: String) -> void:
	GameState.inc(RESTS)


## Whether the one of `key` lies dead (killed since the last rest).
static func is_fallen(key: String) -> bool:
	var flag := FLAG + key
	if not GameState.flags.has(flag):
		return false
	var at := int(GameState.flags[flag])
	if GameState.count(RESTS) > at:
		GameState.clear_flag(flag)
		return false
	return true


## Remembers `enemy` under `key` when it dies.
static func watch(enemy: Enemy, key: String) -> void:
	if enemy == null:
		return
	listen()
	enemy.set_meta("site_key", key)
	enemy.died.connect(func(_killer: Node) -> void: fell(key))


static func fell(key: String) -> void:
	GameState.set_flag(FLAG + key, GameState.count(RESTS))
