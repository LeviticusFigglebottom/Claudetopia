extends Node
## Gossip: what a place is currently saying. Witnessed deeds enter the nearest settled place's
## rumour pool; every game hour the pools cool a little and the hottest rumours walk to the
## neighbouring settlements at the speed of somebody carrying news on foot.
##
## This is the mechanical half of the Candle account (WORLD_BIBLE §1.2): being spoken of is what
## holds. Greeting selection asks knows_deed(place_id, deed_id); the journal reads pool_of().
##
## Data: content type "rumour" (game/content/packs/core/rumours/rumours.json):
##   {id, name, tone, text, variants[]} — text templates use {player}, {place}, {npc}, {title}.
## Save section "gossip".
##
## Emits: EventBus.rumour_spread(rumour_id, place_id) when a rumour reaches a new place.

## How much of a rumour survives a game hour. Small talk is cold within a day; a killing is
## still being chewed over three days later, so the rate is interpolated by how big the news was
## when it was fresh. Below MIN_HEAT it is forgotten.
const DECAY_SMALL_TALK := 0.93
const DECAY_BIG_NEWS := 0.99
const MIN_HEAT := 0.08
## A rumour has to be at least this warm to be worth repeating to the next village.
const SPREAD_THRESHOLD := 0.3
## What survives the walk between places, before distance is taken off.
const TRANSFER := 0.55
## News travels about this far in a game hour (people carry it; nobody rides for gossip).
const TALK_SPEED_M_PER_HOUR := 700.0
## A place further than this from every other is on its own.
const MAX_LINK_M := 3000.0
const MAX_NEIGHBOURS := 4
## Above this heat an NPC in the place will bring the rumour up unprompted.
const KNOWN_HEAT := 0.25

## Place kinds where people live and therefore talk. Deep places and landmarks do not gossip.
const SETTLED_KINDS := ["city", "town", "village", "hamlet", "camp", "fort", "lodge", "ruin_village"]

var pools: Dictionary = {}          # place_id -> {rumour_id -> entry}
var _graph: Dictionary = {}         # place_id -> [{place, hours}]
var _graph_built := false
var rng := RandomNumberGenerator.new()

## Entry shape: {heat, peak, deed, age, spread{place_id: true}, day, hour}


func _ready() -> void:
	add_to_group("gossip")
	SaveSystem.register("gossip", self)
	if not EventBus.hour_changed.is_connected(_on_hour_changed):
		EventBus.hour_changed.connect(_on_hour_changed)


func _on_hour_changed(_hour: int) -> void:
	advance_hours(1.0)


# --- the pools ------------------------------------------------------------------------------------

## Puts a rumour into a place's pool (or warms it if it is already being said).
func add_rumour(rumour_id: String, place_id: String, heat: float = 0.6, deed_id: String = "") -> void:
	if rumour_id == "":
		return
	if not ContentDB.has(rumour_id):
		Log.warn("Gossip", "unknown rumour '%s' (content problem, ignored)" % rumour_id)
		return
	var where := place_id if place_id != "" else _fallback_place()
	if where == "":
		return
	_add_entry(where, rumour_id, clampf(heat, 0.0, 1.5), deed_id, true)


func _add_entry(place_id: String, rumour_id: String, heat: float, deed_id: String, announce: bool) -> void:
	if not pools.has(place_id):
		pools[place_id] = {}
	var pool: Dictionary = pools[place_id]
	if pool.has(rumour_id):
		var e: Dictionary = pool[rumour_id]
		e["heat"] = minf(1.5, maxf(float(e.get("heat", 0.0)), heat))
		e["peak"] = maxf(float(e.get("peak", 0.0)), float(e["heat"]))
		e["age"] = 0.0
		if deed_id != "":
			e["deed"] = deed_id
		return
	pool[rumour_id] = {
		"heat": heat, "peak": heat, "deed": deed_id, "age": 0.0, "spread": {},
		"day": WorldClock.day, "hour": WorldClock.hour(),
	}
	if announce:
		EventBus.rumour_spread.emit(rumour_id, place_id)
		Log.info("Gossip", "%s is being said at %s (heat %.2f)" % [rumour_id, place_id, heat])


## Cools every pool and carries the hottest rumours onward. Called once per game hour; tests
## call it directly to skip time.
func advance_hours(hours: float) -> void:
	if hours <= 0.0:
		return
	var steps := int(ceil(hours))
	for i in steps:
		var step: float = minf(1.0, hours - float(i))
		_decay(step)
		_spread(step)


## What share of a rumour survives an hour, given the heat it reached when it was fresh.
static func decay_rate(peak: float) -> float:
	return lerpf(DECAY_SMALL_TALK, DECAY_BIG_NEWS, clampf(peak, 0.0, 1.0))


func _decay(step: float) -> void:
	for place_id in pools.keys():
		var pool: Dictionary = pools[place_id]
		for rumour_id in pool.keys():
			var e: Dictionary = pool[rumour_id]
			var factor := pow(decay_rate(float(e.get("peak", e["heat"]))), step)
			e["heat"] = float(e["heat"]) * factor
			e["age"] = float(e.get("age", 0.0)) + step
			if float(e["heat"]) < MIN_HEAT:
				pool.erase(rumour_id)
		if pool.is_empty():
			pools.erase(place_id)


func _spread(_step: float) -> void:
	_build_graph()
	var arrivals: Array[Dictionary] = []
	for place_id in pools.keys():
		var pool: Dictionary = pools[place_id]
		for rumour_id in pool.keys():
			var e: Dictionary = pool[rumour_id]
			if float(e["heat"]) < SPREAD_THRESHOLD:
				continue
			var spread: Dictionary = e.get("spread", {})
			for link in _graph.get(place_id, []):
				var to: String = link["place"]
				if spread.has(to):
					continue
				if float(e.get("age", 0.0)) < float(link["hours"]):
					continue
				spread[to] = true
				arrivals.append({"place": to, "rumour": rumour_id, "heat": float(e["heat"]) * TRANSFER,
					"peak": float(e.get("peak", e["heat"])), "deed": str(e.get("deed", ""))})
			e["spread"] = spread
	for a in arrivals:
		if float(a["heat"]) >= MIN_HEAT:
			var already: bool = pools.get(a["place"], {}).has(a["rumour"])
			_add_entry(a["place"], a["rumour"], float(a["heat"]), str(a["deed"]), not already)
			# News keeps its size as it travels: a killing is a killing in the next village too.
			var arrived: Dictionary = pools[a["place"]][a["rumour"]]
			arrived["peak"] = maxf(float(arrived.get("peak", 0.0)), float(a["peak"]))


# --- queries -----------------------------------------------------------------------------------------

## Does this place talk about that deed? (The greeting matrix's question.)
func knows_deed(place_id: String, deed_id: String) -> bool:
	if deed_id == "":
		return false
	for rumour_id in pools.get(place_id, {}):
		var e: Dictionary = pools[place_id][rumour_id]
		if str(e.get("deed", "")) == deed_id and float(e["heat"]) >= KNOWN_HEAT:
			return true
	return false


func knows_rumour(place_id: String, rumour_id: String) -> bool:
	return heat_of(place_id, rumour_id) >= KNOWN_HEAT


func heat_of(place_id: String, rumour_id: String) -> float:
	return float(pools.get(place_id, {}).get(rumour_id, {}).get("heat", 0.0))


## Everything a place is saying, hottest first: [{rumour, heat, deed, text}].
func pool_of(place_id: String, substitutions: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rumour_id in pools.get(place_id, {}):
		var e: Dictionary = pools[place_id][rumour_id]
		out.append({
			"rumour": rumour_id, "heat": float(e["heat"]), "deed": str(e.get("deed", "")),
			"text": rumour_text(rumour_id, place_id, substitutions),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["heat"]) > float(b["heat"]))
	return out


## The hottest rumour a place can offer, or {} when it has nothing to say.
func hottest(place_id: String, substitutions: Dictionary = {}) -> Dictionary:
	var pool := pool_of(place_id, substitutions)
	return pool[0] if not pool.is_empty() else {}


## Fills a rumour's text template. Variants are picked deterministically from the place and
## rumour so the same village tells the same version each time you ask.
func rumour_text(rumour_id: String, place_id: String = "", substitutions: Dictionary = {}) -> String:
	var def := ContentDB.get_or_empty(rumour_id)
	if def.is_empty():
		return ""
	var options: Array = [str(def.get("text", ""))]
	for v in def.get("variants", []):
		options.append(str(v))
	var pick: int = absi(hash(rumour_id + "@" + place_id)) % options.size()
	var text: String = options[pick]
	var subs := substitutions.duplicate()
	if not subs.has("place"):
		subs["place"] = place_name(place_id)
	for key in subs:
		text = text.replace("{%s}" % key, str(subs[key]))
	return text


static func place_name(place_id: String) -> String:
	if place_id == "":
		return "hereabouts"
	var def := ContentDB.get_or_empty(place_id)
	return str(def.get("name", place_id.get_slice("/", 1).replace("_", " ")))


func places_talking() -> Array[String]:
	var out: Array[String] = []
	for p in pools:
		out.append(p)
	out.sort()
	return out


func clear() -> void:
	pools.clear()


func reset_for_new_game() -> void:
	clear()


# --- the talk graph -------------------------------------------------------------------------------

## Nearest settled places and how many game hours news takes to reach them.
func neighbours_of(place_id: String) -> Array:
	_build_graph()
	return _graph.get(place_id, [])


func _build_graph(force := false) -> void:
	if _graph_built and not force:
		return
	_graph_built = true
	_graph.clear()
	var settled: Array[Dictionary] = []
	for p in ContentDB.all("place"):
		if str(p.get("kind", "")) in SETTLED_KINDS:
			settled.append(p)
	for a in settled:
		var links: Array = []
		for b in settled:
			if a["id"] == b["id"]:
				continue
			var d := _distance(a, b)
			if d > MAX_LINK_M:
				continue
			links.append({"place": str(b["id"]), "dist": d, "hours": maxf(1.0, d / TALK_SPEED_M_PER_HOUR)})
		links.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["dist"]) < float(y["dist"]))
		if links.size() > MAX_NEIGHBOURS:
			links = links.slice(0, MAX_NEIGHBOURS)
		_graph[str(a["id"])] = links
	_symmetrise()


## News that reaches a village comes back the other way too, even if the village was not one of
## its neighbour's nearest four.
func _symmetrise() -> void:
	for a in _graph.keys():
		for link in _graph[a]:
			var b: String = link["place"]
			if not _graph.has(b):
				_graph[b] = []
			var found := false
			for back in _graph[b]:
				if str(back["place"]) == a:
					found = true
					break
			if not found:
				_graph[b].append({"place": a, "dist": float(link["dist"]), "hours": float(link["hours"])})


static func _distance(a: Dictionary, b: Dictionary) -> float:
	var pa: Array = a.get("position", [0, 0])
	var pb: Array = b.get("position", [0, 0])
	if pa.size() < 2 or pb.size() < 2:
		return INF
	return Vector2(float(pa[0]), float(pa[1])).distance_to(Vector2(float(pb[0]), float(pb[1])))


## The settled place nearest a world position, for "where did they see me do it".
func nearest_place(pos: Vector3, settled_only := true) -> String:
	var best := ""
	var best_d := INF
	for p in ContentDB.all("place"):
		if settled_only and not str(p.get("kind", "")) in SETTLED_KINDS:
			continue
		var pp: Array = p.get("position", [])
		if pp.size() < 2:
			continue
		var d := Vector2(float(pp[0]), float(pp[1])).distance_to(Vector2(pos.x, pos.z))
		if d < best_d:
			best_d = d
			best = str(p["id"])
	return best


func _fallback_place() -> String:
	var region := GameState.current_region_id
	if region != "":
		for p in ContentDB.all("place"):
			if str(p.get("region", "")) == region and str(p.get("kind", "")) in SETTLED_KINDS:
				return str(p["id"])
	return ""


# --- save ---------------------------------------------------------------------------------------

func to_save() -> Dictionary:
	var out: Dictionary = {}
	for place_id in pools:
		var pool: Dictionary = {}
		for rumour_id in pools[place_id]:
			var e: Dictionary = pools[place_id][rumour_id]
			pool[rumour_id] = {
				"heat": float(e["heat"]), "peak": float(e.get("peak", e["heat"])), "deed": str(e.get("deed", "")),
				"age": float(e.get("age", 0.0)), "spread": (e.get("spread", {}) as Dictionary).keys(),
				"day": int(e.get("day", 1)), "hour": int(e.get("hour", 0)),
			}
		out[place_id] = pool
	return {"pools": out}


func from_save(d: Dictionary) -> void:
	pools.clear()
	var saved: Dictionary = d.get("pools", {})
	for place_id in saved:
		var pool: Dictionary = {}
		for rumour_id in saved[place_id]:
			var e: Dictionary = saved[place_id][rumour_id]
			var spread: Dictionary = {}
			for p in e.get("spread", []):
				spread[str(p)] = true
			pool[str(rumour_id)] = {
				"heat": float(e.get("heat", 0.0)), "peak": float(e.get("peak", e.get("heat", 0.0))),
				"deed": str(e.get("deed", "")), "age": float(e.get("age", 0.0)),
				"spread": spread, "day": int(e.get("day", 1)), "hour": int(e.get("hour", 0)),
			}
		pools[str(place_id)] = pool
