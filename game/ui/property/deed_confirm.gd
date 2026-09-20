extends Control
## Buying a house (DESIGN §5.14). A deed, a price, and a plain question.

var property_id := ""
var property_name := "A house"
var place := ""
var price := 0
var note := ""


func setup(args: Dictionary) -> void:
	property_id = str(args.get("property_id", ""))
	property_name = str(args.get("name", property_name))
	place = str(args.get("place", place))
	price = int(args.get("price", price))
	note = str(args.get("note", note))
	if is_inside_tree():
		_rebuild()


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
	col.add_child(UiKit.label("A Deed", "Title", HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UiKit.divider())
	col.add_child(UiKit.wrapped(property_name, "Heading"))
	(col.get_child(3) as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if place != "":
		col.add_child(UiKit.label(place, "Small", HORIZONTAL_ALIGNMENT_CENTER))
	if note != "":
		col.add_child(UiKit.wrapped(note, "Journal"))
	col.add_child(UiKit.divider())

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
	var registry := get_tree().get_first_node_in_group("property")
	var player := get_tree().get_first_node_in_group("player")
	if registry != null and registry.has_method("buy"):
		var result: Dictionary = registry.call("buy", player, property_id)
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
