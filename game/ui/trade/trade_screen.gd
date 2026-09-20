extends Control
## Two columns and a counter between them: merchants, containers, corpses and chests all use
## this. With `prices` on it is a shop (DESIGN §5.14); with it off it is just moving things
## from one bag to another.
##
## setup({other: Inventory | Node, merchant_id, merchant: Merchant, title, prices, buy_mult,
## sell_mult}). Every sale emits EventBus.transaction(merchant_id, item_id, count, price, bought).
##
## When there is a live `Merchant` behind the counter — a shopkeeper, as against a chest or a
## corpse — the shop is *theirs*: their stock, their marks, their prices, their refusals.
## This screen used to be handed only an npc id and go looking for "any Inventory that is not
## the player's", which meant it traded against whatever bag happened to be first in the tree
## and priced everything off base value with a flat multiplier. `Merchant` has always priced by
## region, stock on hand, disposition, your Speech, the shopkeeper's own temper and how Hollow
## you have become, buys only what it deals in, pays out only what it can afford and refuses a
## Hollow customer in a Vale village — all of DESIGN §5.14, tested, and reached by nothing.

var other: Node = null
var merchant_id := ""
var title := "Trade"
var prices := true
var buy_mult := 1.0
var sell_mult := 0.45

var _bag: Node = null
var _merchant: Node = null
var _mine_box: VBoxContainer
var _theirs_box: VBoxContainer
var _mine_marks: Label
var _theirs_marks: Label
var _note: Label


func setup(args: Dictionary) -> void:
	merchant_id = str(args.get("merchant_id", ""))
	other = args.get("other", null)
	_merchant = args.get("merchant", null)
	if _merchant == null and merchant_id != "":
		_merchant = EconomyService.merchant_for(merchant_id)
	title = str(args.get("title", title))
	prices = bool(args.get("prices", prices))
	buy_mult = float(args.get("buy_mult", buy_mult))
	sell_mult = float(args.get("sell_mult", sell_mult))
	if _merchant == null and other == null and merchant_id != "":
		other = _find_merchant_bag()
	if is_inside_tree():
		_refresh()


## Only for what is not a shopkeeper: a review scene's made-up stall, or a bag handed over
## without one. A real merchant comes from `EconomyService` and never gets here.
func _find_merchant_bag() -> Node:
	for node in get_tree().get_nodes_in_group("merchant_bag"):
		return node
	var root := get_tree().root
	for node in root.find_children("*", "Inventory", true, false):
		if node != _bag:
			return node
	return null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.dim())
	_bag = get_tree().get_first_node_in_group("inventory")
	if _merchant == null and merchant_id != "":
		_merchant = EconomyService.merchant_for(merchant_id)
	if _merchant == null and other == null:
		other = _find_merchant_bag()
	_build()
	_refresh()


func _build() -> void:
	var page := UiKit.page("")
	var frame: PanelContainer = page["frame"]
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 80.0
	frame.offset_top = 40.0
	frame.offset_right = -80.0
	frame.offset_bottom = -40.0
	add_child(frame)
	var body: VBoxContainer = page["body"]

	var head := UiKit.label(_title_text(), "Title", HORIZONTAL_ALIGNMENT_CENTER)
	head.name = "Head"
	body.add_child(head)
	_note = UiKit.label("", "Journal", HORIZONTAL_ALIGNMENT_CENTER)
	body.add_child(_note)
	body.add_child(UiKit.divider())

	var columns := UiKit.row(24)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(columns)

	var mine := UiKit.column(4)
	mine.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(mine)
	mine.add_child(UiKit.label("Yours", "Heading", HORIZONTAL_ALIGNMENT_CENTER))
	_mine_box = UiKit.column(2)
	mine.add_child(UiKit.scroll(_mine_box))
	_mine_marks = UiKit.label("", "Emphasis", HORIZONTAL_ALIGNMENT_CENTER)
	mine.add_child(_mine_marks)

	columns.add_child(VSeparator.new())

	var theirs := UiKit.column(4)
	theirs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(theirs)
	theirs.add_child(UiKit.label("Theirs", "Heading", HORIZONTAL_ALIGNMENT_CENTER))
	_theirs_box = UiKit.column(2)
	theirs.add_child(UiKit.scroll(_theirs_box))
	_theirs_marks = UiKit.label("", "Emphasis", HORIZONTAL_ALIGNMENT_CENTER)
	theirs.add_child(_theirs_marks)

	var foot := UiKit.row(12)
	foot.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(foot)
	if not prices:
		var take_all := UiKit.button("Take everything")
		take_all.pressed.connect(_take_all)
		foot.add_child(take_all)
	var close := UiKit.button("Done", "FlatButton")
	close.pressed.connect(func() -> void: UI.close("trade"))
	foot.add_child(close)
	UiKit.ink_in(frame, 0.0, 0.32)


func _title_text() -> String:
	if merchant_id != "":
		var def := ContentDB.get_or_empty(merchant_id)
		if not def.is_empty():
			return str(def.get("name", title))
	return title


# --- pricing --------------------------------------------------------------------------------

## A shopkeeper prices their own stock. Without one — a chest, a corpse, a review scene — this
## is base value, a flat multiplier and what Speech buys you.
func price_of(item_id: String, count: int, buying: bool) -> int:
	if _merchant != null and is_instance_valid(_merchant):
		var unit := int(_merchant.call("buy_price_of" if buying else "sell_price_of", item_id))
		return maxi(1, unit * maxi(count, 1))
	var def := ContentDB.get_or_empty(item_id)
	var base := float(def.get("value", 0)) * float(count)
	var speech := 0.0
	var prog := get_tree().get_first_node_in_group("progression")
	if prog and prog.has_method("effective_skill"):
		speech = float(prog.call("effective_skill", "speech"))
	var haggle := clampf(1.3 - speech / 300.0, 0.9, 1.3)
	var price := base * (buy_mult * haggle if buying else sell_mult / maxf(haggle, 0.01) * 1.0)
	return maxi(1, roundi(price))


# --- the two columns --------------------------------------------------------------------------

func _refresh() -> void:
	var head := find_child("Head", true, false) as Label
	if head:
		head.text = _title_text()
	_note.text = _note_text()
	_fill(_mine_box, _rows(_bag), true)
	_fill(_theirs_box, _rows(_merchant if _merchant != null else other), false)
	_mine_marks.text = "%s marks" % UiKit.marks(_marks(_bag))
	_theirs_marks.text = ("%s marks" % UiKit.marks(_marks(_their_purse()))) if prices else ""


func _note_text() -> String:
	if not prices:
		return "Take what you like."
	if _refused():
		return "They will not trade with you."
	return "Prices as they stand today."


## A Hollow customer is turned away in a Vale village (DESIGN §5.11). The merchant has always
## known this and the screen never asked, so the shop opened and every purchase was refused
## one at a time with no explanation on the page.
func _refused() -> bool:
	return _merchant != null and is_instance_valid(_merchant) \
		and _merchant.has_method("refuses_trade") and bool(_merchant.call("refuses_trade"))


func _their_purse() -> Node:
	return _merchant if _merchant != null else other


func _marks(bag: Node) -> int:
	if bag and is_instance_valid(bag) and bag.get("marks") != null:
		return int(bag.get("marks"))
	return 0


## One shape for both sides. A bag's rows arrive with a uid and everything on them; a
## shopkeeper's stock is item ids and counts, so the rest is read from the pack.
func _rows(source: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if source == null or not is_instance_valid(source) or not source.has_method("items"):
		return out
	for entry in source.call("items") as Array:
		var row: Dictionary = entry
		if row.has("name"):
			out.append(row)
			continue
		var def := ContentDB.get_or_empty(str(row.get("item_id", "")))
		out.append({
			"item_id": str(row.get("item_id", "")),
			"name": str(def.get("name", row.get("item_id", ""))),
			"description": str(def.get("description", "")),
			"count": int(row.get("count", 1)),
			"uid": -1,
		})
	return out


func _fill(box: VBoxContainer, items: Array[Dictionary], mine: bool) -> void:
	for child in box.get_children():
		child.queue_free()
	if items.is_empty():
		box.add_child(UiKit.wrapped("Nothing here.", "Journal"))
		return
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]) < str(b["name"]))
	var buttons: Array[Control] = []
	var i := 0
	for it in items:
		var def := ContentDB.get_or_empty(str(it["item_id"]))
		var b := UiKit.button("", "FlatButton")
		b.custom_minimum_size = Vector2(0, 34)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = "%s\n%s" % [str(it["name"]), str(it.get("description", ""))]
		var uid := int(it["uid"])
		var item_id := str(it["item_id"])
		b.pressed.connect(func() -> void: _move(uid, item_id, mine))
		b.disabled = prices and _refused()
		var line := UiKit.row(8)
		line.set_anchors_preset(Control.PRESET_FULL_RECT)
		line.offset_left = 8.0
		line.offset_right = -8.0
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(line)
		line.add_child(UiKit.icon_rect(UiKit.item_icon_name(def), 22))
		var name_label := UiKit.label(str(it["name"]), "Body")
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.clip_text = true
		line.add_child(name_label)
		if int(it["count"]) > 1:
			line.add_child(UiKit.label("×%d" % int(it["count"]), "Small"))
		if prices:
			var price := price_of(str(it["item_id"]), 1, not mine)
			line.add_child(UiKit.label("%s m" % UiKit.marks(price), "Tiny"))
		box.add_child(b)
		buttons.append(b)
		if i < 16:
			UiKit.ink_in(b, 0.01 * i, 0.2)
		i += 1
	UiKit.focus_chain(buttons)


# --- moving things ------------------------------------------------------------------------------

func _move(uid: int, item_id: String, mine: bool) -> void:
	# A shopkeeper does their own trading: stock, marks, disposition and the reasons they say
	# no all live on the Merchant, and none of it is this screen's to reimplement.
	if _merchant != null and is_instance_valid(_merchant):
		var player := get_tree().get_first_node_in_group("player")
		var result: Dictionary = _merchant.call("sell" if mine else "buy", player, item_id, 1)
		if bool(result.get("ok", false)):
			EventBus.transaction.emit(merchant_id, item_id, int(result.get("count", 1)),
				int(result.get("price", 0)), not mine)
		_refresh()
		return
	var from: Node = _bag if mine else other
	var to: Node = other if mine else _bag
	if from == null or to == null or not from.has_method("find"):
		return
	var stack: Object = from.call("find", uid)
	if stack == null:
		return
	var moving := str(stack.get("id"))
	var price := price_of(moving, 1, not mine)
	if prices:
		var payer: Node = to if mine else _bag
		if payer and payer.get("marks") != null and int(payer.get("marks")) < price:
			EventBus.emit_notify("They have not got the marks for that." if mine else "You have not got the marks.", "warning")
			return
	if from.has_method("transfer_to"):
		from.call("transfer_to", to, uid, 1)
	if prices:
		if mine:
			if _bag.has_method("add_marks"):
				_bag.call("add_marks", price)
			if other.has_method("remove_marks"):
				other.call("remove_marks", price)
		else:
			if _bag.has_method("remove_marks"):
				_bag.call("remove_marks", price)
			if other.has_method("add_marks"):
				other.call("add_marks", price)
		EventBus.transaction.emit(merchant_id, moving, 1, price, not mine)
	_refresh()


func _take_all() -> void:
	if other and other.has_method("transfer_all_to") and _bag:
		other.call("transfer_all_to", _bag)
	_refresh()
