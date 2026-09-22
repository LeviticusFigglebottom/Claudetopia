class_name RadiantGenerator
extends RefCounted
## Radiant: job boards. Turns the templates in content (core:quest/radiant_*) into real quests
## with region-appropriate targets, written journal text and rewards scaled by how dangerous the
## region is and how far the work is from the board.
##
## A template is an ordinary quest definition carrying a `template` block:
##   {kind, board_kinds[], targets{token: {pool, ...filters}}, count[min, max],
##    reward{base_marks, marks_per_danger, marks_per_count, marks_per_distance_km, renown,
##           rep_with_board_faction, morality},
##    names[], board_lines[], journal[], objective_text[], hand_in_text}
## Its `stages` are the shape: every "{token}" in them is replaced, with ID fields taking the
## chosen definition's id and text fields taking its name, so generated journals never show a
## placeholder.
##
## Boards call generate(region_id, count) (or generate_for_board, which adds the cooldown).
## Generation is deterministic for a given seed: the same board on the same day offers the same
## work, which is what makes a board feel like a board and not a slot machine.

## Which fields of a stage carry content ids rather than prose.
const ID_KEYS := ["target", "place", "item", "place_id", "region", "npc", "faction"]
## Default hours before a board's notices are replaced.
const DEFAULT_COOLDOWN_HOURS := 48.0
const MAX_PER_BOARD := 6

var quest_log: Object = null          # duck-typed: register_runtime(def) -> bool
var factions: Object = null           # duck-typed: law_faction_for_region(region) -> String
## Where definitions are read from. ContentDB in the game; tests pass a stand-in that adds the
## enemy and item defs other streams have not authored yet, so every pool stays covered.
var content: Object = null

var _boards: Dictionary = {}          # board_id -> {day, hour, region, quests: [ids]}
var _rng := RandomNumberGenerator.new()


func _init(quest_log_node: Object = null, factions_node: Object = null, content_db: Object = null) -> void:
	quest_log = quest_log_node
	factions = factions_node
	content = content_db


## The content registry in use (ContentDB unless a stand-in was injected).
func db() -> Object:
	if content != null and is_instance_valid(content):
		return content
	return ContentDB


## Typed wrappers so the rest of the file keeps its static types through the injection seam.
func _def(id: String) -> Dictionary:
	var d: Variant = db().get_or_empty(id)
	return d if typeof(d) == TYPE_DICTIONARY else {}


func _all(type: String) -> Array:
	var a: Variant = db().all(type)
	return a if typeof(a) == TYPE_ARRAY else []


func _known(id: String) -> bool:
	return bool(db().has(id))


# --- templates -----------------------------------------------------------------------------

## Every radiant template in content, sorted by id so generation order is stable.
func templates() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for def in _all("quest"):
		if str(def.get("layer", "")) == "radiant" and typeof(def.get("template")) == TYPE_DICTIONARY:
			out.append(def)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	return out


func template(template_id: String) -> Dictionary:
	var def := _def(template_id)
	return def if typeof(def.get("template")) == TYPE_DICTIONARY else {}


# --- generation -----------------------------------------------------------------------------

## Generates up to `count` quests for a region. `board_place` is the place whose board this is
## (it appears in the text and is where the pay is collected); when empty, a settled place in the
## region is chosen. A seed of 0 derives one from the region, day and board so that the same
## board offers the same work all day.
func generate(region_id: String, count: int = 3, board_place: String = "", seed_value: int = 0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var board := board_place if board_place != "" else _default_board(region_id)
	if board == "":
		Log.warn("Radiant", "no settled place in %s to hang a board on" % region_id)
		return out
	_rng.seed = seed_value if seed_value != 0 else _daily_seed(region_id, board)
	var pool := templates()
	if pool.is_empty():
		Log.warn("Radiant", "no radiant templates in content")
		return out
	var tried: Dictionary = {}
	var attempts := 0
	while out.size() < count and attempts < count * pool.size() + pool.size():
		attempts += 1
		var t: Dictionary = pool[_rng.randi() % pool.size()]
		var key := "%s#%d" % [str(t["id"]), out.size()]
		if tried.has(key):
			continue
		tried[key] = true
		var made := _make_one(t, region_id, board)
		if made.is_empty():
			continue
		var dup := false
		for q in out:
			if str(q["id"]) == str(made["id"]):
				dup = true
				break
		if dup:
			continue
		out.append(made)
	_publish(out)
	return out


## A generated quest has no content-pack definition, so the log can only start it once it has
## been handed the runtime def. Anything this class gives out goes through here, because a
## notice a player can read and cannot accept is worse than no notice: `start()` answers
## "cannot start unknown quest" and the button does nothing.
func _publish(defs: Array) -> void:
	if quest_log == null or not quest_log.has_method("register_runtime"):
		return
	for q in defs:
		if typeof(q) == TYPE_DICTIONARY and not (q as Dictionary).is_empty():
			quest_log.register_runtime(q)


## Board-facing generation with a cooldown: within `cooldown_hours` the same notices come back.
func generate_for_board(board_id: String, region_id: String, count: int = 3, cooldown_hours: float = DEFAULT_COOLDOWN_HOURS) -> Array[Dictionary]:
	count = clampi(count, 1, MAX_PER_BOARD)
	var now := float(WorldClock.day) * 24.0 + WorldClock.time_hours
	var state: Dictionary = _boards.get(board_id, {})
	if not state.is_empty() and now - float(state.get("at", -9999.0)) < cooldown_hours:
		var kept: Array[Dictionary] = []
		for qid in state.get("quests", []):
			var def := _stored_def(str(qid))
			if not def.is_empty():
				kept.append(def)
		if not kept.is_empty():
			# The notices that were already on this board. They are handed straight back out
			# of the board cache, and used not to be registered on the way — so a board read
			# after a load, or after a new game wiped the log while this cache survived, was
			# a list of work that refused to be taken.
			_publish(kept)
			return kept
	var made := generate(region_id, count, board_id, 0)
	var ids: Array[String] = []
	var defs: Array = []
	for q in made:
		ids.append(str(q["id"]))
		defs.append(q)
	_boards[board_id] = {"at": now, "region": region_id, "quests": ids, "defs": defs}
	return made


## Hours until this board's notices change, or 0 when it is ready now.
func board_cooldown_remaining(board_id: String, cooldown_hours: float = DEFAULT_COOLDOWN_HOURS) -> float:
	var state: Dictionary = _boards.get(board_id, {})
	if state.is_empty():
		return 0.0
	var now := float(WorldClock.day) * 24.0 + WorldClock.time_hours
	return maxf(0.0, cooldown_hours - (now - float(state.get("at", 0.0))))


func board_quests(board_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for qid in _boards.get(board_id, {}).get("quests", []):
		var def := _stored_def(str(qid))
		if not def.is_empty():
			out.append(def)
	return out


func _stored_def(quest_id: String) -> Dictionary:
	for board_id in _boards:
		for d in _boards[board_id].get("defs", []):
			if typeof(d) == TYPE_DICTIONARY and str((d as Dictionary).get("id", "")) == quest_id:
				return d
	if quest_log != null and quest_log.has_method("definition"):
		var def: Variant = quest_log.definition(quest_id)
		if typeof(def) == TYPE_DICTIONARY:
			return def
	return {}


## Where a board hangs when the caller does not say: the largest settled place in the region.
func _default_board(region_id: String) -> String:
	const PREFERENCE := ["city", "town", "village", "fort", "camp", "lodge", "hamlet"]
	var best := ""
	var best_rank := PREFERENCE.size()
	for def in _all("place"):
		if str(def.get("region", "")) != region_id:
			continue
		var rank := PREFERENCE.find(str(def.get("kind", "")))
		if rank < 0 or rank > best_rank:
			continue
		if rank < best_rank or str(def["id"]) < best:
			best_rank = rank
			best = str(def["id"])
	return best


func _daily_seed(region_id: String, board: String) -> int:
	return abs(hash("%s|%s|%d" % [region_id, board, WorldClock.day])) | 1


# --- one quest ---------------------------------------------------------------------------------

func _make_one(t: Dictionary, region_id: String, board: String) -> Dictionary:
	var spec: Dictionary = t["template"]
	var board_def := _def(board)
	var board_kinds: Array = spec.get("board_kinds", [])
	if not board_kinds.is_empty() and not board_kinds.has(str(board_def.get("kind", ""))):
		return {}

	var ids: Dictionary = {"place": board, "region": region_id}
	var names: Dictionary = {
		"place": _display(board), "region": _display(region_id),
		"board": _display(board),
	}
	for token in spec.get("targets", {}):
		var chosen := _pick(spec["targets"][token], region_id, board)
		if chosen == "":
			return {}   # the world has no content for this template yet; try another
		ids[token] = chosen
		names[token] = _display(chosen)

	var range_spec: Array = spec.get("count", [1, 1])
	var lo: int = int(range_spec[0]) if range_spec.size() > 0 else 1
	var hi: int = int(range_spec[1]) if range_spec.size() > 1 else lo
	var n: int = _rng.randi_range(mini(lo, hi), maxi(lo, hi))
	ids["count"] = n
	names["count"] = n

	var reward := _rewards(spec, region_id, board, ids, n)
	ids["marks"] = int(reward.get("marks", 0))
	names["marks"] = ids["marks"]

	# Text variants first: they become tokens the stages can use ({journal}, {objective_text}).
	for key in ["names", "board_lines", "journal", "objective_text"]:
		var list: Variant = spec.get(key, [])
		if typeof(list) == TYPE_ARRAY and not (list as Array).is_empty():
			var text := str((list as Array)[_rng.randi() % (list as Array).size()])
			names[_singular(key)] = _fill_text(text, names)
	if spec.has("hand_in_text"):
		names["hand_in_text"] = _fill_text(str(spec["hand_in_text"]), names)

	var quest_id := _make_id(str(t["id"]), ids, n)
	var def: Dictionary = {
		"id": quest_id,
		"name": str(names.get("name", str(t.get("name", "Work")))),
		"layer": "radiant",
		"template_id": str(t["id"]),
		"kind": str(spec.get("kind", "")),
		"region": region_id,
		"board": board,
		"board_line": str(names.get("board_line", "")),
		"giver": board,
		"generated_day": WorldClock.day,
		"stages": _fill_stages(t.get("stages", []), ids, names),
		"rewards": reward,
	}
	_check_placeholders(def)
	return def


func _make_id(template_id: String, ids: Dictionary, n: int) -> String:
	var parts: Array[String] = []
	for token in ids:
		parts.append("%s=%s" % [token, str(ids[token])])
	parts.sort()
	var digest := "%x" % (abs(hash("|".join(parts) + str(n))) % 0xFFFFFF)
	return "%s.%s" % [template_id, digest]


func _rewards(spec: Dictionary, region_id: String, board: String, ids: Dictionary, n: int) -> Dictionary:
	var r: Dictionary = spec.get("reward", {})
	var danger := int(_def(region_id).get("danger", 1))
	var marks := float(r.get("base_marks", 20))
	marks += float(r.get("marks_per_danger", 0)) * float(danger)
	marks += float(r.get("marks_per_count", 0)) * float(n)
	var per_km := float(r.get("marks_per_distance_km", 0.0))
	if per_km > 0.0:
		var far := ""
		for token in ["destination", "den", "ground"]:
			if ids.has(token):
				far = str(ids[token])
				break
		if far != "":
			marks += per_km * (_distance_m(board, far) / 1000.0)
	var out: Dictionary = {
		"marks": int(round(marks)),
		"renown": int(r.get("renown", 0)) + maxi(0, danger - 2),
		"deed": "quest_complete_radiant",
	}
	if int(r.get("morality", 0)) != 0:
		out["morality"] = int(r["morality"])
	var rep := int(r.get("rep_with_board_faction", 0))
	if rep > 0:
		var faction := _board_faction(region_id)
		if faction != "":
			out["rep"] = [[faction, rep]]
	return out


func _board_faction(region_id: String) -> String:
	if factions != null and is_instance_valid(factions) and factions.has_method("law_faction_for_region"):
		var f := str(factions.law_faction_for_region(region_id))
		if f != "":
			return f
	return str(_def(region_id).get("law_faction", ""))


func _distance_m(a_id: String, b_id: String) -> float:
	var a: Array = _def(a_id).get("position", [])
	var b: Array = _def(b_id).get("position", [])
	if a.size() < 2 or b.size() < 2:
		return 0.0
	return Vector2(float(a[0]), float(a[1])).distance_to(Vector2(float(b[0]), float(b[1])))


# --- target pools --------------------------------------------------------------------------------

## Chooses one content id for a target spec, or "" when the world has nothing suitable.
func _pick(spec_value: Variant, region_id: String, board: String) -> String:
	if typeof(spec_value) == TYPE_STRING:
		return str(spec_value)
	var spec: Dictionary = spec_value
	var candidates := _candidates(spec, region_id, board)
	if candidates.is_empty() and spec.has("fallback_pool"):
		var fallback := spec.duplicate(true)
		fallback["pool"] = spec["fallback_pool"]
		fallback.erase("fallback_pool")
		if spec.has("fallback_kinds"):
			fallback["kinds"] = spec["fallback_kinds"]
		candidates = _candidates(fallback, region_id, board)
	if candidates.is_empty():
		Log.info("Radiant", "no %s in %s yet for a radiant target" % [str(spec.get("pool", "?")), region_id])
		return ""
	candidates.sort()
	return candidates[_rng.randi() % candidates.size()]


func _candidates(spec: Dictionary, region_id: String, board: String) -> Array[String]:
	var pool := str(spec.get("pool", ""))
	match pool:
		"enemy":
			return _enemies_for(region_id, spec.get("traits", []))
		"place":
			return _places_for(region_id, spec, board)
		"poi":
			return _pois_for(region_id, spec)
		"npc":
			return _npcs_for(region_id, spec)
		"item":
			return _items_for(spec)
		_:
			Log.warn("Radiant", "unknown target pool '%s' (content problem)" % pool)
			return []


## Enemies whose data places them in the region (the region's ecology list, a region/regions
## field on the enemy, or a region tag), narrowed by archetype or tag when the template asks.
func _enemies_for(region_id: String, traits: Array) -> Array[String]:
	var region := _def(region_id)
	var in_region: Array[String] = []
	for id in region.get("enemy_ecology", []):
		if _known(str(id)):
			in_region.append(str(id))
	if in_region.is_empty():
		for def in _all("enemy"):
			var regions: Variant = def.get("regions", def.get("region", ""))
			var ok := false
			if typeof(regions) == TYPE_ARRAY:
				ok = (regions as Array).has(region_id)
			elif str(regions) == region_id:
				ok = true
			elif typeof(def.get("tags")) == TYPE_ARRAY and (def["tags"] as Array).has(Ids.name_of(region_id)):
				ok = true
			if ok:
				in_region.append(str(def["id"]))
	if traits.is_empty():
		return in_region
	var narrowed: Array[String] = []
	for id in in_region:
		var def := _def(id)
		var tags: Array = def.get("tags", [])
		var archetype := str(def.get("archetype", ""))
		for t in traits:
			if archetype == str(t) or tags.has(str(t)):
				narrowed.append(id)
				break
	# A template that asks for traits nothing in this region has must be skipped, not
	# filled with whatever else lives here: that is how a wanted notice names a wolf.
	return narrowed


func _places_for(region_id: String, spec: Dictionary, board: String) -> Array[String]:
	var kinds: Array = spec.get("kinds", [])
	var out: Array[String] = []
	for def in _all("place"):
		var id := str(def["id"])
		if bool(spec.get("not_board", false)) and id == board:
			continue
		if bool(spec.get("same_region", false)) and str(def.get("region", "")) != region_id:
			continue
		if not kinds.is_empty() and not kinds.has(str(def.get("kind", ""))):
			continue
		if not bool(spec.get("same_region", false)) and str(def.get("region", "")) != region_id:
			# Deliveries may cross a border, but only to a neighbouring region's settlements.
			if not bool(spec.get("allow_other_regions", true)):
				continue
		out.append(id)
	return out


func _pois_for(region_id: String, spec: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for def in _all("poi"):
		if bool(spec.get("same_region", true)) and str(def.get("region", "")) != region_id:
			continue
		var kinds: Array = spec.get("kinds", [])
		if not kinds.is_empty() and not kinds.has(str(def.get("kind", ""))):
			continue
		out.append(str(def["id"]))
	return out


func _npcs_for(region_id: String, spec: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for def in _all("npc"):
		if bool(def.get("no_radiant", false)):
			continue
		var home := str(def.get("home_place", ""))
		if bool(spec.get("same_region", true)):
			if str(_def(home).get("region", "")) != region_id:
				continue
		out.append(str(def["id"]))
	return out


func _items_for(spec: Dictionary) -> Array[String]:
	var tags: Array = spec.get("tags", [])
	var cats: Array = spec.get("fallback_categories", [])
	var tagged: Array[String] = []
	var by_cat: Array[String] = []
	for def in _all("item"):
		if bool(def.get("no_radiant", false)) or bool(def.get("quest_item", false)):
			continue
		var item_tags: Array = def.get("tags", [])
		var hit := false
		for t in tags:
			if item_tags.has(str(t)):
				hit = true
				break
		if hit:
			tagged.append(str(def["id"]))
		elif cats.has(str(def.get("category", ""))):
			by_cat.append(str(def["id"]))
	return tagged if not tagged.is_empty() else by_cat


# --- filling the template ---------------------------------------------------------------------------

func _fill_stages(stages: Array, ids: Dictionary, names: Dictionary) -> Array:
	var out: Array = []
	for s in stages:
		out.append(_fill_value(s, ids, names, ""))
	return out


func _fill_value(value: Variant, ids: Dictionary, names: Dictionary, key: String) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var d: Dictionary = {}
			for k in (value as Dictionary).keys():
				d[k] = _fill_value((value as Dictionary)[k], ids, names, str(k))
			return d
		TYPE_ARRAY:
			var a: Array = []
			for v in value:
				a.append(_fill_value(v, ids, names, key))
			return a
		TYPE_STRING:
			var s := str(value)
			if key in ID_KEYS or key == "count" or key == "radius":
				var filled := _fill_text(s, ids)
				if key == "count" or key == "radius":
					return int(filled) if filled.is_valid_int() else filled
				return filled
			return _fill_text(s, names)
		_:
			return value


static func _fill_text(text: String, values: Dictionary) -> String:
	if text.find("{") < 0:
		return text
	var out := text
	for token in values:
		out = out.replace("{%s}" % token, str(values[token]))
	return out


static func _singular(key: String) -> String:
	match key:
		"names":
			return "name"
		"board_lines":
			return "board_line"
		"objective_text":
			return "objective_text"
		_:
			return key


func _display(id: String) -> String:
	var def := _def(id)
	if def.has("name"):
		return str(def["name"])
	if def.has("title"):
		return str(def["title"])
	return id.get_slice("/", 1).replace("_", " ")


## A generated quest must never show a player a raw token; anything left is a content problem.
func _check_placeholders(def: Dictionary) -> void:
	var leftovers := _find_tokens(def)
	if not leftovers.is_empty():
		Log.warn("Radiant", "%s: unresolved tokens %s (content problem in its template)" % [str(def.get("id", "?")), str(leftovers)])


static func _find_tokens(value: Variant, out: Array[String] = []) -> Array[String]:
	match typeof(value):
		TYPE_DICTIONARY:
			for k in (value as Dictionary).keys():
				_find_tokens((value as Dictionary)[k], out)
		TYPE_ARRAY:
			for v in value:
				_find_tokens(v, out)
		TYPE_STRING:
			var s := str(value)
			var start := s.find("{")
			while start >= 0:
				var end := s.find("}", start)
				if end < 0:
					break
				var token := s.substr(start, end - start + 1)
				if not out.has(token):
					out.append(token)
				start = s.find("{", end)
	return out


# --- save (folded into the quest log's section) -------------------------------------------------

func to_save() -> Dictionary:
	return {"boards": _boards.duplicate(true)}


func from_save(d: Dictionary) -> void:
	_boards = (d.get("boards", {}) as Dictionary).duplicate(true)
	# The boards come back with their notices; the log has to be told what they are, or every
	# job still hanging on a board in the loaded game cannot be taken.
	for board_id in _boards:
		_publish(_boards[board_id].get("defs", []))


## A new game keeps no boards. Without this the generator's cache outlived the quest log it
## had registered its work with, which is the same divergence a load used to cause.
func reset_for_new_game() -> void:
	_boards.clear()
