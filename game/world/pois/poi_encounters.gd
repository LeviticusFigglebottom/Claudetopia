class_name PoiEncounters
extends EnemySpawner
## What a point of interest's `encounter` sentence says is there, standing there.
##
## Every POI has carried a sentence since the registry was written — "two bandits shake down
## late travellers after dark", "a crag-wolf pack in the skull" — and nothing read it but the
## dressing, for its props. The world builder keeps the country's own encounters off every pad
## (`worldgen/encounters.py`), so the places a player is drawn to were the one kind of ground in
## the country sure to be empty, and the Hart of Thorns, whose arena is the Standing Moot rather
## than a deep place, was stood up by nothing at all: the main quest's kill could not be done.
##
## The sentence stays the author's. An `encounter` def (`content/packs/core/encounters/`, CONTRACTS
## `{id, place, spawns}`) says the same thing in terms the game can stand up, one entry per group:
##
##   {"enemy": id, "count": 1, "when": "always|day|night|dawn|dusk|midnight", "at": marker,
##    "spread": 2.5}
##
## `at` names a marker the dressing put down (the Tumbled Watch's `stair_hall`); without one the
## group stands on the pad's rim, the same place every time and out of the water. `when` is read
## off the clock as the cell is raised and again every hour it stands: the ford's bandits step out
## after dark and are gone by morning, unless they are busy with you. A boss once put down
## (`boss_deed/<id>`, which `Social` sets) stays down; its fight is bounded the way any boss's
## outside a deep place is, by the arena it improvises when it wakes.
##
## One of these is a child of the dressing, so it streams and unloads with the cell. The index of
## defs is static, for `QuestWalk`, which asks where a foe stands.

const GROUP := "poi_encounters"
const WHEN := ["always", "day", "night", "dawn", "dusk", "midnight"]
## How far round the pad's rim a group without a marker stands, as a share of the flat radius.
const RIM := 0.62

static var _by_place: Dictionary = {}    # place id -> Array of spawn entries
static var _foes: Dictionary = {}        # enemy id -> Array of place ids
static var _built := false

var poi_id := ""
var entries: Array = []
var pad_radius := 25.0
var terrain: TerrainProvider = null
var _groups: Dictionary = {}             # entry index -> Array[Enemy], the living and the fallen, while raised


# --- the index ----------------------------------------------------------------------------------------

static func reset() -> void:
	_by_place.clear()
	_foes.clear()
	_built = false


static func _build() -> void:
	if _built:
		return
	_built = true
	var defs := ContentDB.all("encounter")
	defs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	for def in defs:
		var place := str(def.get("place", ""))
		for s in def.get("spawns", []):
			if typeof(s) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = s
			var enemy := str(entry.get("enemy", ""))
			if place == "" or not ContentDB.has(enemy):
				continue
			(_by_place.get_or_add(place, []) as Array).append(entry)
			var at: Array = _foes.get_or_add(enemy, [])
			if not at.has(place):
				at.append(place)


## The spawn entries every encounter def gives this place.
static func of(place_id: String) -> Array:
	_build()
	return _by_place.get(place_id, [])


## The places whose encounters stand this enemy up.
static func foes_at(enemy_id: String) -> Array:
	_build()
	return _foes.get(enemy_id, [])


## Whether a `when` holds at this hour of the day (0-24).
static func is_open(when: String, hour: float) -> bool:
	match when:
		"", "always":
			return true
		"day":
			return not _night(hour)
		"night":
			return _night(hour)
		"dawn":
			return hour >= 4.5 and hour < 8.5
		"dusk":
			return hour >= 18.5 and hour < 22.0
		"midnight":
			return hour >= 23.0 or hour < 2.0
	return false


static func _night(hour: float) -> bool:
	return hour < 5.5 or hour >= 20.5


## Stands up whatever this dressing's place is said to have, as a child of the dressing. Null
## when the sentence says nobody is there. Called by `WorldPois` for a near cell only.
static func stand_up(d: PoiDressing) -> PoiEncounters:
	var wanted := of(d.poi_id)
	if wanted.is_empty() or d.far:
		return null
	var node := PoiEncounters.new()
	node.name = "Encounters"
	node.poi_id = d.poi_id
	node.entries = wanted
	node.pad_radius = d.pad_radius
	node.terrain = d._provider
	d.add_child(node)
	return node


# --- standing there -------------------------------------------------------------------------------------

func _init() -> void:
	spawn_on_ready = false
	respawn_on_rest = true
	drop_to_ground = false


func _ready() -> void:
	super._ready()
	add_to_group(GROUP)
	EventBus.hour_changed.connect(_on_hour_changed)
	call_deferred("refresh")


func _on_hour_changed(_hour: int) -> void:
	refresh()


## Brings each group in or out to match the clock and what has been put down. A group that
## was raised and killed is not raised again on the hour: it stays dead until a Hearthstone
## rest brings it back, the rule the rest of the country keeps.
func refresh() -> void:
	if not is_inside_tree():
		return
	for i in entries.size():
		var e: Dictionary = entries[i]
		var open := is_open(str(e.get("when", "always")), WorldClock.time_hours) and not _put_down(e)
		if open and not _groups.has(i):
			_raise(i, e)
		elif not open and _groups.has(i):
			_stand_down(i)


## The living members of one group.
func standing(index: int) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for e in _groups.get(index, []):
		if is_instance_valid(e) and not (e as Enemy).dead and not (e as Enemy).is_queued_for_deletion():
			out.append(e)
	return out


func _put_down(e: Dictionary) -> bool:
	var id := str(e.get("enemy", ""))
	return Ids.type_of(id) == "boss" and GameState.has_flag("boss_deed/" + id)


func _raise(index: int, e: Dictionary) -> void:
	var count := maxi(1, int(e.get("count", 1)))
	var spread := float(e.get("spread", 2.5))
	var anchor := _anchor(index, e)
	var facing := atan2(global_position.x - anchor.x, global_position.z - anchor.z)
	var group: Array[Enemy] = []
	for k in count:
		var at := anchor
		if count > 1:
			var a := TAU * float(k) / float(count) + float(index)
			at += Vector3(cos(a), 0.0, sin(a)) * spread
		at.y = _ground(at)
		var enemy := spawn_one(str(e["enemy"]), at, facing, {"group": "%s#%d" % [poi_id, index]})
		if enemy != null:
			group.append(enemy)
	_groups[index] = group


## Gone with the hour, the fallen with them, except whoever is fighting you: they finish what
## they started, and the group is gone once they have.
func _stand_down(index: int) -> void:
	var kept: Array[Enemy] = []
	for e in _groups.get(index, []):
		if not is_instance_valid(e):
			continue
		var enemy := e as Enemy
		if not enemy.dead and enemy.brain != null and enemy.brain.is_fighting():
			kept.append(enemy)
		else:
			enemy.queue_free()
	if kept.is_empty():
		_groups.erase(index)
	else:
		_groups[index] = kept


## Where a group stands: its marker, or a point on the pad's rim that is not in the water.
func _anchor(index: int, e: Dictionary) -> Vector3:
	var marker := str(e.get("at", ""))
	if marker != "":
		var m := get_parent().find_child(marker, true, false) if get_parent() != null else null
		if m is Node3D:
			return (m as Node3D).global_position
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(("%s#%d" % [poi_id, index]).hash())
	var start := rng.randf() * TAU
	var centre := global_position
	for step in 12:
		var a := start + TAU * float(step) / 12.0
		var p := centre + Vector3(cos(a), 0.0, sin(a)) * pad_radius * RIM
		if terrain == null or not terrain.is_water(p.x, p.z):
			return p
	return centre


func _ground(at: Vector3) -> float:
	if terrain != null:
		return terrain.get_height(at.x, at.z)
	return WorldProbe.get_height(at.x, at.z, at.y)
