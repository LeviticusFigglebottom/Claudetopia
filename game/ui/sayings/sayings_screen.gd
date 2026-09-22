extends Control
## What you can Say (DESIGN §5.3): every saying the character has been taught, grouped by
## school, and the one that is readied to the cast key. Readying is what sets the player's
## `equipped_spell`, so this screen is the only way a saying reaches the world.
##
## Reads the progression stream through the group "progression" — `spells()`, `skill_level()` —
## and the player through the group "player" — `mana`, `max_mana`, `equipped_spell`,
## `equip_spell(id)`, `spell_readied`. Both are optional: with neither, the page says so
## instead of lying.

## What each school is for, under its heading, in the Circle's own words.
const SCHOOL_NOTE := {
	"kindling": "fire and light: the loudest thing a small voice can make",
	"hush": "frost, silence, and not being noticed",
	"binding": "wards, shields, and where a thing stops",
	"mending": "closing and cleansing, said kindly",
	"calling": "what stands up beside you when it is named",
}
## How a saying is delivered: the long form for the detail page, the short one for a list row.
const CAST_TYPE_WORDS := {
	"projectile": "Thrown", "self": "Said over yourself", "aura": "Said outward",
	"target": "Said at your mark", "summon": "Calls something",
}
const CAST_TYPE_SHORT := {
	"projectile": "thrown", "self": "over yourself", "aura": "outward",
	"target": "at your mark", "summon": "calls",
}
## Blank paper left under the last line of lore, so a page that overflows is cut by the fold
## and not by the Ready it button sitting under it.
const BOTTOM_PADDING := 18.0
## Status ids a saying can leave behind, in plain words rather than as an id.
const STATUS_WORDS := {
	"burning": "leaves it burning", "chilled": "leaves it slow", "silenced": "leaves it unable to Say",
	"bleeding": "opens it up", "poisoned": "leaves it poisoned", "stagger": "takes its footing",
	"knockdown": "puts it down", "quieted": "quiets it",
}

var _prog: Node = null
var _player: Node = null
var _selected := ""
var _columns: HBoxContainer
var _empty_box: CenterContainer
var _list_box: VBoxContainer
var _detail_head: HBoxContainer
var _detail_box: VBoxContainer
var _action_row: HBoxContainer
var _mana_bar: TextureProgressBar
var _mana_label: Label
var _readied_plate: PanelContainer
var _readied_mark: SchoolMark
var _readied_label: Label


func setup(args: Dictionary) -> void:
	_selected = str(args.get("spell", ""))
	if is_inside_tree():
		_refresh()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.dim())
	_prog = get_tree().get_first_node_in_group("progression")
	_player = get_tree().get_first_node_in_group("player")
	_build()
	if _prog and _prog.has_signal("sayings_changed"):
		_prog.connect("sayings_changed", _refresh)
	if _player and _player.has_signal("spell_readied"):
		# A method reference, not a closure: the player outlives this screen.
		_player.connect("spell_readied", _on_spell_readied)
	_refresh()


func _on_spell_readied(_id: String) -> void:
	_refresh()


# --- construction ----------------------------------------------------------------------------

func _build() -> void:
	var page := UiKit.page("What You Can Say")
	var frame: PanelContainer = page["frame"]
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 60.0
	frame.offset_top = 34.0
	frame.offset_right = -60.0
	frame.offset_bottom = -34.0
	add_child(frame)
	var body: VBoxContainer = page["body"]

	# what is in the mouth right now, on its own small plate rather than behind another rule
	var plate_holder := CenterContainer.new()
	body.add_child(plate_holder)
	_readied_plate = UiKit.panel("ChromePanel")
	plate_holder.add_child(_readied_plate)
	var plate_row := UiKit.row(10)
	_readied_plate.add_child(UiKit.margins(plate_row, 16, 2, 16, 2))
	_readied_mark = SchoolMark.new()
	_readied_mark.custom_minimum_size = Vector2(24, 24)
	_readied_mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plate_row.add_child(_readied_mark)
	_readied_label = UiKit.label("", "Emphasis")
	plate_row.add_child(_readied_label)

	# wide enough that the list's own scrollbar and the rule between the columns read as two
	# things rather than one thick edge
	_columns = UiKit.row(26)
	_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_columns)

	# --- what you have been taught ---------------------------------------------------------
	_list_box = UiKit.column(4)
	var list_scroll := UiKit.scroll(_list_box)
	list_scroll.custom_minimum_size = Vector2(430, 0)
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_columns.add_child(list_scroll)

	_columns.add_child(VSeparator.new())

	# --- the one in hand ---------------------------------------------------------------------
	# A fixed reading width. Everything outside the scroll (the heading, the buttons) is
	# clipped rather than wrapped, because anything that wraps hands its own idea of a
	# minimum width up to the column and pushes the page off the side of the frame.
	var detail_col := UiKit.column(14)
	detail_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# inset from the frame by the same margin the list's own scrollbar sits at, so the two
	# bars read as a pair of column edges rather than one of them clinging to the brass
	var detail_inset := UiKit.margins(detail_col, 0, 0, 14, 0)
	detail_inset.custom_minimum_size = Vector2(574, 0)
	detail_inset.size_flags_horizontal = Control.SIZE_FILL
	_columns.add_child(detail_inset)
	_detail_head = UiKit.row(12)
	detail_col.add_child(_detail_head)
	_detail_box = UiKit.column(4)
	var detail_scroll := UiKit.scroll(_detail_box)
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_col.add_child(detail_scroll)
	# the action stays out of the scroll: readying is the whole point of the page and must
	# never be a thing you have to scroll down to find
	_action_row = UiKit.row(10)
	detail_col.add_child(_action_row)

	# --- the page a character who has been taught nothing sees ------------------------------
	_empty_box = CenterContainer.new()
	_empty_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty_box.visible = false
	body.add_child(_empty_box)
	var empty_col := UiKit.column(10)
	empty_col.custom_minimum_size = Vector2(620, 0)
	_empty_box.add_child(empty_col)
	empty_col.add_child(UiKit.label("Nobody has taught you anything yet.", "Heading", HORIZONTAL_ALIGNMENT_CENTER))
	var empty_note := UiKit.wrapped(
		"A saying has to be given to you. The Circle at the Sayers' Spire teaches, for a fee "
		+ "or for an argument; so does a book with a working written in it; and so, now and "
		+ "then, does somebody who owes you a favour.", "Journal", 600)
	empty_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_col.add_child(empty_note)

	# --- the breath you have to spend, and the way out --------------------------------------
	body.add_child(UiKit.divider())
	var foot := UiKit.row(14)
	body.add_child(foot)
	_mana_label = UiKit.label("", "Small")
	_mana_label.custom_minimum_size = Vector2(170, 0)
	foot.add_child(_mana_label)
	_mana_bar = TextureProgressBar.new()
	_mana_bar.texture_under = ThemeBuilder.variant_texture(UI.theme_variant, ["bar_track"])
	_mana_bar.texture_progress = ThemeBuilder.fill("mana")
	_mana_bar.nine_patch_stretch = true
	_mana_bar.stretch_margin_left = 6
	_mana_bar.stretch_margin_right = 6
	_mana_bar.stretch_margin_top = 6
	_mana_bar.stretch_margin_bottom = 6
	_mana_bar.min_value = 0.0
	_mana_bar.max_value = 1.0
	_mana_bar.step = 0.0
	_mana_bar.custom_minimum_size = Vector2(0, 18)
	_mana_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mana_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_mana_bar)
	var close := UiKit.button("Close", "FlatButton")
	close.pressed.connect(func() -> void: UI.close("sayings"))
	foot.add_child(close)
	UiKit.ink_in(frame, 0.0, 0.32)


# --- data ------------------------------------------------------------------------------------

func _sayings() -> Array:
	if _prog and is_instance_valid(_prog) and _prog.has_method("spells"):
		return _prog.call("spells")
	return []


func _readied() -> String:
	if _player and is_instance_valid(_player):
		return str(_player.get("equipped_spell"))
	return ""


## x = the breath in hand, y = the whole of it. Zero when there is nobody here to hold it.
func _mana() -> Vector2:
	if _player and is_instance_valid(_player) and _player.get("max_mana") != null:
		return Vector2(float(_player.get("mana")), float(_player.get("max_mana")))
	return Vector2.ZERO


func _refresh() -> void:
	var sayings := _sayings()
	if _selected.is_empty() and not sayings.is_empty():
		_selected = str(sayings[0]["id"])
	_columns.visible = not sayings.is_empty()
	_empty_box.visible = sayings.is_empty()
	_refresh_head()
	_refresh_list(sayings)
	_refresh_detail()


func _refresh_head() -> void:
	var readied := _readied()
	var def := ContentDB.get_or_empty(readied)
	if readied.is_empty() or def.is_empty():
		_readied_mark.visible = false
		_readied_label.text = "Nothing readied"
		_readied_plate.modulate = Color(1, 1, 1, 0.55)
	else:
		_readied_mark.visible = true
		_readied_mark.school = SpellRuntime.school_of(def)
		_readied_label.text = "%s  ·  readied to %s" % [str(def.get("name", readied)), UI.prompt_for("cast")]
		_readied_plate.modulate = Color(1, 1, 1, 1)
	var m := _mana()
	_mana_bar.value = clampf(m.x / maxf(m.y, 0.001), 0.0, 1.0)
	_mana_label.text = "Breath  %d / %d" % [roundi(m.x), roundi(m.y)] if m.y > 0.0 else "Breath  —"


func _refresh_list(sayings: Array) -> void:
	for child in _list_box.get_children():
		child.queue_free()
	if sayings.is_empty():
		return
	var rows: Array[Control] = []
	var school := ""
	var i := 0
	for s in sayings:
		if str(s["school"]) != school:
			school = str(s["school"])
			if i > 0:
				_list_box.add_child(UiKit.spacer(10.0, true))
			_list_box.add_child(_school_heading(school, str(s.get("school_name", ""))))
		var row := _make_row(s)
		_list_box.add_child(row)
		rows.append(row)
		UiKit.ink_in(row, 0.015 * i, 0.24)
		i += 1
	UiKit.focus_chain(rows)


func _school_heading(school: String, school_name: String) -> HBoxContainer:
	var head := UiKit.row(8)
	var mark := SchoolMark.new()
	mark.school = school
	mark.custom_minimum_size = Vector2(22, 22)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(mark)
	var names := UiKit.column(0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := school_name if school_name != "" else school.capitalize()
	if _prog and _prog.has_method("skill_level"):
		title += "   ·   skill %d" % int(_prog.call("skill_level", school))
	names.add_child(UiKit.label(title, "Emphasis"))
	names.add_child(UiKit.label(str(SCHOOL_NOTE.get(school, "")), "Tiny"))
	head.add_child(names)
	return head


func _make_row(s: Dictionary) -> Button:
	var id := str(s["id"])
	var cost := float(s["cost"])
	var m := _mana()
	var affordable := m.y <= 0.0 or cost <= m.x
	var readied := id == _readied()
	var b := UiKit.button("", "FlatButton")
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 34)
	b.clip_contents = true
	b.tooltip_text = "%s\n%s" % [str(s["name"]), str(s["description"])]
	b.pressed.connect(func() -> void:
			_selected = id
			_refresh_detail())

	var line := UiKit.row(8)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.set_anchors_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 4.0
	line.offset_right = -10.0
	b.add_child(line)
	# the page's own brass lozenge, ticked in the margin against the saying in your mouth.
	# State belongs in the gutter; the ledger columns say what a saying is, not how it stands.
	var tick := TextureRect.new()
	tick.texture = ThemeBuilder.texture("rule_mark" if UI.theme_variant == "warm" else "rule_mark_deep")
	tick.custom_minimum_size = Vector2(14, 14)
	tick.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tick.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# kept in the layout when it has nothing to say, or every other row would shuffle left
	tick.modulate = Color(1, 1, 1, 1.0 if readied else 0.0)
	line.add_child(tick)
	var mark := SchoolMark.new()
	mark.school = str(s["school"])
	mark.custom_minimum_size = Vector2(18, 18)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(mark)
	var name_label := UiKit.label(str(s["name"]), "Emphasis" if readied else "Body")
	# a clipped Label reports no minimum width at all, so it is given one by hand or it
	# collapses to nothing the moment anything beside it wants room
	name_label.custom_minimum_size = Vector2(180, 0)
	name_label.clip_text = true
	line.add_child(name_label)
	# what kind of saying it is, kept beside the name: both describe the saying, and the
	# leader space belongs between the words and the figures, as it does in any ledger.
	# The cell expands and the word sits at its left, so the space falls before the numbers.
	var kind := UiKit.label(str(CAST_TYPE_SHORT.get(str(s["cast_type"]), "")), "Tiny")
	kind.custom_minimum_size = Vector2(100, 0)
	kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kind.clip_text = true
	kind.modulate = Color(1, 1, 1, 0.7)
	line.add_child(kind)
	var cost_label := UiKit.label("%d" % roundi(cost), "Small", HORIZONTAL_ALIGNMENT_RIGHT)
	cost_label.custom_minimum_size = Vector2(34, 0)
	if not affordable:
		cost_label.add_theme_color_override("font_color", ThemeBuilder.colour("accent", UI.theme_variant))
	line.add_child(cost_label)
	var time_label := UiKit.label("%.1fs" % float(s["cast_time"]), "Tiny", HORIZONTAL_ALIGNMENT_RIGHT)
	time_label.custom_minimum_size = Vector2(40, 0)
	time_label.modulate = Color(1, 1, 1, 0.7)
	line.add_child(time_label)
	return b


func _selected_saying() -> Dictionary:
	var sayings := _sayings()
	for s in sayings:
		if str(s["id"]) == _selected:
			return s
	return sayings[0] if not sayings.is_empty() else {}


func _refresh_detail() -> void:
	for child in _detail_head.get_children():
		child.queue_free()
	for child in _detail_box.get_children():
		child.queue_free()
	for child in _action_row.get_children():
		child.queue_free()
	var s := _selected_saying()
	if s.is_empty():
		return
	_selected = str(s["id"])

	var mark := SchoolMark.new()
	mark.school = str(s["school"])
	mark.custom_minimum_size = Vector2(44, 44)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_detail_head.add_child(mark)
	var titles := UiKit.column(0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := UiKit.label(str(s["name"]), "Heading")
	name_label.clip_text = true
	name_label.custom_minimum_size = Vector2(240, 0)
	titles.add_child(name_label)
	var kind_label := UiKit.label("%s  ·  %s" % [str(s.get("school_name", "")),
			str(CAST_TYPE_WORDS.get(str(s["cast_type"]), str(s["cast_type"])))], "Small")
	kind_label.clip_text = true
	titles.add_child(kind_label)
	_detail_head.add_child(titles)

	var facts := UiKit.column(0)
	var m := _mana()
	var cost := float(s["cost"])
	var cost_line := "%d of your %d breath" % [roundi(cost), roundi(m.y)] if m.y > 0.0 else "%d breath" % roundi(cost)
	facts.add_child(_fact("Costs", cost_line, m.y > 0.0 and cost > m.x))
	facts.add_child(_fact("Takes", "%.2f s to say" % float(s["cast_time"])))
	if float(s["range"]) > 0.0:
		facts.add_child(_fact("Carries", "%.0f m" % float(s["range"])))
	if float(s["radius"]) > 0.0:
		facts.add_child(_fact("Reaches", "%.1f m around you" % float(s["radius"])))
	if float(s["duration"]) > 0.0:
		facts.add_child(_fact("Holds", "%.0f s" % float(s["duration"])))
	_detail_box.add_child(facts)

	_detail_box.add_child(UiKit.divider())
	for line in plain_words(s):
		_detail_box.add_child(UiKit.wrapped("·   " + line, "Body"))
	_detail_box.add_child(UiKit.spacer(4.0, true))
	_detail_box.add_child(UiKit.wrapped(str(s["description"]), "Journal"))
	# the lore ends on padding, not on the button: what the fold cuts is a line of paper
	_detail_box.add_child(UiKit.spacer(BOTTOM_PADDING, true))

	if str(s["id"]) == _readied():
		var put_away := UiKit.button("Put it away", "FlatButton")
		put_away.pressed.connect(func() -> void: _ready_saying(""))
		_action_row.add_child(put_away)
		_action_row.add_child(UiKit.label("In your mouth. Say it with %s." % UI.prompt_for("cast"), "Tiny"))
	else:
		var take := UiKit.button("Ready it")
		take.pressed.connect(func() -> void: _ready_saying(str(s["id"])))
		_action_row.add_child(take)
		if _player == null or not is_instance_valid(_player):
			_action_row.add_child(UiKit.label("Nobody here to say it.", "Tiny"))
	UiKit.ink_in(_detail_box, 0.0, 0.24)


func _fact(key: String, value: String, warn := false) -> HBoxContainer:
	var row := UiKit.row(8)
	row.custom_minimum_size = Vector2(0, 26)
	var k := UiKit.label(key, "Small")
	k.custom_minimum_size = Vector2(90, 26)
	row.add_child(k)
	var v := UiKit.label(value, "Body")
	v.clip_text = true
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if warn:
		v.add_theme_color_override("font_color", ThemeBuilder.colour("accent", UI.theme_variant))
	row.add_child(v)
	return row


func _ready_saying(spell_id: String) -> void:
	if _player and is_instance_valid(_player) and _player.has_method("equip_spell"):
		_player.call("equip_spell", spell_id)
	_refresh()


## What a saying does, in plain words rather than in effect shapes. Static and pure so the
## wording can be checked without a screen.
static func plain_words(s: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for e in s.get("effects", []):
		if typeof(e) != TYPE_DICTIONARY:
			continue
		match str(e.get("type", "")):
			"damage":
				out.append("Deals %d %s damage." % [roundi(float(e.get("amount", 0.0))), str(e.get("kind", "fire"))])
			"status":
				var id := str(e.get("id", ""))
				var words := str(STATUS_WORDS.get(id, "leaves it " + id))
				out.append(_sentence("%s for %d seconds" % [words, roundi(float(e.get("duration", 0.0)))]))
			"heal":
				out.append("Closes %d of what is open." % roundi(float(e.get("amount", 0.0))))
			"shield":
				out.append("Holds off %d damage for %d seconds." % [
						roundi(float(e.get("amount", 0.0))), roundi(float(e.get("duration", 0.0)))])
			"cleanse":
				var names := PackedStringArray()
				for id in e.get("ids", []):
					names.append(str(id))
				if names.size() > 0:
					out.append("Clears %s." % _and_list(names))
			"summon":
				var who := ContentDB.get_or_empty(str(e.get("enemy", "")))
				out.append("Calls %s to stand with you for %d seconds." % [
						str(who.get("name", "something")), roundi(float(e.get("duration", 0.0)))])
	if out.is_empty():
		out.append("Nothing anybody has written down.")
	return out


## One sentence: first letter up, full stop at the end. String.capitalize() title-cases every
## word, which turns "leaves it burning" into a shop sign.
static func _sentence(text: String) -> String:
	if text.is_empty():
		return text
	return text.substr(0, 1).to_upper() + text.substr(1) + "."


static func _and_list(words: PackedStringArray) -> String:
	if words.size() == 1:
		return words[0]
	return ", ".join(words.slice(0, words.size() - 1)) + " and " + words[words.size() - 1]
