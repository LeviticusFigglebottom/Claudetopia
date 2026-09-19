class_name Crimes
## Pure crime rules (DESIGN §5.13): severity table, witness rule, report delays, fines, jail
## terms and confrontation options per law style. No engine state; Bounty applies these.

const KINDS: Array[String] = ["trespass", "pickpocket", "theft", "assault", "murder", "lockpicking"]
const SEVERITY := {"trespass": 5, "pickpocket": 25, "assault": 40, "murder": 100, "lockpicking": 15}
const THEFT_MIN := 10
const THEFT_VALUE_FRACTION := 0.5
## Suggested Hearth/Hollow change per crime; the Morality system applies it from the
## crime_committed payload (field `morality_delta`). Murder is a Hollow deed.
const MORALITY := {"trespass": 0, "lockpicking": -1, "theft": -3, "pickpocket": -3, "assault": -8, "murder": -20}
const WITNESS_DETECTION := 0.6
const REPORT_DELAY_HOURS := 0.5
const GOSSIP_RANGE_M := 2500.0
const SETTLEMENT_KINDS: Array[String] = ["town", "city", "village", "hamlet", "camp", "fort", "lodge"]
const STYLES: Array[String] = ["fine_or_jail", "blood_price", "exile", "none"]


static func severity(kind: String, value: int = 0) -> int:
	if kind == "theft":
		return maxi(THEFT_MIN, ceili(float(value) * THEFT_VALUE_FRACTION))
	return int(SEVERITY.get(kind, 0))


static func morality_delta(kind: String) -> int:
	return int(MORALITY.get(kind, 0))


static func is_hollow_deed(kind: String) -> bool:
	return kind == "murder"


## An NPC witnesses a crime when its detection meter is at least 0.6 and it has line of sight.
static func is_witness(detection: float, line_of_sight: bool) -> bool:
	return line_of_sight and detection >= WITNESS_DETECTION


## Game hours until a witness reaches the law. Guards report at once; the timid flee first;
## the confrontational shout for the watch; a negative value means no report at all.
static func report_delay_hours(reaction: String, is_guard: bool = false) -> float:
	if is_guard:
		return 0.0
	match reaction:
		"ignore":
			return -1.0
		"flee":
			return REPORT_DELAY_HOURS * 2.0
		"confront":
			return REPORT_DELAY_HOURS * 0.5
	return REPORT_DELAY_HOURS


static func make_crime(kind: String, position: Vector3, region_id: String, law_faction: String, opts: Dictionary = {}) -> Dictionary:
	var value := int(opts.get("value", 0))
	return {
		"kind": kind,
		"severity": severity(kind, value),
		"value": value,
		"position": position,
		"region": region_id,
		"law_faction": law_faction,
		"victim": str(opts.get("victim", "")),
		"target": str(opts.get("target", "")),
		"actor": str(opts.get("actor", "player")),
		"morality_delta": morality_delta(kind),
		"hollow_deed": is_hollow_deed(kind),
		"day": WorldClock.day,
		"hour": WorldClock.time_hours,
		"witnessed": false,
		"witnesses": [],
	}


static func fine(bounty: int, fine_multiplier: float) -> int:
	return maxi(0, ceili(float(bounty) * fine_multiplier))


## Days served: bounty/100 × jail_days_per_100, at least one day when jail applies at all.
static func jail_days(bounty: int, jail_days_per_100: float) -> int:
	if jail_days_per_100 <= 0.0 or bounty <= 0:
		return 0
	return maxi(1, ceili(float(bounty) / 100.0 * jail_days_per_100))


## Confrontation choices for a guard of a faction with `law` and the player's `bounty`.
## Each: {id, label, cost?, days?}. Styles: fine_or_jail (pay | jail | resist),
## blood_price (pay | resist), exile (exile | resist), none (no confrontation).
static func confront_options(style: String, bounty: int, law: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var mult := float(law.get("fine_multiplier", 1.0))
	match style:
		"fine_or_jail":
			var f := fine(bounty, mult)
			out.append({"id": "pay", "label": "Pay the fine (%d marks)" % f, "cost": f})
			var days := jail_days(bounty, float(law.get("jail_days_per_100", 1)))
			out.append({"id": "jail", "label": "Go quietly (%d day%s)" % [days, "" if days == 1 else "s"], "days": days})
			out.append({"id": "resist", "label": "Resist arrest"})
		"blood_price":
			var bp := fine(bounty, mult)
			out.append({"id": "pay", "label": "Pay the blood-price (%d marks)" % bp, "cost": bp})
			out.append({"id": "resist", "label": "Refuse the price"})
		"exile":
			out.append({"id": "exile", "label": "Accept exile from the boardwalks"})
			out.append({"id": "resist", "label": "Refuse to leave"})
	return out


static func style_is_lawful(style: String) -> bool:
	return style != "none" and not style.is_empty()


## Settlement places in the same region within `range_m` of `place_id` that are not yet in
## `known` (a Dictionary place_id -> true). One gossip hop.
static func gossip_targets(place_id: String, places: Array, known: Dictionary, range_m: float = GOSSIP_RANGE_M) -> Array[String]:
	var out: Array[String] = []
	var origin: Dictionary = {}
	for p in places:
		if str(p.get("id", "")) == place_id:
			origin = p
			break
	if origin.is_empty():
		return out
	var o := WorldProbe.xz_of(origin)
	for p in places:
		var pid := str(p.get("id", ""))
		if pid == place_id or known.has(pid):
			continue
		if str(p.get("region", "")) != str(origin.get("region", "")):
			continue
		if not str(p.get("kind", "")) in SETTLEMENT_KINDS:
			continue
		if o.distance_to(WorldProbe.xz_of(p)) <= range_m:
			out.append(pid)
	out.sort()
	return out
