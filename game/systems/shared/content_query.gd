class_name ContentQuery
## Small content lookups the systems in this stream share.
##
## NOTE: `ContentDB.where(type, key, value)` raises "Invalid operands 'Array' and 'String'
## in operator '=='" in Godot 4.7 when any definition of that type has an Array in `key` that
## does not contain `value` (content_db.gd:102 falls through to `v == value`). Tag lookups
## therefore go through `with_tag()` here instead. See the stream report: the one-line fix in
## core/content_db.gd is to guard the `elif` with `typeof(v) != TYPE_ARRAY`.

static var _tag_cache: Dictionary = {}
## The pack generation the cache was built from, so a reload of ContentDB invalidates it.
static var _cache_stamp: int = -1


static func clear_cache() -> void:
	_tag_cache.clear()
	_cache_stamp = -1


static func _stamp() -> int:
	return ContentDB.all("item").size() * 31 + ContentDB.packs.size()


## Every definition of `type` whose "tags" array contains `tag`, ordered by id. The returned
## array is a copy: callers may sort or filter it without corrupting the cache.
static func with_tag(type: String, tag: String) -> Array[Dictionary]:
	var stamp := _stamp()
	if stamp != _cache_stamp:
		_tag_cache.clear()
		_cache_stamp = stamp
	var key := type + "|" + tag
	if _tag_cache.has(key):
		return (_tag_cache[key] as Array[Dictionary]).duplicate()
	var out: Array[Dictionary] = []
	for d in ContentDB.all(type):
		var tags: Variant = d.get("tags", [])
		if typeof(tags) == TYPE_ARRAY and tags.has(tag):
			out.append(d)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("id", "")) < str(b.get("id", "")))
	_tag_cache[key] = out
	return out.duplicate()


static func first_with_tag(type: String, tag: String) -> Dictionary:
	var list := with_tag(type, tag)
	return list[0] if not list.is_empty() else {}


static func id_of_first_with_tag(type: String, tag: String) -> String:
	return str(first_with_tag(type, tag).get("id", ""))


## Definitions of `type` whose scalar field `key` equals `value` (arrays are skipped, so this
## never trips the comparison bug above).
static func where_scalar(type: String, key: String, value: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in ContentDB.all(type):
		if not d.has(key):
			continue
		var v: Variant = d[key]
		if typeof(v) == TYPE_ARRAY or typeof(v) == TYPE_DICTIONARY:
			continue
		if v == value:
			out.append(d)
	return out


static func item_value(item_id: String) -> int:
	return int(ContentDB.get_or_empty(item_id).get("value", 0))


static func item_name(item_id: String) -> String:
	return str(ContentDB.get_or_empty(item_id).get("name", Ids.name_of(item_id)))


static func item_category(item_id: String) -> String:
	return str(ContentDB.get_or_empty(item_id).get("category", "misc"))


## True when the item's category or tags match any entry of `categories` (a merchant's `buys`).
static func item_matches_categories(item_id: String, categories: Array) -> bool:
	if categories.is_empty():
		return false
	if categories.has("all"):
		return true
	var def := ContentDB.get_or_empty(item_id)
	if categories.has(str(def.get("category", ""))):
		return true
	var tags: Variant = def.get("tags", [])
	if typeof(tags) == TYPE_ARRAY:
		for t in tags:
			if categories.has(t):
				return true
	return false
