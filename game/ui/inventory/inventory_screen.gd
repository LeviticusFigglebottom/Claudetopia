extends Control
## What you carry (DESIGN §5.7): the paper doll on the left, everything in the bag in the
## middle, and on the right the piece you have in your hand, with the lore that comes with
## it. The load bar at the foot is the thing that actually changes how you fight.
##
## Uses the inventory stream's own nodes through the documented groups, so it is the real
## bag and the real paper doll, not a copy.

const SLOT_ORDER := ["main_hand", "off_hand", "head", "body", "hands", "feet", "ring_1", "ring_2", "amulet"]
const SLOT_NAMES := {
	"main_hand": "Main hand", "off_hand": "Off hand", "head": "Head", "body": "Body",
	"hands": "Hands", "feet": "Feet", "ring_1": "Ring", "ring_2": "Ring", "amulet": "Amulet",
}
const SLOT_ICONS := {
	"main_hand": "sword", "off_hand": "shield", "head": "helm", "body": "tunic",
	"hands": "tunic", "feet": "boots", "ring_1": "ring", "ring_2": "ring", "amulet": "amulet",
}
const CATEGORIES := ["all", "weapon", "armour", "consumable", "ingredient", "material", "book", "key", "misc"]

var _bag: Node = null
var _doll: Node = null
var _filter := "all"
var _selected_uid := 0
var _slot_rows: Dictionary = {}
var _list_box: VBoxContainer
var _detail_box: VBoxContainer
var _filter_row: HBoxContainer
var _load_bar: TextureProgressBar
var _load_label: Label
var _marks_label: Label


func setup(args: Dictionary) -> void:
	_filter = str(args.get("filter", "all"))
	if is_inside_tree():
		_refresh()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.dim())
	_bag = get_tree().get_first_node_in_group("inventory")
	_doll = get_tree().get_first_node_in_group("equipment")
	_build()
	if _bag and _bag.has_signal("changed"):
		_bag.connect("changed", _refresh)
	if _doll and _doll.has_signal("changed"):
		_doll.connect("changed", func(_slot: String) -> void: _refresh())
	_refresh()


func _build() -> void:
	var page := UiKit.page("What You Carry")
	var frame: PanelContainer = page["frame"]
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 60.0
	frame.offset_top = 34.0
	frame.offset_right = -60.0
	frame.offset_bottom = -34.0
	add_child(frame)
	var body: VBoxContainer = page["body"]

	_filter_row = UiKit.row(2)
	_filter_row.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(_filter_row)
	var filters: Array[Control] = []
	for c in CATEGORIES:
		var b := UiKit.button(c.capitalize(), "FlatButton")
		b.add_theme_font_size_override("font_size", ThemeBuilder.SIZES.small)
		b.pressed.connect(func() -> void:
				_filter = c
				_refresh())
		_filter_row.add_child(b)
		filters.append(b)
	UiKit.focus_chain(filters, false)

	var columns := UiKit.row(18)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(columns)

	# --- the paper doll ---------------------------------------------------------------
	var doll_col := UiKit.column(4)
	doll_col.custom_minimum_size = Vector2(230, 0)
	columns.add_child(doll_col)
	doll_col.add_child(UiKit.label("Worn and held", "Heading"))
	for slot in SLOT_ORDER:
		var row := _make_slot_row(slot)
		doll_col.add_child(row)
		_slot_rows[slot] = row

	columns.add_child(VSeparator.new())

	# --- the bag ----------------------------------------------------------------------
	var bag_col := UiKit.column(6)
	bag_col.custom_minimum_size = Vector2(330, 0)
	bag_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(bag_col)
	_list_box = UiKit.column(2)
	bag_col.add_child(UiKit.scroll(_list_box))

	columns.add_child(VSeparator.new())

	# --- what is in your hand -----------------------------------------------------------
	_detail_box = UiKit.column(8)
	_detail_box.custom_minimum_size = Vector2(300, 0)
	var detail_scroll := UiKit.scroll(_detail_box)
	detail_scroll.size_flags_horizontal = Control.SIZE_FILL
	detail_scroll.custom_minimum_size = Vector2(310, 0)
	columns.add_child(detail_scroll)

	# --- the load ------------------------------------------------------------------------
	body.add_child(UiKit.divider())
	var foot := UiKit.row(14)
	body.add_child(foot)
	_load_label = UiKit.label("", "Small")
	_load_label.custom_minimum_size = Vector2(190, 0)
	foot.add_child(_load_label)
	_load_bar = TextureProgressBar.new()
	_load_bar.texture_under = ThemeBuilder.variant_texture(UI.theme_variant, ["bar_track"])
	_load_bar.texture_progress = ThemeBuilder.fill("xp")
	_load_bar.nine_patch_stretch = true
	_load_bar.stretch_margin_left = 6
	_load_bar.stretch_margin_right = 6
	_load_bar.stretch_margin_top = 6
	_load_bar.stretch_margin_bottom = 6
	_load_bar.min_value = 0.0
	_load_bar.max_value = 1.0
	_load_bar.step = 0.0
	_load_bar.custom_minimum_size = Vector2(0, 18)
	_load_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_load_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_load_bar)
	_marks_label = UiKit.label("", "Emphasis", HORIZONTAL_ALIGNMENT_RIGHT)
	_marks_label.custom_minimum_size = Vector2(170, 0)
	foot.add_child(_marks_label)
	var close := UiKit.button("Close", "FlatButton")
	close.pressed.connect(func() -> void: UI.close("inventory"))
	foot.add_child(close)
	UiKit.ink_in(frame, 0.0, 0.32)


func _make_slot_row(slot: String) -> Button:
	var b := UiKit.button("", "FlatButton")
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 40)
	b.clip_text = true
	b.expand_icon = true
	b.pressed.connect(func() -> void: _select_slot(slot))
	return b


# --- data --------------------------------------------------------------------------------

func _refresh() -> void:
	_refresh_doll()
	_refresh_list()
	_refresh_detail()
	_refresh_load()


func _refresh_doll() -> void:
	var slots: Dictionary = {}
	if _doll and is_instance_valid(_doll) and _doll.has_method("slots"):
		slots = _doll.call("slots")
	for slot: String in SLOT_ORDER:
		var b: Button = _slot_rows[slot]
		var item_id := str(slots.get(slot, ""))
		var def := ContentDB.get_or_empty(item_id)
		b.icon = ThemeBuilder.icon(UiKit.item_icon_name(def) if not def.is_empty() else str(SLOT_ICONS[slot]))
		b.text = "%s" % str(def.get("name", "—")) if not def.is_empty() else "%s" % SLOT_NAMES[slot]
		b.modulate = Color(1, 1, 1, 1.0 if not def.is_empty() else 0.5)
		b.tooltip_text = "%s\n%s" % [SLOT_NAMES[slot], str(def.get("description", ""))] if not def.is_empty() else str(SLOT_NAMES[slot])


func _items() -> Array:
	if _bag == null or not is_instance_valid(_bag) or not _bag.has_method("items"):
		return []
	var out: Array = []
	for it in _bag.call("items"):
		if _filter == "all" or str(it.get("category", "")) == _filter:
			out.append(it)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if str(a["category"]) != str(b["category"]):
				return str(a["category"]) < str(b["category"])
			return str(a["name"]) < str(b["name"]))
	return out


func _refresh_list() -> void:
	for child in _list_box.get_children():
		child.queue_free()
	for b in _filter_row.get_children():
		if b is Button:
			(b as Button).modulate = Color(1, 1, 1, 1.0 if (b as Button).text.to_lower() == _filter else 0.55)
	var items := _items()
	if items.is_empty():
		_list_box.add_child(UiKit.wrapped("Nothing of that kind.", "Journal"))
		return
	var buttons: Array[Control] = []
	var equipped := {}
	if _doll and is_instance_valid(_doll) and _doll.has_method("slots"):
		for slot in _doll.call("slots"):
			equipped[str(_doll.call("slots")[slot])] = true
	var i := 0
	for it in items:
		var def := ContentDB.get_or_empty(str(it["item_id"]))
		var row := UiKit.button("", "FlatButton")
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.custom_minimum_size = Vector2(0, 34)
		row.tooltip_text = "%s\n%s" % [str(it["name"]), str(it.get("description", ""))]
		var uid := int(it["uid"])
		row.pressed.connect(func() -> void:
				_selected_uid = uid
				_refresh_detail())
		var line := UiKit.row(8)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.set_anchors_preset(Control.PRESET_FULL_RECT)
		line.offset_left = 8.0
		line.offset_right = -8.0
		row.add_child(line)
		line.add_child(UiKit.icon_rect(UiKit.item_icon_name(def), 24))
		var mark := "  ·" if equipped.has(str(it["item_id"])) else ""
		var name_label := UiKit.label(str(it["name"]) + mark, "Body")
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.clip_text = true
		line.add_child(name_label)
		if int(it["count"]) > 1:
			line.add_child(UiKit.label("×%d" % int(it["count"]), "Small"))
		line.add_child(UiKit.label(UiKit.weight(float(it["weight"])), "Tiny"))
		_list_box.add_child(row)
		buttons.append(row)
		if i < 18:
			UiKit.ink_in(row, 0.012 * i, 0.2)
		i += 1
	UiKit.focus_chain(buttons)


func _selected() -> Dictionary:
	for it in _items():
		if int(it["uid"]) == _selected_uid:
			return it
	var items := _items()
	if not items.is_empty():
		_selected_uid = int(items[0]["uid"])
		return items[0]
	return {}


func _select_slot(slot: String) -> void:
	if _doll == null or not _doll.has_method("slots"):
		return
	var item_id := str(_doll.call("slots").get(slot, ""))
	if item_id.is_empty():
		_filter = "armour" if slot not in ["main_hand", "off_hand"] else "weapon"
		_refresh()
		return
	for it in _items():
		if str(it["item_id"]) == item_id:
			_selected_uid = int(it["uid"])
			break
	_refresh_detail()


func _refresh_detail() -> void:
	for child in _detail_box.get_children():
		child.queue_free()
	var it := _selected()
	if it.is_empty():
		return
	var def := ContentDB.get_or_empty(str(it["item_id"]))
	var head := UiKit.row(10)
	head.add_child(UiKit.icon_rect(UiKit.item_icon_name(def), 46))
	var titles := UiKit.column(0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(UiKit.wrapped(str(it["name"]), "Heading"))
	titles.add_child(UiKit.label(str(it.get("category", "")).capitalize(), "Small"))
	head.add_child(titles)
	_detail_box.add_child(head)
	_detail_box.add_child(UiKit.divider())

	var facts := UiKit.column(2)
	facts.add_child(_fact("Weight", UiKit.weight(float(it.get("unit_weight", 0.0)))))
	facts.add_child(_fact("Worth", "%s marks" % UiKit.marks(int(it.get("unit_value", 0)))))
	var weapon: Dictionary = def.get("weapon", {})
	if not weapon.is_empty():
		facts.add_child(_fact("Damage", str(weapon.get("damage", 0))))
		facts.add_child(_fact("Poise damage", str(weapon.get("poise_damage", 0))))
		facts.add_child(_fact("Reach", "%.1f m" % float(weapon.get("reach", 0.0))))
		if bool(weapon.get("parry", false)):
			facts.add_child(_fact("Parry", "yes"))
	var armour: Dictionary = def.get("armour", {})
	if not armour.is_empty():
		facts.add_child(_fact("Armour", str(armour.get("armour", 0))))
		facts.add_child(_fact("Class", str(armour.get("weight_class", ""))))
	var book := ContentDB.get_or_empty(str(it.get("reads", "")))
	var teaches := str(book.get("teaches_spell", ""))
	if teaches != "":
		var spell := ContentDB.get_or_empty(teaches)
		facts.add_child(_fact("The saying", str(spell.get("name", teaches))))
		facts.add_child(_fact("School", str(spell.get("school", "")).capitalize()))
		facts.add_child(_fact("Costs to say", "%d breath" % int(spell.get("cost", 0))))
	_detail_box.add_child(facts)
	_detail_box.add_child(UiKit.divider())
	_detail_box.add_child(UiKit.wrapped(str(it.get("description", "")), "Journal"))

	var actions := UiKit.row(8)
	if bool(it.get("equippable", false)):
		var equip := UiKit.button("Equip")
		equip.pressed.connect(func() -> void: _equip(int(it["uid"])))
		actions.add_child(equip)
	if bool(it.get("consumable", false)):
		var use := UiKit.button("Use")
		use.pressed.connect(func() -> void: _use(int(it["uid"])))
		actions.add_child(use)
	if bool(it.get("readable", false)):
		var read := UiKit.button("Read")
		read.pressed.connect(func() -> void: _read(int(it["uid"])))
		actions.add_child(read)
	var drop := UiKit.button("Drop", "FlatButton")
	drop.pressed.connect(func() -> void: _drop(int(it["uid"])))
	actions.add_child(drop)
	_detail_box.add_child(actions)
	UiKit.ink_in(_detail_box, 0.0, 0.24)


func _fact(key: String, value: String) -> HBoxContainer:
	var row := UiKit.row(8)
	var k := UiKit.label(key, "Small")
	k.custom_minimum_size = Vector2(130, 0)
	row.add_child(k)
	row.add_child(UiKit.label(value, "Body"))
	return row


func _refresh_load() -> void:
	if _bag == null or not is_instance_valid(_bag):
		return
	var w := float(_bag.call("weight")) if _bag.has_method("weight") else 0.0
	var cap := float(_bag.call("capacity")) if _bag.has_method("capacity") else 1.0
	_load_bar.value = clampf(w / maxf(cap, 0.001), 0.0, 1.0)
	_load_label.text = "Load  %s / %s" % [UiKit.weight(w), UiKit.weight(cap)]
	if w > cap:
		_load_label.text += "  (overloaded)"
	var marks := int(_bag.get("marks")) if _bag.get("marks") != null else 0
	_marks_label.text = "%s marks" % UiKit.marks(marks)


# --- actions --------------------------------------------------------------------------------

func _equip(uid: int) -> void:
	if _doll and _doll.has_method("equip"):
		_doll.call("equip", uid, "")
	_refresh()


func _use(uid: int) -> void:
	if _bag and _bag.has_method("use"):
		_bag.call("use", uid)
	_refresh()


func _read(uid: int) -> void:
	if _bag and _bag.has_method("read"):
		_bag.call("read", uid)
	_refresh()


func _drop(uid: int) -> void:
	if _bag and _bag.has_method("drop"):
		_bag.call("drop", uid, 1)
	_refresh()
