extends Control
## Two columns and a counter between them: merchants, containers, corpses and chests all use
## this. With `prices` on it is a shop (DESIGN §5.14); with it off it is just moving things
## from one bag to another.
##
## setup({other: Inventory | Node, merchant_id, title, prices: bool, buy_mult, sell_mult}).
## Every sale emits EventBus.transaction(merchant_id, item_id, count, price, bought).

var other: Node = null
var merchant_id := ""
var title := "Trade"
var prices := true
var buy_mult := 1.0
var sell_mult := 0.45

var _bag: Node = null
var _mine_box: VBoxContainer
var _theirs_box: VBoxContainer
var _mine_marks: Label
var _theirs_marks: Label
var _note: Label


func setup(args: Dictionary) -> void:
	merchant_id = str(args.get("merchant_id", ""))
	other = args.get("other", null)
	title = str(args.get("title", title))
	prices = bool(args.get("prices", prices))
	buy_mult = float(args.get("buy_mult", buy_mult))
	sell_mult = float(args.get("sell_mult", sell_mult))
	if other == null and merchant_id != "":
		other = _find_merchant_bag()
	if is_inside_tree():
		_refresh()


func _find_merchant_bag() -> Node:
	# the economy stream will hand us the merchant's own bag; until it does, any Inventory
	# that is not the player's will do, so containers and review data both work
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
	if other == null:
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

## DESIGN §5.14 without the parts other streams own yet: base value, the merchant's own
## multiplier and what Speech buys you. Region, supply and disposition arrive with the
## economy stream and slot in here.
func price_of(item_id: String, count: int, buying: bool) -> int:
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
	_note.text = "Prices as they stand today." if prices else "Take what you like."
	_fill(_mine_box, _bag, true)
	_fill(_theirs_box, other, false)
	_mine_marks.text = "%s marks" % UiKit.marks(_marks(_bag))
	_theirs_marks.text = ("%s marks" % UiKit.marks(_marks(other))) if prices else ""


func _marks(bag: Node) -> int:
	if bag and is_instance_valid(bag) and bag.get("marks") != null:
		return int(bag.get("marks"))
	return 0


func _fill(box: VBoxContainer, bag: Node, mine: bool) -> void:
	for child in box.get_children():
		child.queue_free()
	if bag == null or not is_instance_valid(bag) or not bag.has_method("items"):
		box.add_child(UiKit.wrapped("Nothing here.", "Journal"))
		return
	var items: Array = bag.call("items")
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
		b.pressed.connect(func() -> void: _move(uid, mine))
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

func _move(uid: int, mine: bool) -> void:
	var from: Node = _bag if mine else other
	var to: Node = other if mine else _bag
	if from == null or to == null or not from.has_method("find"):
		return
	var stack: Object = from.call("find", uid)
	if stack == null:
		return
	var item_id := str(stack.get("id"))
	var price := price_of(item_id, 1, not mine)
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
		EventBus.transaction.emit(merchant_id, item_id, 1, price, not mine)
	_refresh()


func _take_all() -> void:
	if other and other.has_method("transfer_all_to") and _bag:
		other.call("transfer_all_to", _bag)
	_refresh()
