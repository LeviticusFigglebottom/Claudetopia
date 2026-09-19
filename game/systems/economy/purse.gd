class_name Purse
## Marks (currency) access for any actor, duck-typed against the inventory stream's contract:
## the holder is the actor's `inventory`, the actor itself, or the "inventory" group node,
## whichever exposes `marks` / `add_marks(n)` / `remove_marks(n)`. With no holder at all the
## balance lives in GameState.counters["marks"], so the economy works in tests and before
## the player exists. Every change emits EventBus.marks_changed unless the holder's own
## add/remove methods are used (they emit it themselves).

const COUNTER := "marks"


static func holder(actor: Object) -> Object:
	if actor != null and is_instance_valid(actor):
		var inv: Variant = actor.get("inventory")
		if inv is Object and _holds_marks(inv):
			return inv
		if _holds_marks(actor):
			return actor
	var reg := Peers.inventory()
	if reg != null and _holds_marks(reg):
		return reg
	return null


static func _holds_marks(o: Object) -> bool:
	return ("marks" in o) or o.has_method("add_marks")


static func balance(actor: Object = null) -> int:
	var h := holder(actor)
	if h == null:
		return GameState.count(COUNTER)
	if "marks" in h:
		return int(h.get("marks"))
	if h.has_method("balance"):
		return int(h.call("balance"))
	return 0


static func can_pay(actor: Object, amount: int) -> bool:
	return amount <= 0 or balance(actor) >= amount


## Takes `amount` marks. False (and nothing taken) when the actor cannot pay.
static func pay(actor: Object, amount: int) -> bool:
	if amount <= 0:
		return true
	if not can_pay(actor, amount):
		return false
	var h := holder(actor)
	if h == null:
		GameState.inc(COUNTER, -amount)
		EventBus.marks_changed.emit(GameState.count(COUNTER), -amount)
		return true
	if h.has_method("remove_marks"):
		h.call("remove_marks", amount)
		return true
	var before := int(h.get("marks"))
	h.set("marks", before - amount)
	EventBus.marks_changed.emit(before - amount, -amount)
	return true


static func give(actor: Object, amount: int) -> void:
	if amount <= 0:
		return
	var h := holder(actor)
	if h == null:
		GameState.inc(COUNTER, amount)
		EventBus.marks_changed.emit(GameState.count(COUNTER), amount)
		return
	if h.has_method("add_marks"):
		h.call("add_marks", amount)
		return
	var before := int(h.get("marks"))
	h.set("marks", before + amount)
	EventBus.marks_changed.emit(before + amount, amount)
