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
##
## Behind the sheet, once the menu is up, the country itself: held, slowly moving shots of the world
## (TitleVista, `core:cinematic/title`), which fade in over the chart when their country has come and
## go with the screen. Off in the Graphics tab (and on Low), and never headless, the chart stays.

const WORLD_SCENE := "res://world/world.tscn"
const NAMING_SCENE := "res://ui/character/naming.tscn"
## What this screen is called on EventBus.menu_opened. The music director brings the title's theme
## up on it, but the title is a scene of its own, not one of UI's menus, and nothing ever said it
## was up: the game's first minute was silent.
const SCREEN_ID := "main_menu"

const BACKDROP_INSET := Vector2(-150.0, -110.0)
## The menu's banner: a sheet hung in the left third, the full height of the screen, so the country
## behind the menu is the picture. Centred at 0.86 over the middle 46% of the screen, the sheet hid
## most of every shot of the title's vista. Left edge and width in the 1280-wide canvas: with its
## margins the sheet ends a third of the way across.
const BANNER_LEFT := 50.0
const BANNER_WIDTH := 330.0
## How far the sheet reaches past the column each side: the torn texture's ragged edge eats about
## a tenth of its width, and the title ran over it.
const SHEET_MARGIN := 44.0
## What the loading caption says while a saved name is read back in.
const LOADING_LINE := "The Roll is read again, and your name is in it."
## How wide safe mode's line under the buttons is wrapped (SafeMode.menu_line).
const SAFE_LINE_WIDTH := 262.0
## What the notice says under its account when the way in is still open onto the coarse ground.
const COARSE_FOOT := "New Game and Continue still go in, onto the coarse ground."

var _backdrop: TextureRect
## The dark paper under the chart. With the country behind the menu it is the dark each shot dips to.
var _back: ColorRect
## The country behind the menu, when there is one (`TitleVista.wanted()`).
var vista: TitleVista = null
var _buttons: Array[Control] = []
var _drift := 0.0
## `WorldStatus.current()` when the screen was built: whether there is a world to enter at all.
var world_status: Dictionary = {}
## The plain account of a world that is not built, or of the coarse ground the player did not ask
## for (see WorldNotice).
var notice: WorldNotice = null
## The one small line under the buttons when the coarse ground was asked for (`--terrain=fallback`),
## or the game started safely (SafeMode: then it says why, and how to have the full terrain back).
var ground_line: Label = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	UI.apply_theme(self)
	UI.close_all()
	UI.hide_hud()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	EventBus.menu_opened.emit(SCREEN_ID)
	StartupTrace.step("title: building the menu")
	_build()
	UiKit.focus_first(self)
	_start_vista()
	await get_tree().process_frame
	StartupTrace.step("title: the menu's first frame (%s)" % ("the country is asked for" if vista != null
			else "the chart only: safe mode" if SafeMode.active else "the chart only"))


## The country behind the menu: asked for after the menu is built and live, and shown when its first
## shot's country has come. The menu never waits for it.
func _start_vista() -> void:
	if not TitleVista.wanted():
		return
	vista = TitleVista.new()
	vista.name = "TitleVista"
	vista.dip = _back
	vista.chart = _backdrop
	add_child(vista)


## The menu is being used, whatever is dark behind it: the country behind it (TitleVista) is built a
## watched frame's few milliseconds at a time, never the curtain's (WorldPace).
func _enter_tree() -> void:
	WorldPace.menu_up += 1


func _exit_tree() -> void:
	WorldPace.menu_up -= 1
	EventBus.menu_closed.emit(SCREEN_ID)


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
	_back = back

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

	# a sheet of paper laid over the chart, so the words are read and not hunted for: hung as a
	# banner down the left third, which the title's shots keep quiet, with a soft shade behind it
	# that seats it on any shot; centred and wider only while it carries the plain account of a
	# world that is not there (compact), when there is no country behind it to show
	if not compact:
		var shade := TextureRect.new()
		var grad := Gradient.new()
		grad.set_color(0, Color(0.08, 0.06, 0.04, 0.55))
		grad.set_color(1, Color(0.08, 0.06, 0.04, 0.0))
		grad.add_point(0.55, Color(0.08, 0.06, 0.04, 0.3))
		var gt := GradientTexture2D.new()
		gt.gradient = grad
		gt.width = 256
		gt.height = 4
		gt.fill_from = Vector2(0.0, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		shade.texture = gt
		shade.stretch_mode = TextureRect.STRETCH_SCALE
		shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
		shade.offset_right = BANNER_LEFT + BANNER_WIDTH + SHEET_MARGIN + 260.0
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shade.name = "BannerShade"
		add_child(shade)
	var sheet := TextureRect.new()
	sheet.name = "Sheet"
	sheet.texture = ThemeBuilder.texture("torn_sheet")
	sheet.stretch_mode = TextureRect.STRETCH_SCALE
	sheet.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	if compact:
		sheet.set_anchors_preset(Control.PRESET_CENTER)
		sheet.anchor_left = 0.5
		sheet.anchor_right = 0.5
		sheet.anchor_top = 0.5
		sheet.anchor_bottom = 0.5
		sheet.offset_left = -400.0
		sheet.offset_right = 400.0
		sheet.offset_top = -350.0
		sheet.offset_bottom = 350.0
		sheet.modulate = Color(1.0, 0.99, 0.96, 0.86)
	else:
		sheet.set_anchors_preset(Control.PRESET_LEFT_WIDE)
		sheet.offset_left = BANNER_LEFT - SHEET_MARGIN
		sheet.offset_right = BANNER_LEFT + BANNER_WIDTH + SHEET_MARGIN
		sheet.offset_top = -30.0
		sheet.offset_bottom = 30.0
		# near opaque: the ink has to read over the brightest sky a shot can put behind it
		sheet.modulate = Color(1.0, 0.99, 0.96, 0.94)
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sheet)

	if compact:
		var vign := ColorRect.new()
		vign.set_anchors_preset(Control.PRESET_FULL_RECT)
		vign.color = Color(0.10, 0.08, 0.06, 0.22)
		vign.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(vign)

	# --- one column: mark, name, rule, tagline, the five words (down the banner) ---------
	var root := VBoxContainer.new()
	root.name = "Column"
	if compact:
		root.set_anchors_preset(Control.PRESET_FULL_RECT)
	else:
		root.set_anchors_preset(Control.PRESET_LEFT_WIDE)
		root.offset_left = BANNER_LEFT
		root.offset_right = BANNER_LEFT + BANNER_WIDTH
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 0)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var mark := TextureRect.new()
	mark.texture = ThemeBuilder.texture("mark_bell")
	# a large UI leaves a short canvas (514 lines at 1.4 on 1280x720, triage 28): a smaller mark
	var short := is_inside_tree() and get_viewport().get_visible_rect().size.y < 600.0
	mark.custom_minimum_size = Vector2(0, 44 if compact else (72 if short else 110))
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(mark)

	var title := UiKit.label("WICKMERE", "DisplayTitle", HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_font_size_override("font_size", 52 if compact else 50)
	root.add_child(title)

	var rule := UiKit.divider()
	rule.custom_minimum_size = Vector2(0, 18)
	var rule_row := CenterContainer.new()
	rule.custom_minimum_size.x = 440 if compact else 270
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rule_row.add_child(rule)
	root.add_child(rule_row)

	var tagline: Label = null
	if not compact:
		tagline = UiKit.label("Everything that is spoken of, stays.", "Journal", HORIZONTAL_ALIGNMENT_CENTER)
		root.add_child(tagline)
		# safe mode's few lines under the buttons take the room of the gap above them
		var safe_line := coarse and str(world_status.get("reason", "")) == "safe_mode"
		root.add_child(UiKit.spacer(10 if safe_line else (18 if short else 34), true))
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
		# said in the startup trace before it is done: a click that froze the game is the last line
		var word := str(e[0])
		b.pressed.connect(func() -> void: StartupTrace.step("title: %s pressed" % word))
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
	if coarse and not announce and str(world_status.get("reason", "")) == "safe_mode":
		# started safely: one line, wrapped to the banner, that says why and the way back
		# narrower than the column: the sheet's torn edge eats the ends of a line the column's width
		ground_line = UiKit.wrapped(SafeMode.menu_line(SafeMode.why), "Small", SAFE_LINE_WIDTH)
		ground_line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ground_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ground_line.name = "GroundLine"
		ground_line.tooltip_text = str(world_status.get("detail", ""))
		ground_line.mouse_filter = Control.MOUSE_FILTER_PASS
		root.add_child(ground_line)
		UiKit.ink_in(ground_line, 1.6, 0.6)
	elif coarse and not announce:
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
