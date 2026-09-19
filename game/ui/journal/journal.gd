extends Control
## The journal (DESIGN §5.16): Quests, Rumours, Bestiary and Books, written on one page.
## Quest entries are in the handwritten Spectral Italic, because they are the character's
## own notes and not a system readout.
##
## Reads the quest log by group ("quest_log": active_quests(), completed_quests()), rumours
## and enemies from ContentDB, and books from GameState.read_books.

const TABS := ["Quests", "Rumours", "Bestiary", "Books"]

var _tab := 0
var _tab_buttons: Array[Control] = []
var _list_box: VBoxContainer
var _detail_box: VBoxContainer
var _selected := ""
var _entries: Array[Dictionary] = []
var _review_bestiary: Array = []


func setup(args: Dictionary) -> void:
	_tab = int(args.get("tab", 0))
	_review_bestiary = args.get("bestiary", [])
	if is_inside_tree():
		_show_tab(_tab)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.dim())
	var page := UiKit.page("The Journal")
	var frame: PanelContainer = page["frame"]
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 90.0
	frame.offset_top = 46.0
	frame.offset_right = -90.0
	frame.offset_bottom = -46.0
	add_child(frame)

	var body: VBoxContainer = page["body"]
	var tabs := UiKit.row(6)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(tabs)
	for i in TABS.size():
		var b := UiKit.button(TABS[i], "FlatButton")
		var index := i
		b.pressed.connect(func() -> void: _show_tab(index))
		tabs.add_child(b)
		_tab_buttons.append(b)
	UiKit.focus_chain(_tab_buttons, false)

	var split := UiKit.row(18)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(split)

	_list_box = UiKit.column(4)
	_list_box.custom_minimum_size = Vector2(330, 0)
	var list_scroll := UiKit.scroll(_list_box)
	list_scroll.size_flags_horizontal = Control.SIZE_FILL
	list_scroll.custom_minimum_size = Vector2(340, 0)
	split.add_child(list_scroll)

	var rule := VSeparator.new()
	split.add_child(rule)

	_detail_box = UiKit.column(10)
	var detail_scroll := UiKit.scroll(_detail_box)
	split.add_child(detail_scroll)

	var close := UiKit.button("Close", "FlatButton")
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(func() -> void: UI.close("journal"))
	body.add_child(close)

	UiKit.ink_in(frame, 0.0, 0.32)
	_show_tab(_tab)


# --- tabs -----------------------------------------------------------------------------------

func _show_tab(index: int) -> void:
	_tab = clampi(index, 0, TABS.size() - 1)
	for i in _tab_buttons.size():
		_tab_buttons[i].modulate = Color(1, 1, 1, 1.0 if i == _tab else 0.55)
	_entries = _gather()
	_selected = str(_entries[0].get("id", "")) if not _entries.is_empty() else ""
	_rebuild_list()
	_rebuild_detail()
	if not _tab_buttons.is_empty():
		_tab_buttons[_tab].grab_focus()


func _gather() -> Array[Dictionary]:
	match _tab:
		0: return _quests()
		1: return _rumours()
		2: return _bestiary()
		_: return _books()


func _quests() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var log := get_tree().get_first_node_in_group("quest_log")
	if log and is_instance_valid(log) and log.has_method("active_quests"):
		for q in log.call("active_quests"):
			var d: Dictionary = q
			d["done"] = false
			out.append(d)
		if log.has_method("completed_quests"):
			for q in log.call("completed_quests"):
				var d: Dictionary = q
				d["done"] = true
				out.append(d)
	return out


func _rumours() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for def in ContentDB.all("rumour"):
		var place := str(def.get("place", ""))
		var heard: bool = GameState.has_flag("rumour:" + str(def.get("id", "")))
		if not heard and not (place != "" and GameState.is_discovered(place)):
			continue
		out.append({"id": str(def.get("id", "")), "name": _rumour_title(def), "def": def})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a["def"].get("heat", 0)) > int(b["def"].get("heat", 0)))
	return out


## Rumours are written as templates with {player} and {place} slots; the gossip stream fills
## them when a rumour actually spreads. Until it hands the journal filled text, fill what we
## can ourselves so the page reads as talk and not as a form.
func rumour_text(def: Dictionary) -> String:
	var text := str(def.get("text", ""))
	if not text.contains("{"):
		return text
	var who := str(GameState.get_flag("player_name", ""))
	if who.is_empty():
		who = "the Foundling"
	var where := str(ContentDB.get_or_empty(str(def.get("place", ""))).get("name", ""))
	if where.is_empty():
		where = str(ContentDB.get_or_empty(GameState.current_region_id).get("name", "the valley"))
	return text.replace("{player}", who).replace("{place}", where).replace("{npc}", "somebody")


## Rumours are overheard talk, so the entry is titled with the talk itself, cut short.
func _rumour_title(def: Dictionary) -> String:
	var text := rumour_text(def).strip_edges()
	var cut := text.find(". ")
	if cut < 12 or cut > 46:
		cut = text.rfind(" ", 44)
	if cut < 12:
		cut = mini(text.length(), 44)
	var title := text.substr(0, cut).strip_edges()
	if title.length() < text.length():
		title += "…"
	return title


func _bestiary() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for def in ContentDB.all("enemy"):
		var id := str(def.get("id", ""))
		var met: bool = GameState.has_flag("bestiary:" + id) or GameState.count("killed:" + id) > 0 or _review_bestiary.has(id)
		if not met:
			continue
		out.append({"id": id, "name": str(def.get("name", id)), "def": def,
				"count": GameState.count("killed:" + id)})
	for def in ContentDB.all("boss"):
		var id := str(def.get("id", ""))
		if GameState.has_flag("bestiary:" + id) or _review_bestiary.has(id):
			out.append({"id": id, "name": str(def.get("name", id)), "def": def, "boss": true, "count": 0})
	return out


func _books() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in GameState.read_books:
		var def := ContentDB.get_or_empty(id)
		if def.is_empty():
			continue
		out.append({"id": id, "name": str(def.get("title", id)), "def": def})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]) < str(b["name"]))
	return out


# --- list and detail --------------------------------------------------------------------------

func _rebuild_list() -> void:
	for child in _list_box.get_children():
		child.queue_free()
	if _entries.is_empty():
		_list_box.add_child(UiKit.wrapped(_empty_line(), "Journal", 310))
		return
	var buttons: Array[Control] = []
	var i := 0
	for e in _entries:
		var label := str(e.get("name", ""))
		if bool(e.get("done", false)):
			label = "✓  " + label
		var b := UiKit.button(label, "FlatButton")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var id := str(e.get("id", ""))
		b.pressed.connect(func() -> void:
				_selected = id
				_rebuild_detail())
		_list_box.add_child(b)
		buttons.append(b)
		UiKit.ink_in(b, 0.02 * i, 0.22)
		i += 1
	UiKit.focus_chain(buttons)


func _empty_line() -> String:
	match _tab:
		0: return "Nothing is asked of you yet."
		1: return "You have not heard anything worth writing down."
		2: return "Nothing has been written down yet. Things have to be met first."
		_: return "You have read nothing yet."


func _entry(id: String) -> Dictionary:
	for e in _entries:
		if str(e.get("id", "")) == id:
			return e
	return _entries[0] if not _entries.is_empty() else {}


func _rebuild_detail() -> void:
	for child in _detail_box.get_children():
		child.queue_free()
	var e := _entry(_selected)
	if e.is_empty():
		return
	match _tab:
		0: _detail_quest(e)
		1: _detail_rumour(e)
		2: _detail_beast(e)
		_: _detail_book(e)
	UiKit.ink_in(_detail_box, 0.0, 0.28)


func _detail_quest(e: Dictionary) -> void:
	_detail_box.add_child(UiKit.wrapped(str(e.get("name", "")), "Title"))
	var layer := str(e.get("layer", ""))
	if layer != "":
		_detail_box.add_child(UiKit.label(layer.capitalize() + (" · finished" if e.get("done", false) else ""), "Small"))
	_detail_box.add_child(UiKit.divider())

	for o in e.get("objectives", []):
		if typeof(o) != TYPE_DICTIONARY:
			continue
		var done := bool(o.get("done", false))
		var row := UiKit.row(8)
		row.add_child(UiKit.icon_rect("quest" if not done else "bell", 20,
				Color(1, 1, 1, 0.5 if done else 1.0)))
		var text := UiKit.wrapped(str(o.get("text", "")), "Body")
		if done:
			text.modulate = Color(1, 1, 1, 0.5)
		row.add_child(text)
		_detail_box.add_child(row)

	_detail_box.add_child(UiKit.divider())
	var journal: Array = e.get("journal", [])
	for i in journal.size():
		var entry := UiKit.wrapped(str(journal[i]), "Journal")
		entry.modulate = Color(1, 1, 1, 0.65 if i < journal.size() - 1 else 1.0)
		_detail_box.add_child(entry)
		if i < journal.size() - 1:
			_detail_box.add_child(UiKit.spacer(6, true))


func _detail_rumour(e: Dictionary) -> void:
	var def: Dictionary = e["def"]
	_detail_box.add_child(UiKit.label("Talk", "Title"))
	var tags: Array = def.get("tags", [])
	if not tags.is_empty():
		var words := PackedStringArray()
		for t in tags:
			words.append(str(t).capitalize())
		_detail_box.add_child(UiKit.label("  ·  ".join(words), "Small"))
	_detail_box.add_child(UiKit.divider())
	_detail_box.add_child(UiKit.wrapped("“%s”" % rumour_text(def), "Journal"))
	for key in ["place", "region"]:
		var where := ContentDB.get_or_empty(str(def.get(key, "")))
		if not where.is_empty():
			_detail_box.add_child(UiKit.label("Heard in %s" % str(where.get("name", "")), "Small"))
			break


func _detail_beast(e: Dictionary) -> void:
	var def: Dictionary = e["def"]
	_detail_box.add_child(UiKit.wrapped(str(e.get("name", "")), "Title"))
	var sub := str(def.get("archetype", "")).capitalize()
	if int(e.get("count", 0)) > 0:
		sub += " · %d put down" % int(e["count"])
	_detail_box.add_child(UiKit.label(sub, "Small"))
	_detail_box.add_child(UiKit.divider())
	var stats: Dictionary = def.get("stats", {})
	if not stats.is_empty():
		var row := UiKit.row(16)
		for key in ["hp", "poise", "armour", "speed"]:
			if stats.has(key):
				var cell := UiKit.column(0)
				cell.add_child(UiKit.label(str(key).to_upper(), "Tiny"))
				cell.add_child(UiKit.label(str(stats[key]), "Emphasis"))
				row.add_child(cell)
		_detail_box.add_child(row)
		_detail_box.add_child(UiKit.divider())
	_detail_box.add_child(UiKit.wrapped(str(def.get("lore", def.get("description", ""))), "Journal"))


func _detail_book(e: Dictionary) -> void:
	var def: Dictionary = e["def"]
	_detail_box.add_child(UiKit.wrapped(str(def.get("title", "")), "Title"))
	_detail_box.add_child(UiKit.wrapped(str(def.get("author", "")), "Small"))
	_detail_box.add_child(UiKit.divider())
	var body := str(def.get("body", ""))
	var taste := body.substr(0, 320)
	if body.length() > 320:
		taste += "…"
	var page := UiKit.rich(UiKit.markdown_lite(taste))
	page.add_theme_font_override("normal_font", ThemeBuilder.body_font(ThemeBuilder.FONT_ITALIC))
	_detail_box.add_child(page)
	var open := UiKit.button("Read it again")
	open.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var id := str(e.get("id", ""))
	open.pressed.connect(func() -> void: UI.open("book", {"book_id": id}))
	_detail_box.add_child(open)
