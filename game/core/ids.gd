class_name Ids
## Namespaced content IDs: "<pack>:<type>/<name>", e.g. "core:item/iron_sword".
## pack and type: [a-z0-9_]+ ; name: [a-z0-9_.]+

static var _re: RegEx = _compile()


static func _compile() -> RegEx:
	var r := RegEx.new()
	r.compile("^([a-z0-9_]+):([a-z0-9_]+)/([a-z0-9_.]+)$")
	return r


static func is_valid(id: String) -> bool:
	return _re.search(id) != null


static func pack_of(id: String) -> String:
	var m := _re.search(id)
	return m.get_string(1) if m else ""


static func type_of(id: String) -> String:
	var m := _re.search(id)
	return m.get_string(2) if m else ""


static func name_of(id: String) -> String:
	var m := _re.search(id)
	return m.get_string(3) if m else ""


static func make(pack: String, type: String, name: String) -> String:
	return "%s:%s/%s" % [pack, type, name]


## True if the string looks like a reference to a content ID (used for dangling-reference checks).
static func looks_like_id(s: String) -> bool:
	return s.length() > 4 and s.find(":") > 0 and s.find("/") > 0 and is_valid(s)
