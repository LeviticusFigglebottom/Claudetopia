extends Control
## What is in the chest (DESIGN §5.10). A chest, a barrel, a cupboard, a dead man's pack: the
## same screen for all of them, because the interesting difference between them is what is
## inside and whose it was, not the furniture.
##
## Containers could be opened, could roll their loot and could be emptied, and nothing in the
## game ever showed you the contents — `take_all()` had no caller outside a test, so a chest in
## a cave was scenery. This is the screen that was missing.
##
## Taking things out of somebody else's chest is one theft rather than nine: the container
## keeps a tally while the screen is open and reports it when the screen closes.

const ROW_HEIGHT := 34
const CHROME_H := 316.0

var _container: Node = null
var _bag: Node = null
var _actor: Node = null
var _list: VBoxContainer
var _title: Label
var _foot: Label
var _whose: Label
var _take_all: Button
var _frame: PanelContainer


func setup(args: Dictionary) -> void:
	_container = args.get("container", null)
	_actor = args.get("actor", null)
	if _actor == null:
		_actor = get_tree().get_first_node_in_group("player")
	_bag = Inventory.for_actor(_actor) if _actor != null else null
	if is_inside_tree():
		_refresh()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.dim())
	_build()
	_refresh()


func _exit_tree() -> void:
	# The visit is over: whatever was taken is reported now, as one theft.
	if _container != null and is_instance_valid(_container) and _container.has_method("close_up"):
		_container.call("close_up", _actor)


func _build() -> void:
	var page := UiKit.page("What Is In It")
	_frame = page["frame"]
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.offset_left = 150.0
	_frame.offset_right = -150.0
	add_child(_frame)
	var body: VBoxContainer = page["body"]

	_title = UiKit.label("", "Subtitle")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_title)

	_whose = UiKit.label("", "Small")
	_whose.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_whose)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_list = UiKit.column(4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	_foot = UiKit.label("", "Small")
	_foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_foot)

	var buttons := UiKit.row(8)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(buttons)
	_take_all = UiKit.button("Take everything")
	_take_all.pressed.connect(_on_take_all)
	buttons.add_child(_take_all)
	var close := UiKit.button("Close", "FlatButton")
	close.pressed.connect(func() -> void: UI.close("container"))
	buttons.add_child(close)


# --- the contents ---------------------------------------------------------------------------

func _refresh() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	if _container == null or not is_instance_valid(_container):
		_title.text = "Nothing"
		return
	_title.text = _display_name()
	var inside: Node = _container.get("inventory")
	if inside == null:
		return

	var rows := 0
	var marks := int(inside.get("marks"))
	if marks > 0:
		_list.add_child(_row("%d marks" % marks, "", func() -> void:
			_container.call("take_marks", _actor)
			_refresh()))
		rows += 1
	for stack in inside.stacks():
		if stack == null:
			continue
		var s: ItemStack = stack
		var label := s.display_name()
		if s.count > 1:
			label = "%s ×%d" % [label, s.count]
		var worth := "%d marks" % s.value() if s.value() > 0 else ""
		_list.add_child(_row(label, worth, func() -> void:
			_container.call("take", s, _actor)
			_refresh()))
		rows += 1

	if rows == 0:
		var empty := UiKit.label("Empty.", "Small")
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_list.add_child(empty)
	_take_all.disabled = rows == 0
	_foot.text = _carry_line()
	_whose.text = "This is not yours." if _is_somebody_elses() else ""
	_size_to_content(rows)


## A chest with four things in it should not be a page of empty paper. The frame takes the
## height its contents need, between a sensible floor and most of the screen.
func _size_to_content(rows: int) -> void:
	if _frame == null:
		return
	# The chrome is the framed header, the two small lines, the buttons and the page's padding;
	# measured rather than guessed, because guessing it low puts a scrollbar on a chest with
	# four things in it.
	var wanted := CHROME_H + float(maxi(rows, 1)) * float(ROW_HEIGHT + 12)
	var available := size.y if size.y > 0.0 else 720.0
	var height := clampf(wanted, 280.0, available - 80.0)
	var margin := maxf((available - height) * 0.5, 40.0)
	_frame.offset_top = margin
	_frame.offset_bottom = -margin


## One line: what it is, what it is worth, and a button that takes it.
func _row(text: String, worth: String, on_take: Callable) -> Control:
	var row := UiKit.row(8)
	row.custom_minimum_size.y = ROW_HEIGHT
	var name_label := UiKit.label(text)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	if worth != "":
		var value_label := UiKit.label(worth, "Small")
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.custom_minimum_size.x = 96
		row.add_child(value_label)
	var take := UiKit.button("Take", "FlatButton")
	take.pressed.connect(on_take)
	row.add_child(take)
	return row


func _on_take_all() -> void:
	if _container == null or not is_instance_valid(_container):
		return
	_container.call("take_all", _actor)
	_refresh()


## What you are carrying, because the answer to "can I take this" is usually about weight.
func _carry_line() -> String:
	if _bag == null or not is_instance_valid(_bag):
		return ""
	var line := "You are carrying %.1f of %.1f" % [float(_bag.weight()), float(_bag.capacity())]
	if bool(_bag.is_overloaded()):
		line += " — overloaded"
	return line


func _display_name() -> String:
	if _container.has_method("display_name"):
		return str(_container.call("display_name"))
	var id := str(_container.get("container_id"))
	return Ids.name_of(id).capitalize().replace("_", " ") if id != "" else "A container"


func _is_somebody_elses() -> bool:
	return _container.has_method("is_owned") and bool(_container.call("is_owned"))
