extends Node
## SaveSystem: versioned JSON saves in user://saves/<slot>.json with a migration chain.
## Systems register a section name and an object exposing to_save() -> Dictionary and
## from_save(Dictionary). Late joiners (e.g. the player spawned after load) call
## take_pending(section) to pull their data.

const SCHEMA_VERSION := 4
const SAVE_DIR := "user://saves"
const QUICK_SLOT := "quick"
const AUTO_SLOT := "auto"

var participants: Dictionary = {}   # section -> Object
var pending: Dictionary = {}        # sections loaded but not yet consumed
var last_slot := ""


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func register(section: String, obj: Object) -> void:
	participants[section] = obj
	if pending.has(section) and obj.has_method("from_save"):
		obj.from_save(pending[section])
		pending.erase(section)


func unregister(section: String) -> void:
	participants.erase(section)


func take_pending(section: String) -> Dictionary:
	if pending.has(section):
		var d: Dictionary = pending[section]
		pending.erase(section)
		return d
	return {}


func serialize() -> Dictionary:
	var sections := {}
	# A participant that was freed without unregistering (a scene torn down, a test double)
	# must not be able to take the whole save with it: assigning a freed instance to a typed
	# Object variable raises, which used to abort this loop part-way and write a save missing
	# every section after it. Read the entry untyped, drop it if it is gone, and carry on.
	for name in participants.keys():
		var obj: Variant = participants[name]
		if not is_instance_valid(obj):
			participants.erase(name)
			continue
		if (obj as Object).has_method("to_save"):
			sections[name] = (obj as Object).to_save()
	return {
		"schema_version": SCHEMA_VERSION,
		"game_version": ProjectSettings.get_setting("application/config/version"),
		"saved_at": Time.get_datetime_string_from_system(),
		"summary": _summary(),
		"sections": sections,
	}


func deserialize(data: Dictionary) -> void:
	data = Migrations.migrate(data)
	pending.clear()
	var sections: Dictionary = data.get("sections", {})
	for name in sections:
		if participants.has(name) and not is_instance_valid(participants[name]):
			participants.erase(name)
		if participants.has(name) and participants[name].has_method("from_save"):
			participants[name].from_save(sections[name])
		else:
			pending[name] = sections[name]


func slot_path(slot: String) -> String:
	return "%s/%s.json" % [SAVE_DIR, slot]


func save_to_slot(slot: String) -> Error:
	var data := serialize()
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if f == null:
		Log.error("Save", "cannot open %s for writing" % slot_path(slot))
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	last_slot = slot
	EventBus.game_saved.emit(slot)
	Log.info("Save", "saved slot '%s'" % slot)
	return OK


func load_from_slot(slot: String) -> Error:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		Log.error("Save", "corrupt save %s" % path)
		return ERR_FILE_CORRUPT
	deserialize(parsed)
	last_slot = slot
	EventBus.game_loaded.emit(slot)
	Log.info("Save", "loaded slot '%s'" % slot)
	return OK


func slot_exists(slot: String) -> bool:
	return FileAccess.file_exists(slot_path(slot))


func delete_slot(slot: String) -> void:
	if slot_exists(slot):
		DirAccess.remove_absolute(slot_path(slot))


## Slot summaries for the load menu: [{slot, saved_at, summary{...}}], newest first.
func list_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in DirAccess.get_files_at(SAVE_DIR):
		if not f.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [SAVE_DIR, f]))
		if typeof(parsed) == TYPE_DICTIONARY:
			out.append({"slot": f.get_basename(), "saved_at": parsed.get("saved_at", ""), "summary": parsed.get("summary", {}), "schema_version": parsed.get("schema_version", 0)})
	out.sort_custom(func(a, b): return a.saved_at > b.saved_at)
	return out


func _summary() -> Dictionary:
	var s := {"region": GameState.current_region_id, "day": WorldClock.day, "time": WorldClock.formatted(), "play_time": GameState.play_time_seconds}
	if participants.has("player") and is_instance_valid(participants.player) and participants.player.has_method("save_summary"):
		s.merge(participants.player.save_summary(), true)
	return s
