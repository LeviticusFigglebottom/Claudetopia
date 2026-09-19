class_name LootDrops
extends Node
## Turns kills into pickups. Listens to EventBus.entity_killed(victim, killer, enemy_id), reads
## the enemy def's `loot` (a core:loot/* id) and `marks` ([min, max]) and spawns WorldItems
## around where the victim fell. Not an autoload: the world or an arena adds one of these.
## A victim node may override the def with `loot_table` (String) and `marks_range` (Array)
## properties; a killer with get_level() supplies the loot context's level.

signal dropped(results: Array, position: Vector3, enemy_id: String)

const WORLD_ITEM_SCENE := "res://systems/inventory/world_item.tscn"
const GROUND_MASK := 1 | (1 << 10)   # world + terrain layers

## Where spawned pickups are parented; empty = the victim's parent, else the current scene.
@export var drop_parent_path: NodePath = NodePath("")
@export var scatter_radius: float = 0.6
@export var snap_to_ground: bool = true
@export var enabled: bool = true

var rng := RandomNumberGenerator.new()
## Optional Callable returning the loot context (region, level, luck, flags, quests).
var context_provider: Callable = Callable()


func _ready() -> void:
	rng.seed = GameState.seed ^ 0x4C4F4F54
	if not EventBus.entity_killed.is_connected(_on_entity_killed):
		EventBus.entity_killed.connect(_on_entity_killed)


func _exit_tree() -> void:
	if EventBus.entity_killed.is_connected(_on_entity_killed):
		EventBus.entity_killed.disconnect(_on_entity_killed)


func context() -> Dictionary:
	if context_provider.is_valid():
		var c: Variant = context_provider.call()
		if typeof(c) == TYPE_DICTIONARY:
			return c
	return LootTable.default_context()


func _on_entity_killed(victim: Node, killer: Node, enemy_id: String) -> void:
	if not enabled:
		return
	var def := ContentDB.get_or_empty(enemy_id).duplicate()
	var pos := Vector3.ZERO
	var parent: Node = null
	if victim != null and is_instance_valid(victim):
		var lt: Variant = victim.get("loot_table")
		if lt is String and lt != "":
			def["loot"] = lt
		var mr: Variant = victim.get("marks_range")
		if typeof(mr) == TYPE_ARRAY:
			def["marks"] = mr
		if victim is Node3D and victim.is_inside_tree():
			pos = (victim as Node3D).global_position
			parent = victim.get_parent()
	if def.is_empty():
		return
	var ctx := context()
	if killer != null and is_instance_valid(killer) and killer.has_method("get_level"):
		ctx["level"] = int(killer.call("get_level"))
	var results := drops_for(def, ctx)
	if results.is_empty():
		return
	if drop_parent_path != NodePath(""):
		parent = get_node_or_null(drop_parent_path)
	if is_inside_tree():
		# let the killing blow's physics step finish before placing bodies and ray-casting for the ground
		await get_tree().physics_frame
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		parent = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	spawn_drops(results, pos, parent, enemy_id)


## Rolls what an enemy def drops: its loot table plus a marks purse. Pure apart from the rng.
func drops_for(enemy_def: Dictionary, ctx: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if ctx.is_empty():
		ctx = context()
	var loot_id := str(enemy_def.get("loot", ""))
	if loot_id != "" and ContentDB.has(loot_id):
		out.append_array(LootTable.roll(loot_id, rng, ctx))
	var marks: Variant = enemy_def.get("marks", null)
	var n := 0
	if typeof(marks) == TYPE_ARRAY and marks.size() >= 2:
		n = rng.randi_range(int(marks[0]), int(marks[1]))
	elif typeof(marks) == TYPE_INT or typeof(marks) == TYPE_FLOAT:
		n = int(marks)
	if n > 0:
		out.append({"marks": n})
	return LootTable.merge(out)


## Spawns WorldItems for loot results around `position` under `parent`. Returns the nodes.
func spawn_drops(results: Array, position: Vector3, parent: Node, enemy_id: String = "") -> Array[Node]:
	var nodes: Array[Node] = []
	var scene := load(WORLD_ITEM_SCENE) as PackedScene
	if scene == null or parent == null:
		return nodes
	var i := 0
	for r in results:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var wi := scene.instantiate()
		if r.has("marks"):
			wi.set("marks", int(r["marks"]))
		else:
			wi.set("item_id", str(r.get("item", "")))
			wi.set("count", int(r.get("count", 1)))
			wi.set("data", r.get("data", {}))
		var offset := Vector3.ZERO
		if results.size() > 1:
			var angle := TAU * float(i) / float(results.size()) + rng.randf() * 0.5
			offset = Vector3(cos(angle), 0.0, sin(angle)) * scatter_radius * (0.4 + 0.6 * rng.randf())
		parent.add_child(wi)
		var p := position + offset + Vector3.UP * 0.1
		if wi.is_inside_tree():
			wi.global_position = p
			if snap_to_ground:
				_snap(wi)
		else:
			wi.position = p
		nodes.append(wi)
		i += 1
	dropped.emit(results, position, enemy_id)
	return nodes


func _snap(wi: Node3D) -> void:
	var world := wi.get_world_3d()
	if world == null:
		return
	var space := world.direct_space_state
	if space == null:
		return
	var from := wi.global_position + Vector3.UP * 1.0
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 5.0, GROUND_MASK)
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		wi.global_position = hit["position"] + Vector3.UP * 0.02
