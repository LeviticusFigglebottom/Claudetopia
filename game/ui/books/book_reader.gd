extends Control
## The book reader (DESIGN §5.17): a two-page parchment spread, markdown-lite, turned with
## the keys or the pad. Opening one marks it read in GameState, which is what puts it in the
## journal's Books tab.
##
## Opened by EventBus.book_opened(book_id), which UI turns into UI.open("book", {book_id}).

const CHARS_PER_PAGE := 560

var book_id := ""
var _pages: PackedStringArray = []
var _spread := 0
var _left: RichTextLabel
var _right: RichTextLabel
var _title: Label
var _author: Label
var _footer: Label
var _prev: Button
var _next: Button


func setup(args: Dictionary) -> void:
	book_id = str(args.get("book_id", ""))
	if is_inside_tree():
		_load_book()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.dim(0.72))
	_build()
	_load_book()


func _build() -> void:
	var frame := UiKit.panel("OakPanel")
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(frame)
	UiFit.inset(frame, 110.0, 40.0)

	var col := UiKit.column(8)
	frame.add_child(col)
	_title = UiKit.label("", "Title", HORIZONTAL_ALIGNMENT_CENTER)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_title)
	_author = UiKit.label("", "Small", HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_author)
	col.add_child(UiKit.divider())

	var spread := UiKit.row(28)
	spread.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spread)
	_left = _make_page()
	spread.add_child(_left)
	var gutter := VSeparator.new()
	spread.add_child(gutter)
	_right = _make_page()
	spread.add_child(_right)

	var foot := UiKit.row(12)
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(foot)
	_prev = UiKit.button("‹  Back", "FlatButton")
	_prev.pressed.connect(func() -> void: turn(-1))
	foot.add_child(_prev)
	_footer = UiKit.label("", "Small", HORIZONTAL_ALIGNMENT_CENTER)
	_footer.custom_minimum_size = Vector2(220, 0)
	foot.add_child(_footer)
	_next = UiKit.button("On  ›", "FlatButton")
	_next.pressed.connect(func() -> void: turn(1))
	foot.add_child(_next)
	var close := UiKit.button("Close", "FlatButton")
	close.pressed.connect(func() -> void: UI.close("book"))
	foot.add_child(close)
	UiKit.focus_chain([_prev, _next, close], false)
	UiKit.ink_in(frame, 0.0, 0.35)


func _make_page() -> RichTextLabel:
	var r := UiKit.rich("")
	r.fit_content = false
	r.scroll_active = false
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return r


# --- content ----------------------------------------------------------------------------------

func _load_book() -> void:
	var def := ContentDB.get_or_empty(book_id)
	if def.is_empty():
		_title.text = "A book with no words in it"
		_author.text = ""
		_pages = PackedStringArray([""])
		_spread = 0
		_render()
		return
	var title := str(def.get("title", ""))
	_title.text = title
	_title.theme_type_variation = &"Heading" if title.length() > 38 else &"Title"
	_author.text = str(def.get("author", ""))
	_pages = paginate(str(def.get("body", "")), CHARS_PER_PAGE)
	_spread = 0
	GameState.mark_book_read(book_id)
	_render()


## Splits markdown-lite into pages on paragraph boundaries, keeping a heading with what
## follows it. Pure and static so it can be checked without a scene.
static func paginate(body: String, budget: int) -> PackedStringArray:
	var blocks := PackedStringArray()
	var current := ""
	for raw in body.split("\n"):
		var line := raw.strip_edges(false, true)
		if line.is_empty():
			if not current.strip_edges().is_empty():
				blocks.append(current)
			current = ""
		else:
			current += ("\n" if not current.is_empty() else "") + line
	if not current.strip_edges().is_empty():
		blocks.append(current)

	var pages := PackedStringArray()
	var page := ""
	var cost := 0
	for i in blocks.size():
		var block := blocks[i]
		# a heading is cheap in characters and expensive in room, and never ends a page
		var is_heading := block.begins_with("#")
		var block_cost := block.length() + (140 if is_heading else 30)
		if cost > 0 and cost + block_cost > budget and not (is_heading and cost > budget * 0.8):
			pages.append(page)
			page = ""
			cost = 0
		page += ("\n\n" if not page.is_empty() else "") + block
		cost += block_cost
	if not page.strip_edges().is_empty():
		pages.append(page)
	if pages.is_empty():
		pages.append("")
	if pages.size() % 2 == 1:
		pages.append("")
	return pages


func _render() -> void:
	var left_index := _spread * 2
	_left.text = UiKit.markdown_lite(_pages[left_index]) if left_index < _pages.size() else ""
	_right.text = UiKit.markdown_lite(_pages[left_index + 1]) if left_index + 1 < _pages.size() else ""
	var spreads := int(ceil(float(_pages.size()) / 2.0))
	_footer.text = "%d of %d" % [_spread + 1, maxi(spreads, 1)]
	_prev.disabled = _spread <= 0
	_next.disabled = _spread >= spreads - 1
	UiKit.ink_in(_left, 0.0, 0.25)
	UiKit.ink_in(_right, 0.04, 0.25)


func turn(direction: int) -> void:
	var spreads := int(ceil(float(_pages.size()) / 2.0))
	var wanted := clampi(_spread + direction, 0, maxi(spreads - 1, 0))
	if wanted == _spread:
		return
	_spread = wanted
	_render()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_page_down"):
		turn(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_page_up"):
		turn(-1)
		get_viewport().set_input_as_handled()
