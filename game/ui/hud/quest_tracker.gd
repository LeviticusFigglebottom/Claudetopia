class_name QuestTracker
extends PanelContainer
## The tracked quest on the HUD (DESIGN §5.16): its name, and under it what is to be done now, each
## with how far ("312 m") and how far along ("2/4 ash-wights"). The user asked for "a small hud
## element showing current step with distance (x meters away) and completion (0/4 enemies, etc)".
##
## It sits top left, on a strip of parchment hung from a brass rail that fades into the country:
## the compass has the top middle, the toasts the top right, the bars, the hints and the belt the
## bottom. It is part of the HUD, so it fades with it when nothing is happening.
##
## The HUD hands it rows ({key, text, detail}) a few times a second. A row that is no longer handed
## over was done: it is ticked, held a moment, and let go; a new one inks in. The timing keeps the
## wall clock (WallTweens), so a step done on a slow frame is still seen being ticked.

## How long a done step stays ticked before it goes, and how long it takes to go.
const DONE_HOLD_S := 1.6
const DONE_FADE_S := 0.9
const WIDTH := 300.0

var _wall := WallTweens.new()
var _title: Label
var _rows_box: VBoxContainer
var _rows: Dictionary = {}          # key -> {node, text, detail, bullet, done_at}
var _quest := ""


# --- words ------------------------------------------------------------------------------------

## How far, as the tracker says it: "" within the objective's own radius (you are there) or when
## nobody can say; 5 m steps under 100 m, 10 m steps under a kilometre, then tenths of one.
static func distance_text(metres: float, radius := 0.0) -> String:
	if not is_finite(metres) or metres < 0.0 or metres <= radius:
		return ""
	if metres < 100.0:
		return "%d m" % maxi(5, int(snappedf(metres, 5.0)))
	if metres < 995.0:
		return "%d m" % int(snappedf(metres, 10.0))
	if metres < 9950.0:
		return "%.1f km" % (metres / 1000.0)
	return "%d km" % roundi(metres / 1000.0)


## How far along, for an objective of more than one: "2/4 ash-wights". "" for a single thing.
static func progress_text(have: int, need: int, about := "") -> String:
	if need <= 1:
		return ""
	var s := "%d/%d" % [clampi(have, 0, need), need]
	return s if about == "" else "%s %s" % [s, about]


## The small line under an objective: its progress and its distance, whichever it has.
static func detail_text(progress: String, distance: String) -> String:
	var parts: PackedStringArray = []
	for p in [progress, distance]:
		if str(p) != "":
			parts.append(str(p))
	return "  ·  ".join(parts)


# --- the control --------------------------------------------------------------------------------

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, 0.0)
	_apply_plate(UI.theme_variant)
	UI.variant_changed.connect(_apply_plate)
	var column := UiKit.column(3)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	_title = UiKit.label("", "Heading")
	_title.add_theme_font_size_override("font_size", 16)
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_title)
	_rows_box = UiKit.column(5)
	_rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_rows_box)
	visible = false


func _apply_plate(variant: String) -> void:
	var sb := ThemeBuilder.variant_box(variant, ["quest_plate"], PackedInt32Array([16, 9, 44, 11]))
	add_theme_stylebox_override("panel", sb)


func _process(_delta: float) -> void:
	_wall.step()
	var now := Time.get_ticks_msec()
	for key in _rows.keys():
		var r: Dictionary = _rows[key]
		var done_at := int(r.get("done_at", -1))
		if done_at >= 0 and now - done_at > int((DONE_HOLD_S + DONE_FADE_S) * 1000.0):
			(r["node"] as Node).queue_free()
			_rows.erase(key)
	if _quest == "" and _rows.is_empty():
		visible = false


## What the tracker shows: the quest's name and its open objectives, [{key, text, detail}], in
## order. A title of "" means nothing is followed.
func show_quest(title: String, rows: Array) -> void:
	if title != _quest:
		# another quest, or none: what was shown goes at once, without being ticked
		for key in _rows.keys():
			(_rows[key]["node"] as Node).queue_free()
		_rows.clear()
		_quest = title
		_title.text = title
		if title != "":
			visible = true
			UiKit.ink_in(self, 0.0, 0.5)
	if title == "":
		return
	var wanted: Dictionary = {}
	var order := 0
	for row_v in rows:
		var row: Dictionary = row_v
		var key := str(row.get("key", ""))
		wanted[key] = true
		var r: Dictionary = _rows.get(key, {})
		if r.is_empty() or int(r.get("done_at", -1)) >= 0:
			if not r.is_empty():
				(r["node"] as Node).queue_free()
			r = _make_row()
			_rows[key] = r
			_rows_box.add_child(r["node"] as Node)
			var ink := _wall.own(create_tween())
			(r["node"] as Control).modulate = Color(0.30, 0.24, 0.19, 0.0)
			ink.tween_property(r["node"], "modulate", Color(1, 1, 1, 1), 0.6).set_trans(Tween.TRANS_CUBIC)
		_rows_box.move_child(r["node"] as Node, order)
		order += 1
		(r["text"] as Label).text = str(row.get("text", ""))
		var detail := str(row.get("detail", ""))
		(r["detail"] as Label).text = detail
		(r["detail"] as Label).visible = detail != ""
	# what is no longer asked for was done: ticked, held, and let go
	for key in _rows.keys():
		if wanted.has(key):
			continue
		var r: Dictionary = _rows[key]
		if int(r.get("done_at", -1)) >= 0:
			continue
		r["done_at"] = Time.get_ticks_msec()
		(r["bullet"] as TextureRect).texture = ThemeBuilder.texture("quest_tick")
		(r["detail"] as Label).visible = false
		(r["text"] as Label).modulate = Color(1, 1, 1, 0.7)
		var tw := _wall.own(create_tween())
		tw.tween_interval(DONE_HOLD_S)
		tw.tween_property(r["node"], "modulate:a", 0.0, DONE_FADE_S)


func _make_row() -> Dictionary:
	var line := UiKit.row(7)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bullet := TextureRect.new()
	bullet.texture = ThemeBuilder.variant_texture(UI.theme_variant, ["quest_pin"])
	bullet.custom_minimum_size = Vector2(15, 15)
	bullet.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bullet.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bullet.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	bullet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(bullet)
	var words := UiKit.column(0)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(words)
	var text := UiKit.wrapped("", "Body", WIDTH - 70.0)
	text.add_theme_font_size_override("font_size", 15)
	text.add_theme_constant_override("line_spacing", 0)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(text)
	var detail := UiKit.label("", "Small")
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(detail)
	return {"node": line, "text": text, "detail": detail, "bullet": bullet, "done_at": -1}


# --- for the tests and the probe -----------------------------------------------------------------

## The quest's name as shown, "" when nothing is.
func shown_title() -> String:
	return _quest if visible else ""


## The rows as shown now, ticked ones included: [{text, detail, done}].
func shown_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for child in _rows_box.get_children():
		for key in _rows:
			var r: Dictionary = _rows[key]
			if r["node"] == child:
				out.append({"text": (r["text"] as Label).text, "detail": (r["detail"] as Label).text if (r["detail"] as Label).visible else "",
						"done": int(r.get("done_at", -1)) >= 0})
	return out
