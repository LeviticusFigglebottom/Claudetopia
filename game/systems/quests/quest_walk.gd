class_name QuestWalk
extends RefCounted
## Every objective of every quest, and what a player could close it with.
##
## A quest is finished by events: a conversation ends, a place is arrived at, a thing dies, an
## item comes into the pack. A green suite says the log listens for them; whether anything in the
## built game ever *sends* one for a given objective is another question, and asking it of the
## whole pack found deliveries with no line to hand them over on, decisions with no button, an
## escort nothing walked, items nothing put anywhere and a boss nothing stood up. This asks it of
## every objective, and `tests/unit/test_quest_walk.gd` fails when a new one cannot be closed.
##
## A verdict is `{ok, how}`: `how` is the way a player closes it (the person and where they live,
## the enemy and where it stands, the item and how it is got, the decision and who puts it), or
## why nothing can. It does not ask whether the stage before is reachable, how hard the fight is,
## or whether a `requires` chain can be met: only whether the thing the objective waits for
## exists in the game. `radiant()` asks the same of every target the job boards could name.

const CELLS_DIR := "res://world/generated/cells"
const PADS_PATH := "res://world/generated/pois.json"

static var _in_the_open: Dictionary = {}    # enemy id -> {region id: count}, off the built cells
static var _below: Dictionary = {}          # enemy id -> [interior id], a deep place's encounters
static var _below_count: Dictionary = {}    # "interior|enemy" -> how many its encounters stand
static var _cave_hearths: Dictionary = {}   # hearthstone id -> interior id
static var _lying_inside: Dictionary = {}   # item id -> [interior id], cave features and house placements
static var _shelved_in: Dictionary = {}     # book id -> [interior id]
static var _started_by: Dictionary = {}     # quest id -> [what starts it]
static var _pads: Dictionary = {}           # place/poi id -> true, stood in the built world
static var _cells_read := false
static var _built := false


static func reset() -> void:
	for d in [_in_the_open, _below, _below_count, _cave_hearths, _lying_inside, _shelved_in, _started_by, _pads]:
		(d as Dictionary).clear()
	_cells_read = false
	_built = false


# --- the walk -------------------------------------------------------------------------------------

## Every objective of every authored quest: [{quest_id, stage_id, index, type, target, optional,
## ok, how}], in pack order.
static func objectives() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for def in _authored():
		for stage_v in def.get("stages", []):
			var stage: Dictionary = stage_v
			var objs: Array = stage.get("objectives", [])
			for i in objs.size():
				var o: Dictionary = objs[i]
				var v := verdict(def, stage, i)
				out.append({"quest_id": str(def["id"]), "stage_id": str(stage.get("id", "")), "index": i,
						"type": str(o.get("type", "")), "target": str(o.get("target", "")),
						"optional": bool(o.get("optional", false)), "ok": bool(v["ok"]), "how": str(v["how"])})
	return out


## How each authored quest begins: [{quest_id, ok, how}]. The opening, or a `start_quest` effect
## in a line of dialogue, a stage or a reward. A `giver` alone starts nothing: nothing reads it to
## offer the quest (`QuestConditions.offers_of` has only ever been called by its tests).
static func beginnings() -> Array[Dictionary]:
	_build()
	var out: Array[Dictionary] = []
	for def in _authored():
		var id := str(def["id"])
		var ways: Array[String] = []
		for how in _started_by.get(id, []):
			ways.append(str(how))
		if ways.is_empty():
			var giver := str(def.get("giver", ""))
			out.append({"quest_id": id, "ok": false, "how": "nothing starts it%s" % (
					"" if giver == "" else ": %s has no line that does" % _name(giver))})
		else:
			out.append({"quest_id": id, "ok": true, "how": "; ".join(ways)})
	return out


## One objective's verdict: {ok, how}.
static func verdict(quest: Dictionary, stage: Dictionary, index: int) -> Dictionary:
	_build()
	var objs: Array = stage.get("objectives", [])
	if index < 0 or index >= objs.size():
		return _no("no such objective")
	var o: Dictionary = objs[index]
	var target := str(o.get("target", ""))
	match str(o.get("type", "")):
		"talk":
			return _person(target)
		"reach":
			return _place(target)
		"kill":
			return _kill(o)
		"collect":
			return _item(target)
		"use_item":
			return _use(target)
		"read_book":
			return _book(target)
		"deliver":
			return _deliver(quest, stage, index)
		"escort":
			return _escort(o)
		"choice":
			return _choice(quest, stage, o)
		"rest_at":
			return _rest(target)
	return _no("no tracker listens for a '%s'" % str(o.get("type", "")))


## Every target the job boards could name, region by region, and whether it can be done:
## [{template, region, token, type, target, ok, how}]. `generator` is the `RadiantGenerator`.
static func radiant(generator: Object) -> Array[Dictionary]:
	_build()
	var out: Array[Dictionary] = []
	if generator == null:
		return out
	var regions := ContentDB.all("region")
	regions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	for t in generator.templates():
		var spec: Dictionary = t.get("template", {})
		var targets: Dictionary = spec.get("targets", {})
		for region_def in regions:
			var region := str(region_def["id"])
			var board: String = generator.default_board(region)
			if board == "":
				continue
			var board_kinds: Array = spec.get("board_kinds", [])
			if not board_kinds.is_empty() and not board_kinds.has(str(ContentDB.get_or_empty(board).get("kind", ""))):
				continue
			for stage_v in t.get("stages", []):
				for o_v in (stage_v as Dictionary).get("objectives", []):
					var o: Dictionary = o_v
					var type := str(o.get("type", ""))
					for field in ["target", "place"]:
						var token := _token(str(o.get(field, "")))
						if token == "":
							continue
						var pool: Array[String] = []
						if token == "place":
							pool.append(board)
						else:
							pool = generator.pool_for(targets.get(token, ""), region, board)
						# an empty pool is a notice the generator never writes (it skips the
						# template there), not one that cannot be done
						for id in pool:
							var v := _radiant_one(type, field, id, region)
							out.append({"template": str(t["id"]), "region": region, "token": token, "type": type,
									"target": id, "ok": bool(v["ok"]), "how": str(v["how"])})
	return out


static func _radiant_one(type: String, field: String, id: String, region: String) -> Dictionary:
	if field == "place" or type == "reach":
		return _place(id)
	match type:
		"kill":
			return _foe(id, region)
		"collect":
			return _item(id, true)
		"talk", "escort":
			return _person(id)
	return _no("no tracker listens for a '%s'" % type)


## The walk as text, for the console and the report: every objective, or only what cannot be closed.
static func report(everything: bool = false) -> String:
	var lines: PackedStringArray = []
	var rows := objectives()
	var cannot := 0
	for r in rows:
		if not bool(r["ok"]):
			cannot += 1
		if everything or not bool(r["ok"]):
			var target := str(r["target"])
			lines.append("%s %s / %s [%s %s]: %s" % ["ok " if bool(r["ok"]) else "NO ", Ids.name_of(str(r["quest_id"])),
					r["stage_id"], r["type"], Ids.name_of(target) if target.contains(":") else target, r["how"]])
	for b in beginnings():
		if not bool(b["ok"]):
			lines.append("NO  %s does not begin: %s" % [Ids.name_of(str(b["quest_id"])), b["how"]])
	lines.insert(0, "%d objectives in %d quests; %d cannot be closed" % [rows.size(), _authored().size(), cannot])
	return "\n".join(lines)


# --- one kind at a time ------------------------------------------------------------------------------

## Somebody to talk to: they exist and they live somewhere. A conversation with somebody who has
## no lines of their own is a bare greeting, and it ends like any other, which is all a `talk` or
## a hand-over waits for; a decision put at a hub (`needs_lines`) needs a hub to put it at.
static func _person(npc_id: String, needs_lines := false) -> Dictionary:
	if npc_id == "" or npc_id == "any" or npc_id.begins_with("tag:"):
		return _yes("anybody")
	var def := ContentDB.get_or_empty(npc_id)
	if def.is_empty() or Ids.type_of(npc_id) != "npc":
		return _no("%s is nobody in the pack" % npc_id)
	var lines := str(def.get("dialogue", "")) != "" and ContentDB.has(str(def["dialogue"]))
	if needs_lines and not lines:
		return _no("%s has no lines of their own to put it in" % _name(npc_id))
	var home := str(def.get("home_place", ""))
	if not _stands(home):
		return _no("%s lives at %s, which is nowhere a body can be stood up" % [_name(npc_id), home])
	return _yes("%s at %s%s" % [_name(npc_id), _name(home), "" if lines else " (a bare greeting)"])


## Somewhere to arrive: a place or point of interest with a position.
static func _place(place_id: String) -> Dictionary:
	if _stands(place_id):
		return _yes("arrive at %s" % _name(place_id))
	return _no("%s has no position to arrive at" % place_id)


## Something to kill, and where it stands: the open country's cells, a deep place's encounters, a
## point of interest's own. With a region, only what stands in it counts (a job board's hunt).
static func _foe(target: String, region: String = "") -> Dictionary:
	_read_cells()
	if target == "" or target == "any":
		return _yes("anything that fights")
	var ids: Array[String] = []
	if target.begins_with("tag:"):
		var tag := target.substr(4)
		for type in ["enemy", "boss"]:
			for def in ContentDB.all(type):
				if (def.get("tags", []) as Array).has(tag):
					ids.append(str(def["id"]))
	elif ContentDB.has(target):
		ids.append(target)
	else:
		return _no("%s is no enemy in the pack" % target)
	var where: Array[String] = []
	for id in ids:
		var open: Dictionary = _in_the_open.get(id, {})
		var n := 0
		for r in open:
			if region == "" or str(r) == region:
				n += int(open[r])
		if n > 0:
			where.append("%d in the open%s" % [n, "" if region == "" else " of " + _name(region)])
		for interior in _below.get(id, []):
			if region == "" or _region_of(str(interior)) == region:
				where.append("in " + _name(str(interior)))
		for poi in PoiEncounters.foes_at(id):
			if region == "" or _region_of(str(poi)) == region:
				where.append("at " + _name(str(poi)))
	if where.is_empty():
		return _no("%s stands nowhere%s: no cell, deep place or point of interest raises one"
				% [_name(target), "" if region == "" else " in " + _name(region)])
	return _yes(", ".join(where))


## A kill where the story puts it (`where`, KillPlaces): in a deep place, as many as its encounters
## stand; at a place in the open, what `QuestFoes` stands for the stage (and what already stands
## there); a boss, where its place stands it. A kill objective with no `where` is asked the old
## question, whether the foe stands anywhere at all.
static func _kill(o: Dictionary) -> Dictionary:
	var target := str(o.get("target", ""))
	var where := str(o.get("where", ""))
	if where == "" or where == KillPlaces.ANYWHERE:
		return _foe(target)
	if not ContentDB.has(target):
		return _no("%s is no enemy in the pack" % target)
	var count := maxi(1, int(o.get("count", 1)))
	if Ids.type_of(where) == "interior":
		var n := int(_below_count.get("%s|%s" % [where, target], 0))
		if n < count:
			return _no("%s holds %d %s, and the story asks for %d there" % [_name(where), n, _name(target), count])
		return _yes("%d in %s" % [n, _name(where)])
	if not _stands(where):
		return _no("%s has no position for the fight" % where)
	if Ids.type_of(target) == "boss":
		for e in PoiEncounters.of(where):
			if str((e as Dictionary).get("enemy", "")) == target:
				return _yes("at %s" % _name(where))
		return _no("%s stands nowhere at %s" % [_name(target), _name(where)])
	var when := str(o.get("when", "always"))
	var already := 0
	for e in PoiEncounters.of(where):
		if str((e as Dictionary).get("enemy", "")) == target:
			already += maxi(1, int((e as Dictionary).get("count", 1)))
	var who := "the stage stands them"
	if str(o.get("stand", "")) == QuestFoes.OWN:
		who = "the stage stands its own"
	elif already >= count:
		who = "%d of its own" % already
	elif already > 0:
		who = "%d of its own, and the stage stands the rest" % already
	return _yes("at %s%s: %s" % [_name(where), "" if when == "always" else " by " + when, who])


## How a player comes by an item, surest first: lying where a quest says, handed over by the
## story, sold, lying in a house or a deep place. A loot table alone is a chance, not a way, for
## the one thing a story turns on; for a job board's "five of these", `chance_ok` counts it.
static func _item(item: String, chance_ok := false) -> Dictionary:
	if item == "" or not ContentDB.has(item) or Ids.type_of(item) != "item":
		return _no("%s is no item in the pack" % item)
	var ways: Array[String] = []
	for row in QuestItems.placements():
		if str(row.get("item", "")) == item:
			ways.append("lies at %s" % _name(str(row["where"])))
	for how in ItemSources.how_given(item):
		var parts := str(how).split(" ", false, 1)
		ways.append("%s (%s)" % [_given_as(parts[0]), Ids.name_of(parts[1]) if parts.size() > 1 else ""])
	for table in ItemSources.sold_by(item):
		ways.append("sold (%s)" % Ids.name_of(str(table)))
	for interior in _lying_inside.get(item, []):
		ways.append("lies in %s" % _name(str(interior)))
	if not ways.is_empty():
		return _yes("; ".join(ways))
	if ItemSources.rolled(item):
		if chance_ok:
			return _yes("a chance on a loot table")
		return _no("%s is only a chance on a loot table" % _name(item))
	return _no("nothing gives, sells or puts down %s" % _name(item))


static func _given_as(how: String) -> String:
	match how:
		"dialogue":
			return "given in conversation"
		"quest":
			return "given by a quest stage"
		"reward":
			return "a quest's reward"
		"drop":
			return "dropped"
		"calling":
			return "a Calling's kit"
	return how


static func _use(item: String) -> Dictionary:
	var got := _item(item)
	if not bool(got["ok"]):
		return got
	var stack := ItemStack.new(item, 1)
	if not (stack.is_tool() or stack.is_consumable() or stack.is_equippable()):
		return _no("%s cannot be used: it is neither eaten, worn nor a tool" % _name(item))
	return _yes("use it: %s" % got["how"])


## A book is read off a shelf where a house keeps it, or out of the bag from the item that reads it.
static func _book(book: String) -> Dictionary:
	if not ContentDB.has(book):
		return _no("%s is no book in the pack" % book)
	var ways: Array[String] = []
	for interior in _shelved_in.get(book, []):
		ways.append("on a shelf in %s" % _name(str(interior)))
	var reader := ItemSources.reader_of(book)
	if reader != "":
		var got := _item(reader)
		if bool(got["ok"]):
			ways.append("%s: %s" % [_name(reader), got["how"]])
		elif ways.is_empty():
			return got
	if ways.is_empty():
		return _no("no item reads %s and no shelf keeps it" % _name(book))
	return _yes("; ".join(ways))


static func _deliver(quest: Dictionary, stage: Dictionary, index: int) -> Dictionary:
	var o: Dictionary = stage["objectives"][index]
	var person := _person(str(o.get("target", "")))
	if not bool(person["ok"]):
		return person
	var closes := "in their own line" if QuestRoutes.dialogue_closes(str(quest["id"]), stage, index) \
			else "when you finish speaking with them"
	var item := str(o.get("item", ""))
	if item == "":
		return _yes("%s; handed over %s" % [person["how"], closes])
	var got := _item(item)
	if not bool(got["ok"]):
		return got
	return _yes("%s to %s, handed over %s" % [_name(item), person["how"], closes])


static func _escort(o: Dictionary) -> Dictionary:
	var person := _person(str(o.get("target", "")))
	if not bool(person["ok"]):
		return person
	var place := str(o.get("place", ""))
	if place != "" and not _stands(place):
		return _no("%s is nowhere to walk anybody to" % place)
	return _yes("%s walks with you to %s" % [person["how"], _name(place) if place != "" else "wherever the stage says"])


static func _choice(quest: Dictionary, stage: Dictionary, o: Dictionary) -> Dictionary:
	var quest_id := str(quest["id"])
	if QuestRoutes.dialogue_offers(quest_id, o):
		return _yes("an authored line puts it")
	for row in QuestItems.placements():
		if str(row["kind"]) == "choice" and str(row["quest_id"]) == quest_id and str(row["stage_id"]) == str(stage.get("id", "")):
			return _yes("decided at %s, where nobody is left to ask" % _name(str(row["where"])))
	var host := QuestRoutes.host_of(quest, stage, o)
	if host == "":
		return _no("nobody to decide it with")
	if Ids.type_of(host) != "npc":
		return _no("its host %s is a place and nothing stands there to decide it at" % host)
	var person := _person(host, true)
	if not bool(person["ok"]):
		return person
	return _yes("offered at the hub of %s" % person["how"])


static func _rest(target: String) -> Dictionary:
	if target == "" or target == "any" or target.begins_with("tag:"):
		return _yes("any Hearthstone")
	var def := ContentDB.get_or_empty(target)
	if not def.is_empty() and _pads.has(target) \
			and (bool(def.get("hearthstone", false)) or PoiDressing.kind_of(target, def) == "hearth"):
		return _yes("the Hearthstone at %s" % _name(target))
	if _cave_hearths.has(target):
		return _yes("the Hearthstone in %s" % _name(str(_cave_hearths[target])))
	return _no("no Hearthstone of that id stands anywhere")


# --- what the game holds ---------------------------------------------------------------------------

static func _authored() -> Array:
	var out: Array = []
	for def in ContentDB.all("quest"):
		if str(def.get("layer", "")) != "radiant":
			out.append(def)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	return out


static func _build() -> void:
	if _built:
		return
	_built = true
	if FileAccess.file_exists(PADS_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PADS_PATH))
		if typeof(parsed) == TYPE_ARRAY:
			for e in parsed:
				if typeof(e) == TYPE_DICTIONARY:
					_pads[str((e as Dictionary).get("place_id", ""))] = true
	for def in ContentDB.all("interior"):
		var path := str(def.get("meta", ""))
		if path == "" or not FileAccess.file_exists(path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var meta: Dictionary = parsed
		var interior := str(def["id"])
		var place := str(def.get("place", ""))
		for e in meta.get("encounters", []):
			var enemy := str((e as Dictionary).get("enemy", ""))
			_note(_below, enemy, interior)
			var key := "%s|%s" % [interior, enemy]
			_below_count[key] = int(_below_count.get(key, 0)) + maxi(1, int((e as Dictionary).get("count", 1)))
		for f_v in meta.get("features", []):
			var f: Dictionary = f_v
			match str(f.get("kind", "")):
				"hearthstone":
					_cave_hearths[str(f.get("id", "%s_hearth" % meta.get("id", "")))] = interior
				"item":
					var item := str(f.get("item", ""))
					if ContentDB.has(item) and not ItemSources.boss_drops_at(item, place):
						_note(_lying_inside, item, interior)
		for p_v in meta.get("placements", []):
			var p: Dictionary = p_v
			if str(p.get("book", "")) != "":
				_note(_shelved_in, str(p["book"]), interior)
			if str(p.get("item", "")) != "" and not bool(p.get("fixed", false)):
				_note(_lying_inside, str(p["item"]), interior)
	var opening := str(ContentDB.get_or_empty(GameServices.OPENING).get("quest", ""))
	if opening != "":
		_note(_started_by, opening, "the opening of a new game")
	for def in ContentDB.all("dialogue"):
		_starts_in(def, "said in %s" % Ids.name_of(str(def["id"])))
	for def in _authored():
		_starts_in(def.get("stages", []), "follows %s" % Ids.name_of(str(def["id"])))
		_starts_in(def.get("rewards", {}), "follows %s" % Ids.name_of(str(def["id"])))


static func _starts_in(v: Variant, how: String) -> void:
	if typeof(v) == TYPE_DICTIONARY:
		var d: Dictionary = v
		if d.has("start_quest"):
			_note(_started_by, str(d["start_quest"]), how)
		for key in d:
			_starts_in(d[key], how)
	elif typeof(v) == TYPE_ARRAY:
		for x in v:
			_starts_in(x, how)


## Which enemies the built cells stand up, by region. The cells are the world as built; the text
## is scanned for each spawn's `def` rather than parsed, since a cell is mostly its scatter.
static func _read_cells() -> void:
	if _cells_read:
		return
	_cells_read = true
	var dir := DirAccess.open(CELLS_DIR)
	if dir == null:
		return
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var text := FileAccess.get_file_as_string("%s/%s" % [CELLS_DIR, file])
		var region := _string_after(text, "\"region\":", 0)
		var at := text.find("\"def\":")
		while at >= 0:
			var id := _string_after(text, "\"def\":", at)
			if id != "":
				var by_region: Dictionary = _in_the_open.get(id, {})
				by_region[region] = int(by_region.get(region, 0)) + 1
				_in_the_open[id] = by_region
			at = text.find("\"def\":", at + 6)


static func _string_after(text: String, key: String, from: int) -> String:
	var at := text.find(key, from)
	if at < 0:
		return ""
	var open := text.find("\"", at + key.length())
	var close := text.find("\"", open + 1) if open >= 0 else -1
	return text.substr(open + 1, close - open - 1) if close > open else ""


## A place a body can be stood up at or arrived at: a pad in the built world, or a position in
## the content.
static func _stands(id: String) -> bool:
	if id == "":
		return false
	_build()
	if _pads.has(id):
		return true
	return WorldProbe.xz_of(ContentDB.get_or_empty(id)) != Vector2.ZERO


static func _region_of(id: String) -> String:
	var def := ContentDB.get_or_empty(id)
	var region := str(def.get("region", ""))
	if region == "" and def.has("place"):
		region = str(ContentDB.get_or_empty(str(def["place"])).get("region", ""))
	return region


static func _name(id: String) -> String:
	var def := ContentDB.get_or_empty(id)
	return str(def.get("name", def.get("title", Ids.name_of(id).replace("_", " "))))


static func _note(into: Dictionary, key: String, value: String) -> void:
	if key == "":
		return
	var list: Array = into.get(key, [])
	if not list.has(value):
		list.append(value)
	into[key] = list


static func _token(value: String) -> String:
	return value.substr(1, value.length() - 2) if value.begins_with("{") and value.ends_with("}") else ""


static func _yes(how: String) -> Dictionary:
	return {"ok": true, "how": how}


static func _no(why: String) -> Dictionary:
	return {"ok": false, "how": why}
