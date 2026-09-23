class_name Schedules
## Pure schedule logic (DESIGN §5.12). An NPC def carries
##   schedule: [{days, hour, place, activity, spot}]   (CONTRACTS §7)
## days: "all" | "workdays" (or "weekdays") | a day name | an int 0..6 (0 = Kindleday) |
##       "1-4" | "0,2,4" |
##       an array of any of those. hour: float 0..24. place: a place id or "home".
## activity: sleep | work | eat | idle | pray | socialise | patrol | shop (travel is derived).
## Rules: the current entry is the latest one at or before the hour (wrapping to earlier days);
## travel to the next entry begins TRAVEL_LEAD_HOURS before it; rain sends outdoor `idle` home.
## A def may also carry `holds: [{when: [conditions], place, activity, spot}]`, which come before
## the timetable whenever their conditions hold (see `held_entry`).

const ACTIVITIES: Array[String] = ["sleep", "work", "eat", "idle", "pray", "socialise", "patrol", "shop"]
const TRAVEL_LEAD_HOURS := 20.0 / 60.0
const RAINY: Array[String] = ["rain", "drizzle", "storm", "squall"]
const DAY_NAMES: Array[String] = ["kindleday", "tallowday", "merrowday", "thornday", "skerrday", "hushday", "tollday"]


static func weekday_of(day: int) -> int:
	return posmod(day - 1, DAY_NAMES.size())


static func is_rainy(weather: String) -> bool:
	return weather.to_lower() in RAINY


static func applies_on(days: Variant, weekday: int) -> bool:
	match typeof(days):
		TYPE_NIL:
			return true
		TYPE_INT, TYPE_FLOAT:
			return int(days) == weekday
		TYPE_STRING:
			return _string_applies(str(days), weekday)
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			if days.is_empty():
				return true
			for d in days:
				if applies_on(d, weekday):
					return true
			return false
	return false


static func _string_applies(spec: String, weekday: int) -> bool:
	var s := spec.strip_edges().to_lower()
	if s in ["", "all", "any", "daily", "every"]:
		return true
	# "weekdays" is what seventy-eight entries in the pack actually say, and it used to fall
	# through every branch below and return false — so a large part of the roster's working
	# day simply never applied and nobody noticed, because the fallback is a plausible
	# schedule rather than an error.
	if s == "workdays" or s == "weekdays":
		return weekday <= 5
	if s == "restday":
		return weekday == 6
	var idx := DAY_NAMES.find(s)
	if idx >= 0:
		return idx == weekday
	if s.is_valid_int():
		return int(s) == weekday
	if s.contains(","):
		for part in s.split(",", false):
			if _string_applies(part, weekday):
				return true
		return false
	if s.contains("-"):
		var ends := s.split("-", false)
		if ends.size() == 2:
			var a := _day_index(ends[0])
			var b := _day_index(ends[1])
			if a >= 0 and b >= 0:
				if a <= b:
					return weekday >= a and weekday <= b
				return weekday >= a or weekday <= b
	return false


static func _day_index(s: String) -> int:
	s = s.strip_edges().to_lower()
	if s.is_valid_int():
		return int(s)
	return DAY_NAMES.find(s)


## Entries applying on `weekday`, sorted by hour (stable).
static func entries_for_day(schedule: Array, weekday: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in schedule:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if applies_on(e.get("days", "all"), weekday):
			out.append(e)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("hour", 0)) < float(b.get("hour", 0)))
	return out


## Is this hour spent under a roof? Three ways an entry can say so, in the order an author
## would reach for them: the explicit flag, a spot named `in:<something>`, or the spot being
## "home" (which is also where the rain override sends people). Sleeping is always indoors.
static func is_indoors(entry: Dictionary) -> bool:
	if bool(entry.get("indoors", false)):
		return true
	var spot := str(entry.get("spot", ""))
	if spot.begins_with("in:") or spot == "home":
		return true
	return str(entry.get("activity", "")) == "sleep"


## Normalises an entry: "home" resolves to home_place, defaults filled, rain override applied.
static func resolve(entry: Dictionary, weather: String, home_place: String) -> Dictionary:
	var place := str(entry.get("place", "home"))
	if place.is_empty() or place == "home":
		place = home_place
	var activity := str(entry.get("activity", "idle"))
	var spot := str(entry.get("spot", ""))
	var out := {"place": place, "activity": activity, "spot": spot, "weather_override": false,
			"indoors": is_indoors(entry)}
	if entry.has("clip"):
		out["clip"] = str(entry["clip"])
	if is_rainy(weather) and activity == "idle" and not is_indoors(entry):
		out["place"] = home_place if not home_place.is_empty() else place
		out["spot"] = "home"
		out["weather_override"] = true
		out["indoors"] = true
	return out


## The NPC's effective schedule state at `weekday`/`hour`:
## {place, activity, spot, hour (entry start, may be negative for yesterday), travelling,
##  weather_override, next{place, activity, spot, starts_in_hours}, after_travel}.
static func entry_at(schedule: Array, weekday: int, hour: float, weather: String = "clear", home_place: String = "") -> Dictionary:
	var today := entries_for_day(schedule, weekday)
	var current: Dictionary = {}
	var current_start := 0.0
	for e in today:
		if float(e.get("hour", 0)) <= hour:
			current = e
			current_start = float(e.get("hour", 0))
	if current.is_empty():
		for back in range(1, DAY_NAMES.size() + 1):
			var list := entries_for_day(schedule, posmod(weekday - back, DAY_NAMES.size()))
			if not list.is_empty():
				current = list.back()
				current_start = float(current.get("hour", 0)) - 24.0 * back
				break
	if current.is_empty():
		return {"place": home_place, "activity": "idle", "spot": "home", "hour": 0.0, "travelling": false, "weather_override": false, "indoors": true, "next": {}, "after_travel": ""}
	var next: Dictionary = {}
	var next_start := INF
	for e in today:
		if float(e.get("hour", 0)) > hour:
			next = e
			next_start = float(e.get("hour", 0))
			break
	if next.is_empty():
		for ahead in range(1, DAY_NAMES.size() + 1):
			var list := entries_for_day(schedule, posmod(weekday + ahead, DAY_NAMES.size()))
			if not list.is_empty():
				next = list[0]
				next_start = float(next.get("hour", 0)) + 24.0 * ahead
				break
	var cur := resolve(current, weather, home_place)
	var out := {
		"place": cur["place"], "activity": cur["activity"], "spot": cur["spot"], "hour": current_start,
		"travelling": false, "weather_override": cur["weather_override"],
		"indoors": bool(cur.get("indoors", false)), "next": {}, "after_travel": "",
	}
	if cur.has("clip"):
		out["clip"] = cur["clip"]
	if not next.is_empty():
		var nxt := resolve(next, weather, home_place)
		out["next"] = {"place": nxt["place"], "activity": nxt["activity"], "spot": nxt["spot"], "starts_in_hours": next_start - hour}
		if next_start - hour <= TRAVEL_LEAD_HOURS and nxt["place"] != cur["place"]:
			out["travelling"] = true
			out["place"] = nxt["place"]
			out["spot"] = nxt["spot"]
			out["activity"] = "travel"
			out["after_travel"] = nxt["activity"]
			out["weather_override"] = nxt["weather_override"]
			if nxt.has("clip"):
				out["clip"] = nxt["clip"]
	return out


## Convenience: state for a whole npc def at the clock's current day/time. A hold that applies
## (`held_entry`) wins over the timetable; `ctx` defaults to the game's own context.
static func entry_for_def(def: Dictionary, day: int, hour: float, weather: String = "clear",
		ctx: SocialContext = null) -> Dictionary:
	var held := held_entry(def, ctx if ctx != null else live_context())
	if not held.is_empty():
		return held
	return entry_at(def.get("schedule", []), weekday_of(day), hour, weather, str(def.get("home_place", "")))


## Where the story is keeping somebody, if it is. A def's `holds` are checked in order, and the
## first whose `when` holds -- the dialogue's own condition vocabulary (`Conditions`), read through
## the live SocialContext -- says where they are for as long as it holds, whatever the hour and
## the weather. That is how the story keeps a person where it needs them without writing them a
## second timetable: Wren Tallow stands at the Stair Head from a new game until the Foundling has
## spoken to her and walked north (DESIGN §5.1a), and then goes back to her own days.
static func held_entry(def: Dictionary, ctx: SocialContext) -> Dictionary:
	var holds: Variant = def.get("holds", [])
	if ctx == null or typeof(holds) != TYPE_ARRAY:
		return {}
	for h_v in holds:
		if typeof(h_v) != TYPE_DICTIONARY:
			continue
		var h: Dictionary = h_v
		var when: Variant = h.get("when", [])
		# a hold that never says when would hold for ever: that is a content problem, not a rule
		if typeof(when) != TYPE_ARRAY or (when as Array).is_empty():
			continue
		if not Conditions.all_of(when, ctx):
			continue
		var cur := resolve(h, "clear", str(def.get("home_place", "")))
		var out := {"place": cur["place"], "activity": cur["activity"], "spot": cur["spot"], "hour": 0.0,
				"travelling": false, "weather_override": false, "indoors": bool(cur.get("indoors", false)),
				"next": {}, "after_travel": "", "held": true}
		if cur.has("clip"):
			out["clip"] = cur["clip"]
		return out
	return {}


## The game's own SocialContext (the `Social` autoload's), or null where there is none.
static func live_context() -> SocialContext:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var social := tree.root.get_node_or_null("Social")
	if social == null:
		return null
	return social.get("ctx") as SocialContext


## Animation intent for an activity (CONTRACTS §3 life clips). `work_clip` comes from the
## entry's `clip`, else from the def's `work_clip`, else Work_Hammer.
static func intent_for(activity: String, entry: Dictionary = {}, def: Dictionary = {}) -> String:
	match activity:
		"sleep":
			return "Sleep_Idle"
		"eat":
			return "Eat"
		"work":
			if not str(entry.get("clip", "")).is_empty():
				return str(entry["clip"])
			if not str(def.get("work_clip", "")).is_empty():
				return str(def["work_clip"])
			return "Work_Hammer"
		"pray":
			return "Sit_Idle"
		"socialise":
			return "Talk_1"
		"travel", "patrol":
			return "Walk"
		"shop", "idle":
			return "Idle"
	return "Idle"


## Validation used by tests and content tools: returns problems for a schedule list.
static func problems(schedule: Array, owner: String = "?") -> Array[String]:
	var out: Array[String] = []
	for i in schedule.size():
		var e: Variant = schedule[i]
		if typeof(e) != TYPE_DICTIONARY:
			out.append("%s: schedule[%d] is not an object" % [owner, i])
			continue
		var h := float(e.get("hour", -1))
		if h < 0.0 or h >= 24.0:
			out.append("%s: schedule[%d] hour %s out of range" % [owner, i, str(e.get("hour"))])
		var a := str(e.get("activity", ""))
		if not a in ACTIVITIES:
			out.append("%s: schedule[%d] unknown activity '%s'" % [owner, i, a])
	return out


## Validation for a def's `holds`: each needs a place, a known activity and a non-empty `when`.
static func hold_problems(def: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var owner := str(def.get("id", "?"))
	var holds: Variant = def.get("holds", [])
	if typeof(holds) != TYPE_ARRAY:
		out.append("%s: holds is not a list" % owner)
		return out
	for i in (holds as Array).size():
		var h_v: Variant = holds[i]
		if typeof(h_v) != TYPE_DICTIONARY:
			out.append("%s: holds[%d] is not an object" % [owner, i])
			continue
		var h: Dictionary = h_v
		var when: Variant = h.get("when", [])
		if typeof(when) != TYPE_ARRAY or (when as Array).is_empty():
			out.append("%s: holds[%d] never says when, so it would hold for ever" % [owner, i])
		if str(h.get("place", "")).is_empty():
			out.append("%s: holds[%d] names no place" % [owner, i])
		var a := str(h.get("activity", "idle"))
		if not a in ACTIVITIES:
			out.append("%s: holds[%d] unknown activity '%s'" % [owner, i, a])
	return out
