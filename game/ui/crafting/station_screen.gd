extends Control
## The working screens (DESIGN §5.8). One scene, three stations, because they are one idea:
## put things together and find out what they do.
##   forge      — recipes, what they cost, and tempering what you already own
##   alembic    — pick two or three ingredients; only the effects you know are named
##   name_table — write a note you have learned into a piece of gear, paid for in motes
##
## Reads the crafting stream through the group "crafting" and the bag through "inventory".

var station := "forge"
var _crafting: Node = null
var _bag: Node = null
var _selected := ""
var _picked: Array[String] = []
var _motes := 2
var _list_box: VBoxContainer
var _detail_box: VBoxContainer
var _title: Label
var _foot: Label

const TEMPER_PREFIX := "temper:"
const TITLES := {"forge": "The Forge", "alembic": "The Alembic", "name_table": "The Name-Table"}
const BLURB := {
	"forge": "Iron does what it is told, if you tell it the same thing often enough.",
	"alembic": "Two things that share an effect make a third thing. The rest is washing up.",
	"name_table": "A note you have learned, said again into something that will hold it.",
}


## `crafting` and `bag` are for a caller that has a particular pair in mind -- a test pressing
## the buttons, a review scene with a made-up character. In the game nothing passes them and
## the screen finds the real ones by their groups.
func setup(args: Dictionary) -> void:
	var wanted := str(args.get("station", "forge"))
	if wanted != station:
		_selected = ""
		_picked.clear()
		set_meta("enchant_target", 0)
	station = wanted
	if args.get("crafting", null) != null:
		_crafting = args["crafting"]
	if args.get("bag", null) != null:
		_bag = args["bag"]
	if is_inside_tree():
		_rebuild()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.dim())
	if _crafting == null:
		_crafting = get_tree().get_first_node_in_group("crafting")
	if _bag == null:
		_bag = get_tree().get_first_node_in_group("inventory")
	_build()
	if _crafting and _crafting.has_signal("known_changed"):
		_crafting.connect("known_changed", _rebuild)
	_rebuild()


func _build() -> void:
	var page := UiKit.page("")
	var frame: PanelContainer = page["frame"]
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(frame)
	UiFit.inset(frame, 90.0, 40.0)
	var body: VBoxContainer = page["body"]

	_title = UiKit.label("", "Title", HORIZONTAL_ALIGNMENT_CENTER)
	body.add_child(_title)
	_foot = UiKit.label("", "Journal", HORIZONTAL_ALIGNMENT_CENTER)
	# the bench's blurb wraps rather than widening the page past a narrow canvas (triage 28)
	_foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_foot)
	var narrow := UiFit.narrow(self)
	body.add_child(UiKit.divider())

	var columns := UiKit.row(20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(columns)
	_list_box = UiKit.column(3)
	_list_box.custom_minimum_size = Vector2(290 if narrow else 330, 0)
	var list_scroll := UiKit.scroll(_list_box)
	list_scroll.custom_minimum_size = Vector2(300 if narrow else 340, 0)
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(list_scroll)
	columns.add_child(VSeparator.new())
	_detail_box = UiKit.column(8)
	_detail_box.custom_minimum_size = Vector2(370 if narrow else 420, 0)
	var detail_scroll := UiKit.scroll(_detail_box)
	detail_scroll.custom_minimum_size = Vector2(380 if narrow else 430, 0)
	detail_scroll.size_flags_horizontal = Control.SIZE_FILL
	columns.add_child(detail_scroll)

	var close := UiKit.button("Leave it", "FlatButton")
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(func() -> void: UI.close("crafting"))
	body.add_child(close)
	UiKit.ink_in(frame, 0.0, 0.32)


func _rebuild() -> void:
	_title.text = str(TITLES.get(station, "The Bench"))
	_foot.text = str(BLURB.get(station, ""))
	for child in _list_box.get_children():
		child.queue_free()
	for child in _detail_box.get_children():
		child.queue_free()
	match station:
		"alembic": _build_alchemy()
		"name_table": _build_enchanting()
		_: _build_recipes()
	UiKit.ink_in(_list_box, 0.0, 0.26)
	UiKit.ink_in(_detail_box, 0.05, 0.26)


# --- the forge ---------------------------------------------------------------------------

func _recipes() -> Array:
	if _crafting and is_instance_valid(_crafting) and _crafting.has_method("recipes_for"):
		return _crafting.call("recipes_for", station)
	return []


## Everything in the bag this forge could take a hammer to, with what the next tier costs.
## `temper_preview` answers "not_temperable" for anything that is not a weapon or a piece of
## armour, and that is the whole filter: the list is your gear, whatever else you are carrying.
func _temperable() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _bag == null or not is_instance_valid(_bag) or not _bag.has_method("items"):
		return out
	if _crafting == null or not is_instance_valid(_crafting) or not _crafting.has_method("temper_preview"):
		return out
	for raw in _bag.call("items"):
		var it: Dictionary = raw
		var uid := int(it.get("uid", 0))
		var preview: Dictionary = _crafting.call("temper_preview", uid)
		if str(preview.get("reason", "")) in ["not_temperable", "no_item"]:
			continue
		out.append({"item": it, "preview": preview})
	return out


func _build_recipes() -> void:
	var recipes := _recipes()
	var gear := _temperable()
	if recipes.is_empty() and gear.is_empty():
		_list_box.add_child(UiKit.wrapped("Nothing here you know how to make.", "Journal"))
		return
	var buttons: Array[Control] = []
	var i := 0
	# Tempering what you already own (DESIGN 5.8). `Crafting.temper` and `temper_preview` were
	# a whole system with tests and no way in: no file under game/ui called either, so the
	# forge could make you a sword and could not improve the one on your hip.
	if not gear.is_empty():
		_list_box.add_child(UiKit.label("What you carry", "Small"))
		for row in gear:
			var it: Dictionary = row["item"]
			var preview: Dictionary = row["preview"]
			var uid := int(it.get("uid", 0))
			var can := bool(preview.get("ok", false))
			var b := UiKit.button("", "FlatButton")
			b.custom_minimum_size = Vector2(0, 36)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.pressed.connect(_select.bind(TEMPER_PREFIX + str(uid)))
			var line := UiKit.row(8)
			line.set_anchors_preset(Control.PRESET_FULL_RECT)
			line.offset_left = 8.0
			line.offset_right = -8.0
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(line)
			var def := ContentDB.get_or_empty(str(it.get("item_id", "")))
			line.add_child(UiKit.icon_rect(UiKit.item_icon_name(def), 24,
					Color(1, 1, 1, 1.0 if can else 0.45)))
			var name_label := UiKit.label(_temper_name(it, preview), "Body")
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_label.modulate = Color(1, 1, 1, 1.0 if can else 0.5)
			line.add_child(name_label)
			line.add_child(UiKit.label(_temper_blocker(preview) if not can
					else "%d %s" % [int(preview.get("cost", 0)),
					_material_name(str(preview.get("material", "")))], "Tiny"))
			_list_box.add_child(b)
			buttons.append(b)
			if i < 16:
				UiKit.ink_in(b, 0.012 * i, 0.2)
			i += 1
		if not recipes.is_empty():
			_list_box.add_child(UiKit.divider())
			_list_box.add_child(UiKit.label("What you can make", "Small"))

	for r in recipes:
		var can := bool(r.get("can_craft", false))
		var b := UiKit.button("", "FlatButton")
		b.custom_minimum_size = Vector2(0, 36)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var id := str(r["id"])
		b.pressed.connect(func() -> void:
				_selected = id
				_show_recipe())
		var line := UiKit.row(8)
		line.set_anchors_preset(Control.PRESET_FULL_RECT)
		line.offset_left = 8.0
		line.offset_right = -8.0
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(line)
		var out_def := ContentDB.get_or_empty(str(r.get("output", {}).get("item", "")))
		line.add_child(UiKit.icon_rect(UiKit.item_icon_name(out_def), 24,
				Color(1, 1, 1, 1.0 if can else 0.45)))
		var name_label := UiKit.label(str(r.get("name", "")), "Body")
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.modulate = Color(1, 1, 1, 1.0 if can else 0.5)
		line.add_child(name_label)
		if not can:
			line.add_child(UiKit.label(_recipe_blocker(r), "Tiny"))
		_list_box.add_child(b)
		buttons.append(b)
		if i < 16:
			UiKit.ink_in(b, 0.012 * i, 0.2)
		i += 1

	UiKit.focus_chain(buttons)
	if _selected.is_empty():
		# What you already own comes first, at the forge and in the list: it is why most people
		# walk up to an anvil, and it is the half that had no control at all until now.
		_selected = TEMPER_PREFIX + str(int((gear[0]["item"] as Dictionary).get("uid", 0))) \
				if not gear.is_empty() else str(recipes[0]["id"])
	_show_recipe()


## A method reference rather than a closure, so a list rebuilt out from under a press
## cannot take the screen with it.
func _select(what: String) -> void:
	_selected = what
	_show_recipe()


func _temper_name(it: Dictionary, preview: Dictionary) -> String:
	var tier := int(preview.get("tier", 0))
	return str(it.get("name", "")) if tier <= 0 else "%s +%d" % [str(it.get("name", "")), tier]


func _material_name(item_id: String) -> String:
	var def := ContentDB.get_or_empty(item_id)
	return str(def.get("name", Ids.name_of(item_id).capitalize()))


func _temper_blocker(preview: Dictionary) -> String:
	match str(preview.get("reason", "")):
		"max_temper": return "as good as it goes"
		"skill_too_low": return "smithing %d" % (int(preview.get("next_tier", 1)) * 10)
		"missing_materials": return "short"
		"no_inventory": return "no bag"
	return ""


func _recipe_blocker(r: Dictionary) -> String:
	match str(r.get("blocker", "")):
		"not_known": return "not known"
		"skill_too_low": return "skill %d" % int(r.get("requires_level", 0))
		"missing_materials": return "short"
		"wrong_station": return "elsewhere"
	return ""


func _show_recipe() -> void:
	if _selected.begins_with(TEMPER_PREFIX):
		_show_temper(int(_selected.substr(TEMPER_PREFIX.length())))
		return
	for child in _detail_box.get_children():
		child.queue_free()
	var recipe: Dictionary = {}
	for r in _recipes():
		if str(r["id"]) == _selected:
			recipe = r
	if recipe.is_empty():
		return
	var out_def := ContentDB.get_or_empty(str(recipe.get("output", {}).get("item", "")))
	var head := UiKit.row(10)
	head.add_child(UiKit.icon_rect(UiKit.item_icon_name(out_def), 44))
	var titles := UiKit.column(0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(UiKit.wrapped(str(recipe.get("name", "")), "Heading"))
	titles.add_child(UiKit.label("%s  ·  needs %s %d" % [station.capitalize().replace("_", " "),
			str(recipe.get("skill", "")), int(recipe.get("requires_level", 0))], "Small"))
	head.add_child(titles)
	_detail_box.add_child(head)
	_detail_box.add_child(UiKit.divider())
	_detail_box.add_child(UiKit.label("It takes", "Small"))
	for input in recipe.get("inputs", []):
		var def := ContentDB.get_or_empty(str(input.get("item", "")))
		var have := int(_bag.call("count", str(input.get("item", "")))) if _bag and _bag.has_method("count") else 0
		var need := int(input.get("count", 1))
		var row := UiKit.row(8)
		row.add_child(UiKit.icon_rect(UiKit.item_icon_name(def), 20))
		var label := UiKit.label("%s  %d / %d" % [str(def.get("name", "")), have, need], "Body")
		label.modulate = Color(1, 1, 1, 1.0 if have >= need else 0.55)
		row.add_child(label)
		_detail_box.add_child(row)
	_detail_box.add_child(UiKit.divider())
	_detail_box.add_child(UiKit.wrapped(str(out_def.get("description", "")), "Journal"))
	var make := UiKit.button("Make it")
	make.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	make.disabled = not bool(recipe.get("can_craft", false))
	var id := str(recipe["id"])
	make.pressed.connect(func() -> void:
			if _crafting and _crafting.has_method("craft"):
				_crafting.call("craft", id)
			_rebuild())
	_detail_box.add_child(make)


## What tempering this piece would cost and what it would make it. The tier the preview
## reports is the system's answer, not the screen's arithmetic: `temper_preview` is what it
## is for, and nothing called it.
func _show_temper(uid: int) -> void:
	for child in _detail_box.get_children():
		child.queue_free()
	var found: Dictionary = {}
	for row in _temperable():
		if int((row["item"] as Dictionary).get("uid", 0)) == uid:
			found = row
	if found.is_empty():
		return
	var it: Dictionary = found["item"]
	var preview: Dictionary = found["preview"]
	var def := ContentDB.get_or_empty(str(it.get("item_id", "")))
	var head := UiKit.row(10)
	head.add_child(UiKit.icon_rect(UiKit.item_icon_name(def), 44))
	var titles := UiKit.column(0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(UiKit.wrapped(_temper_name(it, preview), "Heading"))
	titles.add_child(UiKit.label("Tempering  ·  smithing", "Small"))
	head.add_child(titles)
	_detail_box.add_child(head)
	_detail_box.add_child(UiKit.divider())

	var material_id := str(preview.get("material", ""))
	var cost := int(preview.get("cost", 0))
	var have := int(_bag.call("count", material_id)) if _bag and _bag.has_method("count") else 0
	_detail_box.add_child(UiKit.label("It takes", "Small"))
	var row := UiKit.row(8)
	row.add_child(UiKit.icon_rect(UiKit.item_icon_name(ContentDB.get_or_empty(material_id)), 20))
	var mat_label := UiKit.label("%s  %d / %d" % [_material_name(material_id), have, cost], "Body")
	mat_label.modulate = Color(1, 1, 1, 1.0 if have >= cost else 0.55)
	row.add_child(mat_label)
	_detail_box.add_child(row)
	_detail_box.add_child(UiKit.divider())

	var tier := int(preview.get("tier", 0))
	var next_tier := int(preview.get("next_tier", tier + 1))
	var per_tier := int(round(float(preview.get("bonus_per_tier", 0.1)) * 100.0))
	if str(preview.get("reason", "")) == "max_temper":
		_detail_box.add_child(UiKit.wrapped(
				"+%d is as far as iron goes. There is nothing left to tell it." % tier, "Journal"))
	else:
		_detail_box.add_child(UiKit.wrapped(
				"+%d becomes +%d. Each tier is worth %d%% more, and the ceiling your smithing "
				% [tier, next_tier, per_tier]
				+ "allows is +%d." % int(preview.get("max_tier", 0)), "Journal"))
	var blocker := _temper_blocker(preview)
	if blocker != "":
		_detail_box.add_child(UiKit.label(blocker, "Small"))

	var strike := UiKit.button("Temper it")
	strike.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	strike.disabled = not bool(preview.get("ok", false))
	strike.pressed.connect(_temper.bind(uid))
	_detail_box.add_child(strike)


func _temper(uid: int) -> void:
	if _crafting and is_instance_valid(_crafting) and _crafting.has_method("temper"):
		var r: Dictionary = _crafting.call("temper", uid)
		if bool(r.get("ok", false)):
			# Tempering splits a stack, so the piece that was improved has a new uid.
			var stack: Variant = r.get("stack")
			if stack != null and is_instance_valid(stack):
				_selected = TEMPER_PREFIX + str(int(stack.uid))
	_rebuild()


# --- the alembic --------------------------------------------------------------------------

func _build_alchemy() -> void:
	var ingredients: Array = []
	if _crafting and is_instance_valid(_crafting) and _crafting.has_method("ingredients"):
		ingredients = _crafting.call("ingredients")
	if ingredients.is_empty():
		_list_box.add_child(UiKit.wrapped("You are carrying nothing worth boiling.", "Journal"))
		return
	var buttons: Array[Control] = []
	for ing in ingredients:
		var item_id := str(ing.get("item", ing.get("item_id", "")))
		var def := ContentDB.get_or_empty(item_id)
		var b := UiKit.button("", "FlatButton")
		b.custom_minimum_size = Vector2(0, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		b.button_pressed = _picked.has(item_id)
		b.pressed.connect(func() -> void: _toggle_ingredient(item_id))
		var line := UiKit.row(8)
		line.set_anchors_preset(Control.PRESET_FULL_RECT)
		line.offset_left = 8.0
		line.offset_right = -8.0
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(line)
		line.add_child(UiKit.icon_rect(UiKit.item_icon_name(def), 24))
		var name_label := UiKit.label(str(def.get("name", item_id)), "Body")
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		var known := 0
		for e in ing.get("effects", []):
			if bool(e.get("known", false)):
				known += 1
		line.add_child(UiKit.label("%d of 4 known" % known, "Tiny"))
		if int(ing.get("count", 1)) > 1:
			line.add_child(UiKit.label("×%d" % int(ing["count"]), "Small"))
		_list_box.add_child(b)
		buttons.append(b)
	UiKit.focus_chain(buttons)
	_show_brew(ingredients)


func _toggle_ingredient(item_id: String) -> void:
	if _picked.has(item_id):
		_picked.erase(item_id)
	elif _picked.size() < 3:
		_picked.append(item_id)
	_rebuild()


func _show_brew(ingredients: Array) -> void:
	for child in _detail_box.get_children():
		child.queue_free()
	_detail_box.add_child(UiKit.label("In the pot", "Heading"))
	if _picked.is_empty():
		_detail_box.add_child(UiKit.wrapped("Pick two, or three if you are feeling brave.", "Journal"))
	for item_id in _picked:
		var def := ContentDB.get_or_empty(item_id)
		var row := UiKit.row(8)
		row.add_child(UiKit.icon_rect(UiKit.item_icon_name(def), 22))
		row.add_child(UiKit.label(str(def.get("name", item_id)), "Body"))
		_detail_box.add_child(row)
		for ing in ingredients:
			if str(ing.get("item", ing.get("item_id", ""))) != item_id:
				continue
			for e in ing.get("effects", []):
				var known := bool(e.get("known", false))
				var line := UiKit.label("    %s" % (str(e.get("name", "?")) if known else "— not yet known —"), "Tiny")
				line.modulate = Color(1, 1, 1, 1.0 if known else 0.5)
				_detail_box.add_child(line)
	_detail_box.add_child(UiKit.divider())
	var shared: Array = []
	if _picked.size() >= 2 and _crafting and _crafting.has_method("known_effects"):
		shared = Alchemy.shared_effects(_picked)
	if not shared.is_empty():
		_detail_box.add_child(UiKit.label("They agree on", "Small"))
		for eid in shared:
			var known: bool = _crafting.call("known_effects", str(_picked[0])).has(eid)
			var def := ContentDB.get_or_empty(str(eid))
			_detail_box.add_child(UiKit.label(str(def.get("name", "?")) if known else "something", "Body"))
	var brew := UiKit.button("Brew it")
	brew.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	brew.disabled = _picked.size() < 2
	brew.pressed.connect(func() -> void:
			if _crafting and _crafting.has_method("combine"):
				var result: Dictionary = _crafting.call("combine", _picked)
				if bool(result.get("ok", false)):
					EventBus.emit_notify("Brewed: %s" % str(ContentDB.get_or_empty(str(result.get("item_id", ""))).get("name", "")), "item")
				else:
					EventBus.emit_notify("Nothing but a smell.", "warning")
			_picked.clear()
			_rebuild())
	_detail_box.add_child(brew)


# --- the name-table -----------------------------------------------------------------------

func _build_enchanting() -> void:
	var notes: Array = []
	if _crafting and is_instance_valid(_crafting) and _crafting.has_method("enchantments"):
		notes = _crafting.call("enchantments")
	var known: Array = []
	for n in notes:
		if bool(n.get("known", false)):
			known.append(n)
	_list_box.add_child(UiKit.label("Notes you have learned", "Heading"))
	if known.is_empty():
		_list_box.add_child(UiKit.wrapped("None yet. Take something enchanted apart to learn what is in it.", "Journal"))
	var buttons: Array[Control] = []
	for n in known:
		var b := UiKit.button(str(n.get("name", "")), "FlatButton")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var eid := str(n.get("effect", ""))
		b.pressed.connect(func() -> void:
				_selected = eid
				_rebuild())
		_list_box.add_child(b)
		buttons.append(b)
	_list_box.add_child(UiKit.divider())
	_list_box.add_child(UiKit.label("What you could write on", "Heading"))
	var items: Array = []
	if _bag and _bag.has_method("items"):
		for it in _bag.call("items"):
			if bool(it.get("equippable", false)):
				items.append(it)
	for it in items:
		var def := ContentDB.get_or_empty(str(it["item_id"]))
		var b := UiKit.button(str(it["name"]), "FlatButton")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.icon = ThemeBuilder.icon(UiKit.item_icon_name(def))
		b.expand_icon = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var uid := int(it["uid"])
		b.pressed.connect(func() -> void:
				set_meta("enchant_target", uid)
				_show_enchant())
		_list_box.add_child(b)
		buttons.append(b)
	UiKit.focus_chain(buttons)
	_show_enchant()


func _show_enchant() -> void:
	for child in _detail_box.get_children():
		child.queue_free()
	var preview: Dictionary = {}
	if _crafting and _crafting.has_method("enchant_preview") and Ids.type_of(_selected) == "effect":
		preview = _crafting.call("enchant_preview", _selected, _motes)
	var note := ContentDB.get_or_empty(_selected) if Ids.type_of(_selected) == "effect" else {}
	_detail_box.add_child(UiKit.label(str(note.get("name", "Pick a note")), "Heading"))
	if not note.is_empty():
		_detail_box.add_child(UiKit.wrapped(str(note.get("description", "")), "Journal"))
	var target_uid := int(get_meta("enchant_target", 0))
	var target_name := "nothing yet"
	if _bag and _bag.has_method("items"):
		for it in _bag.call("items"):
			if int(it["uid"]) == target_uid:
				target_name = str(it["name"])
	_detail_box.add_child(UiKit.divider())
	_detail_box.add_child(UiKit.label("On:  %s" % target_name, "Body"))

	var motes_row := UiKit.row(8)
	motes_row.add_child(UiKit.label("Motes", "Small"))
	var slider := HSlider.new()
	slider.min_value = 1
	slider.max_value = 5
	slider.step = 1
	slider.value = _motes
	slider.custom_minimum_size = Vector2(150, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(v: float) -> void:
			_motes = int(v)
			_show_enchant())
	motes_row.add_child(slider)
	motes_row.add_child(UiKit.label(str(_motes), "Body"))
	_detail_box.add_child(motes_row)

	if not preview.is_empty():
		for key in ["magnitude", "duration", "charge"]:
			if preview.has(key):
				_detail_box.add_child(UiKit.label("%s  %s" % [str(key).capitalize(), str(preview[key])], "Small"))
	# The table says why it will not take a note before the button is pressed, as the forge does.
	var check := {"ok": false}
	if Ids.type_of(_selected) == "effect" and target_uid != 0 and _crafting and _crafting.has_method("enchant_check"):
		check = _crafting.call("enchant_check", target_uid, _selected, _motes)
		var why := str(check.get("why", ""))
		if not why.is_empty():
			_detail_box.add_child(UiKit.wrapped(why, "Small"))
	var write := UiKit.button("Write it in")
	write.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	write.disabled = Ids.type_of(_selected) != "effect" or target_uid == 0 or not bool(check.get("ok", false))
	write.pressed.connect(func() -> void:
			if _crafting and _crafting.has_method("enchant"):
				_crafting.call("enchant", target_uid, _selected, _motes)
			_rebuild())
	_detail_box.add_child(write)
