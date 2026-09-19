extends Node3D
## Scene wrapper for a generated house or shop. The `interior` content def names the meta
## file; this builds the house from it.

@export_file("*.json") var meta_override := ""

var house: HouseInterior


func _ready() -> void:
	var meta_path := meta_override
	if meta_path.is_empty():
		meta_path = str(get_meta("meta_path", ""))
	if meta_path.is_empty():
		var id := str(GameState.current_interior_id)
		if ContentDB.has(id):
			meta_path = str(ContentDB.get_def(id).get("meta", ""))
	if meta_path.is_empty():
		Log.error("House", "no meta path: set meta_override, the node meta, or the interior def")
		return
	house = HouseInterior.new()
	house.build_on_ready = false
	add_child(house)
	house.build(meta_path)
