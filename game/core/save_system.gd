extends Node
## SaveSystem: versioned JSON saves in user://saves/<slot>.json with a migration chain.
## Systems register a section name and an object exposing to_save() -> Dictionary and
## from_save(Dictionary). Late joiners (e.g. the player spawned after load) call
## take_pending(section) to pull their data.

const SCHEMA_VERSION := 6
const SAVE_DIR := "user://saves"
const QUICK_SLOT := "quick"
const AUTO_SLOT := "auto"

var participants: Dictionary = {}   # section -> Object
## Where the slots are. The test runner gives each run a folder of its own (use_save_dir): every
## checkout on a machine shares one user://, and two suites at once wrote, read and deleted each
## other's slots.
var save_dir := SAVE_DIR
var pending: Dictionary = {}        # sections loaded but not yet consumed
var last_slot := ""
## Whatever holds the game in a state that is not the player's says so here, and no slot is
## written until it lets go (`hold_saves`). The opening flies its camera over the country with the
## clock, the sky and the body borrowed: a slot written then kept the borrowed hour and weather,
## and the `new_game` flag that plays the opening, so loading it played the opening again.
var _holds: Dictionary = {}         # reason -> true


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
	for part_name in participants.keys():
		var obj: Variant = participants[part_name]
		if not is_instance_valid(obj):
			participants.erase(part_name)
			continue
		if (obj as Object).has_method("to_save"):
			sections[part_name] = (obj as Object).to_save()
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
	for section_name in sections:
		if participants.has(section_name) and not is_instance_valid(participants[section_name]):
			participants.erase(section_name)
		if participants.has(section_name) and participants[section_name].has_method("from_save"):
			participants[section_name].from_save(sections[section_name])
		else:
			pending[section_name] = sections[section_name]


func slot_path(slot: String) -> String:
	return "%s/%s.json" % [save_dir, slot]


## Writes and reads the slots in `dir` from now on.
func use_save_dir(dir: String) -> void:
	save_dir = dir
	DirAccess.make_dir_recursive_absolute(dir)


func hold_saves(reason: String) -> void:
	_holds[reason] = true


func release_saves(reason: String) -> void:
	_holds.erase(reason)


## Why a save would be refused now, or "" when nothing holds it.
func saves_held_by() -> String:
	return ", ".join(PackedStringArray(_holds.keys()))


func save_to_slot(slot: String) -> Error:
	if not _holds.is_empty():
		Log.warn("Save", "slot '%s' not written while %s" % [slot, saves_held_by()])
		return ERR_BUSY
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
	for f in DirAccess.get_files_at(save_dir):
		if not f.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [save_dir, f]))
		if typeof(parsed) == TYPE_DICTIONARY:
			out.append({"slot": f.get_basename(), "saved_at": parsed.get("saved_at", ""), "summary": parsed.get("summary", {}), "schema_version": parsed.get("schema_version", 0)})
	out.sort_custom(func(a, b): return a.saved_at > b.saved_at)
	return out


func _summary() -> Dictionary:
	var s := {"region": GameState.current_region_id, "day": WorldClock.day, "time": WorldClock.formatted(), "play_time": GameState.play_time_seconds}
	if participants.has("player") and is_instance_valid(participants.player) and participants.player.has_method("save_summary"):
		s.merge(participants.player.save_summary(), true)
	return s
