class_name RoadTables
extends RefCounted
## What may happen on a region's roads, read from content: `roadtable` defs (one a region, in
## content/packs/core/roadlife/<region>.json) and the `roadevent` defs their rows name
## (docs/WORLD_LIFE_ROADS.md has the format).
##
## A row is picked by weight among the rows that fit the moment: the hour (`when`, the words
## PoiEncounters.is_open knows), the ground beside the road (`biome`), the player's tier (`tier`
## [lo, hi], from their level), the road's features ahead when the row needs one (`sites`), and
## the row's own cooldown (`cooldown_h`, game hours since that event last began). Two tables for one
## region are merged, rows and caravans and sites, so a second pack can add to a region.

const TIER_LEVELS := [0, 4, 8, 13]   # level at which tiers 1, 2, 3, 4 begin

static var _by_region: Dictionary = {}
static var _built := false


static func reset() -> void:
	_by_region = {}
	_built = false


static func _build() -> void:
	if _built:
		return
	_built = true
	var defs := ContentDB.all("roadtable")
	defs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	for def in defs:
		var region := str(def.get("region", ""))
		var t: Dictionary = _by_region.get_or_add(region, {"rows": [], "caravans": [], "sites": [], "budget": {}})
		for key in ["rows", "caravans", "sites"]:
			for e in def.get(key, []):
				if e is Dictionary:
					var entry: Dictionary = (e as Dictionary).duplicate(true)
					entry["table"] = str(def["id"])
					(t[key] as Array).append(entry)
		(t["budget"] as Dictionary).merge(def.get("budget", {}), true)


static func regions() -> Array:
	_build()
	return _by_region.keys()


static func table(region: String) -> Dictionary:
	_build()
	return _by_region.get(region, {"rows": [], "caravans": [], "sites": [], "budget": {}})


## Every caravan every table names, across the regions: [{event, route: [from, to], ...}].
static func caravans() -> Array:
	_build()
	var out: Array = []
	for r in _by_region:
		for c in (_by_region[r] as Dictionary)["caravans"]:
			var e: Dictionary = (c as Dictionary).duplicate(true)
			e["region"] = r
			out.append(e)
	return out


static func sites() -> Array:
	_build()
	var out: Array = []
	for r in _by_region:
		out.append_array((_by_region[r] as Dictionary)["sites"])
	return out


static func tier_of_level(level: int) -> int:
	var tier := 1
	for i in TIER_LEVELS.size():
		if level >= int(TIER_LEVELS[i]):
			tier = i + 1
	return tier


## The rows of `region`'s table that fit `ctx`: {hour, biome, tier, sites: Array of kinds that
## are ahead, now_h (absolute game hours), cooldowns: {event id: hours it may come again}}.
static func rows_for(region: String, ctx: Dictionary) -> Array:
	var out: Array = []
	var hour := float(ctx.get("hour", 12.0))
	var biome := str(ctx.get("biome", "open"))
	var tier := int(ctx.get("tier", 1))
	var ahead: Array = ctx.get("sites", [])
	var now_h := float(ctx.get("now_h", 0.0))
	var cooldowns: Dictionary = ctx.get("cooldowns", {})
	var on_road := bool(ctx.get("on_road", true))
	for row in table(region)["rows"]:
		var r: Dictionary = row
		var ev := str(r.get("event", ""))
		var def := ContentDB.get_or_empty(ev)
		if def.is_empty():
			continue
		if not PoiEncounters.is_open(str(r.get("when", def.get("when", "always"))).replace("any", "always"), hour):
			continue
		var biomes: Array = r.get("biome", [])
		if not biomes.is_empty() and not biomes.has(biome):
			continue
		var tiers: Array = r.get("tier", [1, 99])
		if tiers.size() >= 2 and (tier < int(tiers[0]) or tier > int(tiers[1])):
			continue
		var needs: Array = r.get("sites", [])
		if not needs.is_empty():
			var any := false
			for k in needs:
				if ahead.has(k):
					any = true
			if not any:
				continue
		if not on_road and str(def.get("kind", "")) not in ["beasts", "wanderer"]:
			continue
		if now_h < float(cooldowns.get(ev, -INF)):
			continue
		if not conditions_hold(def):
			continue
		out.append(r)
	return out


## Whether an event's `if` all hold and none of its `unless` do (the dialogue's condition words).
static func conditions_hold(def: Dictionary) -> bool:
	var need: Variant = def.get("if", [])
	if need is Array and not (need as Array).is_empty():
		if Social.ctx == null or not Conditions.all_of(need, Social.ctx):
			return false
	var unless: Variant = def.get("unless", [])
	if unless is Array and not (unless as Array).is_empty() and Social.ctx != null and Conditions.all_of(unless, Social.ctx):
		return false
	var once_flag := "road_life/done/" + str(def.get("id", ""))
	if bool(def.get("once", false)) and GameState.has_flag(once_flag):
		return false
	return true


## One row by weight, or {} from none.
static func pick(rows: Array, rng: RandomNumberGenerator) -> Dictionary:
	var total := 0.0
	for r in rows:
		total += maxf(float((r as Dictionary).get("weight", 1.0)), 0.0)
	if total <= 0.0:
		return {}
	var roll := rng.randf() * total
	for r in rows:
		roll -= maxf(float((r as Dictionary).get("weight", 1.0)), 0.0)
		if roll <= 0.0:
			return r
	return rows[-1]


## What the problems with the tables and events are, for the content test.
static func problems() -> Array[String]:
	var out: Array[String] = []
	var kinds := RoadEvent.KINDS
	for def in ContentDB.all("roadevent"):
		var id := str(def["id"])
		if not kinds.has(str(def.get("kind", ""))):
			out.append("%s: kind '%s' is not one of %s" % [id, def.get("kind", ""), kinds])
		for c in def.get("cast", []):
			if not (c is Dictionary):
				out.append("%s: a cast entry is not an object" % id)
				continue
			var e: Dictionary = c
			if e.has("enemy") and not ContentDB.has(str(e["enemy"])):
				out.append("%s: cast names unknown enemy %s" % [id, e["enemy"]])
			if not e.has("enemy") and not e.has("folk"):
				out.append("%s: a cast entry needs `enemy` or `folk`" % id)
			var talk: Dictionary = e.get("talk", {})
			if not talk.is_empty() and not RoadEvent.TALKS.has(str(talk.get("do", "say"))):
				out.append("%s: talk.do '%s' is not one of %s" % [id, talk.get("do", ""), RoadEvent.TALKS])
		var m: Dictionary = def.get("merchant", {})
		if not m.is_empty() and not ContentDB.has(str(m.get("stock", ""))):
			out.append("%s: merchant stock %s is unknown" % [id, m.get("stock", "")])
	for region in regions():
		if not ContentDB.has(str(region)):
			out.append("roadtable for unknown region %s" % region)
		var t := table(str(region))
		for r in t["rows"]:
			if not ContentDB.has(str((r as Dictionary).get("event", ""))):
				out.append("%s: row names unknown event %s" % [r.get("table", ""), r.get("event", "")])
		for c in t["caravans"]:
			var cd := ContentDB.get_or_empty(str((c as Dictionary).get("event", "")))
			if str(cd.get("kind", "")) != "caravan":
				out.append("%s: caravan %s is not a caravan event" % [c.get("table", ""), c.get("event", "")])
			var route: Array = (c as Dictionary).get("route", [])
			if route.size() < 2:
				out.append("%s: caravan %s needs a route of two places" % [c.get("table", ""), c.get("event", "")])
			for p in route:
				if not ContentDB.has(str(p)):
					out.append("%s: caravan route names unknown place %s" % [c.get("table", ""), p])
	return out
