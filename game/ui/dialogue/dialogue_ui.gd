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
## The speaker's quest business, beside their name: "?" and "Turn in", in the quest's colour.
var _plate_mark: Label
var _body: RichTextLabel
var _choice_box: VBoxContainer
var _hint: Label
var _choices: Array = []
var _typing := false
## The walking keys held down while answers are up, so a held key or a pushed stick moves the focus once.
var _steer_held: Dictionary = {}
var _tween: Tween
## The fade out on goodbye; a line that comes while it runs cancels it.
var _end_tween: Tween
## How long the page has stood up with no conversation behind it (see _process).
var _stale_s := 0.0
## The page is taken down when it has stood this long with no conversation running behind it.
const STALE_S := 0.4

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
	# the page is up only while a line is on it (_on_line); hidden by its parent alone, anything that
	# showed the parent showed an empty page (close_gesture_wheel, triage 41)
	_panel.visible = false
	# Method references, not closures: the bus outlives this screen, and a closure it holds
	# is not disconnected when the screen is freed.
	EventBus.dialogue_started.connect(_on_dialogue_started)
	EventBus.dialogue_ended.connect(_on_dialogue_ended)
	_find_runner()


func _on_dialogue_started(_npc: String) -> void:
	_find_runner()


## Whether a conversation is on the screen now, for a test or the flow probe to read what a player sees.
func on_screen() -> bool:
	return visible and _panel != null and _panel.visible


func _on_dialogue_ended(_npc: String) -> void:
	_on_ended()


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
	var plate := UiKit.row(10)
	_nameplate.add_child(plate)
	_speaker = UiKit.label("", "Heading")
	plate.add_child(_speaker)
	_plate_mark = UiKit.label("", "Small")
	_plate_mark.name = "QuestMark"
	_plate_mark.visible = false
	_plate_mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plate.add_child(_plate_mark)

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
	if speaker.strip_edges().is_empty() and text.strip_edges().is_empty() and choices.is_empty():
		# nothing to say and nothing to ask: no page (triage 41). The runner is moved on past it.
		call_deferred("_advance_runner")
		return
	_cancel_end_fade()
	_stale_s = 0.0
	visible = true
	_panel.visible = true
	_nameplate.visible = not speaker.is_empty()
	_speaker.text = speaker
	_show_plate_mark()
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
	# when any answer is a quest's, the others keep the icon's room, so the answers stay in a column
	var any_cue := _choices.any(func(c: Variant) -> bool: return typeof(c) == TYPE_DICTIONARY and (c as Dictionary).has("quest"))
	for c in _choices:
		var text := str(c.get("text", "")) if typeof(c) == TYPE_DICTIONARY else str(c)
		var cue: Dictionary = (c as Dictionary).get("quest", {}) if typeof(c) == TYPE_DICTIONARY else {}
		var b := UiKit.button(choice_label(i, text, cue), "FlatButton")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_dress_choice(b, cue, any_cue)
		var index := i
		b.pressed.connect(func() -> void: _pick(index))
		_choice_box.add_child(b)
		buttons.append(b)
		UiKit.ink_in(b, 0.04 * i, 0.25)
		i += 1
	UiKit.focus_chain(buttons)
	if not buttons.is_empty():
		buttons[0].grab_focus()


## An answer as the page writes it: "2.  [New quest]  Is there work?" for one that takes, moves
## on or hands in a quest; the tag says which (QuestCues.TAGS).
static func choice_label(i: int, text: String, cue: Dictionary) -> String:
	var tag := str(cue.get("tag", ""))
	if tag == "":
		return "%d.  %s" % [i + 1, text]
	return "%d.  [%s]  %s" % [i + 1, tag, text]


## What a quest answer's line under the answers says while it has the focus: "Turn in · The
## Relief · Main quest".
static func cue_line(cue: Dictionary) -> String:
	if cue.is_empty():
		return ""
	var parts: PackedStringArray = []
	var tag := str(cue.get("tag", ""))
	parts.append(tag if tag != "" else "About")
	parts.append(str(cue.get("name", "")))
	parts.append(str(cue.get("tier_word", "")))
	return "  ·  ".join(parts)


## A quest answer's mark: the quest's own icon in its tier's colour at the head of the line (dim
## for one that only speaks of a quest), and its quest named on hover and under the answers.
func _dress_choice(b: Button, cue: Dictionary, keep_room := false) -> void:
	if cue.is_empty():
		if keep_room:
			b.icon = ThemeBuilder.icon("quest")
			b.expand_icon = true
			b.add_theme_constant_override("icon_max_width", 20)
			for state in ["icon_normal_color", "icon_focus_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color"]:
				b.add_theme_color_override(state, Color(1, 1, 1, 0))
		return
	var kind := str(cue.get("kind", ""))
	var colour := QuestCues.tier_ink(str(cue.get("tier", "")))
	if kind == "about":
		colour.a = 0.55
	b.icon = ThemeBuilder.icon("bell" if kind == "turn_in" else "quest")
	b.expand_icon = true
	b.add_theme_constant_override("icon_max_width", 20)
	for state in ["icon_normal_color", "icon_focus_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color"]:
		b.add_theme_color_override(state, colour)
	if kind != "about":
		for state in ["font_color", "font_focus_color", "font_hover_color"]:
			b.add_theme_color_override(state, colour)
	var line := cue_line(cue)
	b.tooltip_text = line
	b.set_meta("quest_cue", cue)
	b.focus_entered.connect(func() -> void: _hint.text = line)
	b.mouse_entered.connect(func() -> void: _hint.text = line)
	b.focus_exited.connect(func() -> void: _hint.text = "")


## The speaker's quest business beside their name (QuestCues.state_now through the runner).
func _show_plate_mark() -> void:
	var state: Dictionary = {}
	if _runner != null and is_instance_valid(_runner) and _runner.has_method("speaker_quest_state"):
		state = _runner.call("speaker_quest_state")
	var word := QuestCues.state_word(str(state.get("state", "")))
	_plate_mark.visible = word != "" and _nameplate.visible
	if not _plate_mark.visible:
		_plate_mark.text = ""
		return
	_plate_mark.text = "%s  %s " % [QuestCues.state_glyph(str(state["state"])), word]
	_plate_mark.tooltip_text = "%s  ·  %s" % [str(state.get("name", "")), str(state.get("tier_word", ""))]
	_plate_mark.mouse_filter = Control.MOUSE_FILTER_PASS
	var colour := QuestCues.tier_ink(str(state.get("tier", "")))
	if str(state["state"]) == "in_progress":
		colour.a = 0.6
	_plate_mark.add_theme_color_override("font_color", colour)


## The marks the page shows now, for the tests and the review: {answers: [{text, kind, tier}],
## plate: the nameplate's mark or ""}.
func quest_marks() -> Dictionary:
	var answers: Array = []
	for b in _choice_box.get_children():
		if b.is_queued_for_deletion() or not (b is Button):
			continue
		var cue: Dictionary = b.get_meta("quest_cue", {})
		answers.append({"text": (b as Button).text, "kind": str(cue.get("kind", "")), "tier": str(cue.get("tier", ""))})
	return {"answers": answers, "plate": _plate_mark.text if _plate_mark.visible else ""}


func _pick(index: int) -> void:
	# taken once: the answers are gone before the runner moves on (it may put up the next ones at
	# once), so a second press of the same key, or its echo, takes nothing that was not offered
	_choices = []
	_clear_choices()
	if _runner and is_instance_valid(_runner) and _runner.has_method("choose"):
		_runner.call("choose", index)


func _on_ended() -> void:
	_choices = []
	_clear_choices()
	_typing = false
	_page_was_visible = false
	if not visible or not _panel.visible:
		_take_down()
		return
	_cancel_end_fade()
	_end_tween = create_tween()
	_end_tween.tween_property(_panel, "modulate:a", 0.0, 0.25)
	_end_tween.parallel().tween_property(_nameplate, "modulate:a", 0.0, 0.25)
	_end_tween.tween_callback(_take_down)


## The page off the screen and emptied, so nothing can bring it back up blank: the gesture wheel's
## close put back a page that had only been hidden by its parent, empty, with its plate showing, and
## no key took it down (triage 41: the empty box in the rain after the wake).
func _take_down() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_typing = false
	_choices = []
	_clear_choices()
	_panel.visible = false
	_panel.modulate.a = 1.0
	_nameplate.modulate.a = 1.0
	_speaker.text = ""
	_body.text = ""
	_hint.text = ""
	_stale_s = 0.0
	_page_was_visible = false
	if not _wheel.visible:
		visible = false


func _cancel_end_fade() -> void:
	if _end_tween and _end_tween.is_valid():
		_end_tween.kill()
	_end_tween = null
	_panel.modulate.a = 1.0
	_nameplate.modulate.a = 1.0


func _fading_out() -> bool:
	return _end_tween != null and _end_tween.is_valid() and _end_tween.is_running()


## Whether a conversation is running behind the page. A runner that cannot say is taken at its word.
func conversation_live() -> bool:
	if _runner == null or not is_instance_valid(_runner):
		return false
	return not _runner.has_method("is_running") or bool(_runner.call("is_running"))


func _advance_runner() -> void:
	if conversation_live() and _runner.has_method("advance"):
		_runner.call("advance")


## Leaves the conversation (Escape): the runner ends it, which takes the page down.
func _leave() -> void:
	if conversation_live() and _runner.has_method("stop"):
		_runner.call("stop")
	if visible and _panel.visible and not _fading_out():
		_on_ended()


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
	# the page steps aside while the wheel is up; a gesture is its own beat. Only a page that was on
	# the screen with a conversation behind it comes back after.
	_page_was_visible = visible and _panel.visible and conversation_live()
	_wheel.visible = true
	visible = true
	_panel.visible = false
	_highlight_wheel()


func close_gesture_wheel() -> void:
	_wheel.visible = false
	var back := _page_was_visible and conversation_live()
	_page_was_visible = false
	if back:
		_panel.visible = true
		_panel.modulate.a = 1.0
		visible = true
	else:
		_take_down()


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
		if event.is_action_pressed("pause"):
			# Escape leaves the conversation, whatever is on the page
			_leave()
			get_viewport().set_input_as_handled()
			return
		if not conversation_live():
			# a page with nobody behind it goes at the first key that would move it on
			if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
				_take_down()
				get_viewport().set_input_as_handled()
				return
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
		if _choosing() and _steer_choices(event):
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("gesture") and not UI.is_menu_open():
		open_gesture_wheel(_wheel_npc)
		get_viewport().set_input_as_handled()


## The failsafe: a page on the screen with no conversation running behind it, or with nothing on
## it at all, is taken down shortly (it can have no key that moves it on).
func _watch_page(delta: float) -> void:
	if not visible or not _panel.visible or _wheel.visible or _fading_out():
		_stale_s = 0.0
		return
	var empty := _speaker.text.strip_edges().is_empty() and _body.text.strip_edges().is_empty() and _choices.is_empty()
	if conversation_live() and not empty:
		_stale_s = 0.0
		return
	_stale_s += delta
	if _stale_s >= STALE_S:
		_take_down()


## Whether answers are up to be chosen from (the line has finished typing out).
func _choosing() -> bool:
	if _typing or _choices.is_empty():
		return false
	for b in _choice_box.get_children():
		if not b.is_queued_for_deletion():
			return true
	return false


## The answer the focus is on, as its index, or -1.
func focused_choice() -> int:
	var i := 0
	for b in _choice_box.get_children():
		if b.is_queued_for_deletion():
			continue
		if (b as Control).has_focus():
			return i
		i += 1
	return -1


## The walking keys choose among the answers and the interact key takes one, so a player whose
## hand is on W, S and E (or the stick and A) never has to reach for the arrows or the number
## row (playtest 6). The stick sends a stream of motion past its deadzone; a direction moves the
## focus once each time it is pushed, not once per event.
func _steer_choices(event: InputEvent) -> bool:
	for dir in [["move_forward", -1], ["move_back", 1]]:
		var action: String = dir[0]
		if not InputMap.has_action(action):
			continue
		if event.is_action_released(action):
			_steer_held.erase(action)
			continue
		if event.is_action_pressed(action, false) and not _steer_held.has(action):
			_steer_held[action] = true
			var buttons := _choice_box.get_children().filter(func(b: Node) -> bool: return not b.is_queued_for_deletion())
			var at := focused_choice()
			var next := clampi((0 if at < 0 else at + int(dir[1])), 0, buttons.size() - 1)
			(buttons[next] as Control).grab_focus()
			return true
	if event.is_action_pressed("interact", false):
		var at := focused_choice()
		_pick(at if at >= 0 else 0)
		return true
	return false


func _process(delta: float) -> void:
	_watch_page(delta)
	if not _wheel.visible:
		return
	var stick := Vector2(Input.get_axis("look_left", "look_right"), Input.get_axis("look_up", "look_down"))
	if stick.length() > 0.4:
		_aim_wheel(stick)
