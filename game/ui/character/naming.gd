extends Control
## The Naming (DESIGN §5.1). Character creation is in the fiction: a Warden is standing over
## you asking what you are called, and what you were before you were pulled out of the Hush.
##
## The look is a `CharacterAppearance`, the same record the humanoid model composes a body
## from and an NPC def carries inline, edited in place by the controls: every swatch, chooser
## and slider names a tone, a part or a proportion in that record's own vocabulary.
##
## The body is the first thing on the page and the largest: a portrait lit like one (a warm key,
## a rim from behind, a painted dusk behind the figure and a floor it casts a shadow on), which
## turns under the mouse and closes in on the face whenever a face is what is being chosen.
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
## What this screen is called on EventBus.menu_opened: the music director brings the Naming's own
## piece up on it. The Naming is a scene of its own, not one of UI's menus, and nothing said it was up.
const SCREEN_ID := "character_creation"
const MODEL_SCENE := "res://actors/shared/humanoid_model.tscn"
const BACKDROP_SHADER := "res://assets/shaders/portrait_backdrop.gdshader"
const FLOOR_TEXTURE := "res://assets/textures/terrain/cobbles_albedo_height.png"
const FLOOR_SHADER := "res://assets/shaders/portrait_floor.gdshader"

## What the vocabulary is called out loud.
const SKIN_NAMES := {"porcelain": "Porcelain", "fair": "Fair", "wheat": "Wheat", "olive": "Olive",
	"amber": "Amber", "umber": "Umber", "deep": "Deep", "ebony": "Ebony"}
const HAIR_STYLE_NAMES := {"short": "Short", "cropped": "Cropped", "long": "Loose", "braid": "Braided",
	"bun": "Tied back", "hood_friendly": "Combed back", "tousled": "Wild"}
const HEAD_NAMES := {"default": "Even", "round": "Round", "soft": "Soft", "angular": "Angular",
	"narrow": "Narrow", "broad": "Broad", "hawk": "Hawkish", "heavy_brow": "Heavy-browed"}
const BEARD_NAMES := {"": "None", "stubble": "Stubble", "short_beard": "Short", "long_beard": "Long",
	"moustache": "Moustache"}
const BUILD_WORDS := ["slight", "lean", "even", "solid", "broad"]
## The slider ranges, chosen so both ends are a person: shorter or taller than this and the
## fixed skeleton's clips stop fitting the ground and the doorways.
const HEIGHT_RANGE := Vector2(1.55, 1.95)
## What the loading caption says between "Be named" and the first look at the world.
const LOADING_LINE := "The Warden walks you out of the Hush. Keep up; she does not look back."
## Looks that are worth starting from, by the kind of person they are.
const PRESETS := [
	{"name": "Hearth-born", "skin": "fair", "hair_colour": "chestnut", "eye_colour": "blue", "head": "round",
		"hair": "short", "beard": "", "build": 0.50, "height": 1.74},
	{"name": "Drover", "skin": "wheat", "hair_colour": "dark_brown", "eye_colour": "hazel", "head": "angular",
		"hair": "tousled", "beard": "stubble", "build": 0.58, "height": 1.80},
	{"name": "Fen-walker", "skin": "olive", "hair_colour": "black", "eye_colour": "dark_brown", "head": "narrow",
		"hair": "long", "beard": "", "build": 0.36, "height": 1.72},
	{"name": "Old soldier", "skin": "umber", "hair_colour": "grey", "eye_colour": "grey", "head": "heavy_brow",
		"hair": "cropped", "beard": "short_beard", "build": 0.78, "height": 1.82},
	{"name": "Scholar", "skin": "porcelain", "hair_colour": "ash_blond", "eye_colour": "pale_blue", "head": "soft",
		"hair": "bun", "beard": "", "build": 0.24, "height": 1.68},
	{"name": "Crag-clan", "skin": "fair", "hair_colour": "ginger", "eye_colour": "green", "head": "broad",
		"hair": "braid", "beard": "long_beard", "build": 0.86, "height": 1.86},
]
## The portrait's two framings: the whole figure, and head and shoulders.
const FIGURE := 0.0
const FACE := 1.0
const DEFAULT_YAW := 0.38
const PORTRAIT_WIDTH := 400.0
const MIDDLE_WIDTH := 372.0

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
var _view: TextureRect
var _camera: Camera3D
var _mannequin: Node3D
var _model: Node = null
var _begin: Button
var _choosers: Dictionary = {}     # slot -> OptionButton
var _sliders: Dictionary = {}      # key -> HSlider
var _slider_labels: Dictionary = {}
var _yaw := DEFAULT_YAW
var _yaw_target := DEFAULT_YAW
var _zoom := FIGURE
var _zoom_target := FIGURE
var _idle := 0.0
var _dragging := false
var _pixel_scale := 1.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	UI.apply_theme(self)
	UI.close_all()
	UI.hide_hud()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	EventBus.menu_opened.emit(SCREEN_ID)
	appearance.set_part("head", "default")
	appearance.set_part("hair", "short")
	var callings := ContentDB.all("calling")
	if not callings.is_empty():
		calling_id = str(callings[0].get("id", ""))
	player_name = ValishNames.suggestions(1, 20260919)[0]
	_build()
	_refresh_calling()
	_apply_appearance()
	_frame(true)
	# somewhere for a pad to start from; nothing had focus, so its first press did nothing
	_name_edit.grab_focus()


func _exit_tree() -> void:
	EventBus.menu_closed.emit(SCREEN_ID)


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
	frame.offset_left = 20.0
	frame.offset_top = 12.0
	frame.offset_right = -20.0
	frame.offset_bottom = -12.0
	add_child(frame)
	var body: VBoxContainer = page["body"]

	var columns := UiKit.row(18)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(columns)
	columns.add_child(_build_portrait())

	var right := UiKit.column(4)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	right.add_child(UiKit.label("The Naming", "Title"))
	right.add_child(UiKit.divider())
	var inner := UiKit.row(18)
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(inner)
	inner.add_child(_build_middle())
	inner.add_child(_build_callings())

	var foot := UiKit.row(14)
	foot.alignment = BoxContainer.ALIGNMENT_END
	right.add_child(foot)
	var back_button := UiKit.button("Back", "FlatButton")
	back_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(MENU_SCENE))
	foot.add_child(back_button)
	_begin = UiKit.button("Be named")
	_begin.pressed.connect(_begin_game)
	foot.add_child(_begin)
	UiKit.ink_in(frame, 0.0, 0.4)


## The portrait: a framed view onto a small lit stage, and the Warden's words under it.
func _build_portrait() -> Control:
	var holder := UiKit.column(6)
	holder.custom_minimum_size = Vector2(PORTRAIT_WIDTH, 0)
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var framed := UiKit.panel("OakPanel")
	framed.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.add_child(framed)
	var stage := Control.new()
	stage.clip_contents = true
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	framed.add_child(stage)

	_view = TextureRect.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.mouse_default_cursor_shape = Control.CURSOR_DRAG
	_view.tooltip_text = "Drag to turn; the wheel to look closer"
	_view.gui_input.connect(_on_view_input)
	_view.resized.connect(_fit_preview)
	stage.add_child(_view)

	_preview = SubViewport.new()
	_preview.own_world_3d = true
	_preview.msaa_3d = Viewport.MSAA_4X
	_preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview.size = Vector2i(420, 600)
	stage.add_child(_preview)
	_view.texture = _preview.get_texture()
	_build_stage(_preview)

	# the two framings, and how to turn the figure, right under the portrait
	var lens := UiKit.row(4)
	lens.alignment = BoxContainer.ALIGNMENT_CENTER
	holder.add_child(lens)
	var face := UiKit.button("Face", "FlatButton")
	face.set_meta("focus_to", FACE)
	face.tooltip_text = "Look at the face"
	face.pressed.connect(func() -> void: _focus(FACE))
	lens.add_child(face)
	var whole := UiKit.button("Whole figure", "FlatButton")
	whole.set_meta("focus_to", FIGURE)
	whole.tooltip_text = "Stand back"
	whole.pressed.connect(func() -> void: _focus(FIGURE))
	lens.add_child(whole)
	lens.add_child(UiKit.label("drag the figure to turn it", "Tiny"))

	var caption := UiKit.label("The forge has not made a body yet.", "Tiny", HORIZONTAL_ALIGNMENT_CENTER)
	caption.visible = _model == null
	caption.set_anchors_preset(Control.PRESET_CENTER)
	stage.add_child(caption)

	var blurb := UiKit.wrapped(
		"You came up the Hushline Stair with nothing. A Warden is asking what you are called, " +
		"and she is not going to guess.", "Journal")
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.add_theme_font_size_override("font_size", 14)
	blurb.custom_minimum_size = Vector2(PORTRAIT_WIDTH, 0)
	holder.add_child(blurb)
	return holder


## The small stage inside the portrait: sky, floor, three lights, a camera and the body.
func _build_stage(vp: SubViewport) -> void:
	var world := Node3D.new()
	world.name = "Stage"
	vp.add_child(world)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	if ResourceLoader.exists(BACKDROP_SHADER):
		sky_mat.shader = load(BACKDROP_SHADER)
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
	# Mostly a neutral, slightly cool ambient with a little of the dusk in it. Lit from the dusk
	# alone, the ambient was amber, and with a warm key on top a white gambeson came out cream
	# (37 % saturated) and a mid-brown skin came out orange (68 %) against a 50 % swatch.
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 0.35
	environment.ambient_light_color = Color(0.66, 0.70, 0.78)
	environment.ambient_light_energy = 0.42
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# without a raised white point the mid-greys clip on this renderer (ARCHITECTURE.md §10)
	environment.tonemap_white = 6.0
	environment.tonemap_exposure = 0.92
	env.environment = environment
	world.add_child(env)

	# the key: a touch warm, high and to the camera's left, the only light that casts a shadow
	var key := DirectionalLight3D.new()
	key.name = "Key"
	key.light_color = Color(1.0, 0.95, 0.89)
	key.light_energy = 1.0
	key.shadow_enabled = true
	key.shadow_blur = 1.6
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 9.0
	world.add_child(key)
	key.look_at_from_position(Vector3(-3.0, 3.0, 2.0), Vector3(0.0, 0.9, 0.0), Vector3.UP)
	# the rim: from behind and above, so the silhouette separates from the dusk behind it
	var rim := DirectionalLight3D.new()
	rim.name = "Rim"
	rim.light_color = Color(0.86, 0.91, 1.0)
	rim.light_energy = 1.25
	world.add_child(rim)
	rim.look_at_from_position(Vector3(2.4, 2.4, -2.6), Vector3(0.0, 1.1, 0.0), Vector3.UP)
	# a cool fill low on the other side, so the shadow side is a colour and not a hole
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_color = Color(0.70, 0.78, 0.94)
	fill.light_energy = 0.22
	world.add_child(fill)
	fill.look_at_from_position(Vector3(2.8, 1.1, 2.2), Vector3(0.0, 1.0, 0.0), Vector3.UP)

	# the landing at the top of the stair: flagstones under the feet
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Floor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 30.0)
	floor_mesh.mesh = plane
	var floor_mat := ShaderMaterial.new()
	if ResourceLoader.exists(FLOOR_SHADER):
		floor_mat.shader = load(FLOOR_SHADER)
	if ResourceLoader.exists(FLOOR_TEXTURE):
		floor_mat.set_shader_parameter("stones", load(FLOOR_TEXTURE))
	floor_mesh.material_override = floor_mat
	world.add_child(floor_mesh)

	_camera = Camera3D.new()
	_camera.fov = 28.0
	_camera.near = 0.03
	_camera.current = true
	# framed from _process as the portrait zooms and the stage resizes, in a viewport of its own:
	# interpolating it between physics ticks only warns that it moved outside one
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	world.add_child(_camera)

	_mannequin = Node3D.new()
	# turned every frame below, so it must not also be interpolated between physics ticks
	_mannequin.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	world.add_child(_mannequin)
	if ResourceLoader.exists(MODEL_SCENE):
		_model = (load(MODEL_SCENE) as PackedScene).instantiate()
		_mannequin.add_child(_model)


func _build_middle() -> Control:
	var col := UiKit.column(4)
	col.custom_minimum_size = Vector2(MIDDLE_WIDTH, 0)

	col.add_child(_heading("What are you called?"))
	_name_edit = LineEdit.new()
	_name_edit.text = player_name
	_name_edit.placeholder_text = "a name, said out loud"
	_name_edit.max_length = 28
	_name_edit.text_changed.connect(func(text: String) -> void:
			player_name = text
			_update_begin())
	col.add_child(_name_edit)

	_suggest_row = UiKit.row(4)
	col.add_child(_suggest_row)
	_roll_suggestions()

	col.add_child(UiKit.divider())
	col.add_child(_heading("What you look like"))
	col.add_child(_swatches("Skin", CharacterAppearance.SKIN_TONES, "skin"))
	col.add_child(_swatches("Hair", CharacterAppearance.HAIR_COLOURS, "hair_colour"))
	col.add_child(_swatches("Eyes", CharacterAppearance.EYE_COLOURS, "eye_colour"))
	col.add_child(_chooser("Face", CharacterAppearance.HEADS, HEAD_NAMES, "head"))
	col.add_child(_chooser("Style", CharacterAppearance.HAIR_STYLES, HAIR_STYLE_NAMES, "hair"))
	col.add_child(_chooser("Beard", offered_beards(), BEARD_NAMES, "beard"))
	col.add_child(_slider("Build", "build", 0.0, 1.0, 0.05))
	col.add_child(_slider("Height", "height", HEIGHT_RANGE.x, HEIGHT_RANGE.y, 0.01))

	col.add_child(UiKit.divider())
	var starts := UiKit.row(4)
	starts.add_child(UiKit.label("Start from", "Small"))
	var presets := OptionButton.new()
	presets.set_meta("presets", true)
	presets.fit_to_longest_item = false
	presets.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	presets.add_item("a kind of person...")
	for p in PRESETS:
		presets.add_item(str(p["name"]))
	presets.item_selected.connect(func(index: int) -> void:
			if index > 0:
				apply_preset(PRESETS[index - 1])
			presets.select(0))
	starts.add_child(presets)
	var lots := UiKit.button("Cast lots", "FlatButton")
	lots.tooltip_text = "A look chosen by chance"
	lots.pressed.connect(func() -> void: randomise())
	starts.add_child(lots)
	col.add_child(starts)
	return col


## A heading that wraps rather than widening its column: the capitals are wide, and three of
## them side by side pushed the Callings off the right edge of a 1280-wide screen.
func _heading(text: String) -> Label:
	var h := UiKit.label(text, "Heading")
	h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.custom_minimum_size = Vector2(40, 0)
	return h


func _labelled(text: String, control: Control, label_width := 52.0) -> HBoxContainer:
	var row := UiKit.row(6)
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
	var row := UiKit.row(2)
	for tone in tones:
		var name := str(tone)
		var b := Button.new()
		b.theme_type_variation = &"FlatButton"
		b.custom_minimum_size = Vector2(24, 24)
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
				_mark_swatches(row, key)
				_focus(FACE if key != "skin" else _zoom_target)
				_apply_appearance())
		row.add_child(b)
	_mark_swatches(row, key)
	return _labelled(text, row)


## The chosen swatch stands out from its row, so the record's state can be read off the page.
func _mark_swatches(row: Node, key: String) -> void:
	var current := str(appearance.get(key))
	for b in row.get_children():
		if b is Button and b.has_meta("tone"):
			var on: bool = str(b.get_meta("tone")) == current
			(b as Button).modulate = Color(1, 1, 1, 1) if on else Color(0.86, 0.86, 0.86, 0.92)
			var swatch := b.get_child(0) as ColorRect
			if swatch != null:
				swatch.offset_left = 2.0 if on else 5.0
				swatch.offset_top = 2.0 if on else 5.0
				swatch.offset_right = -2.0 if on else -5.0
				swatch.offset_bottom = -2.0 if on else -5.0


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


## offered_beards(), worked out once a session: the answer does not change while the game runs,
## and every chooser, preset and roll of the dice must see the same list. The Beard chooser is
## built from the first answer, and a later one that differed (a part that failed to load once and
## not the next time) had `_sync_controls` select an entry the chooser does not have. It also
## loaded and built every beard each time it was asked, which a preset click asked for twice.
static var _offered_beards: Array = []


## The beards worth offering: "none", and every style whose part holds a mesh. Three of the
## four once shipped as a skeleton with nothing on it, and a chooser that offers "Long" and
## draws nothing is a broken control. A style comes back by itself when the forge rebuilds it.
static func offered_beards() -> Array:
	if not _offered_beards.is_empty():
		return _offered_beards.duplicate()
	var out: Array = [""]
	for style in CharacterAppearance.BEARD_STYLES:
		var path := "res://assets/models/characters/beards/%s/%s.glb" % [style, style]
		if not ResourceLoader.exists(path):
			continue
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		var inst := packed.instantiate()
		var drawn := false
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).mesh != null:
				drawn = true
				break
		inst.free()
		if drawn:
			out.append(style)
	_offered_beards = out
	return out.duplicate()


## A drop-down over one of the record's part lists; `slot` is the part slot it sets.
func _chooser(text: String, options: Array, names: Dictionary, slot: String) -> HBoxContainer:
	var o := OptionButton.new()
	o.set_meta("slot", slot)
	o.fit_to_longest_item = false
	o.custom_minimum_size = Vector2(150, 0)
	for option in options:
		o.add_item(str(names.get(option, str(option))))
	var current := options.find(appearance.part(slot))
	o.selected = maxi(current, 0)
	o.item_selected.connect(func(index: int) -> void:
			if index < 0 or index >= options.size():
				return
			appearance.set_part(slot, str(options[index]))
			_focus(FACE)
			_apply_appearance())
	_choosers[slot] = o
	var row := _labelled(text, o)
	# the chooser's own arrows, for a mouse player who does not want the list open
	for step in [-1, 1]:
		var b := UiKit.button("<" if step < 0 else ">", "FlatButton")
		b.custom_minimum_size = Vector2(26, 0)
		b.tooltip_text = "%s: %s" % [text, "previous" if step < 0 else "next"]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void:
				var i := wrapi(o.selected + int(step), 0, o.item_count)
				o.select(i)
				o.item_selected.emit(i))
		row.add_child(b)
	return row


func _slider(text: String, key: String, low: float, high: float, step: float) -> HBoxContainer:
	var row := UiKit.row(6)
	var s := HSlider.new()
	s.set_meta("key", key)
	s.min_value = low
	s.max_value = high
	s.step = step
	s.value = float(appearance.get(key))
	s.custom_minimum_size = Vector2(150, 22)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value_label := UiKit.label("", "Small")
	value_label.custom_minimum_size = Vector2(56, 0)
	value_label.text = _value_text(key, float(appearance.get(key)))
	_slider_labels[key] = value_label
	s.value_changed.connect(func(v: float) -> void:
			appearance.set(key, v)
			value_label.text = _value_text(key, v)
			_focus(FIGURE)
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
	return _labelled(text, row)


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
		# The row shares the column's width instead of setting it: three long names ("Hesk of
		# Fallowhithe") widened the middle column at 1280x720, and the right-hand column's
		# heading broke over two lines and its callings' peoples were cut off.
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = name
		b.pressed.connect(func() -> void:
				player_name = name
				_name_edit.text = name
				_update_begin())
		_suggest_row.add_child(b)
	var again := UiKit.icon_button("gesture", "other names", 26)
	again.pressed.connect(_roll_suggestions)
	_suggest_row.add_child(again)


func _build_callings() -> Control:
	var col := UiKit.column(4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_heading("What were you, before?"))
	_calling_box = GridContainer.new()
	_calling_box.columns = 2
	_calling_box.add_theme_constant_override("h_separation", 4)
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
				_focus(FIGURE)
				_apply_appearance())
		var card := UiKit.row(6)
		card.set_anchors_preset(Control.PRESET_FULL_RECT)
		card.offset_left = 6.0
		card.offset_right = -4.0
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(card)
		card.add_child(UiKit.icon_rect(_calling_icon(def), 22))
		var words := UiKit.column(0)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.alignment = BoxContainer.ALIGNMENT_CENTER
		words.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(words)
		words.add_child(UiKit.label(str(def.get("name", id)), "Emphasis"))
		var culture := UiKit.label(str(def.get("culture", "")), "Tiny")
		culture.clip_text = true
		culture.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		words.add_child(culture)
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


# --- looks ------------------------------------------------------------------------------------

## One of PRESETS, through the same record every control writes.
func apply_preset(p: Dictionary) -> void:
	appearance.skin = str(p["skin"])
	appearance.hair_colour = str(p["hair_colour"])
	appearance.eye_colour = str(p["eye_colour"])
	appearance.set_part("head", str(p["head"]))
	appearance.set_part("hair", str(p["hair"]))
	appearance.set_part("beard", str(p["beard"]) if offered_beards().has(str(p["beard"])) else "")
	appearance.build = float(p["build"])
	appearance.height = float(p["height"])
	_sync_controls()
	_focus(FIGURE)
	_apply_appearance()


## A look chosen by chance, from a spread that stays a plausible person: most people have no
## beard, grey hair is for the build of a face that has earned it, and heights cluster.
func randomise(rng_seed: int = -1) -> void:
	var rng := RandomNumberGenerator.new()
	if rng_seed >= 0:
		rng.seed = rng_seed
	else:
		rng.randomize()
	appearance.skin = CharacterAppearance.SKIN_TONES[rng.randi() % CharacterAppearance.SKIN_TONES.size()]
	appearance.hair_colour = CharacterAppearance.HAIR_COLOURS[rng.randi() % (CharacterAppearance.HAIR_COLOURS.size() - 2)]
	if rng.randf() < 0.15:
		appearance.hair_colour = "grey" if rng.randf() < 0.7 else "white"
	appearance.eye_colour = CharacterAppearance.EYE_COLOURS[rng.randi() % CharacterAppearance.EYE_COLOURS.size()]
	appearance.set_part("head", CharacterAppearance.HEADS[rng.randi() % CharacterAppearance.HEADS.size()])
	appearance.set_part("hair", CharacterAppearance.HAIR_STYLES[rng.randi() % CharacterAppearance.HAIR_STYLES.size()])
	var beard := ""
	var beards := offered_beards()
	if rng.randf() < 0.4 and beards.size() > 1:
		beard = str(beards[1 + rng.randi() % (beards.size() - 1)])
	appearance.set_part("beard", beard)
	appearance.build = clampf(snappedf(rng.randfn(0.48, 0.20), 0.05), 0.0, 1.0)
	appearance.height = clampf(snappedf(rng.randfn(1.76, 0.07), 0.01), HEIGHT_RANGE.x, HEIGHT_RANGE.y)
	_sync_controls()
	_focus(FIGURE)
	_apply_appearance()


## Puts every control back in step with the record after something other than that control
## changed it (a preset, the lots, the review harness).
func _sync_controls() -> void:
	var lists := {"hair": CharacterAppearance.HAIR_STYLES, "head": CharacterAppearance.HEADS,
		"beard": offered_beards()}
	for slot in _choosers:
		var index: int = (lists.get(slot, []) as Array).find(appearance.part(slot))
		var chooser := _choosers[slot] as OptionButton
		chooser.select(index if index >= 0 and index < chooser.item_count else 0)
	for key in _sliders:
		(_sliders[key] as HSlider).set_value_no_signal(float(appearance.get(key)))
		if _slider_labels.has(key):
			(_slider_labels[key] as Label).text = _value_text(key, float(appearance.get(key)))
	for pair in [["Skin", "skin"], ["Hair", "hair_colour"], ["Eyes", "eye_colour"]]:
		var row := _swatch_row(str(pair[0]))
		if row != null:
			_mark_swatches(row, str(pair[1]))


func _swatch_row(label_text: String) -> Node:
	for l in find_children("*", "Label", true, false):
		if (l as Label).text == label_text and l.get_parent() is HBoxContainer:
			var row := l.get_parent()
			if row.get_child_count() > 1 and row.get_child(1) is HBoxContainer:
				return row.get_child(1)
	return null


# --- the body ----------------------------------------------------------------------------------

## The Calling says where you were raised, and that people dresses you: culture, clothes and
## cloth colours come from it, deterministically, so the same Calling shows the same coat.
func _dress_for_calling() -> void:
	appearance.dress_for_culture(CharacterAppearance.culture_of_calling(calling_id), abs(calling_id.hash()), true)


func _apply_appearance() -> void:
	_dress_for_calling()
	if _model and is_instance_valid(_model) and _model.has_method("apply_appearance"):
		_model.call("apply_appearance", appearance.to_dict())


# --- the portrait ------------------------------------------------------------------------------

## Face or whole figure. Choosing a face, a tone or a hair style closes in; the build, the
## height and the Calling stand back, because those are read from the whole body.
func _focus(to: float) -> void:
	_zoom_target = clampf(to, FIGURE, FACE)
	_idle = 0.0


func _on_view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			if mb.double_click:
				_focus(FIGURE if _zoom_target > 0.5 else FACE)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_focus(_zoom_target + 0.2)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_focus(_zoom_target - 0.2)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_yaw_target += (event as InputEventMouseMotion).relative.x * 0.012
		_idle = 0.0
		accept_event()


## The view renders at the screen's own pixels, not the page's: the page is laid out at
## 1280x720 and stretched, and a viewport sized in layout units was drawn at a quarter of the
## pixels on a 2560x1440 screen and scaled up, jagged, with a dark fringe round the figure.
func _fit_preview() -> void:
	if _preview == null or _view == null:
		return
	_pixel_scale = maxf(get_viewport().get_final_transform().get_scale().x, 1.0)
	var want := Vector2i(maxi(int(round(_view.size.x * _pixel_scale)), 2), maxi(int(round(_view.size.y * _pixel_scale)), 2))
	if _preview.size != want:
		_preview.size = want


func _process(delta: float) -> void:
	if _preview != null and not is_equal_approx(_pixel_scale, maxf(get_viewport().get_final_transform().get_scale().x, 1.0)):
		_fit_preview()
	_idle += delta
	if not _dragging and _idle > 5.0:
		# left alone, the figure comes back round to the three-quarter view it is lit for
		_yaw_target = lerp_angle(_yaw_target, DEFAULT_YAW, 1.0 - exp(-delta * 0.8))
	_yaw = lerp_angle(_yaw, _yaw_target, 1.0 - exp(-delta * 10.0))
	_zoom = lerpf(_zoom, _zoom_target, 1.0 - exp(-delta * 6.0))
	_frame(false)


## Places the camera for the current zoom and the character's height: the whole figure with a
## little floor under it, or the head and shoulders.
func _frame(snap: bool) -> void:
	if _camera == null:
		return
	if snap:
		_zoom = _zoom_target
		_yaw = _yaw_target
	if _mannequin != null:
		_mannequin.rotation.y = _yaw
	var h := clampf(appearance.height, HEIGHT_RANGE.x, HEIGHT_RANGE.y)
	var half_fov := deg_to_rad(_camera.fov * 0.5)
	var t := _zoom * _zoom * (3.0 - 2.0 * _zoom)
	var fig_target := Vector3(0.0, h * 0.50, 0.0)
	var fig_dist := (h * 0.60) / tan(half_fov)
	# Head and shoulders, with the crown inside the frame: framed 0.23 m either side of the
	# mouth, a broad head at 1.84 m lost the top of its hair to the frame, and looked at from
	# below it was all chin.
	var face_target := Vector3(0.0, h * 0.885, 0.0)
	var face_dist := 0.28 / tan(half_fov)
	var target := fig_target.lerp(face_target, t)
	var dist := exp(lerpf(log(fig_dist), log(face_dist), t))
	var pitch := deg_to_rad(lerpf(3.0, 1.0, t))
	_camera.position = target + Vector3(0.0, sin(pitch) * dist, cos(pitch) * dist)
	_camera.look_at(target, Vector3.UP)


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
	_sync_controls()
	_refresh_calling()
	_apply_appearance()
