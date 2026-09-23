class_name Flask
extends RefCounted
## The Hearth Flask (DESIGN §5.5: "Resting at a Hearthstone: full restore, respawn point set,
## refills flask charges"). One flask, carried in the bag like anything else, with its charges in
## the stack's own data so the save keeps them; a swallow is a committed drink on the belt (the
## player's DRINK state), and resting at a Hearthstone or coming back from death fills it again.
##
## The item's `flask` block says how it behaves: {charges, restore (a fraction of the drinker's
## greatest health), drink_time, takes_at (when in the drink the warmth lands)}. Numbers and the
## reasons for them: DECISIONS 2026-09-23.

const ITEM := "core:item/hearth_flask"
const DEFAULTS := {"charges": 3, "restore": 0.4, "drink_time": 1.0, "takes_at": 0.55}


static func is_flask(item_id: String) -> bool:
	return not item_id.is_empty() and ContentDB.get_or_empty(item_id).has("flask")


## The item's `flask` block over the defaults.
static func spec(item_id: String = ITEM) -> Dictionary:
	var out := DEFAULTS.duplicate()
	var block: Variant = ContentDB.get_or_empty(item_id).get("flask", {})
	if typeof(block) == TYPE_DICTIONARY:
		out.merge(block, true)
	return out


static func max_charges(stack: ItemStack) -> int:
	return int(spec(stack.id).get("charges", 3)) if stack != null else 0


## Charges left in a flask stack; a flask nobody has drunk from yet is full.
static func charges(stack: ItemStack) -> int:
	if stack == null:
		return 0
	return clampi(int(stack.data.get("charges", max_charges(stack))), 0, max_charges(stack))


## The first flask in a bag, or null.
static func find(bag: Inventory) -> ItemStack:
	if bag == null:
		return null
	for s in bag.stacks():
		if is_flask(s.id):
			return s
	return null


## Spends one charge. False (and nothing spent) when the flask is dry.
static func take_swallow(bag: Inventory, stack: ItemStack) -> bool:
	if stack == null or charges(stack) <= 0:
		return false
	stack.data["charges"] = charges(stack) - 1
	if bag != null:
		bag.notify_changed(stack)
	return true


## Fills every flask in the bag. Returns how many charges went back in.
static func refill(bag: Inventory) -> int:
	if bag == null:
		return 0
	var added := 0
	for s in bag.stacks():
		if not is_flask(s.id):
			continue
		var full := max_charges(s)
		added += full - charges(s)
		if int(s.data.get("charges", -1)) != full:
			s.data["charges"] = full
			bag.notify_changed(s)
	return added


## Every character carries one: a new one is given it with the rest of its kit, and a save from
## before the flask existed is given one the first time it is loaded. A flask given here goes on
## the first free belt slot, so the key that drinks it is there from the first fight; one already
## carried is left where its owner put it. Returns the flask.
static func ensure(bag: Inventory, doll: Equipment = null) -> ItemStack:
	if bag == null or not ContentDB.has(ITEM):
		return null
	var stack := find(bag)
	if stack != null:
		return stack
	stack = bag.add(ITEM, 1)
	if stack == null or doll == null:
		return stack
	for slot in Equipment.QUICK_SLOTS:
		if doll.quick_item(slot) == stack.id:
			return stack
	for slot in Equipment.QUICK_SLOTS:
		if doll.quick_item(slot).is_empty():
			doll.bind_quick(slot, stack.id)
			break
	return stack
