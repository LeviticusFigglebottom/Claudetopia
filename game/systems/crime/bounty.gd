class_name Bounty
extends Node
## Bounty ledger and crime reporting (DESIGN §5.13). Totals are kept per key: the law
## faction of the region where the crime happened, or the region id itself where no law
## faction exists (Briarwold, Cinderlea); those lawless totals are ill-feeling that decays
## one point per game day and is never enforced by guards, only by gossip and barred doors.
## Witnesses report after a delay unless silenced or killed; knowledge of a bounty then
## spreads one settlement hop per hour to connected places in the same region.
## Save section "crime" (also carries the Ownership registry).

static var instance: Bounty

signal changed(key: String, total: int)
signal crime_reported(key: String, severity: int, place_id: String)

const SECTION := "crime"
const DECAY_PER_DAY := 1
const HISTORY_MAX := 50
const PLACE_SEARCH_M := 400.0

var totals: Dictionary = {}           # key -> int
var pending: Array[Dictionary] = []   # {witness, key, severity, due, place, kind}
var known: Dictionary = {}            # key -> {place_id: true}
var history: Array[Dictionary] = []   # {kind, key, severity, day, hour, witnessed}


## The bounty service, installing one under the scene root if the world has not added it.
static func ensure() -> Bounty:
	if instance != null and is_instance_valid(instance):
		return instance
	var found := Service.ensure(load("res://systems/crime/bounty.gd"), "Bounty") as Bounty
	# A copy of this service inside a world set `instance` as it entered the tree and cleared it as it
	# left; a copy under the root that entered earlier is then found here with `instance` still empty,
	# and everything that reads `instance` directly finds nothing. Point it at what was found.
	if found != null and (instance == null or not is_instance_valid(instance)):
		instance = found
	return found


func _enter_tree() -> void:
	instance = self
	add_to_group("crime")


func _exit_tree() -> void:
	if instance == self:
		instance = null
	if SaveSystem.participants.get(SECTION) == self:
		SaveSystem.unregister(SECTION)


func _ready() -> void:
	SaveSystem.register(SECTION, self)
	EventBus.hour_changed.connect(_on_hour_changed)
	EventBus.new_day.connect(_on_new_day)
	EventBus.entity_killed.connect(_on_entity_killed)


static func now_hours() -> float:
	return float(WorldClock.day) * 24.0 + WorldClock.time_hours


# --- contracted service API (group "crime") ------------------------------------------------

## Current bounty with a law faction (or lawless region key).
func bounty(faction_id: String) -> int:
	return total(faction_id)


## The same, under the name the dialogue context asks its `bounty` provider for (SocialContext
## `bounty()`). The service never had it, so every `bounty_min` condition and greeting read nought
## however wanted you were: the smith who will not serve a wanted man served everybody.
func bounty_for(faction_id: String) -> int:
	return total(faction_id)


## Other streams report a crime as a Dictionary: {kind, position (Vector3 or [x, y, z]),
## value?, victim?, target?, region_id?, place_id?, witnesses?, actor?}. Returns the
## recorded crime (see commit()).
func report_crime(crime: Dictionary) -> Dictionary:
	var kind := str(crime.get("kind", ""))
	if not kind in Crimes.KINDS:
		Log.warn("Crime", "report_crime: unknown kind '%s'" % kind)
		return {}
	var pos_v: Variant = crime.get("position", Vector3.ZERO)
	var pos := Vector3.ZERO
	if pos_v is Vector3:
		pos = pos_v
	elif typeof(pos_v) == TYPE_ARRAY and pos_v.size() >= 3:
		pos = Vector3(float(pos_v[0]), float(pos_v[1]), float(pos_v[2]))
	elif pos_v is Node3D:
		pos = (pos_v as Node3D).global_position
	var opts := crime.duplicate()
	opts.erase("kind")
	opts.erase("position")
	return commit(kind, pos, opts)


## Pays the fine for a faction's bounty from the player's marks and clears it. Ill-feeling in
## a lawless region cannot be paid off: there is nobody to pay, and it wears away by itself.
func pay_bounty(faction_id: String, payer: Object = null) -> bool:
	var t := total(faction_id)
	if t <= 0:
		return true
	var law: Dictionary = law_for_key(faction_id)["law"]
	if not Crimes.style_is_lawful(str(law.get("style", "none"))):
		return false
	var due := Crimes.fine(t, float(law.get("fine_multiplier", 1.0)))
	if due <= 0:
		return false
	if payer == null:
		payer = Peers.player()
	if not Purse.pay(payer, due):
		return false
	clear(faction_id)
	GameState.inc("fines_paid", due)
	return true


# --- keys and law ----------------------------------------------------------------------

## Bounty key for a region: its law faction, or the region id itself when lawless.
static func key_for_region(region_id: String) -> String:
	var law := WorldProbe.law_of_region(region_id)
	var fid: String = law["faction_id"]
	return fid if not fid.is_empty() else region_id


static func is_lawless_key(key: String) -> bool:
	return Ids.type_of(key) != "faction"


## {faction_id, law} for a key (faction law, or the lawless placeholder for region keys).
static func law_for_key(key: String) -> Dictionary:
	if is_lawless_key(key):
		return WorldProbe.law_of_region(key)
	var f := ContentDB.get_or_empty(key)
	var law: Dictionary = f.get("law", {}).duplicate()
	if law.is_empty():
		return {"faction_id": key, "law": {"style": "none", "arrest_threshold": 0, "fine_multiplier": 0.0, "jail_days_per_100": 0, "jail_place": ""}}
	if not law.has("style"):
		law["style"] = "fine_or_jail"
	return {"faction_id": key, "law": law}


# --- totals ------------------------------------------------------------------------------

func total(key: String) -> int:
	return int(totals.get(key, 0))


func total_for_region(region_id: String) -> int:
	return total(key_for_region(region_id))


func add(key: String, amount: int, place_id: String = "") -> int:
	if amount == 0 or key.is_empty():
		return total(key)
	var t := maxi(0, total(key) + amount)
	totals[key] = t
	if not place_id.is_empty():
		mark_known(key, place_id)
	EventBus.bounty_changed.emit(key, t)
	changed.emit(key, t)
	return t


func set_total(key: String, amount: int) -> void:
	totals[key] = maxi(0, amount)
	EventBus.bounty_changed.emit(key, totals[key])
	changed.emit(key, totals[key])


func clear(key: String) -> void:
	if not totals.has(key) and not known.has(key):
		return
	totals.erase(key)
	known.erase(key)
	var keep: Array[Dictionary] = []
	for p in pending:
		if p["key"] != key:
			keep.append(p)
	pending = keep
	EventBus.bounty_changed.emit(key, 0)
	changed.emit(key, 0)


func clear_all() -> void:
	for key in totals.keys():
		clear(key)


func is_wanted(key: String) -> bool:
	var law: Dictionary = law_for_key(key)["law"]
	return total(key) >= int(law.get("arrest_threshold", 0)) and total(key) > 0 and Crimes.style_is_lawful(str(law.get("style", "none")))


# --- knowledge (gossip) ------------------------------------------------------------------

func is_known_at(key: String, place_id: String) -> bool:
	return known.get(key, {}).has(place_id)


func mark_known(key: String, place_id: String) -> void:
	if place_id.is_empty():
		return
	if not known.has(key):
		known[key] = {}
	if known[key].has(place_id):
		return
	known[key][place_id] = true
	EventBus.rumour_spread.emit("bounty:" + key, place_id)


## One gossip hop for every known bounty. Returns the number of places that learned.
func spread_gossip() -> int:
	var learned := 0
	var places := ContentDB.all("place")
	for key in known.keys():
		if total(key) <= 0:
			continue
		var targets := {}
		for place_id in known[key].keys():
			for t in Crimes.gossip_targets(place_id, places, known[key]):
				targets[t] = true
		for t in targets:
			mark_known(key, t)
			learned += 1
	return learned


# --- committing crimes -------------------------------------------------------------------

## Records a crime by the player (or `opts.actor`) at `position`. opts: value, victim (npc id),
## target (object id), region_id, place_id, witnesses (explicit descriptors or nodes; default:
## every node in group "npc"). Emits EventBus.crime_committed and schedules witness reports.
func commit(kind: String, position: Vector3, opts: Dictionary = {}) -> Dictionary:
	var region_id := str(opts.get("region_id", ""))
	if region_id.is_empty():
		region_id = WorldProbe.region_id_at(position)
	var law := WorldProbe.law_of_region(region_id)
	var key := key_for_region(region_id)
	var crime := Crimes.make_crime(kind, position, region_id, law["faction_id"], opts)
	crime["key"] = key
	var place_id := str(opts.get("place_id", ""))
	if place_id.is_empty():
		var near := WorldProbe.nearest_place(position, PLACE_SEARCH_M)
		place_id = str(near.get("id", ""))
	crime["place"] = place_id
	var witnesses := evaluate_witnesses(crime, opts.get("witnesses", null), opts.get("extra_witnesses", []))
	var ids: Array = []
	for w in witnesses:
		ids.append(w["npc_id"])
		_schedule_report(w, crime, place_id)
	crime["witnesses"] = ids
	crime["witnessed"] = not ids.is_empty()
	history.append({"kind": kind, "key": key, "severity": crime["severity"], "day": crime["day"], "hour": crime["hour"], "witnessed": crime["witnessed"]})
	while history.size() > HISTORY_MAX:
		history.pop_front()
	GameState.inc("crimes")
	GameState.inc("crimes_" + kind)
	if crime["hollow_deed"]:
		GameState.inc("hollow_deeds")
	EventBus.crime_committed.emit(crime)
	if crime["witnessed"]:
		EventBus.notify.emit("You were seen.", "crime")
	process_pending()
	return crime


## Witness descriptors {npc_id, detection, line_of_sight, is_guard, reaction, place_id, alive}
## from explicit dicts or from NPC nodes exposing `detection` and `can_see_point(pos)`.
## `candidates` replaces the default scan of the "npc" group; `extra` is added to it, for a
## witness who saw it whatever their meter says (the victim of a fumbled pickpocket).
func evaluate_witnesses(crime: Dictionary, candidates: Variant = null, extra: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# Built element by element: `get_nodes_in_group` hands back an Array[Node], which would
	# silently refuse the Dictionary descriptors in `extra`.
	var list: Array = []
	if candidates == null:
		if is_inside_tree():
			for n in get_tree().get_nodes_in_group("npc"):
				list.append(n)
	else:
		for c in candidates:
			list.append(c)
	for e in extra:
		list.append(e)
	var seen := {}
	for c in list:
		var w := _describe_witness(c, crime)
		if w.is_empty():
			continue
		if not bool(w.get("alive", true)):
			continue
		if w["npc_id"] == crime.get("victim", "") and crime["kind"] == "murder":
			continue
		if seen.has(w["npc_id"]) and not str(w["npc_id"]).is_empty():
			continue
		if Crimes.is_witness(float(w["detection"]), bool(w["line_of_sight"])):
			seen[w["npc_id"]] = true
			out.append(w)
	return out


func _describe_witness(c: Variant, crime: Dictionary) -> Dictionary:
	if typeof(c) == TYPE_DICTIONARY:
		var d: Dictionary = c.duplicate()
		d["npc_id"] = str(d.get("npc_id", ""))
		d["detection"] = float(d.get("detection", 0.0))
		d["line_of_sight"] = bool(d.get("line_of_sight", true))
		d["is_guard"] = bool(d.get("is_guard", false))
		d["reaction"] = str(d.get("reaction", "report"))
		d["place_id"] = str(d.get("place_id", ""))
		return d
	if c is Node:
		var n: Node = c
		if not is_instance_valid(n) or not ("detection" in n):
			return {}
		var pos: Vector3 = crime.get("position", Vector3.ZERO)
		var los := true
		if n.has_method("can_see_point"):
			los = bool(n.call("can_see_point", pos))
		var reaction := "report"
		var pers: Variant = n.get("personality")
		if pers is Personality:
			reaction = (pers as Personality).crime_reaction()
		var alive := true
		if "alive" in n:
			alive = bool(n.get("alive"))
		return {
			"npc_id": str(n.get("npc_id")) if "npc_id" in n else n.name,
			"detection": float(n.get("detection")),
			"line_of_sight": los,
			"is_guard": n.is_in_group("guard"),
			"reaction": reaction,
			"place_id": str(n.get("place_id")) if "place_id" in n else "",
			"alive": alive,
		}
	return {}


func _schedule_report(w: Dictionary, crime: Dictionary, place_id: String) -> void:
	var delay := Crimes.report_delay_hours(str(w["reaction"]), bool(w["is_guard"]))
	if delay < 0.0:
		return
	var where := str(w.get("place_id", ""))
	if where.is_empty():
		where = place_id
	pending.append({"witness": w["npc_id"], "key": crime["key"], "severity": int(crime["severity"]), "due": now_hours() + delay, "place": where, "kind": crime["kind"]})


## Applies every report whose time has come. Returns how many landed.
func process_pending(now: float = -1.0) -> int:
	if now < 0.0:
		now = now_hours()
	var landed := 0
	var keep: Array[Dictionary] = []
	for p in pending:
		if float(p["due"]) <= now:
			add(p["key"], int(p["severity"]), str(p.get("place", "")))
			crime_reported.emit(p["key"], int(p["severity"]), str(p.get("place", "")))
			landed += 1
		else:
			keep.append(p)
	pending = keep
	return landed


## Removes pending reports by a witness (bribed, intimidated, or dead). Returns how many.
func silence_witness(npc_id: String) -> int:
	var keep: Array[Dictionary] = []
	var removed := 0
	for p in pending:
		if p["witness"] == npc_id:
			removed += 1
		else:
			keep.append(p)
	pending = keep
	return removed


func witness_died(npc_id: String) -> int:
	return silence_witness(npc_id)


func pending_count(key: String = "") -> int:
	if key.is_empty():
		return pending.size()
	var n := 0
	for p in pending:
		if p["key"] == key:
			n += 1
	return n


# --- time ----------------------------------------------------------------------------------

func _on_hour_changed(_hour: int) -> void:
	process_pending()
	spread_gossip()


func _on_new_day(_day: int) -> void:
	decay_lawless()


## Lawless (region-keyed) totals lose DECAY_PER_DAY per day; faction totals never decay.
func decay_lawless(days: int = 1) -> void:
	for key in totals.keys():
		if not is_lawless_key(key):
			continue
		var t := maxi(0, total(key) - DECAY_PER_DAY * days)
		if t == 0:
			clear(key)
		else:
			totals[key] = t
			EventBus.bounty_changed.emit(key, t)
			changed.emit(key, t)


func _on_entity_killed(victim: Node, _killer: Node, _enemy_id: String) -> void:
	if victim != null and is_instance_valid(victim) and "npc_id" in victim:
		witness_died(str(victim.get("npc_id")))


# --- save ----------------------------------------------------------------------------------

func to_save() -> Dictionary:
	var d := {
		"totals": totals.duplicate(true),
		"pending": pending.duplicate(true),
		"known": known.duplicate(true),
		"history": history.duplicate(true),
	}
	if Ownership.instance != null:
		d["ownership"] = Ownership.instance.to_dict()
	return d


func from_save(d: Dictionary) -> void:
	totals = {}
	for k in d.get("totals", {}):
		totals[k] = int(d["totals"][k])
	pending.assign(d.get("pending", []))
	known = d.get("known", {}).duplicate(true)
	history.assign(d.get("history", []))
	if d.has("ownership"):
		# The registry may not exist yet on a load; install it rather than drop what is saved.
		var reg := Ownership.ensure()
		if reg != null:
			reg.from_dict(d["ownership"])
		else:
			Log.warn("Crime", "no scene tree to restore the ownership registry into")
	for k in totals:
		changed.emit(k, totals[k])
