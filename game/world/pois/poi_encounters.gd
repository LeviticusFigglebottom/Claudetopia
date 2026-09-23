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
##    "spread": 2.5, "unless": [conditions], "unless_present": npc id, "rises_when": touch,
##    "if": [conditions], "sits": true, "wakes_for": {"carrying": [item ids], "within_m": m},
##    "toll": {"marks": n, "touch": name, "line": marker, "within_m": m},
##    "killing_costs": {"faction": id, "reputation": -n, "notice": text}}
##
## `at` names a marker the dressing put down (the Tumbled Watch's `stair_hall`); without one the
## group stands on the pad's rim, the same place every time and out of the water. `when` is read
## off the clock as the cell is raised and again every hour it stands: the ford's bandits step out
## after dark and are gone by morning, unless they are busy with you. `unless` is the condition
## vocabulary (CONTRACTS §7) and `unless_present` a person whose being here keeps the group away;
## `rises_when` names a `PoiTouch` in the dressing, and until it is touched the group sits and
## does not see you. A boss once put down (`boss_deed/<id>`, which `Social` sets) stays down; its
## fight is bounded the way any boss's outside a deep place is, by the arena it improvises when
## it wakes.
##
## `if` is the other side of `unless`: the group stands only while its conditions hold (the fallen
## knight on the Headless Watch's stair while the watch has turned). A group that `sits` stands
## at its post and minds its own business -- it fights whoever strikes it or robs the ground at its
## feet (its own greed rule), and whoever `wakes_for` names: the Mossbridge Wardens let anyone
## cross who carries nothing they did not need, and wake for anyone carrying the forest's goods
## out past them. A `toll` group sits at its table and asks its toll of whoever touches `touch`;
## anyone who goes past the `line` marker without paying it today has it out with them. And
## `killing_costs` is what a death here costs the player who dealt it: the reedfolk feed the
## Sallow King's sallowjaws so they nest nowhere else, and hear who killed one.
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
var _minding := 0.0                      # seconds to the next look at who is passing (wakes_for, toll)
## How often a sitting group looks at who is passing, in seconds.
const MIND_EVERY := 0.25


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
	var wanted_here := of(d.poi_id)
	if wanted_here.is_empty() or d.far:
		return null
	var node := PoiEncounters.new()
	node.name = "Encounters"
	node.poi_id = d.poi_id
	node.entries = wanted_here
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
	# Deferred: the registry moves people on the same hour, and who is here decides who comes.
	# Method references, not closures: the bus outlives this node.
	EventBus.hour_changed.connect(_on_hour_changed)
	EventBus.quest_stage_changed.connect(_on_quest_stage_changed)
	call_deferred("refresh")
	set_physics_process(_minds_passers())
	for i in entries.size():
		var toll: Dictionary = (entries[i] as Dictionary).get("toll", {})
		if not toll.is_empty():
			call_deferred("_hang_toll", i)


## Whether any group here looks at who goes by (`wakes_for`, `toll`).
func _minds_passers() -> bool:
	for e in entries:
		if (e as Dictionary).has("wakes_for") or (e as Dictionary).has("toll"):
			return true
	return false


func _physics_process(delta: float) -> void:
	_minding -= delta
	if _minding > 0.0:
		return
	_minding = MIND_EVERY
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null:
		mind(player)


## Looks at `who` going by: wakes any sitting group whose `wakes_for` they answer, and any toll
## group whose line they have passed without paying.
func mind(who: Node3D) -> void:
	for i in _groups:
		var e: Dictionary = entries[int(i)]
		if _answers(who, e, int(i)):
			wake(int(i), who)


func _answers(who: Node3D, e: Dictionary, index: int) -> bool:
	var standing_here := standing(index)
	if standing_here.is_empty() or not standing_here[0].inactive:
		return false
	var wakes: Dictionary = e.get("wakes_for", {})
	if not wakes.is_empty():
		var reach := float(wakes.get("within_m", 8.0))
		for enemy in standing_here:
			if enemy.global_position.distance_to(who.global_position) <= reach and carries_any(who, wakes.get("carrying", [])):
				return true
	var toll: Dictionary = e.get("toll", {})
	if not toll.is_empty() and not toll_paid():
		var line: Node3D = null
		if get_parent() != null:
			line = get_parent().find_child(str(toll.get("line", "")), true, false) as Node3D
		if line != null and line.global_position.distance_to(who.global_position) <= float(toll.get("within_m", 3.5)):
			return true
	return false


## Whether `who` (the player, or anything with an inventory) carries any of `items`.
static func carries_any(who: Node, items: Array) -> bool:
	var bag := Peers.inventory_of(who)
	if bag == null or not bag.has_method("count"):
		return false
	for id in items:
		if int(bag.call("count", str(id))) > 0:
			return true
	return false


# --- the toll ----------------------------------------------------------------------------------------------

## The flag that says the toll here has been paid, and the day it was paid on.
func toll_flag() -> String:
	return "toll_paid/" + poi_id


## Paid today.
func toll_paid() -> bool:
	return int(GameState.get_flag(toll_flag(), 0)) == WorldClock.day


## The toll group's table: its touch pays the toll.
func _hang_toll(index: int) -> void:
	var toll: Dictionary = (entries[index] as Dictionary).get("toll", {})
	var touch: Node = null
	if get_parent() != null:
		touch = get_parent().find_child(str(toll.get("touch", "")), true, false)
	if touch is PoiTouch:
		(touch as PoiTouch).once = false
		(touch as PoiTouch).prompt = "Pay the toll (%d marks)" % int(toll.get("marks", 1))
		if not (touch as PoiTouch).touched.is_connected(_on_toll_touched):
			(touch as PoiTouch).touched.connect(_on_toll_touched.bind(index))


func _on_toll_touched(actor: Node, index: int) -> void:
	pay_toll(actor, index)


## Pays the toll for `actor`: the marks, and the day's flag. False when they cannot pay (and
## nothing is taken), or it is paid already.
func pay_toll(actor: Node, index: int) -> bool:
	var toll: Dictionary = (entries[index] as Dictionary).get("toll", {})
	if toll_paid():
		EventBus.notify.emit("The toll is paid for today.", "info")
		return false
	var marks := int(toll.get("marks", 1))
	if not Purse.pay(actor, marks):
		EventBus.notify.emit("The toll is %d marks, and you have not got them." % marks, "warn")
		return false
	GameState.set_flag(toll_flag(), WorldClock.day)
	EventBus.notify.emit("You pay the toll: %d marks." % marks, "info")
	return true


func _on_hour_changed(_hour: int) -> void:
	call_deferred("refresh")


func _on_quest_stage_changed(_quest: String, _stage: int) -> void:
	call_deferred("refresh")


## Brings each group in or out to match the clock, the story and who is here. A group that was
## raised and killed is not raised again on the hour: it stays dead until a Hearthstone rest
## brings it back, the rule the rest of the country keeps.
func refresh() -> void:
	if not is_inside_tree():
		return
	for i in entries.size():
		var e: Dictionary = entries[i]
		var open := wanted(e)
		if open and not _groups.has(i):
			_raise(i, e)
		elif not open and _groups.has(i):
			_stand_down(i)


## Whether a group should be standing now: its hour, a boss not yet put down, nothing in its
## `unless` true (the Larkbourne Boys stand aside while Ryn is waiting to be heard), everything in
## its `if` true (the fallen knight is on the Headless Watch's stair only while the watch has
## turned), and nobody named in `unless_present` here (the drowned climb the causeway's poles
## only when the lamplighter is not on it).
func wanted(e: Dictionary) -> bool:
	if not is_open(str(e.get("when", "always")), WorldClock.time_hours) or _put_down(e):
		return false
	var unless: Variant = e.get("unless", [])
	if typeof(unless) == TYPE_ARRAY and not (unless as Array).is_empty() and Social.ctx != null \
			and Conditions.all_of(unless, Social.ctx):
		return false
	var need: Variant = e.get("if", [])
	if typeof(need) == TYPE_ARRAY and not (need as Array).is_empty() \
			and (Social.ctx == null or not Conditions.all_of(need, Social.ctx)):
		return false
	var keeper := str(e.get("unless_present", ""))
	if keeper != "" and is_present(keeper, poi_id):
		return false
	return true


## Is this person here and about: alive, at this place by the registry, and not under a roof.
static func is_present(npc_id: String, place_id: String) -> bool:
	var registry := NpcRegistry.instance
	if registry == null or not is_instance_valid(registry):
		return false
	return registry.is_alive(npc_id) and registry.place_of(npc_id) == place_id and not registry.is_indoors(npc_id)


## The living members of one group.
func standing(index: int) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for e in _groups.get(index, []):
		if is_instance_valid(e) and not (e as Enemy).dead and not (e as Enemy).is_queued_for_deletion():
			out.append(e)
	return out


## Every living enemy this place has standing, across its groups.
func everyone() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for i in _groups:
		out.append_array(standing(int(i)))
	return out


func _put_down(e: Dictionary) -> bool:
	var id := str(e.get("enemy", ""))
	return Ids.type_of(id) == "boss" and GameState.has_flag("boss_deed/" + id)


func _raise(index: int, e: Dictionary) -> void:
	var count := maxi(1, int(e.get("count", 1)))
	var spread := float(e.get("spread", 2.5))
	var anchor := _anchor(index, e)
	var at_anchor: Vector3 = anchor["pos"]
	var raised := bool(anchor["raised"])
	var facing := atan2(global_position.x - at_anchor.x, global_position.z - at_anchor.z)
	var asleep := str(e.get("rises_when", "")) != ""
	var sits := bool(e.get("sits", false)) or e.has("toll") or e.has("wakes_for")
	var group: Array[Enemy] = []
	for k in count:
		var at := at_anchor
		if count > 1:
			var a := TAU * float(k) / float(count) + float(index)
			at += Vector3(cos(a), 0.0, sin(a)) * spread
		# on a deck or a stump the marker's own height is the floor; on the ground, the ground is
		if not raised:
			at.y = _ground(at)
		var enemy := spawn_one(str(e["enemy"]), at, facing, {"group": "%s#%d" % [poi_id, index]})
		if enemy == null:
			continue
		if asleep:
			_sleep(enemy)
		elif sits:
			_sit(enemy)
		if e.has("killing_costs"):
			enemy.died.connect(_on_fallen.bind(index))
		group.append(enemy)
	_groups[index] = group
	if asleep:
		_wait_for_touch(index, str(e["rises_when"]))


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


# --- sitting still until something is touched ----------------------------------------------------------

## Seated, and deaf to everything but a blow: Greyfold's people wave at you, and go on waiting.
func _sleep(enemy: Enemy) -> void:
	if enemy.perception != null:
		enemy.perception.enabled = false
	enemy.inactive = true


## Minding its own business: eyes open, and nothing it sees starts a fight. A blow does (the
## enemy's own `take_hit`), and so does the greed rule, and `wake`.
func _sit(enemy: Enemy) -> void:
	enemy.inactive = true


## A death here by the player's hand, and what it costs them (`killing_costs`).
func _on_fallen(killer: Node, index: int) -> void:
	var cost: Dictionary = (entries[index] as Dictionary).get("killing_costs", {})
	if cost.is_empty() or killer == null or not is_instance_valid(killer) or not killer.is_in_group("player"):
		return
	var faction := str(cost.get("faction", ""))
	if faction != "" and Social.factions != null:
		Social.factions.add_reputation(faction, int(cost.get("reputation", -5)), "killed at " + poi_id)
	var notice := str(cost.get("notice", ""))
	if notice != "":
		EventBus.notify.emit(notice, "warn")


## The thing that wakes a sleeping group is a `PoiTouch` the dressing put down under that name.
func _wait_for_touch(index: int, touch_name: String) -> void:
	var holder := get_parent()
	var touch := holder.find_child(touch_name, true, false) if holder != null else null
	if touch is PoiTouch and not (touch as PoiTouch).touched.is_connected(_on_touched):
		(touch as PoiTouch).touched.connect(_on_touched.bind(index))


func _on_touched(actor: Node, index: int) -> void:
	wake(index, actor)


## Rises: hearing and seeing again, and turned on whoever did it.
func wake(index: int, actor: Node = null) -> void:
	for enemy in standing(index):
		if enemy.perception != null:
			enemy.perception.enabled = true
			if actor is Node3D:
				enemy.perception.alert_to((actor as Node3D).global_position, actor as Node3D)
		enemy.inactive = false
		if enemy.brain != null and actor is Node3D:
			enemy.brain.force(Brain.COMBAT)


# --- where ------------------------------------------------------------------------------------------------

## Where a group stands, {pos, raised}: its marker (on a deck or a stump when the marker says
## the floor there is raised), or a point on the pad's rim that is not in the water.
func _anchor(index: int, e: Dictionary) -> Dictionary:
	var marker := str(e.get("at", ""))
	if marker != "":
		var m := get_parent().find_child(marker, true, false) if get_parent() != null else null
		if m is Node3D:
			return {"pos": (m as Node3D).global_position, "raised": bool(m.get_meta("raised", false))}
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(("%s#%d" % [poi_id, index]).hash())
	var start := rng.randf() * TAU
	var centre := global_position
	for step in 12:
		var a := start + TAU * float(step) / 12.0
		var p := centre + Vector3(cos(a), 0.0, sin(a)) * pad_radius * RIM
		if terrain == null or not terrain.is_water(p.x, p.z):
			return {"pos": p, "raised": false}
	return {"pos": centre, "raised": false}


func _ground(at: Vector3) -> float:
	if terrain != null:
		return terrain.get_height(at.x, at.z)
	return WorldProbe.get_height(at.x, at.z, at.y)
