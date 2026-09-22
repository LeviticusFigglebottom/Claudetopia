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
	var o := WorldProbe.xz_of(origin)
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
		var distance := o.distance_to(WorldProbe.xz_of(target))
		out.append({
			"id": "delivery:%s:%s:%d" % [place_id, Ids.name_of(str(target["id"])), day],
			"kind": "delivery",
			"title": "Carry a parcel to %s" % str(target.get("name", "")),
			"from": place_id, "to": str(target["id"]),
			"pay": delivery_pay(distance), "item": DELIVERY_PARCEL, "distance_m": distance,
			"summary": "%s wants a parcel in %s hands before it is missed." % [str(origin.get("name", "")), str(target.get("name", ""))],
		})
	return out


## Radiant jobs for a board: the bounties, hunts and errands the quest system generates for
## this board, and simple deliveries when there is no quest system to ask. Quest rows are
## normalised to the delivery shape, so the board and its screen need not know which it got.
##
## This used to ask only `Peers.quests()` for a method called `generate`. `QuestLog` has no
## such method — it *holds* the `RadiantGenerator`, and `Social.board_jobs()` is what drives
## it, with the per-board daily cooldown that rides in the save. So every board in the game
## fell straight through to the delivery fallback, and the whole of DESIGN §5.10's radiant
## layer — six templates, bounties and hunts with region-appropriate quarry — never reached a
## notice post. The façade is asked now; the duck-typed hook is kept, and tried first, so a
## test can still put its own generator in front.
static func board_offers(place_id: String, count: int = BOARD_JOB_COUNT, day: int = -1) -> Array[Dictionary]:
	if day < 0:
		day = WorldClock.day
	var region := WorldProbe.region_of_place(place_id)
	var generated: Variant = null
	var q := Peers.quests()
	if q != null and q.has_method("generate"):
		generated = q.call("generate", region, count)
	if not _has_rows(generated):
		var social := Peers.social()
		if social != null and social.has_method("board_jobs"):
			generated = social.call("board_jobs", place_id, region, count)
	if _has_rows(generated):
		var out: Array[Dictionary] = []
		for g in generated:
			if typeof(g) == TYPE_DICTIONARY:
				out.append(normalise_offer(g))
			elif typeof(g) == TYPE_STRING:
				out.append(normalise_offer(ContentDB.get_or_empty(str(g))))
		return out
	return delivery_offers(place_id, count, day)


static func _has_rows(v: Variant) -> bool:
	return typeof(v) == TYPE_ARRAY and not (v as Array).is_empty()


## One board row out of a quest definition. A generated quest says what it pays in
## `rewards.marks`, which is where the board has to look: reading only `pay`/`reward_marks`
## would list every bounty in the country at nought marks.
static func normalise_offer(def: Dictionary) -> Dictionary:
	var e: Dictionary = def.duplicate()
	e["id"] = str(e.get("id", ""))
	e["kind"] = str(e.get("kind", "quest"))
	e["title"] = str(e.get("title", e.get("name", "Work")))
	var rewards: Variant = e.get("rewards", {})
	var from_rewards := 0
	if typeof(rewards) == TYPE_DICTIONARY:
		from_rewards = int((rewards as Dictionary).get("marks", 0))
	e["pay"] = int(e.get("pay", e.get("reward_marks", from_rewards)))
	if int(e["pay"]) <= 0:
		e["pay"] = from_rewards
	if not e.has("summary") and str(e.get("board_line", "")) != "":
		e["summary"] = str(e["board_line"])
	return e


## Completes a job: pays the marks, emits job_completed, counts it in GameState.
static func complete(job: Dictionary, worker: Object = null) -> int:
	var pay := int(job.get("pay", 0))
	if pay > 0:
		Purse.give(worker if worker != null else Peers.player(), pay)
	GameState.inc("jobs_done")
	EventBus.job_completed.emit(str(job.get("id", "")), pay)
	EventBus.notify.emit("Work done: %d marks." % pay, "job")
	return pay
