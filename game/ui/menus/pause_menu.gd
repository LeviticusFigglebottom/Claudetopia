extends Control
## The pause page: where you are, what time it is, and the ways out.

const ENTRIES := [
	["Go on", "resume", "bell"],
	["What you carry", "inventory", "coin"],
	["The journal", "journal", "quest"],
	["The chart", "map", "map"],
	["What you have learned", "skills", "book"],
	["How to move and fight", "controls", "book"],
	["Settings", "settings", "settings"],
	["How it began", "opening", "eye"],
	["Write it down", "save", "save"],
	["Take it up again", "load", "load"],
	["Leave for the title", "quit", "hearth"],
]

var _buttons: Array[Control] = []


func setup(_args: Dictionary) -> void:
	pass


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.dim(0.66))
	_build()


func _build() -> void:
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := UiKit.panel("FramedPanel")
	panel.custom_minimum_size = Vector2(460, 0)
	centre.add_child(panel)
	var col := UiKit.column(6)
	panel.add_child(col)

	var region := ContentDB.get_or_empty(GameState.current_region_id)
	col.add_child(UiKit.label(str(region.get("name", "Wickmere")), "Title", HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UiKit.label(WorldClock.formatted(), "Small", HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UiKit.divider())

	for e in ENTRIES:
		# the opening again, only where there is one to watch and a world to watch it in
		if str(e[1]) == "opening" and not CinematicPlayer.can_replay():
			continue
		var b := UiKit.button(str(e[0]), "FlatButton")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.icon = ThemeBuilder.icon(str(e[2]))
		b.expand_icon = true
		b.custom_minimum_size = Vector2(0, 40)
		var what := str(e[1])
		b.pressed.connect(func() -> void: _choose(what))
		col.add_child(b)
		_buttons.append(b)
		UiKit.ink_in(b, 0.025 * _buttons.size(), 0.22)
	UiKit.focus_chain(_buttons)
	if not _buttons.is_empty():
		_buttons[0].grab_focus()
	UiKit.ink_in(panel, 0.0, 0.3)


func _choose(what: String) -> void:
	match what:
		"resume":
			UI.close("pause")
		"save":
			UI.open("save_load", {"mode": "save"})
		"load":
			UI.open("save_load", {"mode": "load"})
		"opening":
			# the menus close and unpause first; the replay puts everything back when it ends
			UI.close_all()
			CinematicPlayer.replay()
		"quit":
			if await UI.confirm("Leave for the title?",
					"Anything you have not written down will go quiet.", "Leave", "Stay"):
				UI.close_all()
				get_tree().paused = false
				get_tree().change_scene_to_file("res://ui/menus/main_menu.tscn")
		_:
			UI.open(what)
