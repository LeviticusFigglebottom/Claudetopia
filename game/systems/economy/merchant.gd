class_name Merchant
extends Node
## A shopkeeper's trade (DESIGN §5.14). Put this under an NPC actor, or run it headless for a
## merchant who is never on screen. Stock comes from a `core:table/stock_*` definition whose
## rows are {item, count: [min, max], restock_hours, chance?}; the merchant holds a marks pool
## and a `buys` list of item categories or tags. Prices come from Pricing with the merchant's
## region, current stock count, the player's standing and Speech, and the shopkeeper's
## personality. Stock restocks on WorldClock hours, per row, toward the row's range.
##
## `open_trade(player)` announces the trade through the "economy" group node's
## `trade_requested(merchant)` signal so the UI stream can open its screen.
## Persisted by EconomyService under the "economy" save section.

signal stock_changed
signal traded(item_id: String, count: int, price: int, bought: bool)
signal refused(reason: String)

const DEFAULT_MARKS := 150
const HOLLOW_REFUSAL_TIER := -2
## Cultures whose shopkeepers turn a deep-Hollow customer away (DESIGN §5.11: Vale villages).
const REFUSING_CULTURES: Array[String] = ["vale"]

@export var npc_id := ""
@export var stock_table := ""
@export var marks := DEFAULT_MARKS
@export var buys: Array[String] = []
@export var place_id := ""
@export var faction := ""
@export var restock_on_clock := true

var stock: Dictionary = {}        # item_id -> int
var next_restock: Dictionary = {}  # item_id -> absolute game hours
var disposition := 0               # earned by trading; added to the standing-derived value
var personality: Personality = null
var _rng := RandomNumberGenerator.new()
var _initialised := false


func _ready() -> void:
	if npc_id.is_empty():
		var parent := get_parent()
		if parent != null and "npc_id" in parent:
			npc_id = str(parent.get("npc_id"))
	load_from_npc_def()
	if not _initialised:
		restock_all(true)
	if restock_on_clock and not EventBus.hour_changed.is_connected(_on_hour_changed):
		EventBus.hour_changed.connect(_on_hour_changed)
	EconomyService.register_merchant(self)


func _exit_tree() -> void:
	if EventBus.hour_changed.is_connected(_on_hour_changed):
		EventBus.hour_changed.disconnect(_on_hour_changed)
	EconomyService.unregister_merchant(self)


## Reads the merchant block of the NPC def (CONTRACTS §7: merchant{stock, marks, buys[]}).
## The stock RNG is seeded from the merchant's id either way, so the same shopkeeper always
## opens with the same shelves.
func load_from_npc_def() -> void:
	_rng.seed = hash(merchant_id())
	if npc_id.is_empty() or not ContentDB.has(npc_id):
		return
	var def := ContentDB.get_or_empty(npc_id)
	var m: Dictionary = def.get("merchant", {})
	if stock_table.is_empty():
		stock_table = str(m.get("stock", m.get("stock_table", "")))
	if marks == DEFAULT_MARKS and m.has("marks"):
		marks = int(m["marks"])
	if buys.is_empty():
		for c in m.get("buys", []):
			buys.append(str(c))
	if place_id.is_empty():
		place_id = str(def.get("home_place", ""))
	if faction.is_empty():
		faction = str(def.get("faction", ""))
	if personality == null:
		personality = Personality.from_def(def)


func region_id() -> String:
	if place_id.is_empty():
		return GameState.current_region_id
	var r := WorldProbe.region_of_place(place_id)
	return r if not r.is_empty() else GameState.current_region_id


func table_rows() -> Array:
	if stock_table.is_empty():
		return []
	return ContentDB.get_or_empty(stock_table).get("rows", [])


func count(item_id: String) -> int:
	return int(stock.get(item_id, 0))


func items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in stock:
		if int(stock[id]) > 0:
			out.append({"item_id": id, "count": int(stock[id])})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["item_id"]) < str(b["item_id"]))
	return out


# --- restocking -------------------------------------------------------------------------------

static func now_hours() -> float:
	return float(WorldClock.day) * 24.0 + WorldClock.time_hours


## Fills every row that is due (or all of them with `force`). Returns the rows restocked.
func restock_all(force := false) -> int:
	var now := now_hours()
	var done := 0
	for row in table_rows():
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var item_id := str(row.get("item", ""))
		if item_id.is_empty():
			continue
		if not force and now < float(next_restock.get(item_id, 0.0)):
			continue
		_restock_row(row, item_id)
		done += 1
	_initialised = true
	if done > 0:
		stock_changed.emit()
	return done


func _restock_row(row: Dictionary, item_id: String) -> void:
	var hours := float(row.get("restock_hours", 48.0))
	next_restock[item_id] = now_hours() + maxf(1.0, hours)
	var chance := float(row.get("chance", 1.0))
	if chance < 1.0 and _rng.randf() > chance:
		return
	var range_v: Variant = row.get("count", [1, 1])
	var lo := 1
	var hi := 1
	if typeof(range_v) == TYPE_ARRAY and range_v.size() >= 2:
		lo = int(range_v[0])
		hi = int(range_v[1])
	elif typeof(range_v) == TYPE_ARRAY and range_v.size() == 1:
		lo = int(range_v[0])
		hi = lo
	else:
		lo = int(range_v)
		hi = lo
	var target := _rng.randi_range(mini(lo, hi), maxi(lo, hi))
	# Restocking tops up toward the target; it never takes away what the player sold in.
	stock[item_id] = maxi(count(item_id), target)


func _on_hour_changed(_hour: int) -> void:
	if restock_all():
		pass
	if marks < _marks_cap():
		@warning_ignore("integer_division")
		marks = mini(_marks_cap(), marks + maxi(1, _marks_cap() / 48))


func _marks_cap() -> int:
	var m: Dictionary = ContentDB.get_or_empty(npc_id).get("merchant", {})
	return int(m.get("marks", DEFAULT_MARKS))


# --- disposition and refusal ------------------------------------------------------------------

func personality_bias() -> float:
	return personality.price_bias() if personality != null else 0.0


func effective_disposition() -> int:
	return Pricing.disposition_for(Peers.reaction_profile(), Peers.faction_rank(faction), disposition)


## A Vale shopkeeper will not serve the deeply Hollow (DESIGN §5.11); others charge them more.
func refuses_trade() -> bool:
	var tier := int(Peers.reaction_profile().get("morality_tier", 0))
	if tier > HOLLOW_REFUSAL_TIER:
		return false
	return WorldProbe.culture_key(region_id()) in REFUSING_CULTURES


func hollow_penalty() -> float:
	var tier := int(Peers.reaction_profile().get("morality_tier", 0))
	return 0.0 if tier >= 0 else minf(0.3, float(-tier) * 0.1)


func buy_price_of(item_id: String) -> int:
	return Pricing.buy_price(ContentQuery.item_value(item_id), region_id(), count(item_id), effective_disposition(), Peers.skill_level("speech"), personality_bias(), hollow_penalty(), Peers.stat_mult("prices_buy"))


func sell_price_of(item_id: String) -> int:
	return Pricing.sell_price(ContentQuery.item_value(item_id), region_id(), count(item_id), effective_disposition(), Peers.skill_level("speech"), personality_bias(), hollow_penalty(), Peers.stat_mult("prices_sell"))


func will_buy(item_id: String) -> bool:
	# A keepsake (the Hearth Flask) is not the kind of thing that is sold, whatever its category.
	var tags: Variant = ContentDB.get_or_empty(item_id).get("tags", [])
	if typeof(tags) == TYPE_ARRAY and (tags as Array).has("keepsake"):
		return false
	# nor is a thing a quest of the player's still wants: sold, it was gone, and the quest with it
	if Social != null and Social.quests != null and str(Social.quests.call("wanted_by", item_id)) != "":
		return false
	return ContentQuery.item_matches_categories(item_id, buys)


# --- trading -----------------------------------------------------------------------------------

## The player buys `count_` of `item_id`. Returns {ok, reason, price, count}.
func buy(player: Object, item_id: String, count_: int = 1) -> Dictionary:
	if refuses_trade():
		refused.emit("hollow")
		EventBus.notify.emit("They will not trade with you.", "refusal")
		return {"ok": false, "reason": "refused", "price": 0, "count": 0}
	if count_ <= 0:
		return {"ok": false, "reason": "count", "price": 0, "count": 0}
	if count(item_id) < count_:
		refused.emit("out_of_stock")
		return {"ok": false, "reason": "out_of_stock", "price": 0, "count": 0}
	var quote := Pricing.bulk(ContentQuery.item_value(item_id), region_id(), count(item_id), count_, effective_disposition(), Peers.skill_level("speech"), "buy", personality_bias(), hollow_penalty(), Peers.stat_mult("prices_buy"))
	var total := int(quote["total"])
	if not Purse.can_pay(player, total):
		refused.emit("poor")
		EventBus.notify.emit("You cannot afford that.", "info")
		return {"ok": false, "reason": "poor", "price": total, "count": 0}
	if not Peers.give_item(player, item_id, count_):
		refused.emit("no_inventory")
		return {"ok": false, "reason": "no_inventory", "price": total, "count": 0}
	Purse.pay(player, total)
	marks += total
	stock[item_id] = count(item_id) - count_
	disposition = clampi(disposition + 1, -50, 50)
	_after_trade(item_id, count_, total, true)
	return {"ok": true, "reason": "", "price": total, "count": count_}


## The player sells `count_` of `item_id`. Returns {ok, reason, price, count}.
func sell(player: Object, item_id: String, count_: int = 1) -> Dictionary:
	if refuses_trade():
		refused.emit("hollow")
		EventBus.notify.emit("They will not trade with you.", "refusal")
		return {"ok": false, "reason": "refused", "price": 0, "count": 0}
	if count_ <= 0:
		return {"ok": false, "reason": "count", "price": 0, "count": 0}
	if not will_buy(item_id):
		refused.emit("not_bought")
		EventBus.notify.emit("They have no use for that.", "info")
		return {"ok": false, "reason": "not_bought", "price": 0, "count": 0}
	if Peers.item_count(player, item_id) < count_:
		return {"ok": false, "reason": "not_held", "price": 0, "count": 0}
	var quote := Pricing.bulk(ContentQuery.item_value(item_id), region_id(), count(item_id), count_, effective_disposition(), Peers.skill_level("speech"), "sell", personality_bias(), hollow_penalty(), Peers.stat_mult("prices_sell"))
	var total := int(quote["total"])
	var paid := total
	var sold := count_
	if marks < total:
		# The shopkeeper buys what they can afford, one unit at a time.
		paid = 0
		sold = 0
		for unit: int in quote["unit_prices"]:
			if paid + unit > marks:
				break
			paid += unit
			sold += 1
		if sold == 0:
			refused.emit("merchant_poor")
			EventBus.notify.emit("They have not the marks for it.", "info")
			return {"ok": false, "reason": "merchant_poor", "price": total, "count": 0}
	if not Peers.take_item(player, item_id, sold):
		return {"ok": false, "reason": "not_held", "price": 0, "count": 0}
	Purse.give(player, paid)
	marks -= paid
	stock[item_id] = count(item_id) + sold
	disposition = clampi(disposition + 1, -50, 50)
	_after_trade(item_id, sold, paid, false)
	return {"ok": true, "reason": "", "price": paid, "count": sold}


func _after_trade(item_id: String, count_: int, price: int, bought: bool) -> void:
	EventBus.transaction.emit(merchant_id(), item_id, count_, price, bought)
	EventBus.skill_used.emit("speech", 1.0 + float(price) * 0.02)
	traded.emit(item_id, count_, price, bought)
	stock_changed.emit()


func merchant_id() -> String:
	return npc_id if not npc_id.is_empty() else str(get_path())


## Asks the UI to open a trade screen for this merchant.
func open_trade(player: Node = null) -> void:
	EconomyService.request_trade(self, player)


# --- save -----------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"stock": stock.duplicate(), "marks": marks, "next_restock": next_restock.duplicate(), "disposition": disposition}


func from_dict(d: Dictionary) -> void:
	stock = {}
	for k in d.get("stock", {}):
		stock[k] = int(d["stock"][k])
	next_restock = {}
	for k in d.get("next_restock", {}):
		next_restock[k] = float(d["next_restock"][k])
	marks = int(d.get("marks", marks))
	disposition = int(d.get("disposition", 0))
	_initialised = true
	stock_changed.emit()
