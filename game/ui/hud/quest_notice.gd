class_name QuestNotice
extends Control
## The quest notice near the top of the screen, under the compass (DESIGN §5.16): when a quest is
## taken, moves on or is finished, a plate says so the way Oblivion's journal updates do --
##
##     QUEST STARTED · FIRST LESSONS                 (the head, in the quest's colour)
##     Once, From Behind                             (the quest)
##     Pick the collector's strongbox, crouched      (what to do now, large)
##     Tomorrow is tithe-day, and Sauve wants ...    (why: the first line of the stage's journal)
##     J  Journal                                    (the key that opens the journal at it)
##
## The owner, of the small line it replaced: "almost every starter quest progresses from
## point-to-point with no clear reason why, or the bit that pops up is small and disappears".
## QuestNoticeQueue keeps the order and the time (held 6-10 s by its words, several in turn, none
## spent under a conversation, a film, a menu or the loading screen); this draws the one up now,
## sounds a page turned when one comes up, and keeps clear of the crosshair, the tracker and the
## dialogue box (it sits in the top quarter; the conversation's box is at the foot of the screen).

signal notice_shown(note: Dictionary)

## The plate's widest (px at the 1280x720 base), and the room it keeps from the tracker on the left.
const MAX_WIDTH := 600.0
const MIN_BESIDE_TRACKER := 470.0
const TOP := 78.0
## The tracker's right edge (HUD: 22 + QuestTracker.WIDTH) and the gap kept from it.
const TRACKER_RIGHT := 22.0 + QuestTracker.WIDTH
const TRACKER_GAP := 14.0
## A frame slower than this counts as this much of a notice's time: on a machine drawing a frame
## every few seconds a notice would otherwise be spent in two frames.
const MAX_STEP_S := 0.25
## How long after a notice goes the journal key still opens at its quest.
const RECENT_S := 30.0
const HEADS := {"started": "Quest started", "updated": "Journal updated", "complete": "Quest complete",
		"failed": "Quest failed", "plain": ""}

const INK := Color(0.96, 0.92, 0.83)
const INK_SOFT := Color(0.86, 0.81, 0.70)
const NAME_INK := Color(0.95, 0.80, 0.50)

var queue := QuestNoticeQueue.new()
## Whether the plate is wider than the room beside the tracker (a large UI): the HUD dims the
## tracker while it is up.
var over_tracker := false

## The quest the last notice was about and when it was last on the screen (Time.get_ticks_msec),
## so the journal key opens there (journal.gd reads recent_quest()).
static var _recent_quest := ""
static var _recent_ms := -1

var _plate: PanelContainer
var _head: Label
var _name: Label
var _objective: Label
var _why: Label
var _hint: Label
var _shown_key := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	get_viewport().size_changed.connect(_fit)
	_fit()
	Settings.changed.connect(_on_setting_changed)
	_apply_settings()
	_plate.modulate.a = 0.0
	_plate.visible = false


func _on_setting_changed(section: String, key: String, _value: Variant) -> void:
	if section == "gameplay" and key == "quest_notice_time":
		_apply_settings()


func _apply_settings() -> void:
	queue.hold_scale = clampf(float(Settings.get_value("gameplay", "quest_notice_time", 1.0)), 0.5, 2.0)


func _build() -> void:
	_plate = PanelContainer.new()
	_plate.name = "QuestNoticePlate"
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.set_anchors_preset(Control.PRESET_CENTER_TOP)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.075, 0.06, 0.045, 0.80)
	sb.border_color = Color(0.80, 0.64, 0.36, 0.75)
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 10
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	_plate.add_theme_stylebox_override("panel", sb)
	add_child(_plate)
	var col := UiKit.column(2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(col)
	_head = _line("Small", 13, INK_SOFT)
	_head.name = "Head"
	col.add_child(_head)
	_name = _line("Heading", 20, NAME_INK)
	_name.name = "QuestName"
	col.add_child(_name)
	_objective = _line("Emphasis", 23, INK)
	_objective.name = "Objective"
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective.max_lines_visible = 2
	col.add_child(_objective)
	_why = _line("Journal", 16, INK_SOFT)
	_why.name = "Why"
	_why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_why.max_lines_visible = 3
	_why.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(_why)
	_hint = _line("Tiny", 12, Color(INK_SOFT, 0.8))
	_hint.name = "Hint"
	col.add_child(_hint)


func _line(variation: String, font_px: int, colour: Color) -> Label:
	var l := UiKit.label("", variation, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_font_size_override("font_size", font_px)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## The plate's width and place on this canvas: beside the tracker when there is room, else wider
## and over it (the HUD dims the tracker for the while).
func _fit() -> void:
	if _plate == null:
		return
	var w := get_viewport_rect().size.x if is_inside_tree() else 1280.0
	var beside := w - 2.0 * (TRACKER_RIGHT + TRACKER_GAP)
	var width := minf(MAX_WIDTH, beside)
	over_tracker = beside < MIN_BESIDE_TRACKER
	if over_tracker:
		width = minf(MAX_WIDTH, w - 32.0)
	_plate.anchor_left = 0.5
	_plate.anchor_right = 0.5
	_plate.offset_left = -width * 0.5
	_plate.offset_right = width * 0.5
	_plate.offset_top = TOP
	_plate.offset_bottom = TOP
	_plate.custom_minimum_size = Vector2(width, 0.0)
	var inner := width - 52.0
	for l: Label in [_objective, _why]:
		l.custom_minimum_size = Vector2(inner, 0.0)


# --- the queue --------------------------------------------------------------------------------

## Puts a notice in line (see QuestNoticeQueue for its keys). It comes up at once when nothing is
## up and nothing has the screen.
## Whether a notice about `quest_id` is up now or waiting.
func has_quest(quest_id: String) -> bool:
	if str(queue.current().get("quest", "")) == quest_id:
		return true
	for n in queue.pending():
		if str(n.get("quest", "")) == quest_id:
			return true
	return false


func push(note: Dictionary) -> void:
	var replaced := queue.push(note)
	if replaced:
		_draw_current(false)
	_step(0.0)


## Whether something has the screen that a notice must not be spent under: the HUD hidden (a full
## menu, the opening, the title), a conversation, a film, a menu, the loading screen, a fade.
func screen_taken() -> bool:
	if not is_visible_in_tree():
		return true
	var tree := get_tree()
	for runner in tree.get_nodes_in_group("dialogue_runner"):
		if runner.has_method("is_running") and bool(runner.call("is_running")):
			return true
	for n in tree.get_nodes_in_group(CinematicPlayer.GROUP):
		if n.has_method("is_playing") and bool(n.call("is_playing")):
			return true
		# its black before the first shot, while the whole film's country is laid (seconds long):
		# a notice spent there was gone before the player had the screen
		if n.has_method("is_starting") and bool(n.call("is_starting")):
			return true
		if n.has_method("is_handing_over") and bool(n.call("is_handing_over")):
			return true
	if UI.is_menu_open() or UI.is_loading_shown() or UI.is_faded_out():
		return true
	return false


func _process(delta: float) -> void:
	_step(minf(delta, MAX_STEP_S))


func _step(dt: float) -> void:
	var changed := queue.step(dt, screen_taken())
	if changed:
		_draw_current(true)
	_show_ink()


## The plate at the ink the queue says, and the quest it is about remembered for the journal key.
func _show_ink() -> void:
	var note := queue.current()
	_plate.visible = not note.is_empty()
	_plate.modulate.a = queue.alpha()
	if not note.is_empty():
		_recent_quest = str(note.get("quest", ""))
		_recent_ms = Time.get_ticks_msec()


## Moves the notice clock on, in the steps a frame would take: for the tests.
func advance(seconds: float, blocked := false) -> void:
	var left := seconds
	while left > 0.0:
		var dt := minf(left, 0.1)
		if queue.step(dt, blocked):
			_draw_current(true)
		left -= dt
		_show_ink()


func _draw_current(fresh: bool) -> void:
	var note := queue.current()
	if note.is_empty():
		_shown_key = ""
		return
	var kind := str(note.get("kind", "updated"))
	var tier := str(note.get("tier", "side"))
	var head := str(HEADS.get(kind, "Journal updated"))
	var tier_word := QuestCues.tier_word(tier) if tier != "" else ""
	_head.text = ("%s  ·  %s" % [head, tier_word] if head != "" and tier_word != "" else head).to_upper()
	_head.add_theme_color_override("font_color", QuestCues.tier_colour(tier).lerp(Color.WHITE, 0.25))
	_head.visible = _head.text != ""
	_name.text = str(note.get("name", ""))
	_name.visible = _name.text != ""
	_objective.text = str(note.get("objective", ""))
	_objective.visible = _objective.text != ""
	_why.text = str(note.get("why", ""))
	_why.visible = _why.text != ""
	var quest := str(note.get("quest", ""))
	_hint.text = "%s   Journal" % _key_glyph() if quest != "" else ""
	_hint.visible = _hint.text != ""
	# the plate shrinks round its words again
	_plate.reset_size()
	_fit()
	var key := "%s|%s|%s" % [quest, kind, _objective.text]
	if key != _shown_key:
		# a page turned when one comes up; one taking the place of the one up a moment is not news twice
		if fresh:
			Foley.play_ui("ui_page_turn", -3.0)
		_shown_key = key
		notice_shown.emit(note)


## The journal's key as the active device names it ("J", or the pad's).
func _key_glyph() -> String:
	var pad := bool(UI.get("using_gamepad")) if UI != null else false
	return "[%s]" % Settings.prompt_for("journal", pad)


# --- what is shown, for the HUD, the journal and the tests -----------------------------------------

## The notice up now: {quest, kind, head, name, objective, why, hint}; {} when none is.
func shown() -> Dictionary:
	var note := queue.current()
	if note.is_empty():
		return {}
	return {"quest": str(note.get("quest", "")), "kind": str(note.get("kind", "")), "head": _head.text,
			"name": _name.text, "objective": _objective.text, "why": _why.text, "hint": _hint.text,
			"alpha": queue.alpha()}


## The plate's rect on the canvas (for the tests: clear of the crosshair).
func plate_rect() -> Rect2:
	return _plate.get_global_rect()


## The quest of the notice up now, or of the last one if it went less than RECENT_S ago; "" else.
static func recent_quest() -> String:
	if _recent_quest == "" or _recent_ms < 0 or Time.get_ticks_msec() - _recent_ms > int(RECENT_S * 1000.0):
		return ""
	return _recent_quest


static func forget_recent() -> void:
	_recent_quest = ""
	_recent_ms = -1
