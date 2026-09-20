class_name NpcStreamer
extends Node
## Puts the people in the world.
##
## `NpcRegistry` has always been able to stand an NPC up — it knows who is alive, whose
## schedule has them in which place at this hour, and where in that place they stand — and
## `simulate_all()` moves the whole roster every hour whether or not anybody is watching.
## Nothing ever called `spawn()`. Outside of a test, the villages of Wickmere were empty: the
## schedules ran, the dispositions changed, the guards noticed crimes, and there was not one
## body standing in a street.
##
## This is the thing that was missing. It follows whoever the world is streaming around and
## keeps bodies up for the people near enough to be seen, in the same near-ring/far-ring shape
## the terrain uses: somebody spawns at `NEAR_M` and is not taken away again until `FAR_M`, so
## walking back and forth across a boundary does not blink the village in and out.
##
## It is deliberately a service rather than a node in `world.tscn`, so every host that installs
## `GameServices` — the world, the scripted journey, the arena — gets people for free.
##
## Indoors is its own case. A schedule that has somebody asleep, or at a spot marked `in:`, or
## flagged `indoors`, means they are in a building — so they are not stood up in the street,
## and a village genuinely empties at night instead of holding twenty-three people standing in
## the dark. When the player goes through a door instead, the people whose house it is are
## stood up *in it*, in the room their hour calls for: the bed if they are asleep, the hearth
## if they are eating, wherever they work if they are working.

const GROUP := "npc_streamer"
## Where bodies appear, and where they are taken away again. The gap is hysteresis.
const NEAR_M := 240.0
const FAR_M := 330.0
## A hard ceiling, because a city's roster is not a frame budget. The nearest win.
const MAX_BODIES := 48
const INTERVAL := 0.75

static func ensure() -> NpcStreamer:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var found := tree.get_first_node_in_group(GROUP)
	if found is NpcStreamer:
		return found as NpcStreamer
	var made := NpcStreamer.new()
	made.name = "NpcStreamer"
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	host.add_child(made)
	return made


@export var enabled := true

## Which room an activity belongs in, by the words an interior's room kinds use.
const ROOM_FOR := {
	"sleep": ["bed", "sleep", "chamber", "loft"],
	"eat": ["hearth", "kitchen", "hall"],
	"work": ["work", "forge", "shop", "still", "brew", "byre", "store"],
	"pray": ["shrine", "chapel", "hearth"],
	"socialise": ["hall", "hearth"],
	"idle": ["hearth", "hall"],
}

var _since := 0.0
var _registry: NpcRegistry = null
var _homes: Dictionary = {}


func _ready() -> void:
	add_to_group(GROUP)
	_registry = NpcRegistry.ensure()
	# The hourly simulation moves people between places; the bodies have to follow it, and
	# waiting up to INTERVAL for that is long enough to watch somebody teleport.
	EventBus.hour_changed.connect(func(_h: int) -> void: refresh())
	# A door is the sharpest change of who should be standing near you that the game has.
	EventBus.interior_entered.connect(func(_id: String) -> void: refresh())
	EventBus.interior_exited.connect(func(_id: String) -> void: refresh())


func _exit_tree() -> void:
	if _registry != null and is_instance_valid(_registry):
		_registry.despawn_all()


func _process(delta: float) -> void:
	if not enabled:
		return
	_since += delta
	if _since < INTERVAL:
		return
	_since = 0.0
	refresh()


## Brings up everybody who should be standing near the anchor and takes down everybody who
## should not. Safe to call at any time; it is the whole of this node's behaviour.
func refresh() -> void:
	if _registry == null or not is_instance_valid(_registry):
		_registry = NpcRegistry.ensure()
		if _registry == null:
			return
	var inside := _interior_now()
	if inside != "":
		_stand_up_indoors(inside)
		return
	var anchor := _anchor()
	if anchor == Vector3.INF:
		return
	var here := Vector2(anchor.x, anchor.z)
	var wanted := _who_is_near(here)
	for id in _registry.spawned.keys():
		var npc_id: String = id
		# Going indoors takes the body away at once, wherever the player is standing: the
		# hysteresis is for somebody walking away from a village, not for somebody going to
		# bed twelve metres in front of you.
		if _registry.is_indoors(npc_id):
			_registry.despawn(npc_id)
		elif not wanted.has(npc_id) and _distance_to(npc_id, here) > FAR_M:
			_registry.despawn(npc_id)
	for npc_id in wanted:
		if not _registry.is_spawned(npc_id):
			_registry.spawn(npc_id)


# --- through a door --------------------------------------------------------------------------

## Inside a building, the only people who matter are the ones whose building it is. Everyone
## standing in the country outside is taken down — they are a kilometre away in a pocket at
## the far corner of the coordinate space — and whoever is at home is stood up in the room
## their hour calls for.
func _stand_up_indoors(interior_id: String) -> void:
	var belong := _residents_of(interior_id)
	for id in _registry.spawned.keys():
		if not belong.has(str(id)):
			_registry.despawn(str(id))
	var root := _interior_root(interior_id)
	var n := 0
	for npc_id in belong:
		if not _registry.is_alive(npc_id) or not _registry.is_indoors(npc_id):
			continue
		var body: Node = _registry.actor(npc_id)
		if body == null:
			body = _registry.spawn(npc_id)
		# The body matters more than the placement: if the building's node cannot be found —
		# a headless test, a pocket that has not finished loading — they are still here.
		if body is Node3D and root != null:
			(body as Node3D).global_position = _spot_inside(root, npc_id, n)
		n += 1


## Whose house this is. The interior def names its resident; the household lives there too,
## but only the resident is a person the roster knows by name.
func _residents_of(interior_id: String) -> Dictionary:
	if _homes.is_empty():
		for def in ContentDB.all("interior"):
			var who := str(def.get("resident", def.get("resident_npc", "")))
			if who == "":
				continue
			var id := str(def.get("id", ""))
			var list: Array = _homes.get(id, [])
			list.append(who)
			_homes[id] = list
	var out: Dictionary = {}
	for who in _homes.get(interior_id, []):
		out[str(who)] = true
	return out


func _interior_root(interior_id: String) -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("interior_root"):
		if node is Node3D and str((node as Node3D).get_meta("interior_id", "")) == interior_id:
			return node as Node3D
	# the manager names what it loads, which is enough to find it without a group
	var wanted := "Interior_" + Ids.name_of(interior_id)
	var found := tree.root.find_child(wanted, true, false)
	return found as Node3D


## The room this person's hour puts them in: the bed if they are asleep, the hearth if they
## are eating or idling, their workroom if they are working. Falls back to the first room,
## and to the building's own origin if the meta is not there at all.
func _spot_inside(root: Node3D, npc_id: String, index: int) -> Vector3:
	var rooms: Array = []
	var meta: Variant = root.get("meta")
	if typeof(meta) == TYPE_DICTIONARY:
		rooms = (meta as Dictionary).get("rooms", [])
	if rooms.is_empty():
		return root.global_position + Vector3(0.0, 0.2, 0.0)
	var activity := str(_registry.activity_of(npc_id))
	var want: Array = ROOM_FOR.get(activity, ["hearth"])
	var best: Dictionary = {}
	for entry in rooms:
		var room: Dictionary = entry
		if int(room.get("storey", 0)) != 0 and activity != "sleep":
			continue
		var kind := str(room.get("kind", room.get("id", "")))
		for word in want:
			if kind.contains(str(word)):
				best = room
				break
		if not best.is_empty():
			break
	if best.is_empty():
		best = rooms[index % rooms.size()]
	var centre: Array = best.get("centre", [0, 0, 0])
	var local := Vector3(float(centre[0]), float(best.get("floor_y", 0.0)) + 0.1, float(centre[2]))
	# two people in one room do not stand in the same place
	local += Vector3(sin(float(index) * 2.3) * 0.7, 0.0, cos(float(index) * 2.3) * 0.7)
	return root.global_transform * local


## Which building the player is standing in, if any. `InteriorManager` writes this on the way
## through the door and clears it on the way out, and it is the one place both it and the save
## file agree on.
func _interior_now() -> String:
	return str(GameState.current_interior_id)


## The people inside the near ring, nearest first, capped. Returns a set of npc ids.
func _who_is_near(here: Vector2) -> Dictionary:
	var by_distance: Array = []
	for place_id in _places_with_people():
		var at := WorldProbe.place_position(place_id)
		var d := Vector2(at.x - here.x, at.z - here.y).length()
		if d > NEAR_M:
			continue
		for npc_id in _registry.npcs_at(place_id):
			# somebody asleep in their own bed does not also stand in the square
			if _registry.is_indoors(npc_id):
				continue
			by_distance.append([d, npc_id])
	by_distance.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var out: Dictionary = {}
	for row in by_distance:
		if out.size() >= MAX_BODIES:
			break
		out[str((row as Array)[1])] = true
	return out


## Every place the roster currently has somebody in. Read off the registry rather than the
## place list, because an NPC's schedule can put them somewhere their home is not.
func _places_with_people() -> Array[String]:
	var seen: Dictionary = {}
	for id in _registry.known_ids():
		if not _registry.is_alive(id):
			continue
		var place := _registry.place_of(id)
		if place != "":
			seen[place] = true
	var out: Array[String] = []
	for place in seen:
		out.append(str(place))
	return out


func _distance_to(npc_id: String, here: Vector2) -> float:
	var node := _registry.actor(npc_id)
	if node is Node3D:
		var at: Vector3 = (node as Node3D).global_position
		return Vector2(at.x - here.x, at.z - here.y).length()
	var place := WorldProbe.place_position(_registry.place_of(npc_id))
	return Vector2(place.x - here.x, place.z - here.y).length()


## Whoever the world is built around: the player if there is one, otherwise whatever the
## streamer is following, which is how a capture or a fly-through gets people too.
func _anchor() -> Vector3:
	var tree := get_tree()
	if tree == null:
		return Vector3.INF
	var player := tree.get_first_node_in_group("player")
	if player is Node3D:
		return (player as Node3D).global_position
	var world := World.instance
	if world != null and world.target != null:
		return world.target.global_position
	return Vector3.INF
