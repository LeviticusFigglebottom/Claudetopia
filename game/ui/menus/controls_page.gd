extends Control
## How to move and fight: every control on one page, as it is bound at this moment, with the
## pad's buttons when a pad is in use. Reached from the pause page. It reads; changing a binding
## is the Controls tab of the settings, one button away.
##
## Built from core/default_bindings.json's categories through Settings.binding_defs, like the
## Controls tab, so an action added there appears here with no code change. A few lines say what
## a binding cannot: a tap of Sprint rolls, a light stick walks, looking is the mouse.

## Things the bindings list cannot say on their own: [category, words, keyboard, pad].
const NOTES := [
	["Movement", "Look about", "mouse", "right stick"],
]

var _content: VBoxContainer


func setup(_args: Dictionary) -> void:
	pass


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.dim(0.66))
	UI.input_device_changed.connect(_on_input_device_changed)
	_build()


func _on_input_device_changed(_pad: bool) -> void:
	for c in get_children():
		if c is CenterContainer:
			remove_child(c)
			c.queue_free()
	_build()


func _build() -> void:
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := UiKit.panel("FramedPanel")
	panel.custom_minimum_size = Vector2(720, 0)
	centre.add_child(panel)
	var col := UiKit.column(6)
	panel.add_child(col)
	col.add_child(UiKit.label("How to move and fight", "Title", HORIZONTAL_ALIGNMENT_CENTER))
	var pad := UI.using_gamepad
	col.add_child(UiKit.label("as bound now, for the %s" % ("pad" if pad else "keyboard and mouse"),
			"Small", HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UiKit.divider())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(680, 460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_content = UiKit.column(2)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)

	var category := ""
	for def in Settings.binding_defs:
		var this_category := str(def.get("category", ""))
		if this_category != category:
			_notes_for(category, pad)
			category = this_category
			_content.add_child(UiKit.label(category, "Heading"))
		var action := str(def.get("action", ""))
		# the walk is said in the notes; an action with nothing on this device (looking about
		# with the right stick, on the keyboard) would show the other device's button
		if action == "walk" or not _bound_on(action, pad):
			continue
		_content.add_child(_line(str(def.get("label", action)), Settings.prompt_for(action, pad)))
	_notes_for(category, pad)

	col.add_child(UiKit.divider())
	var buttons := UiKit.row(12)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	var change := UiKit.button("Change a binding")
	change.pressed.connect(_on_change_pressed)
	buttons.add_child(change)
	var back := UiKit.button("Back")
	back.pressed.connect(_on_back_pressed)
	buttons.add_child(back)
	col.add_child(buttons)
	UiKit.focus_chain([change, back], false)
	back.grab_focus()
	UiKit.ink_in(panel, 0.0, 0.3)


## The lines a category's bindings cannot say on their own, after them.
func _notes_for(category: String, pad: bool) -> void:
	for n in NOTES:
		if str(n[0]) == category:
			_content.add_child(_line(str(n[1]), str(n[3] if pad else n[2])))
	if category != "Movement":
		return
	if not pad and Player.sprint_taps_roll_setting():
		_content.add_child(_line("Roll", "tap %s" % Settings.prompt_for("sprint", false)))
	_content.add_child(_line("Walk", "tilt the stick a little" if pad else
			"hold %s" % Settings.prompt_for("walk", false)))


func _bound_on(action: String, pad: bool) -> bool:
	for s: String in Settings.bindings.get(action, []):
		if s.begins_with("joy") == pad:
			return true
	return false


func _line(words: String, keys: String) -> HBoxContainer:
	var row := UiKit.row(14)
	row.custom_minimum_size = Vector2(0, 30)
	var l := UiKit.label(words, "Body")
	l.custom_minimum_size = Vector2(360, 0)
	row.add_child(l)
	var k := UiKit.label(keys, "Emphasis")
	k.add_theme_color_override("font_color", ThemeBuilder.colour("accent", "warm"))
	row.add_child(k)
	return row


func _on_change_pressed() -> void:
	UI.open("settings", {"tab": 2})


func _on_back_pressed() -> void:
	UI.close("controls")
