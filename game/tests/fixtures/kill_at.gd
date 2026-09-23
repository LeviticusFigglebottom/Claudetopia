extends RefCounted
## A kill that happened somewhere: a body lying in an interior's pocket, or on the ground at a
## place, for the tests of objectives that say where (KillPlaces). The quest log asks the body where
## it fell, the way it does in the game.


## Emits `times` kills of `enemy_id`, each with a body at `where` (an interior, place or POI id), or
## with no body at all when `where` is "".
static func emit(enemy_id: String, where: String = "", times: int = 1) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for i in times:
		var holder: Node3D = null
		var body: Node3D = null
		if where != "":
			holder = Node3D.new()
			tree.root.add_child(holder)
			if Ids.type_of(where) == "interior":
				holder.set_meta("interior_id", where)
				holder.global_position = Vector3(50000.0, 3000.0, 50000.0)
				body = Node3D.new()
				holder.add_child(body)
			else:
				var xz := WorldProbe.xz_of(ContentDB.get_or_empty(where))
				holder.global_position = Vector3(xz.x + 4.0, 0.0, xz.y - 3.0)
				body = holder
		EventBus.entity_killed.emit(body, null, enemy_id)
		if holder != null:
			holder.get_parent().remove_child(holder)
			holder.free()
