extends Control
## Picking a pocket (DESIGN §5.13, Pickpocketing): what the mark carries, each thing with the chance
## of lifting it now, and a hand for each. The chance is Stealth's (Sneak and the thief's perks
## against the mark's awareness, the thing's worth and its weight), and every thing already lifted
## in one go makes the next harder. A lift that fails is a hand closing on your wrist: the mark
## reacts, the law hears of it (Stealth.pickpocket), and the screen closes. {pause} leaves it.
##
## Opened by EventBus.pickpocket_requested (UI), which Npc.interact asks for when you are crouched
## at somebody who has not noticed you.

const ROW_HEIGHT := 34
const WIDTH := 520.0

var mark: Node = null
var actor: Node = null
## Things lifted this visit (Pickpocketing.NERVE_PER_LIFT each).
var lifted := 0
var _list: VBoxContainer = null
var _status: Label = null
var _title: Label = null
var _state: Label = null
var _done := false


func setup(args: Dictionary) -> void:
	mark = args.get("mark", null)
	actor = args.get("actor", null)
	if actor == null:
		actor = get_tree().get_first_node_in_group("player")
	if _list != null:
		_refresh()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# the UI adds a screen before it hands it its arguments (setup), so it is drawn after
	_build.call_deferred()


func _build() -> void:
	add_child(UiKit.dim(0.5))
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := UiKit.panel("FramedPanel")
	panel.custom_minimum_size = Vector2(WIDTH, 0)
	centre.add_child(panel)
	var col := UiKit.column(12)
	panel.add_child(col)
	_title = UiKit.label("", "Title", HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_title)
	_state = UiKit.label("", "Small", HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_state)
	_list = UiKit.column(4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_list)
	_status = UiKit.wrapped(SocialContext.keys_in("Small things come easy; heavy or dear things don't. {key:pause} leaves it."), "Journal")
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_status)
	var leave := UiKit.button("Leave it", "FlatButton")
	leave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	leave.pressed.connect(_close)
	col.add_child(leave)
	_refresh()


func _refresh() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if mark == null or not is_instance_valid(mark):
		_title.text = "Nobody"
		return
	var who := str(mark.call("display_name")) if mark.has_method("display_name") else "Somebody"
	_title.text = "%s's Pockets" % who
	_state.text = _state_words()
	var buttons: Array = []
	var rows := Pickpocketing.contents(mark, actor, lifted)
	for r in rows:
		var row := UiKit.row(8)
		row.custom_minimum_size.y = ROW_HEIGHT
		var label := str(r["name"])
		if int(r["count"]) > 1:
			label = "%s ×%d" % [label, int(r["count"])]
		var name_label := UiKit.label(label)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var odds := UiKit.label("%d%%" % roundi(float(r["chance"]) * 100.0), "Small")
		odds.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		odds.custom_minimum_size.x = 64
		row.add_child(odds)
		var take := UiKit.button("Lift", "FlatButton")
		var id := str(r["id"])
		take.pressed.connect(func() -> void: lift(id))
		take.disabled = _done
		row.add_child(take)
		buttons.append(take)
		_list.add_child(row)
	if rows.is_empty():
		_list.add_child(UiKit.label("Nothing worth the risk.", "Small", HORIZONTAL_ALIGNMENT_CENTER))
	if not buttons.is_empty() and not _done:
		UiKit.focus_chain(buttons)
		_focus.call_deferred(buttons[0])


## A lift redraws the rows at once, so the button asked for may have gone by the time this runs.
func _focus(button: Control) -> void:
	if is_instance_valid(button) and button.is_inside_tree():
		button.grab_focus()


## How the mark is, in words: asleep, or unaware, and how much the last lift has stirred them.
func _state_words() -> String:
	var a := Pickpocketing.awareness_now(mark, lifted)
	var base := "Asleep" if Pickpocketing.is_asleep(mark) else "Unaware of you"
	if a >= DetectionMeter.SUSPICIOUS:
		return base + ", and stirring"
	if lifted > 0:
		return base + ", for now"
	return base


## One try at one thing (Pickpocketing.attempt). Returns its result.
func lift(item_id: String, rng: RandomNumberGenerator = null) -> Dictionary:
	if _done or mark == null or not is_instance_valid(mark):
		return {}
	var r := Pickpocketing.attempt(mark, actor, item_id, rng, lifted)
	if bool(r.get("ok", false)):
		lifted += 1
		_say("Taken.")
		_refresh()
	elif bool(r.get("caught", false)):
		_done = true
		_say("A hand closes on your wrist.")
		_refresh()
		_close_after(0.8)
	else:
		_refresh()
	return r


func _close_after(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout
	_close()


func _close() -> void:
	if UI.is_menu_open("pickpocket"):
		UI.close("pickpocket")


func _say(text: String) -> void:
	if _status != null:
		_status.text = text
