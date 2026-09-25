extends Node
## GameState: world flags, counters, discovery, current region; the small shared blackboard
## that quests, dialogue conditions and world reactions read. Everything here is saved.

var flags: Dictionary = {}          # String -> Variant (bool/int/String)
var counters: Dictionary = {}       # String -> int
var discovered_places: Array[String] = []
var read_books: Array[String] = []
var current_region_id: String = ""
var current_interior_id: String = ""
@warning_ignore("shadowed_global_identifier")
var seed: int = 0
var new_game_started_at_day: int = 1
var play_time_seconds: float = 0.0


func _ready() -> void:
	SaveSystem.register("state", self)


func _process(delta: float) -> void:
	play_time_seconds += delta


func set_flag(key: String, value: Variant = true) -> void:
	flags[key] = value


func get_flag(key: String, default: Variant = false) -> Variant:
	return flags.get(key, default)


func has_flag(key: String) -> bool:
	if not flags.has(key):
		return false
	var v: Variant = flags[key]
	match typeof(v):
		TYPE_BOOL:
			return v
		TYPE_INT, TYPE_FLOAT:
			return v != 0
		TYPE_STRING:
			return not v.is_empty()
		_:
			return v != null


func clear_flag(key: String) -> void:
	flags.erase(key)


func inc(key: String, by: int = 1) -> int:
	counters[key] = int(counters.get(key, 0)) + by
	return counters[key]


func count(key: String) -> int:
	return int(counters.get(key, 0))


func discover(place_id: String) -> void:
	if place_id in discovered_places:
		return
	discovered_places.append(place_id)
	EventBus.place_discovered.emit(place_id)


func is_discovered(place_id: String) -> bool:
	return place_id in discovered_places


func mark_book_read(book_id: String) -> void:
	if not book_id in read_books:
		read_books.append(book_id)


func enter_region(region_id: String) -> void:
	if region_id == current_region_id:
		return
	var prev := current_region_id
	current_region_id = region_id
	EventBus.region_entered.emit(region_id, prev)


func reset_for_new_game(new_seed: int) -> void:
	flags.clear()
	counters.clear()
	discovered_places.clear()
	read_books.clear()
	current_region_id = ""
	current_interior_id = ""
	seed = new_seed
	play_time_seconds = 0.0


func to_save() -> Dictionary:
	return {
		"flags": flags.duplicate(true), "counters": counters.duplicate(true), "discovered_places": discovered_places.duplicate(),
		"read_books": read_books.duplicate(), "current_region_id": current_region_id,
		"current_interior_id": current_interior_id, "seed": seed, "play_time_seconds": play_time_seconds,
	}


func from_save(d: Dictionary) -> void:
	flags = d.get("flags", {})
	counters = d.get("counters", {})
	discovered_places.assign(d.get("discovered_places", []))
	read_books.assign(d.get("read_books", []))
	current_region_id = d.get("current_region_id", "")
	current_interior_id = d.get("current_interior_id", "")
	seed = int(d.get("seed", 0))
	play_time_seconds = float(d.get("play_time_seconds", 0.0))
