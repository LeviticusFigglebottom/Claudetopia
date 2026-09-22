extends Control
## Skills, perks and attributes (DESIGN §5.6). Each skill is a ring that fills as you use
## it; choosing one shows what can be learned from it and why a perk is still out of reach.
##
## Reads the progression stream through the group "progression": skills(), perks_for(id),
## take_perk(id), spend_attribute(name), level, attribute_points, perk_points.

const ATTRIBUTES := ["vigour", "endurance", "will"]
const ATTRIBUTE_NOTE := {
	"vigour": "health", "endurance": "stamina and what you can carry", "will": "mana",
}

var _prog: Node = null
var _selected := ""
var _grid: GridContainer
var _perk_box: VBoxContainer
var _header: Label
var _attr_row: HBoxContainer
var _rings: Dictionary = {}


func setup(args: Dictionary) -> void:
	_selected = str(args.get("skill", ""))
	if is_inside_tree():
		_refresh()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.dim())
	_prog = get_tree().get_first_node_in_group("progression")
	_build()
	if _prog:
		if _prog.has_signal("skills_changed"):
			_prog.connect("skills_changed", _refresh)
		if _prog.has_signal("points_changed"):
			# A method reference, not a closure: the progression node outlives this screen,
			# and a closure it holds is not disconnected when the screen is freed.
			_prog.connect("points_changed", _on_points_changed)
	_refresh()


func _on_points_changed(_attribute_points: int, _perk_points: int) -> void:
	_refresh()


func _build() -> void:
	var page := UiKit.page("What You Have Learned")
	var frame: PanelContainer = page["frame"]
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 60.0
	frame.offset_top = 34.0
	frame.offset_right = -60.0
	frame.offset_bottom = -34.0
	add_child(frame)
	var body: VBoxContainer = page["body"]

	_header = UiKit.label("", "Heading", HORIZONTAL_ALIGNMENT_CENTER)
	body.add_child(_header)
	_attr_row = UiKit.row(26)
	_attr_row.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(_attr_row)
	body.add_child(UiKit.divider())

	var columns := UiKit.row(20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(columns)

	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 4)
	var grid_scroll := UiKit.scroll(_grid)
	grid_scroll.custom_minimum_size = Vector2(560, 0)
	grid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(grid_scroll)

	columns.add_child(VSeparator.new())

	_perk_box = UiKit.column(8)
	_perk_box.custom_minimum_size = Vector2(320, 0)
	var perk_scroll := UiKit.scroll(_perk_box)
	perk_scroll.custom_minimum_size = Vector2(330, 0)
	perk_scroll.size_flags_horizontal = Control.SIZE_FILL
	columns.add_child(perk_scroll)

	var close := UiKit.button("Close", "FlatButton")
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(func() -> void: UI.close("skills"))
	body.add_child(close)
	UiKit.ink_in(frame, 0.0, 0.32)


# --- data -------------------------------------------------------------------------------

func _skills() -> Array:
	if _prog and is_instance_valid(_prog) and _prog.has_method("skills"):
		return _prog.call("skills")
	var out: Array = []
	for def in ContentDB.all("skill"):
		out.append({"id": str(def.get("id", "")), "name": str(def.get("name", "")), "level": 5,
				"progress": 0.0, "group": str(def.get("group", "")), "governs": str(def.get("governs", ""))})
	return out


func _refresh() -> void:
	var skills := _skills()
	if _selected.is_empty() and not skills.is_empty():
		_selected = str(skills[0]["id"])
	_refresh_header()
	_refresh_grid(skills)
	_refresh_perks()


func _refresh_header() -> void:
	var level := 1
	var attr_points := 0
	var perk_points := 0
	if _prog and is_instance_valid(_prog):
		level = int(_prog.get("level"))
		attr_points = int(_prog.get("attribute_points"))
		perk_points = int(_prog.get("perk_points"))
	var bits := ["Level %d" % level]
	if attr_points > 0:
		bits.append("%d attribute point%s" % [attr_points, "" if attr_points == 1 else "s"])
	if perk_points > 0:
		bits.append("%d perk point%s" % [perk_points, "" if perk_points == 1 else "s"])
	_header.text = "  ·  ".join(bits)

	for child in _attr_row.get_children():
		child.queue_free()
	for attr in ATTRIBUTES:
		var value := 0
		if _prog and _prog.has_method("attribute"):
			value = int(_prog.call("attribute", attr))
		var cell := UiKit.row(8)
		cell.tooltip_text = "%s raises %s" % [attr.capitalize(), ATTRIBUTE_NOTE[attr]]
		var label := UiKit.label("%s  %d" % [attr.capitalize(), value], "Body")
		cell.add_child(label)
		if _prog and int(_prog.get("attribute_points")) > 0:
			var plus := UiKit.button("+", "FlatButton")
			plus.custom_minimum_size = Vector2(36, 0)
			plus.pressed.connect(func() -> void:
					if _prog.has_method("spend_attribute"):
						_prog.call("spend_attribute", attr)
					_refresh())
			cell.add_child(plus)
		_attr_row.add_child(cell)


func _refresh_grid(skills: Array) -> void:
	for child in _grid.get_children():
		child.queue_free()
	_rings.clear()
	var tiles: Array[Control] = []
	var i := 0
	for s in skills:
		var tile := _make_tile(s)
		_grid.add_child(tile)
		tiles.append(tile)
		UiKit.ink_in(tile, 0.015 * i, 0.24)
		i += 1
	UiKit.focus_chain(tiles)


func _make_tile(s: Dictionary) -> Button:
	var b := UiKit.button("", "FlatButton")
	b.custom_minimum_size = Vector2(130, 80)
	b.tooltip_text = "%s\n%s" % [str(s.get("name", "")), str(s.get("governs", ""))]
	var id := str(s["id"])
	b.pressed.connect(func() -> void:
			_selected = id
			_refresh_perks())

	var col := UiKit.column(0)
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	b.add_child(col)

	var ring := SkillRing.new()
	ring.progress = float(s.get("progress", 0.0))
	ring.level = int(s.get("level", 0))
	ring.chosen = id == _selected
	ring.custom_minimum_size = Vector2(44, 44)
	ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(ring)
	_rings[id] = ring

	var name_label := UiKit.label(str(s.get("name", "")), "Tiny", HORIZONTAL_ALIGNMENT_CENTER)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(124, 0)
	col.add_child(name_label)
	return b


func _refresh_perks() -> void:
	for child in _perk_box.get_children():
		child.queue_free()
	for id: String in _rings:
		var ring: SkillRing = _rings[id]
		ring.chosen = id == _selected
		ring.queue_redraw()

	var def := ContentDB.get_or_empty(_selected)
	_perk_box.add_child(UiKit.wrapped(str(def.get("name", _selected)), "Title"))
	var level := 0
	var progress := 0.0
	for s in _skills():
		if str(s["id"]) == _selected:
			level = int(s.get("level", 0))
			progress = float(s.get("progress", 0.0))
	_perk_box.add_child(UiKit.label("Level %d  ·  %d%% toward the next" % [level, roundi(progress * 100.0)], "Small"))
	if def.has("governs"):
		_perk_box.add_child(UiKit.wrapped("Governs %s." % str(def["governs"]), "Journal"))
	_perk_box.add_child(UiKit.divider())

	var perks: Array = []
	if _prog and is_instance_valid(_prog) and _prog.has_method("perks_for"):
		perks = _prog.call("perks_for", _selected)
	else:
		for p in ContentDB.where("perk", "skill", _selected):
			perks.append({"id": str(p.get("id", "")), "name": str(p.get("name", "")),
					"description": str(p.get("description", "")),
					"requires_level": int(p.get("requires_level", 0)), "taken": false,
					"available": false, "blocker": "skill_too_low"})
	if perks.is_empty():
		_perk_box.add_child(UiKit.wrapped("Nothing to learn here yet.", "Journal"))
		return
	for p in perks:
		_perk_box.add_child(_make_perk_row(p))


func _make_perk_row(p: Dictionary) -> PanelContainer:
	var taken := bool(p.get("taken", false))
	var available := bool(p.get("available", false))
	var panel := UiKit.panel("ChromePanel" if taken else "PlainPanel")
	var col := UiKit.column(2)
	panel.add_child(col)
	var head := UiKit.row(8)
	head.add_child(UiKit.icon_rect("bell" if taken else "quest", 20,
			Color(1, 1, 1, 1.0 if taken or available else 0.45)))
	var title := UiKit.wrapped(str(p.get("name", "")), "Emphasis")
	head.add_child(title)
	col.add_child(head)
	var note := UiKit.wrapped(str(p.get("description", "")), "Journal")
	note.modulate = Color(1, 1, 1, 1.0 if taken or available else 0.55)
	col.add_child(note)

	if taken:
		col.add_child(UiKit.label("Learned", "Tiny"))
	elif available:
		var take := UiKit.button("Learn it")
		take.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var id := str(p.get("id", ""))
		take.pressed.connect(func() -> void:
				if _prog and _prog.has_method("take_perk"):
					_prog.call("take_perk", id)
				_refresh())
		col.add_child(take)
	else:
		col.add_child(UiKit.label(_blocker_line(p), "Tiny"))
	return panel


func _blocker_line(p: Dictionary) -> String:
	match str(p.get("blocker", "")):
		"skill_too_low": return "Needs the skill at %d" % int(p.get("requires_level", 0))
		"no_points": return "No perk points left"
		"requires_perk":
			var req := ContentDB.get_or_empty(str(p.get("requires_perk", "")))
			return "Needs %s first" % str(req.get("name", "another perk"))
		"already_taken": return "Learned"
	return "Needs the skill at %d" % int(p.get("requires_level", 0))



## A skill's progress drawn as a ring, with its level in the middle.
class SkillRing:
	extends Control

	var progress := 0.0
	var level := 0
	var chosen := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var centre := size * 0.5
		var radius := minf(size.x, size.y) * 0.40
		var track := ThemeBuilder.colour("ink_soft", UI.theme_variant, 0.28)
		var ink := ThemeBuilder.colour("ink", UI.theme_variant)
		var fill := ThemeBuilder.colour("metal", UI.theme_variant)
		draw_arc(centre, radius, 0.0, TAU, 48, track, 5.0, true)
		if chosen:
			draw_arc(centre, radius + 5.0, 0.0, TAU, 52,
					ThemeBuilder.colour("accent", UI.theme_variant, 0.75), 2.0, true)
		if progress > 0.001:
			draw_arc(centre, radius, -PI * 0.5, -PI * 0.5 + TAU * clampf(progress, 0.0, 1.0), 48, fill, 5.0, true)
		var font := ThemeBuilder.body_font()
		var text := str(level)
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 17)
		draw_string(font, centre + Vector2(-text_size.x * 0.5, text_size.y * 0.34), text,
				HORIZONTAL_ALIGNMENT_CENTER, -1, 17, ink)
