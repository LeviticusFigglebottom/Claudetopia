extends Control
## The Naming (DESIGN §5.1). Character creation is in the fiction: a Warden is standing over
## you asking what you are called, and what you were before you were pulled out of the Hush.
##
## The look is a `CharacterAppearance`, the same record the humanoid model composes a body
## from and an NPC def carries inline, edited in place by the controls: every swatch, chooser
## and slider names a tone, a part or a proportion in that record's own vocabulary. It used to
## keep a private one (swatch indices, `height_m`, a head named after a culture) and hand that
## to the model, which read none of it: the preview never changed and neither did the body in
## the world, whatever was chosen.
##
## Writes GameState flags and nothing else:
##   player_name        String
##   player_calling     a `calling` id
##   player_appearance  CharacterAppearance.to_dict()
##   new_game           true
## "Be named" then fades to black and changes to the world scene; the player picks the flags up
## when it stands (`Player._take_the_naming`).

const WORLD_SCENE := "res://world/world.tscn"
const MENU_SCENE := "res://ui/menus/main_menu.tscn"
const MODEL_SCENE := "res://actors/shared/humanoid_model.tscn"

## What the vocabulary is called out loud.
const SKIN_NAMES := {"porcelain": "Porcelain", "fair": "Fair", "wheat": "Wheat", "olive": "Olive",
	"amber": "Amber", "umber": "Umber", "deep": "Deep", "ebony": "Ebony"}
const HAIR_STYLE_NAMES := {"short": "Short", "cropped": "Cropped", "long": "Loose", "braid": "Braided",
	"bun": "Tied back", "hood_friendly": "Under a hood", "tousled": "Wild"}
const HEAD_NAMES := {"default": "Even", "round": "Round", "soft": "Soft", "angular": "Angular",
	"narrow": "Narrow", "broad": "Broad", "hawk": "Hawkish", "heavy_brow": "Heavy-browed"}
const BEARD_NAMES := {"": "None", "stubble": "Stubble", "short_beard": "Short", "long_beard": "Long",
	"moustache": "Moustache"}
const BUILD_WORDS := ["slight", "lean", "even", "solid", "broad"]
## What the loading caption says between "Be named" and the first look at the world.
const LOADING_LINE := "The Warden walks you out of the Hush. Keep up; she does not look back."

var appearance := CharacterAppearance.new()
var calling_id := ""
var player_name := ""
## Where "Be named" goes. A test points this at "" so the press stops at the flags instead of
## tearing the test runner down with a scene change.
var world_scene := WORLD_SCENE

var _name_edit: LineEdit
var _suggest_row: HBoxContainer
var _calling_box: GridContainer
var _calling_detail: VBoxContainer
var _preview: SubViewport
var _mannequin: Node3D
var _model: Node = null
var _begin: Button
var _choosers: Dictionary = {}     # key -> OptionButton
var _sliders: Dictionary = {}      # key -> HSlider
var _spin := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	UI.apply_theme(self)
	UI.close_all()
	UI.hide_hud()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	appearance.set_part("head", "default")
	appearance.set_part("hair", "short")
	var callings := ContentDB.all("calling")
	if not callings.is_empty():
		calling_id = str(callings[0].get("id", ""))
	player_name = ValishNames.suggestions(1, 20260919)[0]
	_build()
	_refresh_calling()
	_apply_appearance()
	# somewhere for a pad to start from; nothing had focus, so its first press did nothing
	_name_edit.grab_focus()


# --- construction -----------------------------------------------------------------------------

func _build() -> void:
	var back := TextureRect.new()
	back.texture = ThemeBuilder.texture("paper_sheet")
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.stretch_mode = TextureRect.STRETCH_SCALE
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.modulate = Color(0.72, 0.68, 0.62)
	add_child(back)

	var page := UiKit.page("")
	var frame: PanelContainer = page["frame"]
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 36.0
	frame.offset_top = 20.0
	frame.offset_right = -36.0
	frame.offset_bottom = -20.0
	add_child(frame)
	var body: VBoxContainer = page["body"]
	body.add_theme_constant_override("separation", 6)

	body.add_child(UiKit.label("The Naming", "Title", HORIZONTAL_ALIGNMENT_CENTER))
	var blurb := UiKit.label(
		"You came up the Hushline Stair with nothing. A Warden is asking what you are called, " +
		"and she is not going to guess.", "Journal", HORIZONTAL_ALIGNMENT_CENTER)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(blurb)
	body.add_child(UiKit.divider())

	var columns := UiKit.row(16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(columns)
	columns.add_child(_build_preview())
	columns.add_child(VSeparator.new())
	columns.add_child(_build_middle())
	columns.add_child(VSeparator.new())
	columns.add_child(_build_callings())

	var foot := UiKit.row(14)
	foot.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(foot)
	var back_button := UiKit.button("Back", "FlatButton")
	back_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(MENU_SCENE))
	foot.add_child(back_button)
	_begin = UiKit.button("Be named")
	_begin.pressed.connect(_begin_game)
	foot.add_child(_begin)
	UiKit.ink_in(frame, 0.0, 0.4)


func _build_preview() -> Control:
	var holder := UiKit.column(6)
	holder.custom_minimum_size = Vector2(236, 0)

	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = Vector2(232, 380)
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.add_child(container)

	_preview = SubViewport.new()
	_preview.size = Vector2i(232, 380)
	_preview.transparent_bg = true
	_preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(_preview)

	var world := Node3D.new()
	_preview.add_child(world)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.10, 0.09, 0.08)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.52, 0.48)
	environment.ambient_light_energy = 0.6
	env.environment = environment
	world.add_child(env)

	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.94, 0.84)
	key.light_energy = 2.0
	key.rotation_degrees = Vector3(-38, 38, 0)
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.68, 0.74, 0.86)
	fill.light_energy = 0.7
	fill.rotation_degrees = Vector3(-14, -140, 0)
	world.add_child(fill)

	var camera := Camera3D.new()
	camera.fov = 34.0
	camera.look_at_from_position(Vector3(0.0, 1.12, 3.3), Vector3(0.0, 0.98, 0.0), Vector3.UP)
	world.add_child(camera)

	_mannequin = Node3D.new()
	# turned every frame below, so it must not also be interpolated between physics ticks
	_mannequin.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	world.add_child(_mannequin)
	if ResourceLoader.exists(MODEL_SCENE):
		_model = (load(MODEL_SCENE) as PackedScene).instantiate()
		_mannequin.add_child(_model)

	var caption := UiKit.label("The forge has not made a body yet.", "Tiny", HORIZONTAL_ALIGNMENT_CENTER)
	caption.visible = _model == null
	holder.add_child(caption)
	return holder


func _build_middle() -> Control:
	var col := UiKit.column(6)
	col.custom_minimum_size = Vector2(330, 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	col.add_child(UiKit.label("What are you called?", "Heading"))
	_name_edit = LineEdit.new()
	_name_edit.text = player_name
	_name_edit.placeholder_text = "a name, said out loud"
	_name_edit.max_length = 28
	_name_edit.text_changed.connect(func(text: String) -> void:
			player_name = text
			_update_begin())
	col.add_child(_name_edit)

	_suggest_row = UiKit.row(6)
	col.add_child(_suggest_row)
	_roll_suggestions()

	col.add_child(UiKit.divider())
	col.add_child(UiKit.label("What you look like", "Heading"))
	col.add_child(_swatches("Skin", CharacterAppearance.SKIN_TONES, "skin"))
	col.add_child(_swatches("Hair", CharacterAppearance.HAIR_COLOURS, "hair_colour"))
	col.add_child(_swatches("Eyes", CharacterAppearance.EYE_COLOURS, "eye_colour"))

	# two to a row: three choosers abreast, each sized to its longest word, wanted more width
	# than the page has at 1280x720 and pushed the Callings off the right edge
	var parts := UiKit.row(14)
	parts.add_child(_chooser("Style", CharacterAppearance.HAIR_STYLES, HAIR_STYLE_NAMES, "hair"))
	parts.add_child(_chooser("Face", CharacterAppearance.HEADS, HEAD_NAMES, "head"))
	col.add_child(parts)
	var beards: Array = [""]
	beards.append_array(CharacterAppearance.BEARD_STYLES)
	var more := UiKit.row(14)
	more.add_child(_chooser("Beard", beards, BEARD_NAMES, "beard"))
	more.add_child(_slider("Build", "build", 0.0, 1.0, 0.05))
	col.add_child(more)
	col.add_child(_slider("Height", "height", 1.55, 1.95, 0.01))
	return UiKit.scroll(col)


func _labelled(text: String, control: Control, label_width := 62.0) -> HBoxContainer:
	var row := UiKit.row(8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := UiKit.label(text, "Small")
	label.custom_minimum_size = Vector2(label_width, 0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	return row


## A row of coloured squares over one of the record's colour tables. The button carries the
## tone's name in `tone` metadata, so a test or a probe can find "the olive swatch".
func _swatches(text: String, tones: Array, key: String) -> HBoxContainer:
	var row := UiKit.row(3)
	for tone in tones:
		var name := str(tone)
		var b := Button.new()
		b.theme_type_variation = &"FlatButton"
		b.custom_minimum_size = Vector2(27, 27)
		b.tooltip_text = "%s: %s" % [text, _tone_name(key, name)]
		b.set_meta("tone", name)
		var swatch := ColorRect.new()
		swatch.color = _tone_colour(key, name)
		swatch.set_anchors_preset(Control.PRESET_FULL_RECT)
		swatch.offset_left = 4.0
		swatch.offset_top = 4.0
		swatch.offset_right = -4.0
		swatch.offset_bottom = -4.0
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(swatch)
		b.pressed.connect(func() -> void:
				appearance.set(key, name)
				_apply_appearance())
		row.add_child(b)
	return _labelled(text, row)


func _tone_colour(key: String, name: String) -> Color:
	match key:
		"skin":
			return CharacterAppearance.skin_colour(name)
		"hair_colour":
			return CharacterAppearance.hair_colour_value(name)
	return CharacterAppearance.eye_colour_value(name)


func _tone_name(key: String, name: String) -> String:
	if key == "skin":
		return str(SKIN_NAMES.get(name, name))
	return name.replace("_", " ").capitalize()


## A drop-down over one of the record's part lists; `slot` is the part slot it sets.
func _chooser(text: String, options: Array, names: Dictionary, slot: String) -> HBoxContainer:
	var o := OptionButton.new()
	o.set_meta("slot", slot)
	o.fit_to_longest_item = false
	o.custom_minimum_size = Vector2(118, 0)
	for option in options:
		o.add_item(str(names.get(option, str(option))))
	var current := options.find(appearance.part(slot))
	o.selected = maxi(current, 0)
	o.item_selected.connect(func(index: int) -> void:
			appearance.set_part(slot, str(options[index]))
			_apply_appearance())
	_choosers[slot] = o
	return _labelled(text, o, 44.0)


func _slider(text: String, key: String, low: float, high: float, step: float) -> HBoxContainer:
	var row := UiKit.row(6)
	var s := HSlider.new()
	s.set_meta("key", key)
	s.min_value = low
	s.max_value = high
	s.step = step
	s.value = float(appearance.get(key))
	s.custom_minimum_size = Vector2(110, 20)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value_label := UiKit.label("", "Tiny")
	value_label.custom_minimum_size = Vector2(50, 0)
	value_label.text = _value_text(key, float(appearance.get(key)))
	s.value_changed.connect(func(v: float) -> void:
			appearance.set(key, v)
			value_label.text = _value_text(key, v)
			_apply_appearance())
	# a plain click on the track moves the grabber with its signals blocked; only a drag
	# reports, so the click is picked up when the button comes back up
	s.drag_ended.connect(func(_changed: bool) -> void:
			if not is_equal_approx(float(appearance.get(key)), s.value):
				appearance.set(key, s.value)
				value_label.text = _value_text(key, s.value)
				_apply_appearance())
	row.add_child(s)
	row.add_child(value_label)
	_sliders[key] = s
	return _labelled(text, row, 46.0)


func _value_text(key: String, value: float) -> String:
	if key == "height":
		return "%.2f m" % value
	return BUILD_WORDS[clampi(int(value * 4.999), 0, BUILD_WORDS.size() - 1)]


func _roll_suggestions() -> void:
	for child in _suggest_row.get_children():
		child.queue_free()
	_suggest_row.add_child(UiKit.label("or", "Tiny"))
	for name in ValishNames.suggestions(3):
		var b := UiKit.button(name, "FlatButton")
		b.add_theme_font_size_override("font_size", ThemeBuilder.SIZES.small)
		b.pressed.connect(func() -> void:
				player_name = name
				_name_edit.text = name
				_update_begin())
		_suggest_row.add_child(b)
	var again := UiKit.icon_button("gesture", "other names")
	again.pressed.connect(_roll_suggestions)
	_suggest_row.add_child(again)


func _build_callings() -> Control:
	var col := UiKit.column(6)
	col.custom_minimum_size = Vector2(340, 0)
	col.add_child(UiKit.label("What were you, before?", "Heading"))
	_calling_box = GridContainer.new()
	_calling_box.columns = 2
	_calling_box.add_theme_constant_override("h_separation", 6)
	_calling_box.add_theme_constant_override("v_separation", 4)
	col.add_child(_calling_box)
	_calling_detail = UiKit.column(4)
	col.add_child(UiKit.divider())
	col.add_child(_calling_detail)

	for def in ContentDB.all("calling"):
		var id := str(def.get("id", ""))
		var b := UiKit.button("", "FlatButton")
		b.custom_minimum_size = Vector2(0, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_meta("calling", id)
		b.pressed.connect(func() -> void:
				calling_id = id
				_refresh_calling()
				_apply_appearance())
		var card := UiKit.row(8)
		card.set_anchors_preset(Control.PRESET_FULL_RECT)
		card.offset_left = 8.0
		card.offset_right = -6.0
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(card)
		card.add_child(UiKit.icon_rect(_calling_icon(def), 22))
		var words := UiKit.column(0)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(words)
		words.add_child(UiKit.label(str(def.get("name", id)), "Emphasis"))
		words.add_child(UiKit.label(str(def.get("culture", "")), "Tiny"))
		_calling_box.add_child(b)
	# No focus chain over the cards: the chain wraps, so once a pad's focus was in the cards
	# Tab and down went round them for ever and Be named could not be reached. The grid's own
	# order and the engine's geometric search do the right thing on their own.
	return UiKit.scroll(col)


## The icon a Calling wears on its card, from the skills it starts you with.
func _calling_icon(def: Dictionary) -> String:
	var bonuses: Dictionary = def.get("skill_bonuses", {})
	for key in ["alchemy", "smithing", "archery", "sneak", "speech", "one_handed", "two_handed",
			"kindling", "hush", "mending", "block"]:
		if bonuses.has(key):
			match key:
				"alchemy": return "alembic"
				"smithing": return "hammer"
				"archery": return "bow"
				"sneak": return "eye"
				"speech": return "rumour"
				"one_handed": return "sword"
				"two_handed": return "axe"
				"kindling": return "hearth"
				"hush": return "lock"
				"mending": return "potion"
				"block": return "shield"
	return "bell"


func _refresh_calling() -> void:
	for child in _calling_box.get_children():
		if child is Button:
			var on: bool = str(child.get_meta("calling", "")) == calling_id
			child.modulate = Color(1, 1, 1, 1.0 if on else 0.6)
	for child in _calling_detail.get_children():
		child.queue_free()
	var def := ContentDB.get_or_empty(calling_id)
	if def.is_empty():
		return
	var description := UiKit.wrapped(str(def.get("description", "")), "Journal")
	description.add_theme_font_size_override("font_size", 14)
	_calling_detail.add_child(description)
	var bonuses: Dictionary = def.get("skill_bonuses", {})
	if not bonuses.is_empty():
		var known: Array[String] = []
		for skill: String in bonuses:
			var skill_def := ContentDB.get_or_empty("core:skill/" + skill)
			known.append("%s +%d" % [str(skill_def.get("name", skill)), int(bonuses[skill])])
		var row := UiKit.row(8)
		row.add_child(UiKit.icon_rect("book", 18))
		row.add_child(UiKit.wrapped("You already know something of " + ", ".join(known) + ".", "Small"))
		_calling_detail.add_child(row)
	var signature := str(def.get("signature_item", ""))
	if signature != "":
		var item := ContentDB.get_or_empty(signature)
		var row := UiKit.row(8)
		row.add_child(UiKit.icon_rect(UiKit.item_icon_name(item), 18))
		row.add_child(UiKit.wrapped("You still have %s." % str(item.get("name", "something")), "Small"))
		_calling_detail.add_child(row)
	UiKit.ink_in(_calling_detail, 0.0, 0.26)
	_update_begin()


func _update_begin() -> void:
	if _begin:
		_begin.disabled = player_name.strip_edges().is_empty() or calling_id.is_empty()


# --- the body ----------------------------------------------------------------------------------

## The Calling says where you were raised, and that people dresses you: culture, clothes and
## cloth colours come from it, deterministically, so the same Calling shows the same coat.
func _dress_for_calling() -> void:
	appearance.dress_for_culture(CharacterAppearance.culture_of_calling(calling_id), abs(calling_id.hash()))


func _apply_appearance() -> void:
	_dress_for_calling()
	if _model and is_instance_valid(_model) and _model.has_method("apply_appearance"):
		_model.call("apply_appearance", appearance.to_dict())


func _process(delta: float) -> void:
	if _mannequin:
		_spin += delta * 0.22
		_mannequin.rotation.y = sin(_spin) * 0.55


# --- writing it down -----------------------------------------------------------------------------

## The record as the world will read it.
func appearance_dict() -> Dictionary:
	_dress_for_calling()
	return appearance.to_dict()


## Writes the character down. A new game starts from a clean slate, so whatever an earlier
## game in this session left in GameState goes first.
func commit() -> void:
	var name := player_name.strip_edges()
	GameState.reset_for_new_game(abs(("%s|%s" % [name, calling_id]).hash()))
	GameState.set_flag("player_name", name)
	GameState.set_flag("player_calling", calling_id)
	GameState.set_flag("player_appearance", appearance_dict())
	GameState.set_flag("new_game", true)


func _begin_game() -> void:
	if player_name.strip_edges().is_empty() or calling_id.is_empty():
		return
	commit()
	if world_scene.is_empty() or not ResourceLoader.exists(world_scene):
		if not world_scene.is_empty():
			EventBus.emit_notify("Named, but the world is not built yet.", "warning")
		return
	var world_status := WorldStatus.current()
	if not bool(world_status.get("playable", false)):
		# the title shuts New Game when there is no world, but the Naming can be opened on its own
		EventBus.emit_notify("Named, but %s Run %s first." % [str(world_status.get("title", "")).to_lower(),
				WorldStatus.BUILD_COMMAND], "warning")
		return
	_begin.disabled = true
	UI.fade_to_black(0.5, LOADING_LINE)
	await get_tree().create_timer(0.55).timeout
	get_tree().change_scene_to_file(world_scene)


## Used by the review harness to show the screen part-way through being filled in.
func review_state() -> void:
	_name_edit.text = "Wren of the Hushline"
	player_name = _name_edit.text
	var callings := ContentDB.all("calling")
	if callings.size() > 2:
		calling_id = str(callings[2].get("id", ""))
	appearance.skin = "amber"
	appearance.hair_colour = "auburn"
	appearance.eye_colour = "green"
	appearance.set_part("hair", "braid")
	appearance.set_part("head", "narrow")
	appearance.build = 0.65
	appearance.height = 1.71
	for slot in _choosers:
		var options: Array = []
		match slot:
			"hair": options = CharacterAppearance.HAIR_STYLES
			"head": options = CharacterAppearance.HEADS
		var index: int = options.find(appearance.part(slot))
		if index >= 0:
			(_choosers[slot] as OptionButton).selected = index
	for key in _sliders:
		(_sliders[key] as HSlider).set_value_no_signal(float(appearance.get(key)))
	_refresh_calling()
	_apply_appearance()
