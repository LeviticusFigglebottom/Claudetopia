extends Node
## ContentDB: loads every content pack (JSON) into one ID-indexed registry.
##
## Packs live in res://content/packs/<pack>/ and user://packs/<pack>/, each with a pack.json
## manifest {id, name, version, depends[]}. Every *.json file below a pack (except pack.json)
## holds one definition object or an array of them. Each definition has an "id" of the form
## "<pack>:<type>/<name>" (see Ids). Definitions may "extends" another id; parents are
## deep-merged under children at load time (child wins). Later packs may override earlier
## definitions with the same id; overrides are logged.
##
## The core pack is loaded through exactly the same path as any future pack.

signal loaded

const PACK_ROOTS: Array[String] = ["res://content/packs", "user://packs"]

var packs: Array[Dictionary] = []
var problems: Array[String] = []
var is_loaded := false

var _defs: Dictionary = {}      # id -> Dictionary (read-only for callers; use dup() to mutate)
var _by_type: Dictionary = {}   # type -> Array[Dictionary]
var _sources: Dictionary = {}   # id -> "pack:relative/path.json"


func _ready() -> void:
	if not is_loaded:
		load_all()


func load_all() -> void:
	_defs.clear()
	_by_type.clear()
	_sources.clear()
	packs.clear()
	problems.clear()
	var manifests := _discover_packs()
	manifests = _order_by_dependencies(manifests)
	for m in manifests:
		_load_pack(m)
	_resolve_inheritance()
	for id in _defs:
		var def: Dictionary = _defs[id]
		var type := Ids.type_of(id)
		if not _by_type.has(type):
			_by_type[type] = []
		_by_type[type].append(def)
	for id in _defs:
		problems.append_array(Schemas.validate_def(_defs[id], _sources.get(id, "?")))
		problems.append_array(Schemas.find_dangling(_defs[id], _defs, _sources.get(id, "?")))
	is_loaded = true
	Log.info("ContentDB", "loaded %d packs, %d definitions, %d problems" % [packs.size(), _defs.size(), problems.size()])
	for p in problems:
		Log.warn("ContentDB", p)
	loaded.emit()


# --- queries -----------------------------------------------------------------------------

func has(id: String) -> bool:
	return _defs.has(id)


## Returns the definition (shared, treat as read-only) or an empty Dictionary.
func get_def(id: String) -> Dictionary:
	if not _defs.has(id):
		Log.error("ContentDB", "unknown id '%s'" % id)
		return {}
	return _defs[id]


func get_or_empty(id: String) -> Dictionary:
	return _defs.get(id, {})


func dup(id: String) -> Dictionary:
	return get_def(id).duplicate(true)


## All definitions of a type, e.g. all("item").
func all(type: String) -> Array:
	return _by_type.get(type, [])


func ids_of(type: String) -> Array[String]:
	var out: Array[String] = []
	for d in all(type):
		out.append(d["id"])
	out.sort()
	return out


## Definitions of a type whose field equals value (or contains it, for arrays).
func where(type: String, key: String, value: Variant) -> Array:
	var out: Array = []
	for d in all(type):
		if not d.has(key):
			continue
		var v: Variant = d[key]
		if typeof(v) == TYPE_ARRAY and v.has(value):
			out.append(d)
		elif v == value:
			out.append(d)
	return out


func source_of(id: String) -> String:
	return _sources.get(id, "")


# --- loading -----------------------------------------------------------------------------

func _discover_packs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for root in PACK_ROOTS:
		if not DirAccess.dir_exists_absolute(root):
			continue
		for dir in DirAccess.get_directories_at(root):
			var manifest_path := "%s/%s/pack.json" % [root, dir]
			if not FileAccess.file_exists(manifest_path):
				Log.warn("ContentDB", "pack dir without pack.json: %s" % dir)
				continue
			var m: Variant = _read_json(manifest_path)
			if typeof(m) != TYPE_DICTIONARY or not m.has("id"):
				Log.error("ContentDB", "bad manifest %s" % manifest_path)
				continue
			m["_path"] = "%s/%s" % [root, dir]
			out.append(m)
	return out


func _order_by_dependencies(manifests: Array[Dictionary]) -> Array[Dictionary]:
	var by_id: Dictionary = {}
	for m in manifests:
		by_id[m["id"]] = m
	var ordered: Array[Dictionary] = []
	var visiting: Dictionary = {}
	var visit: Callable
	visit = func(m: Dictionary) -> void:
		if m in ordered:
			return
		if visiting.has(m["id"]):
			Log.error("ContentDB", "dependency cycle at pack %s" % m["id"])
			return
		visiting[m["id"]] = true
		for dep in m.get("depends", []):
			if by_id.has(dep):
				visit.call(by_id[dep])
			else:
				Log.error("ContentDB", "pack %s depends on missing pack %s" % [m["id"], dep])
		ordered.append(m)
	# stable: core first, then alphabetical
	manifests.sort_custom(func(a, b): return (a["id"] == "core") or (b["id"] != "core" and a["id"] < b["id"]))
	for m in manifests:
		visit.call(m)
	return ordered


func _load_pack(m: Dictionary) -> void:
	var path: String = m["_path"]
	var count := 0
	for file in _list_json_recursive(path):
		if file.get_file() == "pack.json":
			continue
		var data: Variant = _read_json(file)
		var rel := file.trim_prefix(path + "/")
		var source := "%s:%s" % [m["id"], rel]
		if data == null:
			continue
		var entries: Array = data if typeof(data) == TYPE_ARRAY else [data]
		for e in entries:
			if typeof(e) != TYPE_DICTIONARY or not e.has("id"):
				problems.append("%s: entry without id" % source)
				continue
			var id: String = e["id"]
			if _defs.has(id):
				Log.info("ContentDB", "%s overrides %s (from %s)" % [source, id, _sources[id]])
			e["_pack"] = m["id"]
			_defs[id] = e
			_sources[id] = source
			count += 1
	m["_count"] = count
	packs.append(m)
	Log.info("ContentDB", "pack %s v%s: %d definitions" % [m["id"], m.get("version", "?"), count])


func _list_json_recursive(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".json"):
			out.append("%s/%s" % [dir, f])
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_list_json_recursive("%s/%s" % [dir, d]))
	out.sort()
	return out


func _read_json(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		Log.error("ContentDB", "cannot read %s" % path)
		return null
	var j := JSON.new()
	var err := j.parse(text)
	if err != OK:
		Log.error("ContentDB", "%s:%d: %s" % [path, j.get_error_line(), j.get_error_message()])
		problems.append("%s: JSON parse error line %d: %s" % [path, j.get_error_line(), j.get_error_message()])
		return null
	return j.data


func _resolve_inheritance() -> void:
	var resolved: Dictionary = {}
	for id in _defs.keys():
		_defs[id] = _resolve_one(id, resolved, [])


func _resolve_one(id: String, resolved: Dictionary, chain: Array) -> Dictionary:
	if resolved.has(id):
		return resolved[id]
	var def: Dictionary = _defs[id]
	if not def.has("extends"):
		resolved[id] = def
		return def
	var parent_id: String = def["extends"]
	if parent_id in chain:
		problems.append("%s: inheritance cycle via %s" % [id, parent_id])
		resolved[id] = def
		return def
	if not _defs.has(parent_id):
		problems.append("%s: extends missing '%s'" % [id, parent_id])
		resolved[id] = def
		return def
	chain.append(id)
	var parent := _resolve_one(parent_id, resolved, chain)
	var merged := deep_merge(parent, def)
	merged.erase("extends")
	merged["id"] = id
	resolved[id] = merged
	return merged


## Deep merge: values from `over` replace values in `base`; nested dictionaries merge recursively.
static func deep_merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k in over.keys():
		if out.has(k) and typeof(out[k]) == TYPE_DICTIONARY and typeof(over[k]) == TYPE_DICTIONARY:
			out[k] = deep_merge(out[k], over[k])
		else:
			out[k] = over[k]
	return out
