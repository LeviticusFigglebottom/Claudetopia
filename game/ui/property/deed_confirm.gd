extends Control
## Buying a house (DESIGN §5.14). A deed, a price, and a plain question.
##
## The same board in two moods. Outside a house that is for sale it quotes the price and asks.
## Outside one you already own it is the landlord's board: the rent waiting, whether the place
## is to let, and the furnishings on offer for it — because §5.14 says "Furnishings bought" and
## there was nowhere in the game to buy one. `PropertyRegistry.add_furnishing()` was written,
## saved and tested, and nothing outside a test had ever called it.

var property_id := ""
var property_name := "A house"
var place := ""
var price := 0
var note := ""
var _registry: Node = null


func setup(args: Dictionary) -> void:
	property_id = str(args.get("property_id", ""))
	property_name = str(args.get("name", property_name))
	place = str(args.get("place", place))
	price = int(args.get("price", price))
	note = str(args.get("note", note))
	if is_inside_tree():
		_rebuild()


func registry() -> Node:
	if _registry == null or not is_instance_valid(_registry):
		_registry = get_tree().get_first_node_in_group("property")
	return _registry


## Whether this is the landlord's board rather than the buyer's question.
func owned() -> bool:
	var reg := registry()
	return reg != null and reg.has_method("is_owned") and bool(reg.call("is_owned", property_id))


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.dim(0.6))
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		if child.has_meta("deed"):
			child.queue_free()
	var centre := CenterContainer.new()
	centre.set_meta("deed", true)
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var panel := UiKit.panel("FramedPanel")
	panel.custom_minimum_size = Vector2(540, 0)
	centre.add_child(panel)
	var col := UiKit.column(12)
	panel.add_child(col)

	col.add_child(UiKit.icon_rect("hearth", 52))
	(col.get_child(0) as Control).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(UiKit.label("Your Own Door" if owned() else "A Deed", "Title",
		HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UiKit.divider())
	col.add_child(UiKit.wrapped(property_name, "Heading"))
	(col.get_child(3) as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if place != "":
		col.add_child(UiKit.label(place, "Small", HORIZONTAL_ALIGNMENT_CENTER))
	if note != "":
		col.add_child(UiKit.wrapped(note, "Journal"))
	col.add_child(UiKit.divider())

	if owned():
		_build_landlord(panel, col)
		return

	var marks := _marks()
	var afford := marks >= price
	var price_row := UiKit.row(10)
	price_row.alignment = BoxContainer.ALIGNMENT_CENTER
	price_row.add_child(UiKit.icon_rect("coin", 26))
	price_row.add_child(UiKit.label("%s marks" % UiKit.marks(price), "Title"))
	col.add_child(price_row)
	var have := UiKit.label("You have %s" % UiKit.marks(marks), "Small", HORIZONTAL_ALIGNMENT_CENTER)
	have.modulate = Color(1, 1, 1, 1.0 if afford else 0.6)
	col.add_child(have)

	var actions := UiKit.row(16)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(actions)
	var buy := UiKit.button("Take the key")
	buy.disabled = not afford
	buy.pressed.connect(_buy)
	actions.add_child(buy)
	var no := UiKit.button("Not today", "FlatButton")
	no.pressed.connect(func() -> void: UI.close("deed"))
	actions.add_child(no)
	UiKit.focus_chain([buy, no], false)
	if afford:
		buy.grab_focus()
	else:
		no.grab_focus()
	UiKit.ink_in(panel, 0.0, 0.3)


## The landlord's board. Rent first, because money waiting is what you came out for; then
## whether the place is to let; then what you can put in it.
func _build_landlord(panel: Control, col: VBoxContainer) -> void:
	var reg := registry()
	var marks := _marks()
	col.add_child(UiKit.label("You have %s marks" % UiKit.marks(marks), "Small",
		HORIZONTAL_ALIGNMENT_CENTER))

	var actions := UiKit.row(12)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(actions)
	var focus: Array = []

	var due := int(reg.call("rent_due", property_id)) if reg.has_method("rent_due") else 0
	if due > 0:
		var collect := UiKit.button("Collect %s marks of rent" % UiKit.marks(due))
		collect.pressed.connect(func() -> void:
			reg.call("collect_rent", get_tree().get_first_node_in_group("player"), property_id)
			_rebuild())
		actions.add_child(collect)
		focus.append(collect)

	var is_let := bool(reg.call("is_let", property_id)) if reg.has_method("is_let") else false
	var rent_per_day := PropertyRegistry.rent_per_day(property_id)
	var let_button := UiKit.button("Take it off the market" if is_let
		else "Put it to let (%s marks a day)" % UiKit.marks(rent_per_day), "FlatButton")
	let_button.pressed.connect(func() -> void:
		reg.call("set_let", property_id, not is_let)
		_rebuild())
	actions.add_child(let_button)
	focus.append(let_button)

	col.add_child(UiKit.divider())
	col.add_child(UiKit.label("Furnishings", "Heading", HORIZONTAL_ALIGNMENT_CENTER))
	var already: Array = reg.call("furnishings", property_id) if reg.has_method("furnishings") else []
	var rows := UiKit.column(6)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UiKit.scroll(rows))
	var offered := 0
	for def in PropertyRegistry.all_furnishings():
		var item_id := str(def["id"])
		var in_place := already.has(item_id)
		var cost := PropertyRegistry.furnishing_price(item_id)
		var row := UiKit.row(8)
		var name_label := UiKit.label(str(def.get("name", item_id)))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		row.add_child(UiKit.label("%s marks" % UiKit.marks(cost), "Small",
			HORIZONTAL_ALIGNMENT_RIGHT))
		if in_place:
			row.add_child(UiKit.label("in the house", "Small"))
		else:
			offered += 1
			var buy := UiKit.button("Buy it", "FlatButton")
			buy.disabled = marks < cost
			buy.pressed.connect(func() -> void: _buy_furnishing(item_id))
			row.add_child(buy)
			focus.append(buy)
		rows.add_child(row)
	if offered == 0:
		rows.add_child(UiKit.label("The house wants for nothing.", "Small",
			HORIZONTAL_ALIGNMENT_CENTER))

	var away := UiKit.button("Away", "FlatButton")
	away.pressed.connect(func() -> void: UI.close("deed"))
	col.add_child(away)
	focus.append(away)
	UiKit.focus_chain(focus, true)
	if not focus.is_empty():
		(focus[0] as Control).grab_focus()
	UiKit.ink_in(panel, 0.0, 0.3)


## Buying a furnishing goes through the registry, which takes the marks and records it against
## the property so the save keeps it and `HouseInterior` puts it in the room.
func _buy_furnishing(item_id: String) -> void:
	var reg := registry()
	if reg == null or not reg.has_method("buy_furnishing"):
		Log.warn("UI", "no PropertyRegistry to buy %s through" % item_id)
		return
	reg.call("buy_furnishing", get_tree().get_first_node_in_group("player"), property_id, item_id)
	_rebuild()


func _marks() -> int:
	var bag := get_tree().get_first_node_in_group("inventory")
	if bag and is_instance_valid(bag) and bag.get("marks") != null:
		return int(bag.get("marks"))
	return 0


## Buying goes through `PropertyRegistry`, which is the thing that knows what owning a house
## means: the deed in your bag, the key with it, the door and the bed and the chest claimed in
## your name so taking your own things is not theft, and rent owed by the day. This screen used
## to take the marks itself, set a flag called `owns:<id>` that nothing else reads, and emit
## the purchase signal — a second kind of ownership that left the registry, and therefore
## `property.owns()`, saying you did not own it.
func _buy() -> void:
	var reg := get_tree().get_first_node_in_group("property")
	var player := get_tree().get_first_node_in_group("player")
	if reg != null and reg.has_method("buy"):
		var result: Dictionary = reg.call("buy", player, property_id)
		if not bool(result.get("ok", false)):
			UI.close("deed")
			return
		EventBus.emit_notify("%s is yours." % property_name, "quest")
		UI.close("deed")
		return
	# No registry in the tree — the UI review and its made-up save. Say what happened rather
	# than pretending a house changed hands.
	Log.warn("UI", "deed screen bought %s with no PropertyRegistry to record it" % property_id)
	UI.close("deed")
