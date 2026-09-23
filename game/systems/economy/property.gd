class_name PropertyRegistry
extends Node
## Player property (DESIGN §5.14). A deed is an item `core:item/deed_*` carrying a
## `property` block {place, interior, name, price, rent, storage, bed, key}. Buying one
## (from a steward NPC or a property sign) takes the marks, gives the deed and its key item,
## marks the interior, its door and its storage as the player's in the Ownership registry,
## and unlocks a bed the player may sleep in without trespass. A let property pays rent per
## game day, collected when the player next asks the steward (or automatically at the door).
## Save section "property".

static var instance: PropertyRegistry

signal purchased(property_id: String)
signal rent_collected(property_id: String, marks: int)
signal let_changed(property_id: String, is_let: bool)
signal furnished(property_id: String, item_id: String)

const SECTION := "property"
const RENT_FRACTION := 0.004   # per game day, of the deed price, when let
const PRICE_FLOOR := 0.75      # the best a buyer can ever haggle a posted price down to

var owned: Dictionary = {}     # property_id (deed item id) -> {bought_day, let, rent_owed_day, furnishings[]}


static func ensure() -> PropertyRegistry:
	if instance != null and is_instance_valid(instance):
		return instance
	return Service.ensure(load("res://systems/economy/property.gd"), "PropertyRegistry") as PropertyRegistry


func _enter_tree() -> void:
	instance = self
	add_to_group("property")


func _exit_tree() -> void:
	if instance == self:
		instance = null
	if SaveSystem.participants.get(SECTION) == self:
		SaveSystem.unregister(SECTION)


func _ready() -> void:
	SaveSystem.register(SECTION, self)
	var pending := SaveSystem.take_pending(SECTION)
	if not pending.is_empty():
		from_save(pending)
	EventBus.new_day.connect(_on_new_day)


# --- deed data ------------------------------------------------------------------------------

## Every deed item in the content packs, ordered by id.
static func all_deeds() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in ContentDB.all("item"):
		if d.has("property"):
			out.append(d)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	return out


static func deeds_at(place_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in all_deeds():
		if str(d["property"].get("place", "")) == place_id:
			out.append(d)
	return out


static func block(property_id: String) -> Dictionary:
	return ContentDB.get_or_empty(property_id).get("property", {})


static func price_of(property_id: String) -> int:
	var b := block(property_id)
	return int(b.get("price", ContentDB.get_or_empty(property_id).get("value", 0)))


static func display_name(property_id: String) -> String:
	var b := block(property_id)
	return str(b.get("name", ContentQuery.item_name(property_id)))


static func place_of(property_id: String) -> String:
	return str(block(property_id).get("place", ""))


## The interior id (a place id in pass one; real interiors land later).
static func interior_of(property_id: String) -> String:
	var b := block(property_id)
	return str(b.get("interior", b.get("place", "")))


static func key_item_of(property_id: String) -> String:
	return str(block(property_id).get("key", ""))


static func storage_id_of(property_id: String) -> String:
	return str(block(property_id).get("storage", interior_of(property_id) + "#storage"))


static func bed_id_of(property_id: String) -> String:
	return str(block(property_id).get("bed", interior_of(property_id) + "#bed"))


static func door_id_of(property_id: String) -> String:
	return interior_of(property_id) + "#door"


# --- ownership -------------------------------------------------------------------------------

func is_owned(property_id: String) -> bool:
	return owned.has(property_id)


func owned_ids() -> Array[String]:
	var out: Array[String] = []
	for id in owned:
		out.append(id)
	out.sort()
	return out


func owns_property_at(place_id: String) -> bool:
	for id in owned:
		if place_of(id) == place_id:
			return true
	return false


## True when the player may sleep in this bed without trespass.
func owns_bed(bed_id: String) -> bool:
	for id in owned:
		if bed_id_of(id) == bed_id:
			return true
	return false


func storage_ids() -> Array[String]:
	var out: Array[String] = []
	for id in owned:
		out.append(storage_id_of(id))
	out.sort()
	return out


# --- buying ------------------------------------------------------------------------------------

## What the steward will take today. A deed's `price` is the posted asking price and is the
## ceiling: standing, faction rank and Speech bargain it *down* (never up, unlike shop goods,
## because a house has a price on a board), and never below three-quarters of the posting.
func asking_price(property_id: String, seller_faction := "") -> int:
	var base := price_of(property_id)
	var region := WorldProbe.region_of_place(place_of(property_id))
	var disposition := Pricing.disposition_for(Peers.reaction_profile(), Peers.faction_rank(seller_faction))
	var p := Pricing.price(base, Pricing.region_mod(region), 1.0, Pricing.disposition_mod(disposition), Peers.skill_level("speech"), Peers.stat_mult("prices_buy"))
	return clampi(p, maxi(1, roundi(float(base) * PRICE_FLOOR)), base)


## {ok, reason, price}. reasons: unknown, already_owned, poor.
func buy(player: Object, property_id: String, seller_faction := "") -> Dictionary:
	if not ContentDB.has(property_id) or block(property_id).is_empty():
		return {"ok": false, "reason": "unknown", "price": 0}
	if is_owned(property_id):
		return {"ok": false, "reason": "already_owned", "price": 0}
	var price := asking_price(property_id, seller_faction)
	if not Purse.can_pay(player, price):
		EventBus.notify.emit("You cannot afford %s." % display_name(property_id), "info")
		return {"ok": false, "reason": "poor", "price": price}
	Purse.pay(player, price)
	grant(property_id, player)
	EventBus.transaction.emit(seller_faction, property_id, 1, price, true)
	return {"ok": true, "reason": "", "price": price}


## Records the property as the player's (also used by quest rewards and the debug console).
func grant(property_id: String, player: Object = null) -> void:
	if is_owned(property_id):
		return
	owned[property_id] = {"bought_day": WorldClock.day, "let": false, "rent_owed_day": WorldClock.day, "furnishings": []}
	if player != null:
		Peers.give_item(player, property_id, 1)
		var key := key_item_of(property_id)
		if not key.is_empty() and ContentDB.has(key):
			Peers.give_item(player, key, 1)
	var reg := Ownership.ensure()
	if reg != null:
		reg.claim_for_player(interior_of(property_id))
		reg.claim_for_player(door_id_of(property_id))
		reg.claim_for_player(storage_id_of(property_id))
		reg.claim_for_player(bed_id_of(property_id))
	GameState.set_flag("owns_" + Ids.name_of(property_id), true)
	GameState.inc("properties_owned")
	EventBus.property_purchased.emit(property_id)
	EventBus.notify.emit("%s is yours." % display_name(property_id), "property")
	purchased.emit(property_id)


# --- letting and rent -----------------------------------------------------------------------------

func set_let(property_id: String, is_let: bool) -> bool:
	if not is_owned(property_id):
		return false
	owned[property_id]["let"] = is_let
	owned[property_id]["rent_owed_day"] = WorldClock.day
	let_changed.emit(property_id, is_let)
	return true


func is_let(property_id: String) -> bool:
	return is_owned(property_id) and bool(owned[property_id].get("let", false))


## Rent per game day for a let property.
static func rent_per_day(property_id: String) -> int:
	var b := block(property_id)
	if b.has("rent"):
		return int(b["rent"])
	return maxi(1, roundi(float(price_of(property_id)) * RENT_FRACTION))


## Rent accrued and not yet collected.
func rent_due(property_id: String) -> int:
	if not is_let(property_id):
		return 0
	var days := maxi(0, WorldClock.day - int(owned[property_id].get("rent_owed_day", WorldClock.day)))
	return days * rent_per_day(property_id)


func total_rent_due() -> int:
	var total := 0
	for id in owned:
		total += rent_due(id)
	return total


## Pays accrued rent into the player's purse. Returns the marks collected.
func collect_rent(player: Object = null, property_id := "") -> int:
	var ids := [property_id] if not property_id.is_empty() else owned.keys()
	var total := 0
	for id: String in ids:
		var due := rent_due(id)
		if due <= 0:
			continue
		owned[id]["rent_owed_day"] = WorldClock.day
		total += due
		rent_collected.emit(id, due)
	if total > 0:
		Purse.give(player if player != null else Peers.player(), total)
		EventBus.notify.emit("Rent: %d marks." % total, "property")
	return total


func _on_new_day(_day: int) -> void:
	# Rent accrues by the day count; nothing to do but let the UI know there is money waiting.
	if total_rent_due() > 0:
		EventBus.notify.emit("Rent is waiting to be collected.", "property")


# --- furnishing ---------------------------------------------------------------------------------

## Every item in the packs that is a furnishing somebody could put in a house, ordered by id.
## A furnishing is a `misc` item carrying a `furnishing` block (CONTRACTS §7):
## `{prop, room?, spot?, storage?}` — the prop kind `PropLibrary` draws it as, the room it
## belongs in, whether it stands on the floor or hangs on a wall, and whether it is storage.
static func all_furnishings() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in ContentDB.all("item"):
		if typeof(d.get("furnishing")) == TYPE_DICTIONARY and not (d["furnishing"] as Dictionary).is_empty():
			out.append(d)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	return out


static func furnishing_block(item_id: String) -> Dictionary:
	var b: Variant = ContentDB.get_or_empty(item_id).get("furnishing", {})
	return b if typeof(b) == TYPE_DICTIONARY else {}


static func furnishing_price(item_id: String) -> int:
	return int(ContentDB.get_or_empty(item_id).get("value", 0))


## Which property, if any, this interior belongs to the player through. A deed's `interior` is
## a plain name in pass one and a built house's meta id is a full `core:house/*`, so both
## spellings match. "" when the player does not own this house.
func property_for_interior(interior_key: String) -> String:
	if interior_key.is_empty():
		return ""
	var short := Ids.name_of(interior_key) if interior_key.contains("/") else interior_key
	for id in owned_ids():
		var mine := interior_of(id)
		if mine == interior_key or mine == short:
			return id
	return ""


## Buys a furnishing for a house you own: takes the marks and records it against the property,
## which is what `HouseInterior` reads when it builds the house you walk into.
## {ok, reason, price}. reasons: not_owned, unknown, already_there, poor.
func buy_furnishing(player: Object, property_id: String, item_id: String) -> Dictionary:
	if not is_owned(property_id):
		return {"ok": false, "reason": "not_owned", "price": 0}
	if furnishing_block(item_id).is_empty():
		return {"ok": false, "reason": "unknown", "price": 0}
	if item_id in furnishings(property_id):
		return {"ok": false, "reason": "already_there", "price": 0}
	var price := furnishing_price(item_id)
	if not Purse.can_pay(player, price):
		EventBus.notify.emit("You cannot afford that.", "info")
		return {"ok": false, "reason": "poor", "price": price}
	Purse.pay(player, price)
	add_furnishing(property_id, item_id)
	var name_of := str(ContentDB.get_or_empty(item_id).get("name", "It"))
	EventBus.transaction.emit("", item_id, 1, price, true)
	EventBus.notify.emit("%s, for %s." % [name_of, display_name(property_id)], "property")
	furnished.emit(property_id, item_id)
	return {"ok": true, "reason": "", "price": price}


func add_furnishing(property_id: String, furnishing_id: String) -> bool:
	if not is_owned(property_id):
		return false
	var list: Array = owned[property_id].get("furnishings", [])
	if furnishing_id in list:
		return false
	list.append(furnishing_id)
	owned[property_id]["furnishings"] = list
	return true


func furnishings(property_id: String) -> Array:
	return owned.get(property_id, {}).get("furnishings", [])


# --- save ------------------------------------------------------------------------------------------

func to_save() -> Dictionary:
	return {"owned": owned.duplicate(true)}


func from_save(d: Dictionary) -> void:
	owned = d.get("owned", {}).duplicate(true)
	var reg := Ownership.ensure()
	if reg != null:
		for id: String in owned:
			reg.claim_for_player(interior_of(id))
			reg.claim_for_player(door_id_of(id))
			reg.claim_for_player(storage_id_of(id))
			reg.claim_for_player(bed_id_of(id))
