extends Control
## Conversation (DESIGN §5.9): a nameplate, a line that writes itself onto the paper, and
## choices you can walk with a stick. Plus the gesture wheel, which is an input and not a
## menu: it opens over the world on `gesture` and emits EventBus.gesture_performed.
##
## It binds to whatever is in the group "dialogue_runner" and needs only:
##   signals line_shown(speaker, text, choices), choice_needed(choices), ended
##   method  choose(index)   (and advance() if it has one)

const CHARS_PER_SECOND := 52.0
const MAX_TYPE_SECONDS := 2.6
const WHEEL_RADIUS := 148.0

var _runner: Node = null
var _panel: PanelContainer
var _nameplate: PanelContainer
var _speaker: Label
var _body: RichTextLabel
var _choice_box: VBoxContainer
var _hint: Label
var _choices: Array = []
var _typing := false
var _tween: Tween

var _wheel: Control
var _wheel_items: Array[Dictionary] = []
var _wheel_index := 0
var _wheel_npc := ""
var _wheel_label: Label
var _wheel_desc: Label
var _page_was_visible := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_build_wheel()
	visible = false
	EventBus.dialogue_started.connect(func(_npc: String) -> void: _find_runner())
	EventBus.dialogue_ended.connect(func(_npc: String) -> void: _on_ended())
	_find_runner()


# --- construction ----------------------------------------------------------------------------

func _build() -> void:
	_panel = UiKit.panel("OakPanel")
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 150.0
	_panel.offset_right = -150.0
	_panel.offset_top = -258.0
	_panel.offset_bottom = -38.0
	# choices make the page taller: grow upward so it never runs off the screen
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_panel)

	var col := UiKit.column(10)
	_panel.add_child(col)

	# the speaker's name is a small plate pinned to the top of the page
	var plate_row := UiKit.row(0)
	col.add_child(plate_row)
	_nameplate = UiKit.panel("ChromePanel")
	_nameplate.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	plate_row.add_child(_nameplate)
	_speaker = UiKit.label("", "Heading")
	_nameplate.add_child(_speaker)

	_body = UiKit.rich("")
	_body.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	_body.custom_minimum_size = Vector2(0, 62)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_body)

	_choice_box = UiKit.column(4)
	col.add_child(_choice_box)

	_hint = UiKit.label("", "Tiny", HORIZONTAL_ALIGNMENT_RIGHT)
	_hint.modulate.a = 0.7
	col.add_child(_hint)



func _build_wheel() -> void:
	_wheel = Control.new()
	_wheel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wheel.visible = false
	_wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_wheel)

	var dim := UiKit.dim(0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wheel.add_child(dim)

	# the name sits in the middle of the ring; what it means sits below it
	_wheel_label = UiKit.label("", "Title", HORIZONTAL_ALIGNMENT_CENTER)
	_wheel_label.set_anchors_preset(Control.PRESET_CENTER)
	_wheel_label.anchor_left = 0.5
	_wheel_label.anchor_right = 0.5
	_wheel_label.anchor_top = 0.5
	_wheel_label.anchor_bottom = 0.5
	_wheel_label.offset_left = -170.0
	_wheel_label.offset_right = 170.0
	_wheel_label.offset_top = 192.0
	_wheel_label.offset_bottom = 238.0
	_wheel_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_wheel_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wheel.add_child(_wheel_label)

	_wheel_desc = UiKit.wrapped("", "Journal", 540)
	_wheel_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wheel_desc.set_anchors_preset(Control.PRESET_CENTER)
	_wheel_desc.anchor_left = 0.5
	_wheel_desc.anchor_right = 0.5
	_wheel_desc.anchor_top = 0.5
	_wheel_desc.anchor_bottom = 0.5
	_wheel_desc.offset_left = -280.0
	_wheel_desc.offset_right = 280.0
	_wheel_desc.offset_top = 242.0
	_wheel_desc.offset_bottom = 320.0
	_wheel_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wheel.add_child(_wheel_desc)


# --- runner ------------------------------------------------------------------------------------

func _find_runner() -> void:
	var found := get_tree().get_first_node_in_group("dialogue_runner")
	if found and found != _runner:
		bind_runner(found)


func bind_runner(runner: Node) -> void:
	if _runner and is_instance_valid(_runner):
		for pair in [["line_shown", _on_line], ["choice_needed", _on_choices], ["ended", _on_ended]]:
			if _runner.has_signal(pair[0]) and _runner.is_connected(pair[0], pair[1]):
				_runner.disconnect(pair[0], pair[1])
	_runner = runner
	if _runner == null:
		return
	if _runner.has_signal("line_shown"):
		_runner.connect("line_shown", _on_line)
	if _runner.has_signal("choice_needed"):
		_runner.connect("choice_needed", _on_choices)
	if _runner.has_signal("ended"):
		_runner.connect("ended", _on_ended)


func _on_line(speaker: String, text: String, choices: Array) -> void:
	visible = true
	_panel.visible = true
	_nameplate.visible = not speaker.is_empty()
	_speaker.text = speaker
	_choices = choices
	_clear_choices()
	_body.text = UiKit.markdown_lite(text)
	_body.visible_ratio = 0.0
	_typing = true
	_hint.text = "%s  skip" % UI.prompt_for("interact")
	UiKit.ink_in(_panel, 0.0, 0.30)
	if _nameplate.visible:
		UiKit.ink_in(_nameplate, 0.05, 0.30)
	var seconds := clampf(float(_body.get_total_character_count()) / CHARS_PER_SECOND, 0.25, MAX_TYPE_SECONDS)
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_body, "visible_ratio", 1.0, seconds)
	_tween.tween_callback(_finish_typing)


func _finish_typing() -> void:
	_typing = false
	_body.visible_ratio = 1.0
	if _choices.is_empty():
		_hint.text = "%s  go on" % UI.prompt_for("interact")
	else:
		_show_choices()


func _on_choices(choices: Array) -> void:
	_choices = choices
	if not _typing:
		_show_choices()


func _clear_choices() -> void:
	for child in _choice_box.get_children():
		child.queue_free()


func _show_choices() -> void:
	_clear_choices()
	_hint.text = ""
	var buttons: Array[Control] = []
	var i := 0
	for c in _choices:
		var text := str(c.get("text", "")) if typeof(c) == TYPE_DICTIONARY else str(c)
		var b := UiKit.button("%d.  %s" % [i + 1, text], "FlatButton")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var index := i
		b.pressed.connect(func() -> void: _pick(index))
		_choice_box.add_child(b)
		buttons.append(b)
		UiKit.ink_in(b, 0.04 * i, 0.25)
		i += 1
	UiKit.focus_chain(buttons)
	if not buttons.is_empty():
		buttons[0].grab_focus()


func _pick(index: int) -> void:
	if _runner and is_instance_valid(_runner) and _runner.has_method("choose"):
		_runner.call("choose", index)
	_clear_choices()


func _on_ended() -> void:
	_choices = []
	_clear_choices()
	_typing = false
	var tw := create_tween()
	tw.tween_property(_panel, "modulate:a", 0.0, 0.25)
	tw.parallel().tween_property(_nameplate, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func() -> void:
			visible = false
			_panel.modulate.a = 1.0
			_nameplate.modulate.a = 1.0)


# --- the gesture wheel ---------------------------------------------------------------------------

## Which drawn icon stands for a gesture. The gesture defs carry no icon of their own, so
## the wheel reads it from the gesture's name — and falls back to an open hand.
const GESTURE_ICONS := {
	"bow": "gesture", "wave": "gesture", "laugh": "rumour", "cheer": "bell",
	"dance": "hearth", "rude": "skull", "threaten": "sword", "flex": "shield",
	"point": "quest", "apologise": "amulet", "salute": "helm", "beckon": "gesture",
}


func gestures() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for def in ContentDB.all("gesture"):
		out.append(def)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var oa := int(a.get("order", 50))
			var ob := int(b.get("order", 50))
			if oa != ob:
				return oa < ob
			return str(a.get("name", "")) < str(b.get("name", "")))
	return out


func gesture_icon(def: Dictionary) -> String:
	if def.has("icon"):
		return str(def["icon"])
	return str(GESTURE_ICONS.get(Ids.name_of(str(def.get("id", ""))), "gesture"))


func open_gesture_wheel(npc_id := "") -> void:
	var defs := gestures()
	if defs.is_empty():
		return
	_wheel_npc = npc_id
	_wheel_items.clear()
	for child in _wheel.get_children():
		if child.has_meta("wheel_item"):
			child.queue_free()
	var count := defs.size()
	for i in count:
		var def: Dictionary = defs[i]
		var angle := -PI * 0.5 + TAU * float(i) / float(count)
		var node := UiKit.panel("ChromePanel")
		node.set_meta("wheel_item", true)
		node.custom_minimum_size = Vector2(76, 76)
		node.set_anchors_preset(Control.PRESET_CENTER)
		node.anchor_left = 0.5
		node.anchor_right = 0.5
		node.anchor_top = 0.5
		node.anchor_bottom = 0.5
		node.offset_left = cos(angle) * WHEEL_RADIUS - 38.0
		node.offset_right = cos(angle) * WHEEL_RADIUS + 38.0
		node.offset_top = sin(angle) * WHEEL_RADIUS - 38.0
		node.offset_bottom = sin(angle) * WHEEL_RADIUS + 38.0
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := UiKit.icon_rect(gesture_icon(def), 44)
		node.add_child(icon)
		_wheel.add_child(node)
		_wheel_items.append({"def": def, "node": node, "angle": angle})
		UiKit.ink_in(node, 0.03 * i, 0.22)
	_wheel_index = 0
	_wheel.visible = true
	visible = true
	# the page steps aside while the wheel is up; a gesture is its own beat
	_page_was_visible = _panel.visible
	_panel.visible = false
	_highlight_wheel()


func close_gesture_wheel() -> void:
	_wheel.visible = false
	_panel.visible = _page_was_visible
	_panel.modulate.a = 1.0
	visible = _panel.visible


func wheel_open() -> bool:
	return _wheel.visible


func _highlight_wheel() -> void:
	for i in _wheel_items.size():
		var node: Control = _wheel_items[i]["node"]
		var on := i == _wheel_index
		node.modulate = Color(1, 1, 1, 1) if on else Color(0.85, 0.85, 0.85, 0.62)
		node.scale = Vector2(1.12, 1.12) if on else Vector2.ONE
		node.pivot_offset = node.size * 0.5
	if _wheel_items.is_empty():
		return
	var def: Dictionary = _wheel_items[_wheel_index]["def"]
	_wheel_label.text = str(def.get("name", ""))
	_wheel_desc.text = str(def.get("description", ""))


func _perform_wheel() -> void:
	if _wheel_items.is_empty():
		return
	var def: Dictionary = _wheel_items[_wheel_index]["def"]
	EventBus.gesture_performed.emit(str(def.get("id", "")), _wheel_npc)
	close_gesture_wheel()


func _aim_wheel(direction: Vector2) -> void:
	if direction.length() < 0.35 or _wheel_items.is_empty():
		return
	var want := atan2(direction.y, direction.x)
	var best := 0
	var best_delta := TAU
	for i in _wheel_items.size():
		var delta := absf(Compass.wrap_delta(rad_to_deg(want - float(_wheel_items[i]["angle"]))))
		if delta < best_delta:
			best_delta = delta
			best = i
	if best != _wheel_index:
		_wheel_index = best
		_highlight_wheel()


func _unhandled_input(event: InputEvent) -> void:
	if _wheel.visible:
		if event.is_action_pressed("pause") or event.is_action_released("gesture"):
			if event.is_action_pressed("pause"):
				close_gesture_wheel()
				get_viewport().set_input_as_handled()
				return
		if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact") or event.is_action_pressed("gesture"):
			_perform_wheel()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseMotion:
			var centre := size * 0.5
			_aim_wheel((event as InputEventMouseMotion).position - centre)
		elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
			_wheel_index = (_wheel_index + 1) % _wheel_items.size()
			_highlight_wheel()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
			_wheel_index = (_wheel_index - 1 + _wheel_items.size()) % _wheel_items.size()
			_highlight_wheel()
			get_viewport().set_input_as_handled()
		return

	if _panel.visible and visible:
		if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
			if _typing:
				if _tween and _tween.is_valid():
					_tween.kill()
				_finish_typing()
				get_viewport().set_input_as_handled()
				return
			if _choices.is_empty() and _runner and is_instance_valid(_runner) and _runner.has_method("advance"):
				_runner.call("advance")
				get_viewport().set_input_as_handled()
				return
		for i in mini(_choices.size(), 9):
			if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_1 + i:
				_pick(i)
				get_viewport().set_input_as_handled()
				return

	if event.is_action_pressed("gesture") and not UI.is_menu_open():
		open_gesture_wheel(_wheel_npc)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not _wheel.visible:
		return
	var stick := Vector2(Input.get_axis("look_left", "look_right"), Input.get_axis("look_up", "look_down"))
	if stick.length() > 0.4:
		_aim_wheel(stick)
