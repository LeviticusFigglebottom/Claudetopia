extends Control
## The title screen: a drawn chart of the basin drifting behind the Cracked Toll's mark,
## the game's name in Cinzel, and five words to choose from.
##
## New Game goes to the Naming (ui/character/naming.tscn). Continue picks the newest slot.
## Nothing here needs the world to exist: if it does not (`WorldStatus`), the sheet says so plainly,
## with the command that builds it, and New Game, Continue and Load stay shut, because the way in
## used to open onto a grey void with the HUD up. If the world is there but Terrain3D cannot draw
## it, the sheet says that too, as plainly and with the way to the full terrain, and the way in
## stays open onto the coarse ground: one small line said it once, and a player never saw it.
## Only the coarse ground asked for with `--terrain=fallback` gets the small line.

const WORLD_SCENE := "res://world/world.tscn"
const NAMING_SCENE := "res://ui/character/naming.tscn"

const BACKDROP_INSET := Vector2(-150.0, -110.0)
## What the loading caption says while a saved name is read back in.
const LOADING_LINE := "The Roll is read again, and your name is in it."
## What the notice says under its account when the way in is still open onto the coarse ground.
const COARSE_FOOT := "New Game and Continue still go in, onto the coarse ground."

var _backdrop: TextureRect
var _buttons: Array[Control] = []
var _drift := 0.0
## `WorldStatus.current()` when the screen was built: whether there is a world to enter at all.
var world_status: Dictionary = {}
## The plain account of a world that is not built, or of the coarse ground the player did not ask
## for (see WorldNotice).
var notice: WorldNotice = null
## The one small line under the buttons when the coarse ground was asked for (`--terrain=fallback`).
var ground_line: Label = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	UI.apply_theme(self)
	UI.close_all()
	UI.hide_hud()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()
	UiKit.focus_first(self)


func _build() -> void:
	world_status = WorldStatus.current()
	var playable := bool(world_status.get("playable", false))
	var coarse := str(world_status.get("state", "")) == "fallback"
	# the ground will be the coarse one and the player did not ask for it: say so across the sheet
	var announce := coarse and bool(world_status.get("announce", false))
	# the notice takes the tagline's place and the room of the slot line, so the sheet tightens
	var compact := not playable or announce
	# --- the chart behind everything ---------------------------------------------------
	var back := ColorRect.new()
	back.color = ThemeBuilder.colour("paper_lo", "warm").darkened(0.35)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)

	# the drawn chart, not the player's one: the world map carries its region names in
	# Cinzel and they fight the title
	_backdrop = TextureRect.new()
	_backdrop.texture = ThemeBuilder.texture("menu_backdrop")
	_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.offset_left = -150.0
	_backdrop.offset_right = 150.0
	_backdrop.offset_top = -110.0
	_backdrop.offset_bottom = 110.0
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.modulate = Color(0.92, 0.88, 0.80, 1.0)
	add_child(_backdrop)

	# a sheet of paper laid over the chart, so the words are read and not hunted for
	var sheet := TextureRect.new()
	sheet.texture = ThemeBuilder.texture("torn_sheet")
	sheet.stretch_mode = TextureRect.STRETCH_SCALE
	sheet.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sheet.set_anchors_preset(Control.PRESET_CENTER)
	sheet.anchor_left = 0.5
	sheet.anchor_right = 0.5
	sheet.anchor_top = 0.5
	sheet.anchor_bottom = 0.5
	sheet.offset_left = -400.0 if compact else -368.0
	sheet.offset_right = 400.0 if compact else 368.0
	sheet.offset_top = -350.0 if compact else -340.0
	sheet.offset_bottom = 350.0 if compact else 330.0
	sheet.modulate = Color(1.0, 0.99, 0.96, 0.86)
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sheet)

	var vign := ColorRect.new()
	vign.set_anchors_preset(Control.PRESET_FULL_RECT)
	vign.color = Color(0.10, 0.08, 0.06, 0.22)
	vign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vign)

	# --- one centred column: mark, name, rule, tagline, the five words ------------------
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 0)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var mark := TextureRect.new()
	mark.texture = ThemeBuilder.texture("mark_bell")
	mark.custom_minimum_size = Vector2(0, 44 if compact else 124)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(mark)

	var title := UiKit.label("WICKMERE", "DisplayTitle", HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_font_size_override("font_size", 52 if compact else 68)
	root.add_child(title)

	var rule := UiKit.divider()
	rule.custom_minimum_size = Vector2(0, 18)
	var rule_row := CenterContainer.new()
	rule.custom_minimum_size.x = 440
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rule_row.add_child(rule)
	root.add_child(rule_row)

	var tagline: Label = null
	if not compact:
		tagline = UiKit.label("Everything that is spoken of, stays.", "Journal", HORIZONTAL_ALIGNMENT_CENTER)
		root.add_child(tagline)
		root.add_child(UiKit.spacer(34, true))
	else:
		# No world on disk: the first thing on the sheet is what is missing and how to build it,
		# and nothing below it leads into the world. The coarse ground: the same account, and the
		# way in stays open.
		root.add_child(UiKit.spacer(8, true))
		var holder := CenterContainer.new()
		var said := world_status.duplicate()
		if playable:
			said["foot"] = COARSE_FOOT
		notice = WorldNotice.panel(said, 680.0)
		holder.add_child(notice)
		root.add_child(holder)
		root.add_child(UiKit.spacer(14, true))

	UiKit.ink_in(mark, 0.10, 0.9)
	UiKit.ink_in(title, 0.35, 1.0)
	UiKit.ink_in(tagline, 0.75, 0.9)

	var latest := _latest_slot()
	var entries := [
		["New Game", _on_new_game, playable],
		["Continue", _on_continue, playable and not latest.is_empty()],
		["Load", func() -> void: UI.open("save_load", {"mode": "load", "from_menu": true}), playable and _has_any_slot()],
		["Settings", func() -> void: UI.open("settings", {"from_menu": true}), true],
		["Quit", _on_quit, true],
	]
	var i := 0
	for e in entries:
		var b := UiKit.button(str(e[0]), "TitleButton")
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.disabled = not bool(e[2])
		b.pressed.connect(e[1] as Callable)
		b.custom_minimum_size = Vector2(0, 38 if compact else 46)
		root.add_child(b)
		_buttons.append(b)
		UiKit.ink_in(b, 0.9 + i * 0.09, 0.55, 6.0)
		i += 1
	UiKit.focus_chain(_buttons)

	if not compact:
		# with no world there is nothing to continue into, and the notice needs the room
		root.add_child(UiKit.spacer(10, true))
		var note := UiKit.label(_slot_line(latest) if not latest.is_empty() else "No saved names yet.",
				"Small", HORIZONTAL_ALIGNMENT_CENTER)
		root.add_child(note)
		UiKit.ink_in(note, 1.5, 0.6)
	if coarse and not announce:
		# the coarse ground was asked for: one small line is enough
		ground_line = UiKit.label(str(world_status.get("title", "")) + " The ground will be drawn from the coarse map.",
				"Tiny", HORIZONTAL_ALIGNMENT_CENTER)
		ground_line.name = "GroundLine"
		ground_line.tooltip_text = str(world_status.get("detail", ""))
		ground_line.mouse_filter = Control.MOUSE_FILTER_PASS
		root.add_child(ground_line)
		UiKit.ink_in(ground_line, 1.6, 0.6)

	var version := UiKit.label("v%s" % ProjectSettings.get_setting("application/config/version", "0"), "Tiny")
	version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version.offset_left = -140.0
	version.offset_top = -34.0
	version.offset_right = -18.0
	version.offset_bottom = -12.0
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(version)


func _process(delta: float) -> void:
	# the chart drifts, the way a map does when you lean over it
	_drift += delta * 0.06
	if _backdrop:
		# `position` overrides the anchored rect, so drift from the inset, not from zero
		_backdrop.position = BACKDROP_INSET + Vector2(sin(_drift) * 44.0, cos(_drift * 0.63) * 26.0)


# --- actions ------------------------------------------------------------------------------

func _on_new_game() -> void:
	if not _world_is_there():
		return
	if not ResourceLoader.exists(NAMING_SCENE):
		EventBus.emit_notify("The Naming is not built yet.", "warning")
		return
	get_tree().change_scene_to_file(NAMING_SCENE)


## Asked again at the moment of going in, not only when the screen was drawn: the buttons are shut
## when there is no world, but the load screen calls `load_slot` itself.
func _world_is_there() -> bool:
	world_status = WorldStatus.current()
	if bool(world_status.get("playable", false)):
		return true
	EventBus.emit_notify("%s Run %s first." % [str(world_status.get("title", "")), WorldStatus.BUILD_COMMAND], "warning")
	return false


func _on_continue() -> void:
	var slot := _latest_slot()
	if slot.is_empty():
		return
	_enter_world({"load": slot})


func _on_quit() -> void:
	get_tree().quit()


## Called by the load screen when a slot is chosen from the title menu.
func load_slot(slot: String) -> void:
	_enter_world({"load": slot})


func _enter_world(args: Dictionary) -> void:
	if not _world_is_there():
		return
	if not ResourceLoader.exists(WORLD_SCENE):
		EventBus.emit_notify("The world is not built yet — %s is missing." % WORLD_SCENE, "warning")
		return
	if args.has("load"):
		GameState.set_flag("_pending_load_slot", str(args["load"]))
	for b in _buttons:
		b.disabled = true
	UI.fade_to_black(0.3, LOADING_LINE)
	await get_tree().create_timer(0.32).timeout
	get_tree().change_scene_to_file(WORLD_SCENE)


# --- slots --------------------------------------------------------------------------------

func _latest_slot() -> String:
	var slots := SaveSystem.list_slots()
	return str(slots[0]["slot"]) if slots.size() > 0 else ""


func _has_any_slot() -> bool:
	return SaveSystem.list_slots().size() > 0


func _slot_line(slot: String) -> String:
	for s in SaveSystem.list_slots():
		if s["slot"] == slot:
			var sm: Dictionary = s.get("summary", {})
			var region: String = str(ContentDB.get_or_empty(str(sm.get("region", ""))).get("name", "the road"))
			return "%s — %s, day %d" % [slot, region, int(sm.get("day", 1))]
	return slot
