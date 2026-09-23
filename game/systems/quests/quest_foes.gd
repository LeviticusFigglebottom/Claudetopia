class_name QuestFoes
extends Node
## What a story sends you to fight, standing where it sends you.
##
## A kill objective counts only where its stage says the fight is (`where`, KillPlaces): the ring at
## the Sunken Choir after a bell, the wreck at Gullhithe where the sayers are, the Hound's eye where
## three wolves circle Bramble, the lane at Greyfold between bells. Of the sixteen fights in the open
## that the pack's stages send you to, ten had nothing of the kind standing there and one had half.
## The country's own encounters are laid down by the world builder, which keeps them off every pad,
## and a point of interest stands only what its own sentence says, so the fights the stories wrote
## had no one in them.
##
## So the stage stands up what it asks for. For each open kill objective of a current stage whose
## `where` is a place or point of interest in the open, once the player is within STAND_M of it and
## its cell has been standing for a moment (so the place's own groups are already up): the living
## foes of that kind already there, within the objective's radius, are counted, and the shortfall is
## stood up on clear ground round the place, facing in. The Tumbled Watch keeps its own five
## bandits and gets none; the Gullhithe Wreck, where no sayer ever stood, gets both.
##
## `stand: "own"` on the objective stands what is left to do whatever else is there: the six in the
## newer grey at the Cold Fire are not the ring that has sat there since the Ash Winter. `when` (the
## hour windows of `PoiEncounters.WHEN`) keeps a group to its hour: the choristers come to the ring
## on a full night. A boss is never stood here; its place stands it, and a boss put down stays down.
## Deep places are not stood here either: what a deep place holds is in its own meta, and the walk
## (QuestWalk) checks it holds enough.
##
## Each group is an EnemySpawner under this node, so its fallen get up again after a Hearthstone rest
## like everyone else's. It goes once its objective is done, or out of its hour, and the player is
## away. Nothing is saved: the objectives are, and the groups follow from them.

const GROUP := "quest_foes"
const STAND_M := 300.0
const LEAVE_M := 520.0
## How far round the place a group stands, as a ring (metres), inside a kill objective's radius.
const RING_MIN_M := 9.0
const RING_MAX_M := 22.0
## How far above a spot the look for anything standing over it starts: above the tallest thing the
## world stands (the Choir's colossi are fifty metres).
const OVERHEAD_M := 120.0
const POLL_S := 1.0
const OWN := "own"

@export var enabled := true
## How long a cell has to have been standing before its place's shortfall is counted: the place's
## own groups (PoiEncounters) are raised on the frames after the cell is.
var settle_ms := 1500

var _groups: Dictionary = {}       # objective key -> EnemySpawner (or null: enough stood already)
var _cells: Dictionary = {}        # Vector2i -> ticks msec it was loaded
var _since := 0.0


static func ensure() -> QuestFoes:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var found := tree.get_first_node_in_group(GROUP)
	if found is QuestFoes:
		return found as QuestFoes
	var made := QuestFoes.new()
	made.name = "QuestFoes"
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	host.add_child(made)
	return made


func _ready() -> void:
	add_to_group(GROUP)
	EventBus.cell_loaded.connect(_on_cell_loaded)
	EventBus.cell_unloaded.connect(_on_cell_unloaded)
	EventBus.quest_stage_changed.connect(_on_quest_stage_changed)


func _process(delta: float) -> void:
	if not enabled:
		return
	_since += delta
	if _since < POLL_S:
		return
	_since = 0.0
	refresh()


func _on_cell_loaded(cell: Vector2i) -> void:
	if not _cells.has(cell):
		_cells[cell] = Time.get_ticks_msec()


func _on_cell_unloaded(cell: Vector2i) -> void:
	_cells.erase(cell)


## A new stage asks again: an objective done by the ambient foes of the last visit is recounted.
func _on_quest_stage_changed(_quest: String, _stage: int) -> void:
	for key in _groups.keys():
		if _groups[key] == null:
			_groups.erase(key)


## Marks a cell as standing now and long enough ago to count (tests, and a load that begins in it).
func cell_ready(cell: Vector2i) -> void:
	_cells[cell] = Time.get_ticks_msec() - settle_ms - 1


## The objectives this service stands foes for, now: {key: {objective, quest_id, need, at}}.
func wanted() -> Dictionary:
	var out: Dictionary = {}
	var log_node := get_tree().get_first_node_in_group("quest_log") if is_inside_tree() else null
	if log_node == null or not log_node.has_method("current_objectives"):
		return out
	for entry in log_node.call("current_objectives", "kill"):
		var e: Dictionary = entry
		if bool(e["done"]):
			continue
		var o: Dictionary = e["objective"]
		var target := str(o.get("target", ""))
		if target == "" or target.begins_with("tag:") or Ids.type_of(target) == "boss" or not ContentDB.has(target):
			continue
		var at := KillPlaces.place_position(o)
		if at == Vector3.INF:
			continue
		if not PoiEncounters.is_open(str(o.get("when", "always")), WorldClock.time_hours):
			continue
		var key := "%s|%d|%d" % [e["quest_id"], int(e["stage"]), int(e["index"])]
		out[key] = {"objective": o, "quest_id": str(e["quest_id"]), "at": at,
				"need": maxi(1, int(o.get("count", 1))) - int(e.get("progress", 0))}
	return out


## Stands up what is wanted near the player, and stands down what is no longer wanted once the
## player is away. Safe to call at any time; what the tests drive.
func refresh() -> void:
	if not is_inside_tree():
		return
	var player := _player_position()
	var want := wanted()
	for key in want:
		if _groups.has(key):
			continue
		var w: Dictionary = want[key]
		var at: Vector3 = w["at"]
		if player == Vector3.INF or _flat(player, at) > STAND_M or not _cell_settled(at):
			continue
		_stand_up(str(key), w)
	for key in _groups.keys():
		if want.has(key):
			continue
		var group: Variant = _groups[key]
		if group == null or not is_instance_valid(group):
			_groups.erase(key)
			continue
		var spawner := group as EnemySpawner
		if player == Vector3.INF or _flat(player, spawner.global_position) > LEAVE_M or _all_fallen(spawner):
			spawner.queue_free()
			_groups.erase(key)


## The group standing for one objective, or null.
func group_for(key: String) -> EnemySpawner:
	var g: Variant = _groups.get(key)
	if g == null or not is_instance_valid(g):
		return null
	return g as EnemySpawner


func _stand_up(key: String, w: Dictionary) -> void:
	var o: Dictionary = w["objective"]
	var target := str(o["target"])
	var at: Vector3 = w["at"]
	var radius := float(o.get("radius", KillPlaces.RADIUS_M))
	var standing := 0 if str(o.get("stand", "")) == OWN else living_near(target, at, radius)
	var short := int(w["need"]) - standing
	if short <= 0:
		_groups[key] = null
		return
	var spawner := EnemySpawner.new()
	spawner.name = "Foes_%d" % abs(key.hash())
	spawner.spawn_on_ready = false
	spawner.respawn_on_rest = true
	spawner.drop_to_ground = false
	add_child(spawner)
	spawner.global_position = at
	for p in clear_ground(key, at, short):
		var spot: Vector3 = p
		var facing := atan2(at.x - spot.x, at.z - spot.z)
		spawner.spawn_one(target, spot, facing, {"group": key})
	_groups[key] = spawner
	Log.info("QuestFoes", "%s: %d %s stood at %s" % [w["quest_id"], short, Ids.name_of(target), Ids.name_of(str(o.get("where", "")))])


## Living foes of a kind in the open within `radius` of a point.
func living_near(enemy_id: String, at: Vector3, radius: float) -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy == null or enemy.dead or enemy.is_queued_for_deletion() or enemy.content_id() != enemy_id:
			continue
		if KillPlaces.interior_of(enemy) != "":
			continue
		if _flat(enemy.global_position, at) <= radius:
			n += 1
	return n


## `count` points on the ground round `at`, each with room for a body: the same points every time
## for the same objective, off walls, props and water where the world says so, and never under or
## inside anything solid.
func clear_ground(key: String, at: Vector3, count: int) -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(key.hash())
	var out: Array[Vector3] = []
	var start := rng.randf() * TAU
	var tries := 0
	while out.size() < count and tries < count * 12:
		var a := start + float(tries) * 2.39996    # the golden angle: no two tries on one line
		var r := lerpf(RING_MIN_M, RING_MAX_M, float(tries % 7) / 6.0)
		tries += 1
		var p := at + Vector3(cos(a), 0.0, sin(a)) * r
		p.y = WorldProbe.get_height(p.x, p.z, at.y)
		if _blocked(p):
			continue
		out.append(p)
	# a place so crowded nothing fits still gets its fight, at the middle
	while out.size() < count:
		out.append(at + Vector3(0.0, 0.0, float(out.size()) * 1.2))
	return out


func _blocked(p: Vector3) -> bool:
	var terrain := World.terrain()
	if terrain != null and terrain.is_water(p.x, p.z):
		return true
	var world := get_viewport().get_world_3d() if is_inside_tree() else null
	if world == null:
		return false
	var space := world.direct_space_state
	# A landmark's collision is its mesh's surface (WorldStreamer._add_collision), so a body standing
	# inside the Choir's colossus touches nothing, and the query below called the spot clear. Two of
	# the Naming's three ash-wights were stood inside its robe, where nobody could reach them and the
	# Naming could not be finished. Anything solid straight overhead means under a roof or inside a
	# hull, and no place for a foe. The look goes down to a hand above the ground, because a hull's
	# flared foot is only a little higher than that just inside its edge, and a shape with most of
	# itself behind a face does not touch it either.
	var over := PhysicsRayQueryParameters3D.create(p + Vector3.UP * OVERHEAD_M, p + Vector3.UP * 0.3, 1 << 0)
	if not space.intersect_ray(over).is_empty():
		return true
	var shape := CapsuleShape3D.new()
	shape.radius = 0.45
	shape.height = 1.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1 << 0
	q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0.0, 1.05, 0.0))
	return not space.intersect_shape(q, 1).is_empty()


func _all_fallen(spawner: EnemySpawner) -> bool:
	for e in spawner.all():
		if is_instance_valid(e) and not (e as Enemy).dead:
			return false
	return true


func _cell_settled(at: Vector3) -> bool:
	var cell := WorldProbe.cell_of(at)
	if not _cells.has(cell):
		return false
	return Time.get_ticks_msec() - int(_cells[cell]) >= settle_ms


func _player_position() -> Vector3:
	var player := get_tree().get_first_node_in_group("player") as Node3D if is_inside_tree() else null
	return player.global_position if player != null else Vector3.INF


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
