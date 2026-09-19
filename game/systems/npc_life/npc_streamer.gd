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

var _since := 0.0
var _registry: NpcRegistry = null


func _ready() -> void:
	add_to_group(GROUP)
	_registry = NpcRegistry.ensure()
	# The hourly simulation moves people between places; the bodies have to follow it, and
	# waiting up to INTERVAL for that is long enough to watch somebody teleport.
	EventBus.hour_changed.connect(func(_h: int) -> void: refresh())


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
	var anchor := _anchor()
	if anchor == Vector3.INF:
		return
	var here := Vector2(anchor.x, anchor.z)
	var wanted := _who_is_near(here)
	for id in _registry.spawned.keys():
		var npc_id: String = id
		if not wanted.has(npc_id) and _distance_to(npc_id, here) > FAR_M:
			_registry.despawn(npc_id)
	for npc_id in wanted:
		if not _registry.is_spawned(npc_id):
			_registry.spawn(npc_id)


## The people inside the near ring, nearest first, capped. Returns a set of npc ids.
func _who_is_near(here: Vector2) -> Dictionary:
	var by_distance: Array = []
	for place_id in _places_with_people():
		var at := WorldProbe.place_position(place_id)
		var d := Vector2(at.x - here.x, at.z - here.y).length()
		if d > NEAR_M:
			continue
		for npc_id in _registry.npcs_at(place_id):
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
