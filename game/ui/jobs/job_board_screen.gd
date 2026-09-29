extends Control
## The day's notices (DESIGN §5.15). A charter-board in Tollmere, a notice post nailed to a
## barn in Merrowby: the same paper either way, because what is interesting about a board is
## the work on it and not the wood.
##
## `JobBoard` could always list the day's work and hand a parcel over — `offers()`, `take()`
## and `deliver()` are all tested — and no screen ever showed it, because nothing in the game
## placed a board at all. This is the other half of that.
##
## A delivery already in hand shows what it is and where it goes, so the board is also the
## place you come back to when you have forgotten who the parcel was for.

const ROW_HEIGHT := 40

var _board: Node = null
var _actor: Node = null
var _list: VBoxContainer
var _title: Label
var _foot: Label


func setup(args: Dictionary) -> void:
	_board = args.get("board", null)
	_actor = args.get("actor", null)
	if _actor == null:
		_actor = get_tree().get_first_node_in_group("player")
	if is_inside_tree():
		_refresh()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.dim())
	_build()
	_refresh()


func _build() -> void:
	var page := UiKit.page("What Is Wanted")
	var frame: PanelContainer = page["frame"]
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(frame)
	UiFit.inset(frame, 180.0, 90.0)
	var body: VBoxContainer = page["body"]

	_title = UiKit.label("", "Subtitle")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_list = UiKit.column(6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	_foot = UiKit.label("", "Small")
	_foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_foot)

	var buttons := UiKit.row(8)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(buttons)
	var close := UiKit.button("Away", "FlatButton")
	close.pressed.connect(func() -> void: UI.close("job_board"))
	buttons.add_child(close)


func _refresh() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	if _board == null or not is_instance_valid(_board):
		_title.text = "Nothing"
		return
	_title.text = str(_board.get("display_name"))

	var carrying: Array = _board.get("taken")
	for job_v in carrying:
		var job: Dictionary = job_v
		_list.add_child(_row(
			"%s — for %s" % [str(job.get("title", "work")), _place_name(str(job.get("to", "")))],
			"%d marks" % int(job.get("pay", 0)), "Hand it over",
			func() -> void:
				_board.call("deliver", job, _actor)
				_refresh()))

	var offers: Array = _board.call("offers")
	var open_count := 0
	for job_v in offers:
		var job: Dictionary = job_v
		if bool(_board.call("has_taken", str(job.get("id", "")))):
			continue
		open_count += 1
		var where := str(job.get("to", ""))
		var text := str(job.get("title", "Work"))
		if where != "":
			text += " — to %s" % _place_name(where)
		_list.add_child(_row(text, "%d marks" % int(job.get("pay", 0)), "Take it",
			func() -> void:
				_board.call("take", offers.find(job_v), _actor)
				_refresh()))

	if open_count == 0 and carrying.is_empty():
		var empty := UiKit.label("Nothing is wanted today.", "Small")
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_list.add_child(empty)
	_foot.text = "The notices change with the day."


func _row(text: String, pay: String, action: String, on_press: Callable) -> Control:
	var row := UiKit.row(8)
	row.custom_minimum_size.y = ROW_HEIGHT
	var name_label := UiKit.label(text)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var pay_label := UiKit.label(pay, "Small")
	pay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pay_label.custom_minimum_size.x = 110
	row.add_child(pay_label)
	var button := UiKit.button(action, "FlatButton")
	button.pressed.connect(on_press)
	row.add_child(button)
	return row


func _place_name(place_id: String) -> String:
	if place_id.is_empty():
		return "somewhere"
	var def := ContentDB.get_or_empty(place_id)
	return str(def.get("name", Ids.name_of(place_id).capitalize().replace("_", " ")))
