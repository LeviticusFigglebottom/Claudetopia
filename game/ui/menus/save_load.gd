extends Control
## Saving and loading (DESIGN §5.18). A slot says where you were, what day it was, what time
## of day, and how long you have been at it, because that is what tells one from another.

const SLOT_COUNT := 6

var mode := "save"          ## "save" or "load"
var from_menu := false
var _list: VBoxContainer
var _note: Label


func setup(args: Dictionary) -> void:
	mode = str(args.get("mode", "save"))
	from_menu = bool(args.get("from_menu", false))
	if is_inside_tree():
		_rebuild()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.dim())
	_build()
	_rebuild()


func _build() -> void:
	var page := UiKit.page("")
	var frame: PanelContainer = page["frame"]
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(frame)
	UiFit.inset(frame, 190.0, 46.0)
	var body: VBoxContainer = page["body"]
	var head := UiKit.label("", "Title", HORIZONTAL_ALIGNMENT_CENTER)
	head.name = "Head"
	body.add_child(head)
	_note = UiKit.label("", "Journal", HORIZONTAL_ALIGNMENT_CENTER)
	body.add_child(_note)
	body.add_child(UiKit.divider())
	_list = UiKit.column(5)
	body.add_child(UiKit.scroll(_list))
	var foot := UiKit.row(10)
	foot.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(foot)
	var close := UiKit.button("Back", "FlatButton")
	close.pressed.connect(func() -> void: UI.close("save_load"))
	foot.add_child(close)
	UiKit.ink_in(frame, 0.0, 0.32)


func _rebuild() -> void:
	var head := find_child("Head", true, false) as Label
	if head:
		head.text = "Write It Down" if mode == "save" else "Take It Up Again"
	_note.text = ("A name is only kept if somebody writes it down." if mode == "save"
			else "Everything that is spoken of, stays.")
	for child in _list.get_children():
		child.queue_free()

	var existing: Dictionary = {}
	for s in SaveSystem.list_slots():
		existing[str(s["slot"])] = s
	var rows: Array[Control] = []
	var names: Array[String] = []
	for special in ["quick", "auto"]:
		if existing.has(special):
			names.append(special)
	for i in SLOT_COUNT:
		names.append("slot%d" % (i + 1))
	for id in existing:
		if not names.has(str(id)):
			names.append(str(id))

	var i := 0
	for slot in names:
		var row := _slot_row(slot, existing.get(slot, {}))
		if row == null:
			continue
		_list.add_child(row)
		rows.append(row)
		UiKit.ink_in(row, 0.02 * i, 0.22)
		i += 1
	UiKit.focus_chain(rows)
	if not rows.is_empty():
		rows[0].grab_focus()


func _slot_row(slot: String, data: Dictionary) -> Control:
	var used := not data.is_empty()
	if mode == "load" and not used:
		return null
	var b := UiKit.button("", "FlatButton")
	b.custom_minimum_size = Vector2(0, 62)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func() -> void: _act(slot, used))

	var line := UiKit.row(14)
	line.set_anchors_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 12.0
	line.offset_right = -12.0
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(line)
	line.add_child(UiKit.icon_rect("save" if used else "load", 30,
			Color(1, 1, 1, 1.0 if used else 0.4)))

	var words := UiKit.column(0)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(words)
	words.add_child(UiKit.label(_slot_name(slot), "Emphasis"))
	if used:
		var summary: Dictionary = data.get("summary", {})
		var region := ContentDB.get_or_empty(str(summary.get("region", "")))
		var where := str(region.get("name", "somewhere between"))
		var day := int(summary.get("day", 1))
		var time := str(summary.get("time", ""))
		var played := UiKit.play_time(float(summary.get("play_time", 0.0)))
		words.add_child(UiKit.label("%s  ·  %s  ·  %s played" % [where, time if time != "" else "day %d" % day, played], "Small"))
	else:
		words.add_child(UiKit.label("empty", "Small"))

	if used:
		var stamp := UiKit.label(str(data.get("saved_at", "")).replace("T", "  "), "Tiny")
		line.add_child(stamp)
		var kill := UiKit.button("Erase", "FlatButton")
		kill.focus_mode = Control.FOCUS_NONE
		kill.pressed.connect(func() -> void: _erase(slot))
		line.add_child(kill)
		kill.mouse_filter = Control.MOUSE_FILTER_STOP
	return b


func _slot_name(slot: String) -> String:
	match slot:
		"quick": return "Quicksave"
		"auto": return "At the Hearthstone"
	return "Slot %s" % slot.trim_prefix("slot")


func _act(slot: String, used: bool) -> void:
	if mode == "save":
		if used and not await UI.confirm("Write over it?",
				"%s already has a name written in it." % _slot_name(slot), "Write over it", "Leave it"):
			return
		var err := SaveSystem.save_to_slot(slot)
		if err == OK:
			EventBus.emit_notify("Written down: %s." % _slot_name(slot), "info")
		else:
			EventBus.emit_notify("Not written down (%s)." % (SaveSystem.saves_held_by() if err == ERR_BUSY else error_string(err)), "warning")
		_rebuild()
		return
	if not used:
		return
	if from_menu:
		var menu := get_tree().current_scene
		if menu and menu.has_method("load_slot"):
			UI.close("save_load")
			menu.call("load_slot", slot)
			return
	UI.close_all()
	SaveSystem.load_from_slot(slot)


func _erase(slot: String) -> void:
	if not await UI.confirm("Let it go quiet?",
			"%s will be gone for good." % _slot_name(slot), "Erase it", "Keep it"):
		return
	SaveSystem.delete_slot(slot)
	_rebuild()
