extends Node3D
## Scene wrapper for a generated deep place. The `interior` content def names the meta
## file; this builds the cave from it and spawns whatever the encounter markers ask for.

@export_file("*.json") var meta_override := ""

var cave: CaveInterior


func _ready() -> void:
	var meta_path := meta_override
	if meta_path.is_empty():
		meta_path = str(get_meta("meta_path", ""))
	if meta_path.is_empty():
		var id := str(GameState.current_interior_id)
		if ContentDB.has(id):
			meta_path = str(ContentDB.get_def(id).get("meta", ""))
	if meta_path.is_empty():
		Log.error("DeepPlace", "no meta path: set meta_override, the node meta, or the interior def")
		return
	cave = CaveInterior.new()
	cave.build_on_ready = false
	cave.spawn_encounters = true
	# The builder asks itself which interior it is (to raise what a quest left in here); Interiors
	# names the wrapper, so the name is handed down.
	cave.set_meta("interior_id", get_meta("interior_id", GameState.current_interior_id))
	add_child(cave)
	cave.build(meta_path)
	_spawn_from_markers()


## Encounter markers carry an enemy id; the spawner turns them into actors if the enemy
## scene exists. Markers stay in the tree either way so a designer can see the placement.
func _spawn_from_markers() -> void:
	var enemy_scene := "res://actors/enemy/enemy.tscn"
	if not ResourceLoader.exists(enemy_scene):
		return
	var packed: PackedScene = load(enemy_scene)
	var holder := Node3D.new()
	holder.name = "Spawned"
	add_child(holder)
	var spawned := 0
	for marker in get_tree().get_nodes_in_group("enemy_spawn"):
		if not is_ancestor_of(marker):
			continue
		var enemy_id := str(marker.get_meta("enemy", ""))
		if enemy_id.is_empty() or not ContentDB.has(enemy_id):
			continue
		var enemy := packed.instantiate()
		if enemy.has_method("setup"):
			enemy.setup(enemy_id)
		elif "enemy_id" in enemy:
			enemy.set("enemy_id", enemy_id)
		holder.add_child(enemy)
		(enemy as Node3D).global_position = (marker as Node3D).global_position
		(enemy as Node3D).global_rotation.y = (marker as Node3D).global_rotation.y
		if marker.get_meta("ambush", false) and enemy.has_method("set_ambush"):
			enemy.set_ambush(true)
		spawned += 1
	Log.info("DeepPlace", "spawned %d enemies from markers" % spawned)
