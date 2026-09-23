extends Node
## Standing: the Hearth/Hollow axis (morality, -100..100), Renown (0..1000), the deed table that
## moves both, and the per-NPC disposition and witness memory the greeting matrix reads.
## Save section "standing". Joins the group "standing".
##
## DESIGN.md §5.11: Renown is not vanity, it is anchoring. A deed nobody saw barely holds, so
## every deed's renown has a base plus a per-witness share (capped), and witnessed deeds are
## handed to Gossip, which carries them between places over game hours.
##
## Data: core:table/deeds (game/content/packs/core/tables/deeds.json), rows:
##   {id, label, hearth, renown, witness_renown, witness_cap, rumour, heat}
##
## Emits: EventBus.morality_changed(new, delta, reason), EventBus.renown_changed(new, delta, reason),
##        EventBus.deed_applied(deed_id, hearth_delta, renown_delta, witnesses),
##        EventBus.disposition_changed(npc_id, new, delta)

const DEED_TABLE := "core:table/deeds"

const MORALITY_MIN := -100
const MORALITY_MAX := 100
const RENOWN_MIN := 0
const RENOWN_MAX := 1000

## Renown tiers: thresholds and the title the world starts using. Tier 0 has no title; you are
## a face. The top tier is what the world bible calls the Named.
const RENOWN_THRESHOLDS: Array[int] = [0, 25, 100, 300, 600]
const RENOWN_TITLES: Array[String] = ["", "the Heard-Of", "the Known", "the Spoken-Of", "the Named"]

## Morality tiers are signed: -3 is deepest Hollow, +3 is deepest Hearth, 0 is unremarkable.
## Thresholds are the |value| needed for tiers 1, 2 and 3 on either side.
const MORALITY_THRESHOLDS: Array[int] = [15, 40, 75]
const HEARTH_TITLES: Array[String] = ["", "Kindly", "Hearth-Warm", "the Hearth-Kept"]
const HOLLOW_TITLES: Array[String] = ["", "Cold-Handed", "Quiet-eyed", "the Hollow"]

## Repeating the same good deed moves you less each time (the village stops being surprised).
## Cruelty never softens: a Hollow deed costs full price however often you do it.
const REPEAT_SOFTEN := 0.06
const REPEAT_FLOOR := 0.25

## Disposition is per-NPC liking, -100..100, moved by gestures, gifts and what they have seen.
const DISPOSITION_MIN := -100
const DISPOSITION_MAX := 100

var morality_value: int = 0
var renown_value: int = 0

var _deed_counts: Dictionary = {}       # deed_id -> times applied (for softening)
var _disposition: Dictionary = {}       # npc_id -> int
var _witnessed: Dictionary = {}         # npc_id -> last cold deed id they saw
var _deed_rows: Dictionary = {}         # deed_id -> row (cached from content)

## Injected by the owner (Social) so apply_deed can seed the rumour pool. Duck-typed:
## needs add_rumour(rumour_id, place_id, heat, deed_id) and nearest_place(Vector3).
var gossip: Object = null
## Optional provider for "where am I": duck-typed place_id() -> String.
var place_provider: Object = null


func _ready() -> void:
	add_to_group("standing")
	SaveSystem.register("standing", self)


# --- the axes ---------------------------------------------------------------------------------

func morality() -> int:
	return morality_value


func renown() -> int:
	return renown_value


func add_morality(delta: int, reason: String = "") -> int:
	if delta == 0:
		return morality_value
	var before := morality_value
	morality_value = clampi(morality_value + delta, MORALITY_MIN, MORALITY_MAX)
	if morality_value != before:
		EventBus.morality_changed.emit(morality_value, morality_value - before, reason)
	return morality_value


func add_renown(delta: int, reason: String = "") -> int:
	if delta == 0:
		return renown_value
	if delta > 0 and reason != "set":
		# Loud Name: deeds travel 20% further. What is earned grows; what is lost does not.
		delta = int(round(float(delta) * Peers.stat_mult("renown_gain")))
	var before := renown_value
	renown_value = clampi(renown_value + delta, RENOWN_MIN, RENOWN_MAX)
	if renown_value != before:
		EventBus.renown_changed.emit(renown_value, renown_value - before, reason)
	return renown_value


func set_morality(value: int) -> void:
	add_morality(clampi(value, MORALITY_MIN, MORALITY_MAX) - morality_value, "set")


func set_renown(value: int) -> void:
	add_renown(clampi(value, RENOWN_MIN, RENOWN_MAX) - renown_value, "set")


# --- tiers and titles ---------------------------------------------------------------------------

func renown_tier() -> int:
	return tier_for_renown(renown_value)


static func tier_for_renown(value: int) -> int:
	var out := 0
	for i in RENOWN_THRESHOLDS.size():
		if value >= RENOWN_THRESHOLDS[i]:
			out = i
	return out


## Signed: -3..+3. Negative is Hollow, positive is Hearth.
func morality_tier() -> int:
	return tier_for_morality(morality_value)


static func tier_for_morality(value: int) -> int:
	var mag := absi(value)
	var step := 0
	for i in MORALITY_THRESHOLDS.size():
		if mag >= MORALITY_THRESHOLDS[i]:
			step = i + 1
	return step if value >= 0 else -step


func renown_title() -> String:
	return RENOWN_TITLES[renown_tier()]


func morality_title() -> String:
	var t := morality_tier()
	return HEARTH_TITLES[t] if t >= 0 else HOLLOW_TITLES[-t]


## What a villager would call you: your renown title if you have one, otherwise what your deeds
## have made of your face. Empty for an unremarkable stranger.
func title() -> String:
	var r := renown_title()
	if r != "":
		return r
	return morality_title()


## The contract other streams read (visuals, prices, greetings, guards).
func reaction_profile() -> Dictionary:
	return {
		"renown": renown_value,
		"renown_tier": renown_tier(),
		"renown_title": renown_title(),
		"morality": morality_value,
		"morality_tier": morality_tier(),
		"morality_title": morality_title(),
		"title": title(),
		"hollow": morality_value < 0,
	}


# --- deeds ---------------------------------------------------------------------------------------

## The deed row from core:table/deeds, or {} (logged once) when the id is not in the table.
func deed_row(deed_id: String) -> Dictionary:
	if _deed_rows.is_empty():
		_load_deeds()
	var row: Variant = _deed_rows.get(deed_id)
	if row == null:
		Log.warn("Standing", "unknown deed '%s' (content problem, ignored)" % deed_id)
		return {}
	return row


func _load_deeds() -> void:
	var table := ContentDB.get_or_empty(DEED_TABLE)
	for row in table.get("rows", []):
		if typeof(row) == TYPE_DICTIONARY and row.has("id"):
			_deed_rows[str(row["id"])] = row
	if _deed_rows.is_empty():
		Log.error("Standing", "deed table %s is missing or empty" % DEED_TABLE)


func deed_ids() -> Array[String]:
	if _deed_rows.is_empty():
		_load_deeds()
	var out: Array[String] = []
	for id in _deed_rows:
		out.append(id)
	out.sort()
	return out


## Applies a deed. `witnesses` is an array of NPC ids (empty strings allowed for anonymous
## bystanders) or an int count. `place_id` defaults to the place provider's answer.
## Returns {deed, hearth, renown, witnesses, rumour, place}.
func apply_deed(deed_id: String, witnesses: Variant = [], place_id: String = "") -> Dictionary:
	var row := deed_row(deed_id)
	if row.is_empty():
		return {}
	var witness_ids := _witness_ids(witnesses)
	var n := witness_ids.size()
	var cap := int(row.get("witness_cap", 0))
	var counted: int = mini(n, cap) if cap > 0 else 0

	var hearth_base := int(row.get("hearth", 0))
	var renown_base := int(row.get("renown", 0)) + int(row.get("witness_renown", 0)) * counted

	var soften := _soften_for(deed_id)
	var hearth_delta := hearth_base if hearth_base < 0 else int(round(float(hearth_base) * soften))
	var renown_delta := int(round(float(renown_base) * soften)) if renown_base > 0 else renown_base
	# A deed worth anything at all never rounds away to nothing.
	if hearth_base > 0 and hearth_delta == 0:
		hearth_delta = 1
	if renown_base > 0 and renown_delta == 0:
		renown_delta = 1

	_deed_counts[deed_id] = int(_deed_counts.get(deed_id, 0)) + 1

	var reason := "deed:" + deed_id
	add_morality(hearth_delta, reason)
	add_renown(renown_delta, reason)

	var where := place_id if place_id != "" else _current_place()
	var rumour_id := str(row.get("rumour", ""))
	if n > 0 and hearth_base < 0:
		for npc_id in witness_ids:
			if npc_id != "":
				_witnessed[npc_id] = deed_id
	if n > 0 and rumour_id != "" and gossip != null and is_instance_valid(gossip) and gossip.has_method("add_rumour"):
		var heat := float(row.get("heat", 0.5)) * clampf(0.5 + 0.25 * float(counted), 0.5, 1.5)
		gossip.add_rumour(rumour_id, where, heat, deed_id)

	EventBus.deed_applied.emit(deed_id, hearth_delta, renown_delta, n)
	Log.info("Standing", "deed %s: hearth %+d renown %+d (%d witnesses) at %s" % [deed_id, hearth_delta, renown_delta, n, where if where != "" else "nowhere in particular"])
	return {"deed": deed_id, "hearth": hearth_delta, "renown": renown_delta, "witnesses": n, "rumour": rumour_id, "place": where}


## How much a repeat of this deed is still worth (1.0 the first time, never below REPEAT_FLOOR).
func _soften_for(deed_id: String) -> float:
	var prior := int(_deed_counts.get(deed_id, 0))
	return maxf(REPEAT_FLOOR, 1.0 - REPEAT_SOFTEN * float(prior))


func deed_count(deed_id: String) -> int:
	return int(_deed_counts.get(deed_id, 0))


static func _witness_ids(witnesses: Variant) -> Array[String]:
	var out: Array[String] = []
	match typeof(witnesses):
		TYPE_ARRAY:
			for w in witnesses:
				out.append(str(w))
		TYPE_INT, TYPE_FLOAT:
			for i in int(witnesses):
				out.append("")
		TYPE_STRING:
			if str(witnesses) != "":
				out.append(str(witnesses))
	return out


func _current_place() -> String:
	if place_provider != null and is_instance_valid(place_provider) and place_provider.has_method("place_id"):
		return str(place_provider.place_id())
	return ""


# --- per-NPC disposition and witness memory -------------------------------------------------------

func disposition(npc_id: String) -> int:
	return int(_disposition.get(npc_id, 0))


func add_disposition(npc_id: String, delta: int) -> int:
	if npc_id == "" or delta == 0:
		return disposition(npc_id)
	var before := disposition(npc_id)
	var after := clampi(before + delta, DISPOSITION_MIN, DISPOSITION_MAX)
	if after == before:
		return before
	_disposition[npc_id] = after
	EventBus.disposition_changed.emit(npc_id, after, after - before)
	return after


## The last cold deed this NPC saw you do, or "".
func npc_witnessed(npc_id: String) -> String:
	return str(_witnessed.get(npc_id, ""))


func forget_witness(npc_id: String) -> void:
	_witnessed.erase(npc_id)


func reset_for_new_game() -> void:
	morality_value = 0
	renown_value = 0
	_deed_counts.clear()
	_disposition.clear()
	_witnessed.clear()


# --- save --------------------------------------------------------------------------------------

func to_save() -> Dictionary:
	return {
		"morality": morality_value, "renown": renown_value,
		"deed_counts": _deed_counts.duplicate(true), "disposition": _disposition.duplicate(true),
		"witnessed": _witnessed.duplicate(true),
	}


func from_save(d: Dictionary) -> void:
	morality_value = clampi(int(d.get("morality", 0)), MORALITY_MIN, MORALITY_MAX)
	renown_value = clampi(int(d.get("renown", 0)), RENOWN_MIN, RENOWN_MAX)
	_deed_counts = (d.get("deed_counts", {}) as Dictionary).duplicate(true)
	_disposition = (d.get("disposition", {}) as Dictionary).duplicate(true)
	_witnessed = (d.get("witnessed", {}) as Dictionary).duplicate(true)
