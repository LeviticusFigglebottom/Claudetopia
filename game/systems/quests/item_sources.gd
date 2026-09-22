class_name ItemSources
extends RefCounted
## Where a player can get an item from, read off the content pack.
##
## Four ways, told apart because they are not equally sure: what the **story** hands over (a
## line of dialogue gives it, a quest stage or reward gives it, a boss or an enemy always drops
## it, a Calling starts with it); what a **shop** sells (a stock table some shopkeeper keeps);
## what a **loot table** may roll, which is a chance and not a promise; and a **shelf**, for a
## book a house keeps where it can be read. `QuestItems` places what none of the first two cover,
## and the quest-completability walk says which of the four an objective depends on.

static var _given: Dictionary = {}       # item -> Array[String], how the story hands it over
static var _sold: Dictionary = {}        # item -> Array[String], stock tables a shopkeeper keeps
static var _rolled: Dictionary = {}      # item -> Array[String], loot tables that may roll it
static var _readers: Dictionary = {}     # book -> Array[String], items that read it
static var _shelved: Dictionary = {}     # book -> true, kept on a house's shelf
static var _boss_drops: Dictionary = {}  # item -> Array[String], the arena places it drops at
static var _built := false


static func reset() -> void:
	for d in [_given, _sold, _rolled, _readers, _shelved, _boss_drops]:
		(d as Dictionary).clear()
	_built = false


static func _build() -> void:
	if _built:
		return
	_built = true
	for def in ContentDB.all("dialogue"):
		_gives_in(def, "dialogue " + str(def.get("id", "")))
	for def in ContentDB.all("quest"):
		if str(def.get("layer", "")) == "radiant":
			continue
		_gives_in(def.get("stages", []), "quest " + str(def.get("id", "")))
		var rewards: Dictionary = def.get("rewards", {})
		for entry in rewards.get("items", []):
			_note(_given, str(entry[0]) if typeof(entry) == TYPE_ARRAY else str(entry), "reward " + str(def.get("id", "")))
		_gives_in(rewards.get("effects", []), "reward " + str(def.get("id", "")))
	for type in ["boss", "enemy"]:
		for def in ContentDB.all(type):
			for entry in def.get("drops", []):
				var item := str(entry.get("item", "")) if typeof(entry) == TYPE_DICTIONARY else str(entry)
				_note(_given, item, "drop " + str(def.get("id", "")))
				if type == "boss":
					_note(_boss_drops, item, str(def.get("arena", "")))
	for def in ContentDB.all("calling"):
		for entry in def.get("starting_items", []):
			var item := str(entry.get("item", "")) if typeof(entry) == TYPE_DICTIONARY else str(entry)
			_note(_given, item, "calling " + str(def.get("id", "")))
	var kept: Dictionary = {}
	for def in ContentDB.all("npc"):
		var merchant: Variant = def.get("merchant", {})
		if typeof(merchant) == TYPE_DICTIONARY and str((merchant as Dictionary).get("stock", "")) != "":
			kept[str(merchant["stock"])] = true
	for table_id in kept:
		for item in _items_in(ContentDB.get_or_empty(str(table_id))):
			_note(_sold, item, str(table_id))
	for def in ContentDB.all("loot"):
		for item in _items_in(def):
			_note(_rolled, item, str(def.get("id", "")))
	for def in ContentDB.all("item"):
		var book := str(def.get("reads", ""))
		if book == "" and str(def.get("category", "")) == "book":
			var guess := Ids.make(Ids.pack_of(str(def["id"])), "book", Ids.name_of(str(def["id"])))
			book = guess if ContentDB.has(guess) else ""
		if book != "":
			_note(_readers, book, str(def["id"]))
	for def in ContentDB.all("interior"):
		var path := str(def.get("meta", ""))
		if path == "" or not FileAccess.file_exists(path):
			continue
		var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(meta) != TYPE_DICTIONARY:
			continue
		for p in (meta as Dictionary).get("placements", []):
			if typeof(p) == TYPE_DICTIONARY and str((p as Dictionary).get("book", "")) != "":
				_shelved[str(p["book"])] = true


static func _note(into: Dictionary, key: String, how: String) -> void:
	if key == "":
		return
	var list: Array = into.get(key, [])
	if not list.has(how):
		list.append(how)
	into[key] = list


static func _gives_in(v: Variant, how: String) -> void:
	if typeof(v) == TYPE_DICTIONARY:
		var d: Dictionary = v
		if d.has("give_item"):
			var g: Variant = d["give_item"]
			_note(_given, str(g[0]) if typeof(g) == TYPE_ARRAY and (g as Array).size() > 0 else str(g), how)
		for key in d:
			_gives_in(d[key], how)
	elif typeof(v) == TYPE_ARRAY:
		for x in v:
			_gives_in(x, how)


## Every `item` named anywhere in a table or loot definition.
static func _items_in(v: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(v) == TYPE_DICTIONARY:
		var d: Dictionary = v
		if typeof(d.get("item")) == TYPE_STRING:
			out.append(str(d["item"]))
		for key in d:
			if str(key) != "item":
				out.append_array(_items_in(d[key]))
	elif typeof(v) == TYPE_ARRAY:
		for x in v:
			out.append_array(_items_in(x))
	return out


# --- asking ---------------------------------------------------------------------------------------------

## Does the story hand this over — dialogue, a quest, a guaranteed drop, a Calling's kit?
static func story_gives(item: String) -> bool:
	_build()
	return _given.has(item)


static func how_given(item: String) -> Array:
	_build()
	return (_given.get(item, []) as Array).duplicate()


## Does some shopkeeper's stock table carry it?
static func sold(item: String) -> bool:
	_build()
	return _sold.has(item)


static func sold_by(item: String) -> Array:
	_build()
	return (_sold.get(item, []) as Array).duplicate()


## May a loot table roll it? A chance, not a promise.
static func rolled(item: String) -> bool:
	_build()
	return _rolled.has(item)


## The item that reads a book (the first by id), or "".
static func reader_of(book: String) -> String:
	_build()
	var list: Array = (_readers.get(book, []) as Array).duplicate()
	list.sort()
	return str(list[0]) if not list.is_empty() else ""


## Does some house keep this book on a shelf where it can be read?
static func on_a_shelf(book: String) -> bool:
	_build()
	return _shelved.has(book)


## Is this item a boss's own drop in the place its arena is? (A cave's prop of it stays a prop.)
static func boss_drops_at(item: String, place: String) -> bool:
	_build()
	return (_boss_drops.get(item, []) as Array).has(place)
