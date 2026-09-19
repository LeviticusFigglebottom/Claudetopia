class_name EnemySpawner
extends Node3D
## Places enemies from content ids and keeps them alive across hearthstone rests.
## Used by the test arena and by encounter data (CONTRACTS §6 cell "spawns").
##
## `spawns` is an Array of Dictionaries: {"def": "core:enemy/x", "pos": Vector3 or [x,y,z],
## "yaw": deg, "group": "pack_a", "patrol": [[x,y,z], ...], "count": n, "radius": m}.
## Set `spawn_on_ready` false and call spawn_all() when the ground is ready.

signal spawned(enemy: Node3D)
signal wave_cleared

const ENEMY_SCENE := "res://actors/enemy/enemy.tscn"
const GROUND_MASK := (1 << 0) | (1 << 10)

@export var spawns: Array = []
@export var spawn_on_ready: bool = true
@export var respawn_on_rest: bool = true
@export var drop_to_ground: bool = true

var living: Array[Enemy] = []


func _ready() -> void:
	add_to_group("enemy_spawner")
	if respawn_on_rest:
		EventBus.hearthstone_rested.connect(_on_rested)
	if spawn_on_ready:
		call_deferred("spawn_all")


func spawn_all() -> void:
	for entry in spawns:
		var e: Dictionary = entry
		var count := int(e.get("count", 1))
		for i in count:
			var offset := Vector3.ZERO
			if count > 1:
				var radius := float(e.get("radius", 2.5))
				var a := TAU * float(i) / float(count)
				offset = Vector3(cos(a), 0.0, sin(a)) * radius
			spawn_one(str(e.get("def", "")), _to_vec(e.get("pos", Vector3.ZERO)) + offset, deg_to_rad(float(e.get("yaw", 0.0))), e)


func spawn_one(def_id: String, position: Vector3, yaw: float, options: Dictionary = {}) -> Enemy:
	if def_id.is_empty() or not ContentDB.has(def_id):
		Log.warn("EnemySpawner", "unknown enemy id '%s'" % def_id)
		return null
	var packed := load(ENEMY_SCENE) as PackedScene
	if packed == null:
		return null
	var enemy := packed.instantiate() as Enemy
	enemy.configure(def_id)
	if options.has("patrol"):
		var points := PackedVector3Array()
		for p in options["patrol"]:
			points.append(_to_vec(p))
		enemy.patrol_points = points
	if options.has("group"):
		enemy.pack_group = str(options["group"])
	add_child(enemy)
	enemy.global_position = _grounded(position)
	enemy.rotation.y = yaw
	enemy.spawn_position = enemy.global_position
	enemy.spawn_yaw = yaw
	enemy.brain.post = enemy.global_position
	living.append(enemy)
	enemy.died.connect(_on_enemy_died.bind(enemy))
	spawned.emit(enemy)
	return enemy


func _grounded(position: Vector3) -> Vector3:
	if not drop_to_ground or not is_inside_tree():
		return position
	var space := get_world_3d().direct_space_state
	var from := position + Vector3.UP * 6.0
	var q := PhysicsRayQueryParameters3D.create(from, position + Vector3.DOWN * 40.0, GROUND_MASK)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return position
	return Vector3(position.x, float(hit["position"].y) + 0.05, position.z)


static func _to_vec(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and v.size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO


func alive() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for e in living:
		if is_instance_valid(e) and not e.dead:
			out.append(e)
	return out


func alive_count() -> int:
	return alive().size()


## All spawned enemies, dead or not (the arena's debug readout uses this).
func all() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for e in living:
		if is_instance_valid(e):
			out.append(e)
	return out


func find_by_id(def_id: String) -> Enemy:
	for e in all():
		if e.enemy_id == def_id:
			return e
	return null


func _on_enemy_died(_killer: Node, _enemy: Enemy) -> void:
	if alive_count() == 0:
		wave_cleared.emit()


func _on_rested(_id: String) -> void:
	# Enemies reset themselves on the same signal; the spawner only revives ones freed since.
	for e in all():
		if e.dead and not e.is_boss:
			e.reset_to_spawn()


func clear_all() -> void:
	for e in all():
		e.queue_free()
	living.clear()
