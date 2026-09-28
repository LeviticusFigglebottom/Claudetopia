extends TestCase
## The "Size of the UI" (triage 28): the setting scales the whole canvas (Settings.apply_ui_scale:
## the root window's content_scale_factor over the project's canvas_items stretch from 1280x720),
## so at 1.4 a 1280x720 screen is laid out on 914x514 and drawn 1.4 times as large. Every screen
## has to fit that canvas. This lays the main screens out on the canvas each size leaves at
## 1280x720 (0.8: 1600x900, 1.0: 1280x720, 1.4: 914x514), with believable state (the UI review
## harness's), and asserts every visible Button, Label, LineEdit and slider is on the screen, or
## in a scroll area that is on the screen and not squeezed shut, as the Naming's own test does.

const FAKES := "res://tools_gd/ui_review_fakes.gd"
const NAMING := "res://ui/character/naming.tscn"
const SCALES := [0.8, 1.0, 1.4]
const BASE := Vector2(1280.0, 720.0)

var fakes: Node
var _state_was: Dictionary = {}
var _quests_was: Dictionary = {}
var _scale_was: Variant = 1.0


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	_state_was = GameState.to_save()
	_scale_was = Settings.get_value("accessibility", "ui_scale", 1.0)
	var log := _tree().get_first_node_in_group("quest_log")
	_quests_was = log.call("to_save") if log != null else {}
	fakes = (load(FAKES) as GDScript).new()
	_tree().root.add_child(fakes)
	# build() but the save slots: a test writes nobody's saves
	fakes.call("_world_state")
	fakes.call("_player")
	fakes.call("_bags")
	fakes.call("_progression")
	fakes.call("_quests")
	fakes.call("_dialogue")


func after_each() -> void:
	Settings.set_value("accessibility", "ui_scale", _scale_was)
	if is_instance_valid(fakes):
		fakes.free()
	var log := _tree().get_first_node_in_group("quest_log")
	if log != null and not _quests_was.is_empty():
		log.call("from_save", _quests_was)
	GameState.from_save(_state_was)
	WorldClock.running = true
	_tree().paused = false


## The canvas a 1280x720 window leaves the UI at this size.
static func canvas_for(scale: float) -> Vector2i:
	return Vector2i(floori(BASE.x / scale), floori(BASE.y / scale))


func test_the_setting_scales_the_whole_canvas() -> void:
	var root := _tree().root
	Settings.set_value("accessibility", "ui_scale", 1.4)
	assert_near(root.content_scale_factor, 1.4, 0.001, "the window's canvas is 1.4 times as large")
	Settings.set_value("accessibility", "ui_scale", 3.0)
	assert_near(root.content_scale_factor, Settings.UI_SCALE_MAX, 0.001, "and no more than the slider's end")
	Settings.set_value("accessibility", "ui_scale", 1.0)
	assert_near(root.content_scale_factor, 1.0, 0.001, "and back, at once")


func test_the_naming_fits_at_every_size() -> void:
	for scale: float in SCALES:
		var vp := _viewport(scale)
		var screen: Control = (load(NAMING) as PackedScene).instantiate()
		screen.set("world_scene", "")
		vp.add_child(screen)
		var pages: Array = ["who"]
		if not StyleDef.all_styles().is_empty():
			pages.append("how")
		for page: String in pages:
			screen.call("show_page", page)
			await _settle()
			_assert_fits(screen, vp, "the Naming, page %s" % page, scale)
		vp.free()


func test_the_pause_and_settings_menus_fit_at_every_size() -> void:
	var shots: Array = [["res://ui/menus/pause_menu.tscn", {}, "pause"]]
	for tab in ["Video", "Graphics", "Audio", "Controls", "Gameplay", "Accessibility"]:
		shots.append(["res://ui/menus/settings_menu.tscn", {"tab": tab}, "settings, " + tab])
	shots.append(["res://ui/menus/save_load.tscn", {"mode": "save"}, "save and load"])
	shots.append(["res://ui/menus/main_menu.tscn", {}, "the title"])
	await _each(shots)


func test_the_inventory_journal_and_chart_fit_at_every_size() -> void:
	var shots: Array = [["res://ui/inventory/inventory_screen.tscn", {"bag": fakes.get("bag"), "doll": fakes.get("doll")}, "inventory"]]
	for tab in 5:
		shots.append(["res://ui/journal/journal.tscn", {"tab": tab}, "journal, tab %d" % tab])
	shots.append(["res://ui/map/map_screen.tscn", {}, "the chart", 2])
	shots.append(["res://ui/skills/skills_screen.tscn", {}, "skills"])
	shots.append(["res://ui/sayings/sayings_screen.tscn", {}, "sayings"])
	await _each(shots)


func test_the_workbenches_books_and_trade_fit_at_every_size() -> void:
	var shots: Array = [["res://ui/books/book_reader.tscn", {"book_id": "core:book/the_falling_of_the_toll"}, "a book"]]
	for station in ["forge", "alembic", "name_table"]:
		shots.append(["res://ui/crafting/station_screen.tscn", {"station": station}, "the " + station])
	shots.append(["res://ui/trade/trade_screen.tscn", {"merchant_id": "core:npc/review_merchant"}, "trade"])
	await _each(shots)


func test_the_hud_and_a_conversation_fit_at_every_size() -> void:
	for scale: float in SCALES:
		var vp := _viewport(scale)
		var hud: Control = (load(UI.HUD_SCENE) as PackedScene).instantiate()
		hud.theme = UI.theme_for("warm")
		vp.add_child(hud)
		fakes.call("set_state", "default")
		if hud.has_method("review_state"):
			hud.call("review_state", "default")
		fakes.call("fire_hud_events", "default")
		var talk: Control = (load(UI.DIALOGUE_SCENE) as PackedScene).instantiate()
		talk.theme = UI.theme_for("warm")
		vp.add_child(talk)
		fakes.call("drive_dialogue", talk, "default")
		await _settle()
		_assert_fits(hud, vp, "the HUD", scale, 3)
		_assert_fits(talk, vp, "a conversation", scale, 2)
		vp.free()


# --- how ----------------------------------------------------------------------------------------

func _viewport(scale: float) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = canvas_for(scale)
	vp.disable_3d = true
	_tree().root.add_child(vp)
	return vp


func _settle() -> void:
	for i in 4:
		await _tree().process_frame


## Each [scene, args, what] at each size, opened as UI.open opens a menu.
func _each(shots: Array) -> void:
	for scale: float in SCALES:
		for shot: Array in shots:
			var vp := _viewport(scale)
			var screen: Control = (load(str(shot[0])) as PackedScene).instantiate()
			screen.theme = UI.theme_for("warm")
			screen.set_anchors_preset(Control.PRESET_FULL_RECT)
			vp.add_child(screen)
			if screen.has_method("setup"):
				screen.call("setup", shot[1])
			await _settle()
			_assert_fits(screen, vp, str(shot[2]), scale, int(shot[3]) if shot.size() > 3 else 4)
			vp.free()
			await _tree().process_frame


func _assert_fits(screen: Control, vp: SubViewport, what: String, scale: float, least := 4) -> void:
	var view := Rect2(Vector2.ZERO, Vector2(vp.size))
	var where := "%s at %.1f (%dx%d)" % [what, scale, vp.size.x, vp.size.y]
	var seen := 0
	var bad: Array[String] = []
	for n in screen.find_children("*", "Control", true, false):
		var c := n as Control
		if not (c is Button or c is Label or c is RichTextLabel or c is LineEdit or c is Range) or c is ScrollBar or not c.is_visible_in_tree():
			continue
		if c is Label and (c as Label).text.strip_edges().is_empty():
			continue
		if c is RichTextLabel and (c as RichTextLabel).get_parsed_text().strip_edges().is_empty():
			continue
		if c is Button and (c as Button).text.strip_edges().is_empty() and (c as Button).icon == null and c.get_child_count() == 0:
			continue
		if _clipped_away(c):
			continue
		seen += 1
		var r := c.get_global_rect()
		var name := "%s '%s'" % [c.get_class(), _words(c)]
		var scroll := _scroll_above(c)
		if scroll != null:
			var sr := scroll.get_global_rect()
			if not view.encloses(sr.grow(-0.5)):
				bad.append("%s: its scroll area %s leaves the screen" % [name, sr])
			elif sr.size.y < 40.0:
				bad.append("%s: its scroll area is squeezed to %.0f px" % [name, sr.size.y])
			continue
		if not view.encloses(r.grow(-0.5)):
			bad.append("%s: %s is not inside the screen" % [name, r])
	assert_true(seen >= least, "%s: only %d controls showing" % [where, seen])
	assert_true(bad.is_empty(), "%s: %d cut off:\n  %s" % [where, bad.size(), "\n  ".join(bad.slice(0, 40))])


## A control drawn inside a clipping parent that is not a scroll area (the chart's paper) is
## where that parent puts it, on purpose.
func _clipped_away(c: Control) -> bool:
	var p := c.get_parent()
	while p != null and p is Control:
		if (p as Control).clip_contents and not p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


func _scroll_above(c: Control) -> ScrollContainer:
	var p := c.get_parent()
	while p != null and p is Control:
		if p is ScrollContainer:
			return p
		p = p.get_parent()
	return null


func _words(c: Control) -> String:
	if c is Button:
		return (c as Button).text.left(24)
	if c is Label:
		return (c as Label).text.left(24)
	return c.name
