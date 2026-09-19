class_name UiKit
extends RefCounted
## Small shared builders so every Wickmere screen is put together the same way:
## the same paper, the same rules, the same "fade in from ink" arrival, the same
## focus wiring for a controller. Screens build their controls in code from these.

const ICON_SIZE := 32


# --- construction ---------------------------------------------------------------------

static func label(text: String, variation := "Body", align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = StringName(variation)
	l.horizontal_alignment = align
	return l


static func wrapped(text: String, variation := "Body", width := 0.0) -> Label:
	var l := label(text, variation)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if width > 0.0:
		l.custom_minimum_size.x = width
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func rich(text: String, width := 0.0) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.text = text
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if width > 0.0:
		r.custom_minimum_size.x = width
	return r


static func button(text: String, variation := "") -> Button:
	var b := Button.new()
	b.text = text
	if not variation.is_empty():
		b.theme_type_variation = StringName(variation)
	b.focus_mode = Control.FOCUS_ALL
	return b


static func icon_button(icon_name: String, tip := "", size := 30) -> Button:
	var b := button("", "FlatButton")
	b.icon = ThemeBuilder.icon(icon_name)
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(size + 14, size + 10)
	b.expand_icon = true
	return b


static func icon_rect(icon_name: String, size := ICON_SIZE, tint := Color(1, 1, 1, 1)) -> TextureRect:
	var t := TextureRect.new()
	t.texture = ThemeBuilder.icon(icon_name)
	t.custom_minimum_size = Vector2(size, size)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.modulate = tint
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


static func panel(variation := "FramedPanel") -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = StringName(variation)
	return p


static func column(separation := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	return v


static func row(separation := 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	return h


static func margins(control: Control, l: int, t: int, r: int, b: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", l)
	m.add_theme_constant_override("margin_top", t)
	m.add_theme_constant_override("margin_right", r)
	m.add_theme_constant_override("margin_bottom", b)
	m.add_child(control)
	return m


static func spacer(min_size := 0.0, vertical := false) -> Control:
	var c := Control.new()
	if vertical:
		c.custom_minimum_size.y = min_size
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL if min_size <= 0.0 else Control.SIZE_FILL
	else:
		c.custom_minimum_size.x = min_size
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL if min_size <= 0.0 else Control.SIZE_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## The inked rule with a brass lozenge, used to break a page. The line stretches to any
## width; the lozenge keeps its size and stays in the middle.
static func divider(width := 0.0) -> Control:
	var deep := UI.theme_variant != "warm"
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(width, 20)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var line := NinePatchRect.new()
	line.texture = ThemeBuilder.texture("rule_line_deep" if deep else "rule_line")
	line.patch_margin_left = 8
	line.patch_margin_right = 8
	line.set_anchors_preset(Control.PRESET_FULL_RECT)
	line.offset_top = 2.0
	line.offset_bottom = -2.0
	line.modulate.a = 0.8
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(line)

	var mark := TextureRect.new()
	mark.texture = ThemeBuilder.texture("rule_mark_deep" if deep else "rule_mark")
	mark.set_anchors_preset(Control.PRESET_CENTER)
	mark.anchor_left = 0.5
	mark.anchor_right = 0.5
	mark.anchor_top = 0.5
	mark.anchor_bottom = 0.5
	mark.offset_left = -20.0
	mark.offset_right = 20.0
	mark.offset_top = -12.0
	mark.offset_bottom = 12.0
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(mark)
	return holder


static func scroll(child: Control, horizontal := false) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if horizontal else ScrollContainer.SCROLL_MODE_DISABLED
	s.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.follow_focus = true
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s


## A full-screen dim behind a screen, so the world reads as "set aside".
static func dim(alpha := 0.62) -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(0.06, 0.05, 0.04, alpha)
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	return c


## The page a screen is written on: a parchment sheet inside a brass frame.
static func page(title: String, variation := "FramedPanel") -> Dictionary:
	var frame := panel(variation)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var col := column(12)
	frame.add_child(col)
	if not title.is_empty():
		var head := label(title, "Title", HORIZONTAL_ALIGNMENT_CENTER)
		col.add_child(head)
		col.add_child(divider())
	var body := column(10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	return {"frame": frame, "column": col, "body": body}


# --- arrival --------------------------------------------------------------------------

## DESIGN §9: UI arrives "from ink" — dark and transparent, settling into paper.
## Only `modulate` is animated: a container owns its children's position and size, and a
## tween that fights it piles every control on top of the first one.
static func ink_in(control: Control, delay := 0.0, seconds := 0.40, _drift := 0.0) -> void:
	if control == null:
		return
	control.modulate = Color(0.30, 0.24, 0.19, 0.0)
	var tw := control.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(control, "modulate", Color(1, 1, 1, 1), seconds).set_trans(Tween.TRANS_CUBIC)


static func ink_out(control: Control, seconds := 0.25) -> void:
	if control == null:
		return
	var tw := control.create_tween()
	tw.tween_property(control, "modulate", Color(0.28, 0.22, 0.18, 0.0), seconds)


# --- controller focus -----------------------------------------------------------------

## Wires up/down (or left/right) neighbours through a list and focuses the first.
static func focus_chain(controls: Array, vertical := true, wrap := true) -> void:
	var live: Array[Control] = []
	for c in controls:
		if c is Control and (c as Control).focus_mode != Control.FOCUS_NONE:
			live.append(c)
	for i in live.size():
		var prev: Control = live[(i - 1 + live.size()) % live.size()] if wrap else live[maxi(i - 1, 0)]
		var next: Control = live[(i + 1) % live.size()] if wrap else live[mini(i + 1, live.size() - 1)]
		if vertical:
			live[i].focus_neighbor_top = prev.get_path()
			live[i].focus_neighbor_bottom = next.get_path()
			live[i].focus_previous = prev.get_path()
			live[i].focus_next = next.get_path()
		else:
			live[i].focus_neighbor_left = prev.get_path()
			live[i].focus_neighbor_right = next.get_path()
			live[i].focus_previous = prev.get_path()
			live[i].focus_next = next.get_path()


static func focus_first(root: Node) -> void:
	var c := _first_focusable(root)
	if c:
		c.grab_focus()


static func _first_focusable(node: Node) -> Control:
	for child in node.get_children():
		if child is Control:
			var c := child as Control
			if c.focus_mode == Control.FOCUS_ALL and c.visible and not c.is_queued_for_deletion():
				return c
		var deeper := _first_focusable(child)
		if deeper:
			return deeper
	return null


# --- content helpers -------------------------------------------------------------------

## Which of the 32 drawn icons stands for an item.
static func item_icon_name(def: Dictionary) -> String:
	if def.has("icon"):
		return str(def["icon"])
	var tags: Array = def.get("tags", [])
	var category := str(def.get("category", ""))
	if tags.has("shield"):
		return "shield"
	if tags.has("ring"):
		return "ring"
	if tags.has("amulet") or tags.has("jewellery"):
		return "amulet"
	if def.has("weapon"):
		match str(def["weapon"].get("class", "")):
			"bow", "crossbow": return "bow"
			"staff": return "staff"
			"axe", "greataxe": return "axe"
			"hammer", "mace", "maul": return "hammer"
			_: return "sword"
	if def.has("armour"):
		match str(def["armour"].get("slot", "")):
			"head": return "helm"
			"feet": return "boots"
			"hands", "body": return "tunic"
			"off_hand": return "shield"
			"ring", "ring_1", "ring_2": return "ring"
			"amulet": return "amulet"
			_: return "tunic"
	if tags.has("potion"):
		return "potion"
	if tags.has("letter") or category == "book":
		return "book"
	if tags.has("light"):
		return "hearth"
	match category:
		"consumable": return "potion" if tags.has("potion") else "food"
		"ingredient": return "ingredient"
		"material": return "hammer"
		"key": return "key"
		"book": return "book"
		"tool": return "alembic" if tags.has("alchemy") else "hammer"
	return "coin"


static func item_icon(def: Dictionary, size := ICON_SIZE) -> TextureRect:
	return icon_rect(item_icon_name(def), size)


## "1 240 marks" reads better on paper than "1240".
static func marks(value: int) -> String:
	var s := str(absi(value))
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if value < 0 else "") + s + out


static func weight(value: float) -> String:
	return "%.1f" % value


static func play_time(seconds: float) -> String:
	var total := int(seconds)
	return "%d:%02d" % [total / 3600, (total % 3600) / 60]


## Markdown-lite used by books and item lore: `#` headings, *italics*, blank-line paragraphs.
static func markdown_lite(text: String) -> String:
	var out := PackedStringArray()
	for raw in text.split("\n"):
		var line := raw.strip_edges(false, true)
		if line.begins_with("---") and line.strip_edges().replace("-", "").is_empty():
			out.append("[center]·   ·   ·[/center]")
		elif line.begins_with("### "):
			out.append("[font_size=19][b]%s[/b][/font_size]" % _inline(line.substr(4)))
		elif line.begins_with("## "):
			out.append("[font_size=22][b]%s[/b][/font_size]" % _inline(line.substr(3)))
		elif line.begins_with("# "):
			out.append("[center][font_size=26]%s[/font_size][/center]" % _inline(line.substr(2)))
		elif line.begins_with("> "):
			out.append("[i]    %s[/i]" % _inline(line.substr(2)))
		else:
			out.append(_inline(line))
	return "\n".join(out)


static func _inline(text: String) -> String:
	var out := ""
	var italic := false
	var i := 0
	while i < text.length():
		var ch := text[i]
		if ch == "*":
			out += "[i]" if not italic else "[/i]"
			italic = not italic
		elif ch == "[":
			out += "[lb]"
		else:
			out += ch
		i += 1
	if italic:
		out += "[/i]"
	return out
