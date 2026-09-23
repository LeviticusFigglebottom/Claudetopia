extends RefCounted
## Definitions a test lays over the loaded pack for its own length, and takes away again: for the
## rules that only show on content the pack does not have yet (a quest nothing but its giver starts).


static func add(def: Dictionary) -> void:
	var id := str(def["id"])
	ContentDB._defs[id] = def
	var type := Ids.type_of(id)
	if not ContentDB._by_type.has(type):
		ContentDB._by_type[type] = []
	(ContentDB._by_type[type] as Array).append(def)


static func remove(id: String) -> void:
	ContentDB._defs.erase(id)
	var list: Array = ContentDB._by_type.get(Ids.type_of(id), [])
	for i in range(list.size() - 1, -1, -1):
		if str((list[i] as Dictionary).get("id", "")) == id:
			list.remove_at(i)
