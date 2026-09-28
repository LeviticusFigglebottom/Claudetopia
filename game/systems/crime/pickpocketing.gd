class_name Pickpocketing
extends RefCounted
## A hand in somebody's pocket (DESIGN §5.13), from the player's side. Stealth.pickpocket had the
## rule, moved the goods and recorded the crime, and nothing in play ever called it: the player had
## no way to pick a pocket and nothing taught it (triage 25). This is the way in.
##
## - The offer: crouched, at a living person who is not hostile and is unaware of you (their
##   awareness under DetectionMeter.SUSPICIOUS), the interact key picks their pocket instead of
##   talking (`can_offer`, asked by Npc.prompt_text and Npc.interact). A sleeper sees nothing (Npc
##   _sense), is a fifth as aware as their meter says, and their pocket is ASLEEP_BONUS easier. Somebody who has just caught you at it is wary for WARY_HOURS.
## - The pockets: an Inventory under the person ("Pockets"), filled once from their def's `pockets`
##   ({items: [[id, n]], marks, table}), else a loot table (a trader's, with a thing from their own
##   stock, or anybody's), and kept, with what has been taken from them, in the "pockets" save
##   section. They fill again after REFILL_HOURS.
## - The screen (ui/inventory/pickpocket_screen.gd) lists what is there with each thing's chance:
##   Stealth.pickpocket_chance from Sneak and the thief's perks, the mark's awareness, the thing's
##   worth and weight. Each thing already lifted in one go makes the next harder (NERVE_PER_LIFT).
## - A lift (`attempt`) is Stealth.pickpocket: the roll, the goods moved, Sneak practised, the crime
##   recorded (witnessed by the mark when it fails), and the `pickpocket` act on a success. Caught,
##   the mark reacts by their personality's crime_reaction (confront, flee, or a hard look), turns
##   wary, and the screen closes.
##
## Stolen goods carry no mark of it in the bag: as with a chest (WorldContainer.close_up), the law
## hears of the taking, not of the thing.

const SAVE_SECTION := "pockets"
const POCKETS_NODE := "Pockets"
const REFILL_HOURS := 72.0
const WARY_HOURS := 6.0
## How much of their meter a sleeper has: a lot has to happen before a sleeping man knows it.
const ASLEEP_FACTOR := 0.2
## And how much easier a sleeper's pocket is, on top: Sneak 0 lifts a sleeping collector's key
## about half the time rather than a third.
const ASLEEP_BONUS := 0.25
## Awareness added for each thing already lifted from the same pocket in one visit.
const NERVE_PER_LIFT := 0.08
const COMMON_TABLE := "core:loot/pockets_common"
const MERCHANT_TABLE := "core:loot/pockets_merchant"
## Never a mark: an animal has no pockets, a child is not a lesson.
const NOT_MARKS: Array[String] = ["dog", "animal", "child"]


## Every pocket's state, by npc id: {inventory, filled (hours), wary_until (hours)}. `seed` is the
## game's, so a new game in the same session does not find the last one's emptied pockets.
class Store:
	extends RefCounted
	var states: Dictionary = {}
	var game_seed := 0

	func to_save() -> Dictionary:
		return {"states": states.duplicate(true), "seed": game_seed}

	func from_save(d: Dictionary) -> void:
		var s: Variant = d.get("states", {})
		states = s.duplicate(true) if typeof(s) == TYPE_DICTIONARY else {}
		game_seed = int(d.get("seed", GameState.seed))

	func clear() -> void:
		states.clear()


static var store: Store = Store.new()
static var _registered := false


static func _store() -> Store:
	if not _registered:
		SaveSystem.register(SAVE_SECTION, store)
		_registered = true
	if store.game_seed != GameState.seed:
		store.clear()
		store.game_seed = GameState.seed
	return store


static func now_hours() -> float:
	return float(WorldClock.day - 1) * 24.0 + WorldClock.time_hours


# --- the offer -----------------------------------------------------------------------------------

## Whether this person is somebody whose pocket could be picked at all.
static func is_mark(mark: Node) -> bool:
	if mark == null or not is_instance_valid(mark) or not ("npc_id" in mark):
		return false
	if str(mark.get("npc_id")).is_empty() or not _flag(mark, "alive", true) or _flag(mark, "hostile") or _flag(mark, "fleeing"):
		return false
	if (mark.has_method("is_following") and bool(mark.call("is_following"))):
		return false
	if mark.has_method("is_child") and bool(mark.call("is_child")):
		return false
	var def: Variant = mark.get("def")
	if def is Dictionary:
		for t in (def as Dictionary).get("tags", []):
			if str(t) in NOT_MARKS:
				return false
	if (mark.has_method("is_with_you") and bool(mark.call("is_with_you"))) or wanted_for_a_word(str(mark.get("npc_id"))):
		return false
	return not NpcRegistry.is_talking(str(mark.get("npc_id")))


## True when a quest's stage now wants a word with this person (a `talk` objective not yet done):
## crouched at their back, the key talks, it does not go into their coat. The Rogue arrives at Sauve
## by the South Channel crouched, as he taught, and the key there offered his pocket.
static func wanted_for_a_word(npc_id: String) -> bool:
	if npc_id.is_empty() or Social.quests == null:
		return false
	for row in Social.quests.call("current_objectives", "talk"):
		var o: Dictionary = (row as Dictionary).get("objective", {})
		if str(o.get("target", "")) == npc_id and not bool((row as Dictionary).get("done", false)):
			return true
	return false


static func _flag(o: Object, prop: String, fallback := false) -> bool:
	return bool(o.get(prop)) if prop in o else fallback


static func is_asleep(mark: Node) -> bool:
	if mark == null or not is_instance_valid(mark):
		return false
	if "activity" in mark and str(mark.get("activity")) == "sleep":
		return true
	return mark.has_method("current_intent") and str(mark.call("current_intent")) == "Sleep_Idle"


## How aware of the thief the mark is, 0..1: their meter, a fraction of it asleep (a sleeper
## caught at it is wide awake, and wary besides).
static func awareness(mark: Node) -> float:
	var a := Stealth.awareness_of(mark)
	if is_asleep(mark) and a < DetectionMeter.DETECTED:
		a *= ASLEEP_FACTOR
	return clampf(a, 0.0, 1.0)


static func is_wary(mark: Node) -> bool:
	if mark == null or not ("npc_id" in mark):
		return false
	var st: Dictionary = _store().states.get(str(mark.get("npc_id")), {})
	return float(st.get("wary_until", -1.0)) > now_hours()


## The interact key picks this pocket: the actor is the player, crouched, and the mark is unaware
## of them and not wary of them.
static func can_offer(mark: Node, actor: Node) -> bool:
	if actor == null or not is_instance_valid(actor) or not actor.is_in_group("player"):
		return false
	if not Stealth.is_crouched(actor) or not is_mark(mark):
		return false
	return awareness(mark) < DetectionMeter.SUSPICIOUS and not is_wary(mark)


static func prompt_for(mark: Node) -> String:
	var who := str(mark.call("display_name")) if mark.has_method("display_name") else "their"
	return "Pick %s's pocket" % who


## Asks for the pickpocket screen (the UI answers EventBus.pickpocket_requested).
static func request(mark: Node, actor: Node) -> void:
	pockets(mark)
	EventBus.pickpocket_requested.emit(mark, actor)


# --- the pockets ---------------------------------------------------------------------------------

## The mark's pockets, filled and kept: the Inventory under them the thief's hand goes into.
static func pockets(mark: Node) -> Inventory:
	if mark == null or not is_instance_valid(mark):
		return null
	var inv := mark.get_node_or_null(POCKETS_NODE) as Inventory
	if inv == null:
		inv = Inventory.new()
		inv.name = POCKETS_NODE
		inv.capacity_override = 1000.0
		mark.add_child(inv)
	var id := str(mark.get("npc_id")) if "npc_id" in mark else ""
	var s := _store()
	var st: Dictionary = s.states.get(id, {})
	var now := now_hours()
	if not st.is_empty() and now - float(st.get("filled", now)) < REFILL_HOURS:
		if not bool(inv.get_meta("pockets_loaded", false)):
			inv.from_save(st.get("inventory", {}))
			inv.set_meta("pockets_loaded", true)
		return inv
	inv.clear()
	inv.marks = 0
	_fill(mark, inv, id)
	inv.set_meta("pockets_loaded", true)
	st["filled"] = now
	st["inventory"] = inv.to_save()
	s.states[id] = st
	return inv


static func _fill(mark: Node, inv: Inventory, id: String) -> void:
	var def: Dictionary = mark.get("def") if mark.get("def") is Dictionary else ContentDB.get_or_empty(id)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id) ^ GameState.seed ^ int(now_hours() / REFILL_HOURS)
	var own: Variant = def.get("pockets", null)
	var table := ""
	if own is Dictionary:
		for row in (own as Dictionary).get("items", []):
			if row is Array and (row as Array).size() >= 1 and ContentDB.has(str(row[0])):
				inv.add(str(row[0]), int(row[1]) if (row as Array).size() > 1 else 1)
		inv.add_marks(int((own as Dictionary).get("marks", 0)))
		table = str((own as Dictionary).get("table", ""))
	else:
		table = MERCHANT_TABLE if def.has("merchant") else COMMON_TABLE
		var shop: Variant = mark.call("merchant") if mark.has_method("merchant") else null
		if shop is Merchant:
			var wares := _pocketable_stock(shop as Merchant)
			if not wares.is_empty():
				inv.add(wares[rng.randi() % wares.size()], 1)
	if not table.is_empty() and ContentDB.has(table):
		for r in LootTable.roll_merged(table, rng, LootTable.world_context()):
			if r.has("marks"):
				inv.add_marks(int(r["marks"]))
			else:
				inv.add(str(r["item"]), int(r["count"]), r.get("data", {}))


## What of a trader's stock would go in a pocket: light things.
static func _pocketable_stock(shop: Merchant) -> Array[String]:
	var out: Array[String] = []
	for row in shop.items():
		var item_id := str(row["item_id"])
		if float(ContentDB.get_or_empty(item_id).get("weight", 9.0)) <= 1.0:
			out.append(item_id)
	return out


static func _persist(mark: Node) -> void:
	var inv := mark.get_node_or_null(POCKETS_NODE) as Inventory if mark != null and is_instance_valid(mark) else null
	if inv == null or not ("npc_id" in mark):
		return
	var id := str(mark.get("npc_id"))
	var st: Dictionary = _store().states.get(id, {})
	st["inventory"] = inv.to_save()
	if not st.has("filled"):
		st["filled"] = now_hours()
	store.states[id] = st


## What is in the pockets, each with the chance of lifting it now: [{id, name, count, value,
## weight, chance}], the purse (Stealth.PURSE) first. `lifted` is how many things this visit has
## already taken.
static func contents(mark: Node, actor: Node, lifted := 0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var inv := pockets(mark)
	if inv == null:
		return out
	if inv.marks > 0:
		out.append({"id": Stealth.PURSE, "name": "A purse, %d marks" % inv.marks, "count": 1, "value": inv.marks, "weight": 0.0,
				"chance": chance_for(mark, actor, Stealth.PURSE, lifted)})
	for s in inv.stacks():
		out.append({"id": s.id, "name": s.display_name(), "count": s.count, "value": ContentQuery.item_value(s.id),
				"weight": float(ContentDB.get_or_empty(s.id).get("weight", 0.0)), "chance": chance_for(mark, actor, s.id, lifted)})
	return out


static func awareness_now(mark: Node, lifted := 0) -> float:
	return clampf(awareness(mark) + NERVE_PER_LIFT * float(maxi(lifted, 0)), 0.0, 1.0)


## What the mark's state adds to the thief's chance: a sleeper's pocket is open to the hand
## (ASLEEP_BONUS), where an unaware waking man's is only unwatched.
static func situation_bonus(mark: Node) -> float:
	return ASLEEP_BONUS if is_asleep(mark) else 0.0


## The chance of lifting `item_id` (or the purse) from the mark now, the way Stealth.pickpocket
## will roll it.
static func chance_for(mark: Node, actor: Node, item_id: String, lifted := 0) -> float:
	var worth := Stealth.pocket_worth(mark, item_id)
	return Stealth.pickpocket_chance(Peers.skill_level("sneak"), awareness_now(mark, lifted), int(worth["value"]),
			Stealth.stat_add_of(actor, "pickpocket_chance") + situation_bonus(mark), float(worth["weight"]))


# --- the lift ------------------------------------------------------------------------------------

## One try at one thing: {ok, chance, caught, item_id} (Stealth.pickpocket), and the mark's
## reaction when they caught you ("confront", "flee", "watch"; "" otherwise).
static func attempt(mark: Node, actor: Node, item_id: String, rng: RandomNumberGenerator = null, lifted := 0) -> Dictionary:
	pockets(mark)
	var st := Stealth.ensure()
	var r := st.pickpocket(actor, mark, item_id, rng, awareness_now(mark, lifted), situation_bonus(mark))
	r["reaction"] = ""
	_persist(mark)
	if bool(r.get("caught", false)):
		r["reaction"] = caught(mark, actor)
	return r


## Caught at it: the mark is wary of the thief for WARY_HOURS and reacts by their nature, and says so.
static func caught(mark: Node, actor: Node) -> String:
	var id := str(mark.get("npc_id")) if mark != null and "npc_id" in mark else ""
	if id.is_empty():
		return ""
	var s := _store()
	var st: Dictionary = s.states.get(id, {})
	st["wary_until"] = now_hours() + WARY_HOURS
	s.states[id] = st
	var kind := reaction_for(mark.get("personality") as Personality)
	var who := str(mark.call("display_name")) if mark.has_method("display_name") else "Someone"
	EventBus.notify.emit(Reactions.line_for(kind, who), "reaction")
	var reactions := Reactions.ensure()
	if reactions != null:
		reactions.reaction.emit(id, kind)
	if kind == "flee" and mark.has_method("flee_from"):
		mark.call("flee_from", actor)
		if mark.has_method("play_intent"):
			mark.call("play_intent", Reactions.intent_for(kind), true)
	elif mark.has_method("play_reaction"):
		mark.call("play_reaction", kind)
	return kind


## What somebody does with a thief's hand in their coat: square up to them, run, or look at them
## hard enough to remember the face (the report is the crime system's, not this).
static func reaction_for(personality: Personality) -> String:
	var r := personality.crime_reaction() if personality != null else "report"
	match r:
		"confront":
			return "confront"
		"flee":
			return "flee"
	return "watch"
