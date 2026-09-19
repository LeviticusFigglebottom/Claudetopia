class_name Jobs
## Work for marks (DESIGN §5.14). Two kinds:
##
## * **Board jobs** — a job board asks the quest system for radiant work
##   (`generate(region_id, count)`); with no quest system it offers its own simple deliveries
##   between settlements of the region, which still pay and still emit job_completed.
## * **Station jobs** — chop, smith, brew, fish and dig at a workbench: a timed interaction
##   paying marks and skill XP, with a cooldown per station so a player cannot stand at a
##   chopping block for a living.
##
## Both are pure enough to test: `offers()` builds the list, `resolve()` computes pay.

## Station work. `yield` names an item the worker keeps as well as the wage; a station whose
## yield item is not in the loaded packs simply pays marks.
const STATIONS := {
	"chop": {"label": "Chop wood", "skill": "athletics", "seconds": 6.0, "pay": [4, 8], "xp": 8.0, "clip": "Work_Chop", "cooldown_hours": 4.0, "yield": "core:item/oak_plank"},
	"smith": {"label": "Work the bellows", "skill": "smithing", "seconds": 8.0, "pay": [6, 12], "xp": 12.0, "clip": "Work_Hammer", "cooldown_hours": 4.0, "yield": "core:item/iron_ingot"},
	"brew": {"label": "Stir the mash", "skill": "alchemy", "seconds": 7.0, "pay": [5, 10], "xp": 10.0, "clip": "Work_Stir", "cooldown_hours": 4.0, "yield": "core:item/cider"},
	"fish": {"label": "Haul the eel traps", "skill": "athletics", "seconds": 7.0, "pay": [4, 9], "xp": 8.0, "clip": "Work_Dig", "cooldown_hours": 4.0, "yield": "core:item/eel_liver"},
	"dig": {"label": "Cut chalk", "skill": "athletics", "seconds": 8.0, "pay": [3, 7], "xp": 8.0, "clip": "Work_Dig", "cooldown_hours": 4.0, "yield": "core:item/chalk"},
}
const DELIVERY_PAY_PER_KM := 14
const DELIVERY_MIN_PAY := 20
const DELIVERY_PARCEL := "core:item/econ_parcel"
const BOARD_JOB_COUNT := 3


static func station_kinds() -> Array[String]:
	var out: Array[String] = []
	for k in STATIONS:
		out.append(k)
	out.sort()
	return out


## Pay for one shift at a station: the range, scaled by how skilled the worker is.
static func station_pay(kind: String, skill_level: int, rng: RandomNumberGenerator) -> int:
	var s: Dictionary = STATIONS.get(kind, {})
	if s.is_empty():
		return 0
	var lo := int(s["pay"][0])
	var hi := int(s["pay"][1])
	var base := rng.randi_range(lo, hi)
	return maxi(1, roundi(float(base) * (1.0 + clampf(float(skill_level), 0.0, 100.0) / 200.0)))


static func station_xp(kind: String) -> float:
	return float(STATIONS.get(kind, {}).get("xp", 0.0))


static func station_skill(kind: String) -> String:
	return str(STATIONS.get(kind, {}).get("skill", "athletics"))


static func station_seconds(kind: String) -> float:
	return float(STATIONS.get(kind, {}).get("seconds", 5.0))


static func station_clip(kind: String) -> String:
	return str(STATIONS.get(kind, {}).get("clip", "Work_Hammer"))


## Pay for carrying a parcel `distance_m` metres.
static func delivery_pay(distance_m: float) -> int:
	return maxi(DELIVERY_MIN_PAY, roundi(distance_m / 1000.0 * DELIVERY_PAY_PER_KM))


## Fallback radiant work: deliveries from `place_id` to other settlements of its region.
## Deterministic for a given board, day and place. Returns [{id, kind, title, from, to, pay,
## item, distance_m, summary}].
static func delivery_offers(place_id: String, count: int, day: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var origin := ContentDB.get_or_empty(place_id)
	if origin.is_empty():
		return out
	var oxz: Array = origin.get("position", [0, 0])
	var o := Vector2(float(oxz[0]), float(oxz[1]))
	var candidates: Array[Dictionary] = []
	for p in ContentDB.all("place"):
		if str(p["id"]) == place_id:
			continue
		if str(p.get("region", "")) != str(origin.get("region", "")):
			continue
		if not str(p.get("kind", "")) in Crimes.SETTLEMENT_KINDS:
			continue
		candidates.append(p)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	if candidates.is_empty():
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%d" % [place_id, day])
	for i in mini(count, candidates.size()):
		var target: Dictionary = candidates[(rng.randi() + i) % candidates.size()]
		var already := false
		for existing in out:
			if existing["to"] == target["id"]:
				already = true
		if already:
			continue
		var txz: Array = target.get("position", [0, 0])
		var distance := o.distance_to(Vector2(float(txz[0]), float(txz[1])))
		out.append({
			"id": "delivery:%s:%s:%d" % [place_id, Ids.name_of(str(target["id"])), day],
			"kind": "delivery",
			"title": "Carry a parcel to %s" % str(target.get("name", "")),
			"from": place_id, "to": str(target["id"]),
			"pay": delivery_pay(distance), "item": DELIVERY_PARCEL, "distance_m": distance,
			"summary": "%s wants a parcel in %s hands before it is missed." % [str(origin.get("name", "")), str(target.get("name", ""))],
		})
	return out


## Radiant jobs for a board: the quest system's `generate(region_id, count)` when one is
## registered, else deliveries. Quest entries are normalised to the same shape.
static func board_offers(place_id: String, count: int = BOARD_JOB_COUNT, day: int = -1) -> Array[Dictionary]:
	if day < 0:
		day = WorldClock.day
	var region := WorldProbe.region_of_place(place_id)
	var q := Peers.quests()
	if q != null and q.has_method("generate"):
		var generated: Variant = q.call("generate", region, count)
		if typeof(generated) == TYPE_ARRAY and not generated.is_empty():
			var out: Array[Dictionary] = []
			for g in generated:
				if typeof(g) == TYPE_DICTIONARY:
					var e: Dictionary = g.duplicate()
					e["kind"] = str(e.get("kind", "quest"))
					e["id"] = str(e.get("id", ""))
					e["title"] = str(e.get("title", e.get("name", "Work")))
					e["pay"] = int(e.get("pay", e.get("reward_marks", 0)))
					out.append(e)
				elif typeof(g) == TYPE_STRING:
					var def := ContentDB.get_or_empty(str(g))
					out.append({"id": str(g), "kind": "quest", "title": str(def.get("name", "Work")), "pay": int(def.get("rewards", {}).get("marks", 0))})
			return out
	return delivery_offers(place_id, count, day)


## Completes a job: pays the marks, emits job_completed, counts it in GameState.
static func complete(job: Dictionary, worker: Object = null) -> int:
	var pay := int(job.get("pay", 0))
	if pay > 0:
		Purse.give(worker if worker != null else Peers.player(), pay)
	GameState.inc("jobs_done")
	EventBus.job_completed.emit(str(job.get("id", "")), pay)
	EventBus.notify.emit("Work done: %d marks." % pay, "job")
	return pay
