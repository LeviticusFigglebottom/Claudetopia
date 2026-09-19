extends Node
## Factions: reputation (-100..100) per faction, ranks from the faction def's rank_thresholds,
## membership with rival penalties, and the law lookup that tells the crime system who polices a
## region. Save section "factions". Joins the group "factions" so other streams can find it.
##
## Data: content type "faction" (game/content/packs/core/factions/factions.json):
##   {id, name, kind, joinable, rival, ranks[], rank_thresholds[], law{region, jail_place,
##    arrest_threshold, fine_multiplier, jail_days_per_100, style}}
##
## Emits: EventBus.faction_reputation_changed(faction_id, new_value, delta)
##        EventBus.faction_rank_changed(faction_id, new_rank)

const MIN_REP := -100
const MAX_REP := 100
## Joining a faction costs this much standing with its rival, and expels you from the rival.
const RIVAL_JOIN_PENALTY := 25
## While a member, positive reputation with your faction bleeds this share away from its rival.
const RIVAL_BLEED := 0.5

var _rep: Dictionary = {}          # faction_id -> int
var _members: Dictionary = {}      # faction_id -> true
var _expelled: Dictionary = {}     # faction_id -> reason (barred from rejoining until cleared)


func _ready() -> void:
	add_to_group("factions")
	SaveSystem.register("factions", self)


# --- reputation ------------------------------------------------------------------------------

func reputation(faction_id: String) -> int:
	return int(_rep.get(faction_id, 0))


## Adds (or subtracts) reputation, clamped to -100..100, and applies the rival bleed for gains
## made as a member. Returns the new value.
func add_reputation(faction_id: String, delta: int, reason: String = "") -> int:
	if not _known(faction_id, "add_reputation"):
		return 0
	var before := reputation(faction_id)
	var after: int = clampi(before + delta, MIN_REP, MAX_REP)
	if after == before:
		return before
	_set_rep(faction_id, after, after - before)
	if delta > 0 and is_member(faction_id):
		var rival := rival_of(faction_id)
		if rival != "":
			var bleed := int(round(float(delta) * RIVAL_BLEED))
			if bleed > 0:
				var r_before := reputation(rival)
				var r_after: int = clampi(r_before - bleed, MIN_REP, MAX_REP)
				if r_after != r_before:
					_set_rep(rival, r_after, r_after - r_before)
	return after


func set_reputation(faction_id: String, value: int) -> void:
	if not _known(faction_id, "set_reputation"):
		return
	var before := reputation(faction_id)
	var after: int = clampi(value, MIN_REP, MAX_REP)
	if after != before:
		_set_rep(faction_id, after, after - before)


func _set_rep(faction_id: String, value: int, delta: int) -> void:
	var rank_before := rank(faction_id)
	_rep[faction_id] = value
	EventBus.faction_reputation_changed.emit(faction_id, value, delta)
	var rank_after := rank(faction_id)
	if rank_after != rank_before:
		EventBus.faction_rank_changed.emit(faction_id, rank_after)


# --- ranks ------------------------------------------------------------------------------------

## Rank index into the faction's ranks[], or -1 when not a member or the faction has no ranks.
func rank(faction_id: String) -> int:
	if not is_member(faction_id):
		return -1
	var def := ContentDB.get_or_empty(faction_id)
	var thresholds: Array = def.get("rank_thresholds", [])
	if thresholds.is_empty():
		return -1
	var rep := reputation(faction_id)
	var out := -1
	for i in thresholds.size():
		if rep >= int(thresholds[i]):
			out = i
	return out


func rank_name(faction_id: String) -> String:
	var i := rank(faction_id)
	if i < 0:
		return ""
	var ranks: Array = ContentDB.get_or_empty(faction_id).get("ranks", [])
	return str(ranks[i]) if i < ranks.size() else ""


## Reputation needed for the next rank, or -1 at the top (or outside the faction).
func next_rank_at(faction_id: String) -> int:
	var thresholds: Array = ContentDB.get_or_empty(faction_id).get("rank_thresholds", [])
	var i := rank(faction_id)
	if thresholds.is_empty() or i + 1 >= thresholds.size():
		return -1
	return int(thresholds[i + 1])


# --- membership --------------------------------------------------------------------------------

func is_member(faction_id: String) -> bool:
	return _members.has(faction_id)


func members() -> Array[String]:
	var out: Array[String] = []
	for id in _members:
		out.append(id)
	out.sort()
	return out


func rival_of(faction_id: String) -> String:
	return str(ContentDB.get_or_empty(faction_id).get("rival", ""))


func is_joinable(faction_id: String) -> bool:
	return bool(ContentDB.get_or_empty(faction_id).get("joinable", false))


func was_expelled(faction_id: String) -> bool:
	return _expelled.has(faction_id)


## Joins a joinable faction. Fails (returns false) for unknown, unjoinable or previously expelled
## factions. Joining expels you from the rival and costs RIVAL_JOIN_PENALTY standing with it.
func join(faction_id: String) -> bool:
	if not _known(faction_id, "join"):
		return false
	if not is_joinable(faction_id):
		Log.warn("Factions", "%s is not joinable" % faction_id)
		return false
	if was_expelled(faction_id):
		Log.info("Factions", "%s refuses a rejoin: %s" % [faction_id, _expelled[faction_id]])
		return false
	if is_member(faction_id):
		return true
	_members[faction_id] = true
	var rival := rival_of(faction_id)
	if rival != "":
		if is_member(rival):
			expel(rival, "joined %s" % faction_id)
		add_reputation(rival, -RIVAL_JOIN_PENALTY, "rival joined %s" % faction_id)
	EventBus.faction_rank_changed.emit(faction_id, rank(faction_id))
	Log.info("Factions", "joined %s (rank %s)" % [faction_id, rank_name(faction_id)])
	return true


## Removes membership and bars rejoining until clear_expulsion(). Keeps reputation as it is;
## the caller decides whether a crime also costs standing.
func expel(faction_id: String, reason: String = "") -> void:
	if not is_member(faction_id):
		return
	_members.erase(faction_id)
	_expelled[faction_id] = reason
	EventBus.faction_rank_changed.emit(faction_id, -1)
	Log.info("Factions", "expelled from %s (%s)" % [faction_id, reason])


func clear_expulsion(faction_id: String) -> void:
	_expelled.erase(faction_id)


# --- law ------------------------------------------------------------------------------------

## The faction that polices a region, or "" where there is no law (the Briarwold has bows).
func law_faction_for_region(region_id: String) -> String:
	for def in ContentDB.all("faction"):
		var law: Variant = def.get("law")
		if typeof(law) == TYPE_DICTIONARY and str(law.get("region", "")) == region_id:
			return str(def["id"])
	var region := ContentDB.get_or_empty(region_id)
	return str(region.get("law_faction", ""))


## The law block for a region: {faction, region, jail_place, arrest_threshold, fine_multiplier,
## jail_days_per_100, style}. Empty when the region is lawless.
func law_for_region(region_id: String) -> Dictionary:
	var fid := law_faction_for_region(region_id)
	if fid == "":
		return {}
	var law: Variant = ContentDB.get_or_empty(fid).get("law")
	if typeof(law) != TYPE_DICTIONARY:
		return {}
	var out: Dictionary = (law as Dictionary).duplicate(true)
	out["faction"] = fid
	return out


func is_lawless(region_id: String) -> bool:
	return law_for_region(region_id).is_empty()


# --- standing summary for other streams ---------------------------------------------------------

## {faction_id: {reputation, rank, rank_name, member}} for the journal and UI.
func summary() -> Dictionary:
	var out: Dictionary = {}
	for def in ContentDB.all("faction"):
		var id: String = def["id"]
		out[id] = {
			"name": str(def.get("name", id)), "reputation": reputation(id), "rank": rank(id),
			"rank_name": rank_name(id), "member": is_member(id),
		}
	return out


func reset_for_new_game() -> void:
	_rep.clear()
	_members.clear()
	_expelled.clear()


func _known(faction_id: String, where: String) -> bool:
	if ContentDB.has(faction_id):
		return true
	Log.warn("Factions", "%s: unknown faction '%s' (content problem)" % [where, faction_id])
	return false


# --- save -------------------------------------------------------------------------------------

func to_save() -> Dictionary:
	return {"reputation": _rep.duplicate(true), "members": _members.keys(), "expelled": _expelled.duplicate(true)}


func from_save(d: Dictionary) -> void:
	_rep = (d.get("reputation", {}) as Dictionary).duplicate(true)
	_members.clear()
	for id in d.get("members", []):
		_members[str(id)] = true
	_expelled = (d.get("expelled", {}) as Dictionary).duplicate(true)
