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
## A pack with fighting styles (core:style/*, DESIGN §5.1) gets a second page, *How you fight*:
## one card each, with a picture of its start town, the teacher's name, the kit and a line about
## the start. The style picks where the game begins (Openings).
##
## Writes GameState flags and nothing else:
##   player_name        String
##   player_calling     a `calling` id
##   player_appearance  CharacterAppearance.to_dict()
##   player_style       a `style` id, when the pack has styles
##   style_start, style_opening_due   true, for a styled character (Openings)
##   new_game           true, for one with no style: the fallback start, straight onto the wake
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
	"bun": "Tied back", "hood_friendly": "Combed back", "tousled": "Wild", "long_loose": "Long and loose",
	"shoulder": "To the shoulder", "twin_braids": "Two braids", "crown_braid": "Plaited crown",
	"chignon": "Low knot", "curly": "Curls", "cropped_curls": "Cropped curls", "shaved_sides": "Shaved sides",
	"shaven": "Shaven", "receding": "Receding", "ponytail": "Tail"}
const HEAD_NAMES := {"default": "Even", "round": "Round", "soft": "Soft", "angular": "Angular",
	"narrow": "Narrow", "broad": "Broad", "hawk": "Hawkish", "heavy_brow": "Heavy-browed"}
const BEARD_NAMES := {"": "None", "stubble": "Stubble", "short_beard": "Short", "long_beard": "Long",
	"moustache": "Moustache", "full_beard": "Full", "goatee": "Goatee", "mutton_chops": "Side-whiskers",
	"walrus": "Heavy moustache"}
## The Face page (triage 39): what each slider, brow, scar and paint is called out loud.
const FACE_NAMES := {"jaw_width": "Jaw", "chin_length": "Chin, long", "chin_projection": "Chin, out",
	"face_length": "Face, long", "cheekbones": "Cheekbones", "cheek_fullness": "Cheeks, full",
	"nose_length": "Nose, long", "nose_width": "Nose, wide", "nose_bridge": "Bridge", "eye_size": "Eyes, size",
	"eye_spacing": "Eyes, apart", "eye_tilt": "Eyes, tilt", "eye_lids": "Lids, heavy", "brow_height": "Brow, high", "brow_ridge": "Brow ridge",
	"lip_fullness": "Lips", "mouth_width": "Mouth, wide", "ear_size": "Ears"}
const BROW_NAMES := {"": "As they grow", "full": "Full", "straight": "Straight", "arched": "Arched",
	"bushy": "Bushy", "joined": "Meeting"}
const SCAR_NAMES := {"": "None", "cheek": "Across the cheek", "brow": "Through the brow", "lip": "On the lip",
	"nose": "Over the nose", "jaw": "Along the jaw"}
const PAINT_NAMES := {"": "None", "woad": "Woad band (Clans)", "reed_dots": "Reed dots (Reedfolk)",
	"ash_mark": "Ash mark (Pilgrims)", "leaf_lines": "Leaf lines (Woodfolk)", "lake_tears": "Lake tears (Lakefolk)"}
## The Adornment page (triage 48): tattoos and jewellery, said out loud.
const TATTOO_NAMES := {"": "None", "knotwork": "Knotwork band (Clans)", "triple_knot": "Three-looped knot (Clans)",
	"water_lines": "Water lines (Reedfolk)", "reeds": "Reeds (Reedfolk)", "leaf": "Leaf (Woodfolk)",
	"antlers": "Antlers (Woodfolk)", "ash_rings": "Ash rings (Pilgrims)", "hearth_mark": "Hearth-mark (Vale)",
	"tally": "Tally (Lakefolk)", "dots": "Dots", "bands": "Bands"}
const TATTOO_PLACE_NAMES := {"cheek_l": "Left cheek", "cheek_r": "Right cheek", "brow": "Brow", "chin": "Chin",
	"neck": "Neck", "forearm_l": "Left forearm", "forearm_r": "Right forearm", "upper_arm_l": "Left upper arm",
	"upper_arm_r": "Right upper arm", "hand_l": "Left hand", "hand_r": "Right hand", "collarbone_l": "Left collarbone",
	"collarbone_r": "Right collarbone", "back": "Back"}
const INK_NAMES := {"soot": "Soot black", "blue_black": "Blue-black", "woad": "Woad", "indigo": "Marsh indigo",
	"ochre": "Red ochre", "green": "Leaf green", "ash": "Ash"}
const METAL_NAMES := {"iron": "Iron", "bronze": "Bronze", "silver": "Silver", "gold": "Gold", "bone": "Bone",
	"glass": "Glass"}
## How many tattoos the page offers to set (the record takes two on the face and four on the body).
const TATTOO_SLOTS := 4
## The jewellery rows: a label, and its choices as [kind, on, words] ("" kind for none).
const JEWEL_ROWS := [
	["Ears", [["", "", "None"], ["stud", "ears", "Studs"], ["hoop", "ears", "Hoops"], ["drop", "ears", "Drops"],
		["stud", "ear_l", "A stud, left"], ["hoop", "ear_l", "A hoop, left"], ["hoop", "ear_r", "A hoop, right"]]],
	["Nose", [["", "", "None"], ["nose_stud", "nose", "A stud"], ["nose_ring", "nose", "A ring"]]],
	["Lip", [["", "", "None"], ["lip_ring", "lip", "A ring"]]],
	["Neck", [["", "", "None"], ["torc", "neck", "A torc"], ["beads", "neck", "Beads"], ["pendant", "neck", "A pendant"]]],
	["Breast", [["", "", "None"], ["brooch", "breast", "A brooch"]]],
	["Fingers", [["", "", "None"], ["ring", "hand_l", "A ring, left"], ["ring", "hand_r", "A ring, right"],
		["ring", "hands", "Rings, both"]]],
	["Wrists", [["", "", "None"], ["bracelet", "wrist_l", "Left wrist"], ["bracelet", "wrist_r", "Right wrist"],
		["bracelet", "wrists", "Both wrists"]]],
	["Brow", [["", "", "None"], ["circlet", "brow", "A circlet"]]],
	["Hair", [["", "", "None"], ["hair_pin", "hair", "Pins"], ["braid_rings", "hair", "Braid rings"]]],
]
const AGE_WORDS := ["young", "grown", "in middle years", "older", "old"]
const BUILD_WORDS := ["slight", "lean", "even", "solid", "broad"]
## The two bodies, as the Body row names them, in the order it shows them: the record's
## `feminine` for each. A woman wears the forge's woman's body and her cut of every face.
const BODIES := [["Woman", 1.0], ["Man", 0.0]]
## How much shorter a woman is than the man a preset or the lots describe: about a hand, as the
## villagers are (CharacterAppearance.random).
const WOMAN_SHORTER := 0.07
## The slider ranges, chosen so both ends are a person: shorter or taller than this and the
## fixed skeleton's clips stop fitting the ground and the doorways.
const HEIGHT_RANGE := Vector2(1.55, 1.95)
## What the loading caption says between "Be named" and the first look at the world.
const LOADING_LINE := "The Warden walks you out of the Hush. Keep up; she does not look back."
## The two pages, when the pack has styles.
const PAGE_WHO := "who"
const PAGE_HOW := "how"
## How tall a style card's picture of its town is drawn.
const STYLE_PICTURE_HEIGHT := 118.0
## Looks that are worth starting from, by the kind of person they are. A preset follows the body
## chosen: `hair` is a man's, `hair_woman` the same kind of person's as a woman, and a woman takes
## it beardless and a hand shorter (apply_preset).
const PRESETS := [
	{"name": "Hearth-born", "skin": "fair", "hair_colour": "chestnut", "eye_colour": "blue", "head": "round",
		"hair": "short", "hair_woman": "long_loose", "beard": "", "build": 0.50, "height": 1.74},
	{"name": "Drover", "skin": "wheat", "hair_colour": "dark_brown", "eye_colour": "hazel", "head": "angular",
		"hair": "tousled", "hair_woman": "shoulder", "beard": "stubble", "build": 0.58, "height": 1.80},
	{"name": "Fen-walker", "skin": "olive", "hair_colour": "black", "eye_colour": "dark_brown", "head": "narrow",
		"hair": "long", "hair_woman": "twin_braids", "beard": "", "build": 0.36, "height": 1.72},
	{"name": "Old soldier", "skin": "umber", "hair_colour": "grey", "eye_colour": "grey", "head": "heavy_brow",
		"hair": "cropped", "hair_woman": "chignon", "beard": "short_beard", "build": 0.78, "height": 1.82},
	{"name": "Scholar", "skin": "porcelain", "hair_colour": "ash_blond", "eye_colour": "pale_blue", "head": "soft",
		"hair": "bun", "hair_woman": "crown_braid", "beard": "", "build": 0.24, "height": 1.68},
	{"name": "Crag-clan", "skin": "fair", "hair_colour": "ginger", "eye_colour": "green", "head": "broad",
		"hair": "braid", "hair_woman": "twin_braids", "beard": "long_beard", "build": 0.86, "height": 1.86},
]
## The portrait's two framings: the whole figure, and head and shoulders.
const FIGURE := 0.0
const FACE := 1.0
const DEFAULT_YAW := 0.38
const PORTRAIT_WIDTH := 400.0
## The portrait's width on a narrow canvas (a large UI, triage 28: 914x514 at 1.4 on 1280x720).
const PORTRAIT_WIDTH_NARROW := 290.0
const MIDDLE_WIDTH := 372.0

var appearance := CharacterAppearance.new()
var calling_id := ""
## The fighting style chosen ("" when the pack has none).
var style_id := ""
var player_name := ""
## Where "Be named" goes. A test points this at "" so the press stops at the flags instead of
## tearing the test runner down with a scene change.
var world_scene := WORLD_SCENE

var _name_edit: LineEdit
var _suggest_row: HBoxContainer
var _calling_box: GridContainer
var _calling_detail: VBoxContainer
var _style_box: HBoxContainer
var _style_detail: VBoxContainer
var _pages: Dictionary = {}        # page name -> Control
var _tabs: Dictionary = {}         # page name -> Button
var _blurb: Label
## Laid out for a narrow canvas (UiFit.narrow at _build): the Callings under the look in one
## scroll, the page tabs under the title, the portrait narrower, the style cards scrolling with
## what they say.
var _narrow := false
var _preview: SubViewport
var _view: TextureRect
var _camera: Camera3D
var _mannequin: Node3D
var _model: Node = null
var _begin: Button
var _choosers: Dictionary = {}     # slot -> OptionButton
var _body_buttons: Array[Button] = []
var _sliders: Dictionary = {}      # key -> HSlider ("face:<slider>" for a face slider)
var _look_box: Control             # the look's controls, in the middle column
var _face_box: Control             # the Face page, in the same scroll, in their place
var _adorn_box: Control            # the Adornment page, likewise (triage 48)
var _tattoo_choosers: Array = []   # per tattoo slot: {design, on, ink: OptionButton}
var _jewel_choosers: Array = []    # per JEWEL_ROWS row: [kind OptionButton, metal OptionButton]
var _mark_choosers: Dictionary = {}   # record key (brows, scar, paint) -> [OptionButton, options]
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
	# the world is next, and its ground's textures are seconds to read: they are read on a worker
	# thread while the character is made, and the world takes them from there (World._terrain_assets)
	if DisplayServer.get_name() != "headless" and ResourceLoader.exists(World.ASSETS_RESOURCE):
		ResourceLoader.load_threaded_request(World.ASSETS_RESOURCE)
	appearance.set_part("head", "default")
	appearance.set_part("hair", "short")
	var callings := ContentDB.all("calling")
	if not callings.is_empty():
		calling_id = str(callings[0].get("id", ""))
	var styles := StyleDef.all_styles()
	if not styles.is_empty():
		style_id = str(styles[0].get("id", ""))
	player_name = ValishNames.suggestions(1, 20260919)[0]
	_build()
	_refresh_calling()
	_refresh_style()
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

	_narrow = UiFit.narrow(self)
	var page := UiKit.page("")
	var frame: PanelContainer = page["frame"]
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	# a thinner margin above and below than beside: at 720 lines the height is what is short
	frame.offset_left = 20.0
	frame.offset_top = 8.0
	frame.offset_right = -20.0
	frame.offset_bottom = -8.0
	add_child(frame)
	var body: VBoxContainer = page["body"]

	var columns := UiKit.row(18)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(columns)
	columns.add_child(_build_portrait())

	var right := UiKit.column(4)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	var head := UiKit.row(18)
	right.add_child(head)
	head.add_child(UiKit.label("The Naming", "Title"))
	# narrow: the page tabs go on a row of their own under the title
	var tab_row: HBoxContainer = head
	if _narrow:
		tab_row = UiKit.row(8)
		right.add_child(tab_row)
	right.add_child(UiKit.divider())
	var inner := UiKit.row(18)
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(inner)
	# The middle column scrolls if it must. The foot below is outside it, so Back and Be named
	# are always on the page: with the Body row added, the column outgrew 720 lines and pushed
	# the foot off the bottom of the screen (triage 23). At 1280x720 it fits and does not scroll.
	if _narrow:
		# narrow: the Callings under the look, in the same scroll
		var both := UiKit.column(10)
		both.add_child(_build_middle())
		both.add_child(_build_callings())
		var middle_narrow := UiKit.scroll(both)
		middle_narrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		inner.add_child(middle_narrow)
	else:
		var middle := UiKit.scroll(_build_middle())
		middle.size_flags_horizontal = Control.SIZE_FILL
		inner.add_child(middle)
		inner.add_child(_build_callings())
	_pages[PAGE_WHO] = inner
	if not StyleDef.all_styles().is_empty():
		# two pages: who you are, then how you fight; the tabs sit beside the title
		if not _narrow:
			head.add_child(UiKit.spacer())
		for pair in [[PAGE_WHO, "I. Who you are"], [PAGE_HOW, "II. How you fight"]]:
			var page_name: String = pair[0]
			var tab := UiKit.button(str(pair[1]), "FlatButton")
			tab.set_meta("page", page_name)
			tab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			tab.pressed.connect(func() -> void: show_page(page_name))
			tab_row.add_child(tab)
			_tabs[page_name] = tab
		var how := _build_styles()
		how.visible = false
		right.add_child(how)
		_pages[PAGE_HOW] = how

	var foot := UiKit.row(14)
	foot.alignment = BoxContainer.ALIGNMENT_END
	right.add_child(foot)
	var back_button := UiKit.button("Back", "FlatButton")
	back_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(MENU_SCENE))
	foot.add_child(back_button)
	if _pages.has(PAGE_HOW):
		var next := UiKit.button("How you fight", "FlatButton")
		next.set_meta("next_page", true)
		next.pressed.connect(func() -> void: show_page(PAGE_HOW))
		foot.add_child(next)
	_begin = UiKit.button("Be named")
	_begin.pressed.connect(_begin_game)
	foot.add_child(_begin)
	UiKit.ink_in(frame, 0.0, 0.4)
	show_page(PAGE_WHO)


## The portrait: a framed view onto a small lit stage, and the Warden's words under it.
func _build_portrait() -> Control:
	var holder := UiKit.column(6)
	holder.custom_minimum_size = Vector2(_portrait_width(), 0)
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
	if not _narrow:
		lens.add_child(UiKit.label("drag the figure to turn it", "Tiny"))
	# where to start a look from, under the look: in the middle column it was the row that
	# did not fit
	holder.add_child(_presets_row())

	var caption := UiKit.label("The forge has not made a body yet.", "Tiny", HORIZONTAL_ALIGNMENT_CENTER)
	caption.visible = _model == null
	caption.set_anchors_preset(Control.PRESET_CENTER)
	stage.add_child(caption)

	_blurb = UiKit.wrapped(_portrait_words(), "Journal")
	_blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_blurb.add_theme_font_size_override("font_size", 14)
	_blurb.custom_minimum_size = Vector2(_portrait_width(), 0)
	holder.add_child(_blurb)
	return holder


## The words under the portrait. The fallback start is the Naming in the fiction, a Warden over you
## at the top of the stair; a styled character is named before the story, by the life they had.
func _portrait_words() -> String:
	if StyleDef.all_styles().is_empty():
		return "You came up the Hushline Stair with nothing. A Warden is asking what you are called, " + \
				"and she is not going to guess."
	return "Before the Hush, you had a name, a people and somebody who taught you to fight. " + \
			"Say them, so they are said."


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
	col.add_child(_body_row())
	col.add_child(_swatches("Skin", CharacterAppearance.SKIN_TONES, "skin"))
	# the first twelve; the wider palette's shades are on the Face page
	col.add_child(_swatches("Hair", CharacterAppearance.HAIR_COLOURS.slice(0, 12), "hair_colour"))
	col.add_child(_swatches("Eyes", CharacterAppearance.EYE_COLOURS, "eye_colour"))
	var face_row := _chooser("Face", CharacterAppearance.HEADS, HEAD_NAMES, "head")
	# the Face page: the sliders, the years and the marks, in this column's place
	var shape := UiKit.button("Shape...", "FlatButton")
	shape.set_meta("face_page", true)
	shape.tooltip_text = "Shape the face: its sliders, the years, the brows and marks"
	shape.pressed.connect(func() -> void: show_face_page(true))
	face_row.add_child(shape)
	col.add_child(face_row)
	col.add_child(_chooser("Style", CharacterAppearance.HAIR_STYLES, HAIR_STYLE_NAMES, "hair"))
	var beard_row := _chooser("Beard", offered_beards(), BEARD_NAMES, "beard")
	# the Adornment page: tattoos and jewellery (triage 48), in the same place the Face page takes
	var adorn := UiKit.button("Adorn...", "FlatButton")
	adorn.set_meta("adorn_page", true)
	adorn.tooltip_text = "Tattoos and jewellery"
	adorn.pressed.connect(func() -> void: show_adorn_page(true))
	beard_row.add_child(adorn)
	col.add_child(beard_row)
	col.add_child(_slider("Build", "build", 0.0, 1.0, 0.05))
	col.add_child(_slider("Height", "height", HEIGHT_RANGE.x, HEIGHT_RANGE.y, 0.01))
	# the Face page takes the look's place in the same scroll area (show_face_page)
	var both := UiKit.column(4)
	both.custom_minimum_size = Vector2(MIDDLE_WIDTH, 0)
	col.custom_minimum_size = Vector2(0, 0)
	_look_box = col
	both.add_child(col)
	_face_box = _build_face()
	_face_box.visible = false
	both.add_child(_face_box)
	_adorn_box = _build_adorn()
	_adorn_box.visible = false
	both.add_child(_adorn_box)
	return both


## The Adornment page (triage 48): up to four tattoos (the design, where, the ink, how old) and the
## jewellery, a row to each place it is worn, with what it is made of. It scrolls in the middle
## column's own scroll area, as the Face page does.
func _build_adorn() -> Control:
	var col := UiKit.column(4)
	var top := UiKit.row(6)
	var back := UiKit.button("< The look", "FlatButton")
	back.set_meta("adorn_page", false)
	back.tooltip_text = "Back to the look"
	back.pressed.connect(func() -> void: show_adorn_page(false))
	top.add_child(back)
	top.add_child(UiKit.spacer())
	var lots := UiKit.button("Cast lots for them", "FlatButton")
	lots.set_meta("adorn_lots", true)
	lots.tooltip_text = "Tattoos and jewellery chosen by chance, as your people wear them"
	lots.pressed.connect(func() -> void: randomise_adornment())
	top.add_child(lots)
	col.add_child(top)
	col.add_child(_heading("Tattoos"))
	var designs: Array = CharacterAppearance.TATTOO_DESIGNS.duplicate()
	var places: Array = CharacterAppearance.FACE_TATTOO_PLACES + CharacterAppearance.BODY_TATTOO_PLACES
	var inks: Array = CharacterAppearance.TATTOO_INK_ORDER.duplicate()
	_tattoo_choosers = []
	for i in TATTOO_SLOTS:
		var design := _adorn_option(designs, TATTOO_NAMES, "tattoo_design", i)
		var on := _adorn_option(places, TATTOO_PLACE_NAMES, "tattoo_on", i)
		var ink := _adorn_option(inks, INK_NAMES, "tattoo_ink", i)
		col.add_child(_labelled("Mark %d" % (i + 1), design))
		# where it is, and in what
		var where := UiKit.row(4)
		ink.custom_minimum_size = Vector2(112, 0)
		ink.size_flags_horizontal = Control.SIZE_SHRINK_END
		where.add_child(on)
		where.add_child(ink)
		col.add_child(_labelled("On the", where))
		# how old the ink is: a fresh line, or one gone soft and blue under the skin
		col.add_child(_slider("Its age", "tfade:%d" % i, 0.0, 1.0, 0.05))
		_tattoo_choosers.append({"design": design, "on": on, "ink": ink})
	col.add_child(UiKit.divider())
	col.add_child(_heading("Jewellery"))
	var metals: Array = CharacterAppearance.JEWELLERY_METALS.duplicate()
	_jewel_choosers = []
	for r in JEWEL_ROWS.size():
		var names := {}
		var kinds: Array = []
		for k in (JEWEL_ROWS[r][1] as Array).size():
			kinds.append(k)
			names[k] = str(JEWEL_ROWS[r][1][k][2])
		var kind := _adorn_option(kinds, names, "jewel_kind", r)
		var metal := _adorn_option(metals, METAL_NAMES, "jewel_metal", r)
		metal.custom_minimum_size = Vector2(108, 0)
		metal.size_flags_horizontal = Control.SIZE_SHRINK_END
		var row := UiKit.row(4)
		row.add_child(kind)
		row.add_child(metal)
		col.add_child(_labelled(str(JEWEL_ROWS[r][0]), row))
		_jewel_choosers.append([kind, metal])
	return col


## A drop-down on the Adornment page: `what` and `index` say which (a tattoo slot's design, place or
## ink; a jewellery row's kind or stuff), and choosing writes it into the record.
func _adorn_option(options: Array, names: Dictionary, what: String, index: int) -> OptionButton:
	var o := OptionButton.new()
	o.set_meta("adorn", "%s:%d" % [what, index])
	o.fit_to_longest_item = false
	o.custom_minimum_size = Vector2(60, 0)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.clip_text = true
	for option in options:
		o.add_item(str(names.get(option, str(option))))
	# Opened on the click's release, not its press: a list too long to fit above or below its
	# chooser (the hair styles, eighteen since the face work) is laid over it, and the release of
	# a press that had opened it picked an item and shut it again (flow, 2026-09-28).
	o.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	var popup := o.get_popup()
	popup.about_to_popup.connect(func() -> void: _open_below.call_deferred(o))
	o.item_selected.connect(func(chosen: int) -> void:
			if chosen < 0 or chosen >= options.size():
				return
			_choose_adornment(what, index, options[chosen]))
	return o


## What one of the Adornment page's choosers writes into the record.
func _choose_adornment(what: String, index: int, value: Variant) -> void:
	var tattoos: Array = appearance.tattoos.duplicate(true)
	match what:
		"tattoo_design", "tattoo_on", "tattoo_ink":
			var t: Dictionary = tattoos[index] if index < tattoos.size() else {}
			if what == "tattoo_design" and str(value).is_empty():
				if index < tattoos.size():
					tattoos.remove_at(index)
			else:
				if t.is_empty():
					t = {"design": "knotwork", "on": _free_tattoo_place(tattoos), "ink": "soot", "fade": 0.0}
				t[{"tattoo_design": "design", "tattoo_on": "on", "tattoo_ink": "ink"}[what]] = str(value)
				if index < tattoos.size():
					tattoos[index] = t
				else:
					tattoos.append(t)
			appearance.set_tattoos(tattoos)
			var on := str(value) if what == "tattoo_on" else str(t.get("on", ""))
			_focus(FACE if CharacterAppearance.FACE_TATTOO_PLACES.has(on) else FIGURE)
		"jewel_kind", "jewel_metal":
			var row: Array = JEWEL_ROWS[index][1]
			var kinds: Array = []
			for choice in row:
				if not str(choice[0]).is_empty():
					kinds.append(str(choice[0]))
			var metal_o := (_jewel_choosers[index] as Array)[1] as OptionButton
			var metal := str(CharacterAppearance.JEWELLERY_METALS[maxi(metal_o.selected, 0)])
			var worn := appearance.jewel_of(kinds)
			var list: Array = appearance.jewellery.filter(func(j: Dictionary) -> bool: return not kinds.has(str(j["kind"])))
			if what == "jewel_kind":
				var choice: Array = row[int(value)]
				if not str(choice[0]).is_empty():
					list.append({"kind": str(choice[0]), "on": str(choice[1]), "metal": metal})
			elif not worn.is_empty():
				worn = worn.duplicate()
				worn["metal"] = str(value)
				list.append(worn)
			appearance.set_jewellery(list)
			# the ears, the nose, the lip, the brow and the hair are seen close; the rest on the figure
			_focus(FACE if index <= 2 or index >= 7 else FIGURE)
	_sync_adornment()
	_apply_appearance()


## A place no tattoo in `list` has, for a new one (the first of the body's, then the face's).
func _free_tattoo_place(list: Array) -> String:
	var taken := {}
	for t in list:
		taken[str(t.get("on", ""))] = true
	for p in CharacterAppearance.BODY_TATTOO_PLACES + CharacterAppearance.FACE_TATTOO_PLACES:
		if not taken.has(p):
			return p
	return "forearm_l"


## The Adornment page's choosers, in step with the record.
func _sync_adornment() -> void:
	var places: Array = CharacterAppearance.FACE_TATTOO_PLACES + CharacterAppearance.BODY_TATTOO_PLACES
	for i in _tattoo_choosers.size():
		var c: Dictionary = _tattoo_choosers[i]
		var t: Dictionary = appearance.tattoos[i] if i < appearance.tattoos.size() else {}
		(c["design"] as OptionButton).select(maxi(CharacterAppearance.TATTOO_DESIGNS.find(str(t.get("design", ""))), 0))
		(c["on"] as OptionButton).select(maxi(places.find(str(t.get("on", ""))), 0))
		(c["ink"] as OptionButton).select(maxi(CharacterAppearance.TATTOO_INK_ORDER.find(str(t.get("ink", "soot"))), 0))
		(c["on"] as OptionButton).disabled = t.is_empty()
		(c["ink"] as OptionButton).disabled = t.is_empty()
	for r in _jewel_choosers.size():
		var row: Array = JEWEL_ROWS[r][1]
		var pair: Array = _jewel_choosers[r]
		var chosen := 0
		for k in row.size():
			var choice: Array = row[k]
			if str(choice[0]).is_empty():
				continue
			for j in appearance.jewellery:
				if str(j["kind"]) == str(choice[0]) and str(j["on"]) == str(choice[1]):
					chosen = k
					(pair[1] as OptionButton).select(maxi(CharacterAppearance.JEWELLERY_METALS.find(str(j["metal"])), 0))
		(pair[0] as OptionButton).select(chosen)


## The look's controls, or the Adornment page's in their place (as the Face page takes it).
func show_adorn_page(on: bool) -> void:
	if _look_box == null or _adorn_box == null:
		return
	_face_box.visible = false
	_look_box.visible = not on
	_adorn_box.visible = on
	var p := _adorn_box.get_parent()
	while p != null and not (p is ScrollContainer):
		p = p.get_parent()
	if p != null:
		(p as ScrollContainer).set_deferred("scroll_vertical", 0)
	_sync_controls()
	if on:
		_focus(FACE)


## Tattoos and jewellery by chance, as the people of the Calling chosen wear them (their own dice).
func randomise_adornment(rng_seed: int = -1) -> void:
	var rng := RandomNumberGenerator.new()
	if rng_seed >= 0:
		rng.seed = rng_seed
	else:
		rng.randomize()
	_dress_for_calling()
	appearance.roll_adornment(rng, rng.randf_range(0.3, 0.8))
	_sync_controls()
	_apply_appearance()


## The Face page: the sliders in their groups, the years, the brows and the marks, the hair's greys
## and the wider palette, the shoulders. It scrolls, in the middle column's own scroll area.
func _build_face() -> Control:
	var col := UiKit.column(4)
	var top := UiKit.row(6)
	var back := UiKit.button("< The look", "FlatButton")
	back.set_meta("face_page", false)
	back.tooltip_text = "Back to the look"
	back.pressed.connect(func() -> void: show_face_page(false))
	top.add_child(back)
	top.add_child(UiKit.spacer())
	var lots := UiKit.button("Cast lots for the face", "FlatButton")
	lots.set_meta("face_lots", true)
	lots.tooltip_text = "A face chosen by chance, and nothing else"
	lots.pressed.connect(func() -> void: randomise_face())
	top.add_child(lots)
	col.add_child(top)
	col.add_child(_heading("Your face"))
	col.add_child(_slider("Years", "age", 0.05, 1.0, 0.05))
	for group in CharacterAppearance.FACE_GROUPS:
		col.add_child(UiKit.label(str(group[0]), "Small"))
		for slider in group[1]:
			col.add_child(_slider(str(FACE_NAMES.get(slider, slider)), "face:%s" % slider, -1.0, 1.0, 0.05, 86.0))
	col.add_child(UiKit.divider())
	col.add_child(_heading("Brows and marks"))
	col.add_child(_mark_chooser("Brows", CharacterAppearance.BROW_STYLES, BROW_NAMES, "brows"))
	col.add_child(_mark_chooser("Scar", CharacterAppearance.SCARS, SCAR_NAMES, "scar"))
	col.add_child(_mark_chooser("Paint", CharacterAppearance.PAINTS, PAINT_NAMES, "paint"))
	col.add_child(_slider("Moles", "moles", 0.0, 1.0, 0.1))
	col.add_child(_slider("Freckles", "freckles", 0.0, 0.6, 0.05))
	col.add_child(UiKit.divider())
	col.add_child(_heading("Hair and shoulders"))
	var more: Array = []
	for tone in CharacterAppearance.HAIR_COLOURS:
		if CharacterAppearance.HAIR_COLOURS.find(tone) >= 12:
			more.append(tone)
	col.add_child(_swatches("Shades", more, "hair_colour"))
	col.add_child(_slider("Grey", "grey", 0.0, 1.0, 0.05))
	col.add_child(_slider("Shoulders", "shoulder_width", 0.86, 1.14, 0.02))
	return col


## The look's controls or the Face page's, in the middle column. The Face page closes in on the face.
func show_face_page(on: bool) -> void:
	if _look_box == null or _face_box == null:
		return
	if _adorn_box != null:
		_adorn_box.visible = false
	_look_box.visible = not on
	_face_box.visible = on
	# from the top of the page each time: its way back and its lots are there
	var p := _face_box.get_parent()
	while p != null and not (p is ScrollContainer):
		p = p.get_parent()
	if p != null:
		(p as ScrollContainer).set_deferred("scroll_vertical", 0)
	_sync_controls()
	if on:
		_focus(FACE)


## A drop-down over one of the record's own words (brows, scar, paint), not a part.
func _mark_chooser(text: String, options: Array, names: Dictionary, key: String) -> HBoxContainer:
	var o := OptionButton.new()
	o.set_meta("mark", key)
	o.fit_to_longest_item = false
	o.custom_minimum_size = Vector2(150, 0)
	for option in options:
		o.add_item(str(names.get(option, str(option))))
	o.selected = maxi(options.find(str(appearance.get(key))), 0)
	# Opened on the click's release, not its press: a list too long to fit above or below its
	# chooser (the hair styles, eighteen since the face work) is laid over it, and the release of
	# a press that had opened it picked an item and shut it again (flow, 2026-09-28).
	o.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	var popup := o.get_popup()
	popup.about_to_popup.connect(func() -> void: _open_below.call_deferred(o))
	o.item_selected.connect(func(index: int) -> void:
			if index < 0 or index >= options.size():
				return
			appearance.set(key, str(options[index]))
			_focus(FACE)
			_apply_appearance())
	_mark_choosers[key] = [o, options]
	return _labelled(text, o)


## A value the sliders show: the record's own, or a face slider's ("face:<slider>"), or how grey the
## hair is now (the years' grey until the slider is moved).
func _value_of(key: String) -> float:
	if key.begins_with("face:"):
		return appearance.face_value(key.substr(5))
	if key.begins_with("tfade:"):
		var i := int(key.substr(6))
		return float((appearance.tattoos[i] as Dictionary).get("fade", 0.0)) if i < appearance.tattoos.size() else 0.0
	if key == "grey":
		return appearance.hair_grey()
	return float(appearance.get(key))


func _set_value(key: String, v: float) -> void:
	if key.begins_with("face:"):
		appearance.set_face(key.substr(5), v)
	elif key.begins_with("tfade:"):
		var i := int(key.substr(6))
		if i < appearance.tattoos.size():
			var list: Array = appearance.tattoos.duplicate(true)
			list[i]["fade"] = v
			appearance.set_tattoos(list)
	else:
		appearance.set(key, v)


## Start from a kind of person, or cast lots: a whole look at once.
func _presets_row() -> HBoxContainer:
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
	return starts


## Woman or man: two buttons that hold down, one of them always. The body is read from the whole
## figure, so choosing one stands the portrait back to show it. A woman has no beard unless she
## chooses one after: the one a man had is taken off with the change.
func _body_row() -> HBoxContainer:
	var row := UiKit.row(4)
	var group := ButtonGroup.new()
	_body_buttons.clear()
	for pair in BODIES:
		var b := UiKit.button(str(pair[0]), "FlatButton")
		b.toggle_mode = true
		b.button_group = group
		b.set_meta("feminine", float(pair[1]))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = "Body: %s" % str(pair[0]).to_lower()
		b.pressed.connect(func() -> void: choose_body(float(pair[1])))
		row.add_child(b)
		_body_buttons.append(b)
	_mark_body()
	return _labelled("Body", row)


## Puts the record in a woman's body (1.0) or a man's (0.0), as the Body row does.
func choose_body(feminine: float) -> void:
	var was_woman := appearance.is_woman()
	appearance.feminine = feminine
	if appearance.is_woman() and not was_woman:
		appearance.set_part("beard", "")
	if appearance.is_woman() != was_woman:
		# and the same kind of cut on her (or him): the Naming starts short-haired, and a woman
		# chosen kept a man's crop
		appearance.set_part("hair", appearance.hair_for_body(appearance.part("hair")))
	_sync_controls()
	_focus(FIGURE)
	_apply_appearance()


func _mark_body() -> void:
	for b in _body_buttons:
		var on := is_equal_approx(float(b.get_meta("feminine")), 1.0 if appearance.is_woman() else 0.0)
		b.set_pressed_no_signal(on)
		# as a chosen swatch stands out from its row
		b.modulate = Color(1, 1, 1, 1) if on else Color(0.86, 0.86, 0.86, 0.92)


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
		var tone_label := str(tone)
		var b := Button.new()
		b.theme_type_variation = &"FlatButton"
		b.custom_minimum_size = Vector2(24, 24)
		b.tooltip_text = "%s: %s" % [text, _tone_name(key, tone_label)]
		b.set_meta("tone", tone_label)
		var swatch := ColorRect.new()
		swatch.color = _tone_colour(key, tone_label)
		swatch.set_anchors_preset(Control.PRESET_FULL_RECT)
		swatch.offset_left = 4.0
		swatch.offset_top = 4.0
		swatch.offset_right = -4.0
		swatch.offset_bottom = -4.0
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(swatch)
		b.pressed.connect(func() -> void:
				appearance.set(key, tone_label)
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


func _tone_colour(key: String, tone: String) -> Color:
	match key:
		"skin":
			return CharacterAppearance.skin_colour(tone)
		"hair_colour":
			return CharacterAppearance.hair_colour_value(tone)
	return CharacterAppearance.eye_colour_value(tone)


func _tone_name(key: String, tone: String) -> String:
	if key == "skin":
		return str(SKIN_NAMES.get(tone, tone))
	return tone.replace("_", " ").capitalize()


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
	# A list opens below its chooser. At 720 lines the Body row took the room the style list needed,
	# and one that does not fit is moved up over the chooser, where the release of the click that
	# opened it chose an item and shut it (flow, 2026-09-27). Opened, it keeps below its chooser and
	# scrolls within the room there is.
	# Opened on the click's release, not its press: a list too long to fit above or below its
	# chooser (the hair styles, eighteen since the face work) is laid over it, and the release of
	# a press that had opened it picked an item and shut it again (flow, 2026-09-28).
	o.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	var popup := o.get_popup()
	popup.about_to_popup.connect(func() -> void: _open_below.call_deferred(o))
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


## A chooser's list opens below its chooser, or where there is no room for it there, just above:
## never over it. The engine moved a list that did not fit up over its chooser, and at 720 lines
## the release of the click that opened the face list landed on it and shut it, so the list could
## not be opened by the mouse at all (flow, and a probe under a display, 2026-09-28). A list will
## not be made shorter than its items, so it is moved, not shrunk.
func _open_below(o: OptionButton) -> void:
	var popup := o.get_popup()
	if not popup.visible:
		return
	var r := o.get_screen_transform() * Rect2(Vector2.ZERO, o.size)
	var screen := get_viewport().get_visible_rect().size
	var h := popup.size.y
	if r.end.y + h <= screen.y:
		popup.position = Vector2i(popup.position.x, int(r.end.y))
	elif r.position.y - h >= 0.0:
		popup.position = Vector2i(popup.position.x, int(r.position.y) - h)


func _slider(text: String, key: String, low: float, high: float, step: float, label_width := 52.0) -> HBoxContainer:
	var row := UiKit.row(6)
	var s := HSlider.new()
	s.set_meta("key", key)
	s.min_value = low
	s.max_value = high
	s.step = step
	s.value = _value_of(key)
	s.custom_minimum_size = Vector2(150, 22)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value_label := UiKit.label("", "Small")
	value_label.custom_minimum_size = Vector2(56, 0)
	value_label.text = _value_text(key, _value_of(key))
	_slider_labels[key] = value_label
	# the build and the height are read from the whole figure; everything else here from the face
	var framing := FIGURE if key in ["build", "height", "shoulder_width"] else FACE
	s.value_changed.connect(func(v: float) -> void:
			_set_value(key, v)
			value_label.text = _value_text(key, v)
			_focus(framing)
			_apply_appearance())
	# a plain click on the track moves the grabber with its signals blocked; only a drag
	# reports, so the click is picked up when the button comes back up
	s.drag_ended.connect(func(_changed: bool) -> void:
			if not is_equal_approx(_value_of(key), s.value):
				_set_value(key, s.value)
				value_label.text = _value_text(key, s.value)
				_apply_appearance())
	row.add_child(s)
	row.add_child(value_label)
	_sliders[key] = s
	return _labelled(text, row, label_width)


func _value_text(key: String, value: float) -> String:
	if key == "height":
		return "%.2f m" % value
	if key.begins_with("face:"):
		return "%+.1f" % value if absf(value) >= 0.05 else "as made"
	if key.begins_with("tfade:"):
		return "fresh" if value < 0.2 else ("worn" if value < 0.6 else "old")
	match key:
		"age":
			return AGE_WORDS[clampi(int(value * 4.999), 0, AGE_WORDS.size() - 1)]
		"grey", "moles", "freckles":
			return "none" if value < 0.05 else "%d%%" % int(round(value * 100.0))
		"shoulder_width":
			return "narrow" if value < 0.95 else ("broad" if value > 1.05 else "even")
	return BUILD_WORDS[clampi(int(value * 4.999), 0, BUILD_WORDS.size() - 1)]


func _roll_suggestions() -> void:
	for child in _suggest_row.get_children():
		child.queue_free()
	_suggest_row.add_child(UiKit.label("or", "Tiny"))
	for suggestion in ValishNames.suggestions(3):
		var b := UiKit.button(suggestion, "FlatButton")
		b.add_theme_font_size_override("font_size", ThemeBuilder.SIZES.small)
		# The row shares the column's width instead of setting it: three long names ("Hesk of
		# Fallowhithe") widened the middle column at 1280x720, and the right-hand column's
		# heading broke over two lines and its callings' peoples were cut off.
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = suggestion
		b.pressed.connect(func() -> void:
				player_name = suggestion
				_name_edit.text = suggestion
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
	# Narrow, the column is already in the look's scroll (_build), and a scroll in a scroll is
	# squeezed to nothing.
	if _narrow:
		return col
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
		_begin.disabled = player_name.strip_edges().is_empty() or calling_id.is_empty() \
				or (_pages.has(PAGE_HOW) and style_id.is_empty())


# --- how you fight -----------------------------------------------------------------------------

## Shows one of the two pages, and marks its tab.
func show_page(page_name: String) -> void:
	if not _pages.has(page_name):
		return
	for key in _pages:
		(_pages[key] as Control).visible = key == page_name
	for key in _tabs:
		(_tabs[key] as Button).modulate = Color(1, 1, 1, 1.0 if key == page_name else 0.62)
	for b in find_children("*", "Button", true, false):
		if b.has_meta("next_page"):
			(b as Button).visible = page_name != PAGE_HOW
	if page_name == PAGE_HOW:
		_focus(FIGURE)
		UiKit.ink_in(_pages[page_name], 0.0, 0.3)


## The page of fighting styles: a card each, side by side, and what the chosen one means below.
func _build_styles() -> Control:
	var col := UiKit.column(8)
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_heading("How were you taught to fight?"))
	_style_box = UiKit.row(8)
	_style_detail = UiKit.column(6)
	if _narrow:
		# narrow: the cards and what the chosen one means scroll together, or the cards leave
		# what they mean no room at all
		var both := UiKit.column(8)
		both.add_child(_style_box)
		both.add_child(UiKit.divider())
		both.add_child(_style_detail)
		col.add_child(UiKit.scroll(both))
	else:
		col.add_child(_style_box)
		col.add_child(UiKit.divider())
		col.add_child(UiKit.scroll(_style_detail))
	for def in StyleDef.all_styles():
		_style_box.add_child(_style_card(def))
	return col


func _portrait_width() -> float:
	return PORTRAIT_WIDTH_NARROW if _narrow else PORTRAIT_WIDTH


## One style's card: the start town's picture, the style's name, and where and by whom.
func _style_card(def: Dictionary) -> Button:
	var id := str(def.get("id", ""))
	var b := UiKit.button("", "FlatButton")
	b.set_meta("style", id)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.tooltip_text = str(def.get("blurb", ""))
	b.pressed.connect(func() -> void:
			style_id = id
			_refresh_style())
	var inside := UiKit.column(2)
	inside.set_anchors_preset(Control.PRESET_FULL_RECT)
	inside.offset_left = 5.0
	inside.offset_top = 5.0
	inside.offset_right = -5.0
	inside.offset_bottom = -4.0
	inside.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(inside)
	var frame := UiKit.panel("OakPanel")
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.custom_minimum_size = Vector2(0, STYLE_PICTURE_HEIGHT)
	inside.add_child(frame)
	var picture := TextureRect.new()
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.custom_minimum_size = Vector2(0, STYLE_PICTURE_HEIGHT - 8.0)
	var path := str(def.get("picture", ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		picture.texture = load(path)
	frame.add_child(picture)
	var name_row := UiKit.row(6)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inside.add_child(name_row)
	name_row.add_child(UiKit.icon_rect(str(def.get("icon", "sword")), 20))
	name_row.add_child(UiKit.label(str(def.get("name", id)), "Emphasis"))
	var start := ContentDB.get_or_empty(str(def.get("start", "")))
	var teacher := ContentDB.get_or_empty(str(def.get("teacher", "")))
	var where := UiKit.label("%s · %s" % [str(start.get("name", "")), str(teacher.get("name", ""))], "Tiny")
	where.clip_text = true
	where.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	inside.add_child(where)
	# The words are drawn on the button, not laid out by it, so it is told how tall they stand:
	# a fixed height left each card's name and its town under the card, over the rule below.
	var fit := func() -> void:
		b.custom_minimum_size = Vector2(0, inside.get_combined_minimum_size().y
				+ inside.offset_top - inside.offset_bottom)
	inside.minimum_size_changed.connect(fit)
	fit.call()
	return b


## Marks the chosen card and writes what it means: the line about the start, the kit, the skills,
## the horse, and a word on a Calling from far away.
func _refresh_style() -> void:
	if _style_box == null:
		return
	for child in _style_box.get_children():
		if child is Button:
			var on: bool = str(child.get_meta("style", "")) == style_id
			child.modulate = Color(1, 1, 1, 1.0 if on else 0.6)
	for child in _style_detail.get_children():
		child.queue_free()
	var def := ContentDB.get_or_empty(style_id)
	if def.is_empty():
		_update_begin()
		return
	var blurb := UiKit.wrapped(str(def.get("blurb", "")), "Journal")
	blurb.add_theme_font_size_override("font_size", 15)
	_style_detail.add_child(blurb)
	var kit := StyleDef.kit_words(def)
	if not kit.is_empty():
		_detail_row(_style_detail, str(def.get("icon", "sword")), "You start with %s." % kit)
	var bonuses: Dictionary = def.get("skill_bonuses", {})
	if not bonuses.is_empty():
		var known: Array[String] = []
		for skill: String in bonuses:
			var skill_def := ContentDB.get_or_empty("core:skill/" + skill)
			known.append("%s +%d" % [str(skill_def.get("name", skill)), int(bonuses[skill])])
		_detail_row(_style_detail, "book", "Taught: " + ", ".join(known) + ", on top of your Calling's.")
	var mount := ContentDB.get_or_empty(str(def.get("mount", "")))
	var teacher := ContentDB.get_or_empty(str(def.get("teacher", "")))
	if not mount.is_empty():
		_detail_row(_style_detail, "map",
				"%s will give you a horse, %s, and send you south." % [str(teacher.get("name", "Your teacher")), str(mount.get("name", ""))])
	UiKit.ink_in(_style_detail, 0.0, 0.26)
	_update_begin()


func _detail_row(into: Control, icon: String, text: String) -> void:
	var row := UiKit.row(8)
	row.add_child(UiKit.icon_rect(icon, 18))
	row.add_child(UiKit.wrapped(text, "Small"))
	into.add_child(row)


# --- looks ------------------------------------------------------------------------------------

## One of PRESETS, through the same record every control writes. A preset is a kind of person,
## not a body: it keeps the body chosen, and a woman takes it beardless and a hand shorter.
func apply_preset(p: Dictionary) -> void:
	appearance.skin = str(p["skin"])
	appearance.hair_colour = str(p["hair_colour"])
	appearance.eye_colour = str(p["eye_colour"])
	appearance.set_part("head", str(p["head"]))
	appearance.set_part("hair", str(p.get("hair_woman", p["hair"]) if appearance.is_woman() else p["hair"]))
	var beard := "" if appearance.is_woman() else str(p["beard"])
	appearance.set_part("beard", beard if offered_beards().has(beard) else "")
	appearance.build = float(p["build"])
	appearance.height = clampf(float(p["height"]) - (WOMAN_SHORTER if appearance.is_woman() else 0.0),
			HEIGHT_RANGE.x, HEIGHT_RANGE.y)
	_sync_controls()
	_focus(FIGURE)
	_apply_appearance()


## A look chosen by chance, from a spread that stays a plausible person: most people have no
## beard, grey hair is for the build of a face that has earned it, and heights cluster. The body
## is the one chosen: the lots cast a face and a build for it, and no beard for a woman.
func randomise(rng_seed: int = -1) -> void:
	var rng := RandomNumberGenerator.new()
	if rng_seed >= 0:
		rng.seed = rng_seed
	else:
		rng.randomize()
	appearance.skin = CharacterAppearance.SKIN_TONES[rng.randi() % CharacterAppearance.SKIN_TONES.size()]
	appearance.hair_colour = CharacterAppearance.NATURAL_HAIR[rng.randi() % CharacterAppearance.NATURAL_HAIR.size()]
	if rng.randf() < 0.15:
		appearance.hair_colour = "grey" if rng.randf() < 0.7 else "white"
	appearance.eye_colour = CharacterAppearance.EYE_COLOURS[rng.randi() % CharacterAppearance.EYE_COLOURS.size()]
	appearance.set_part("head", CharacterAppearance.HEADS[rng.randi() % CharacterAppearance.HEADS.size()])
	# a woman's lots fall mostly on the women's cuts, as a villager's do
	var styles: Array[String] = CharacterAppearance.WOMEN_HAIR if appearance.is_woman() else CharacterAppearance.HAIR_STYLES
	appearance.set_part("hair", styles[rng.randi() % styles.size()])
	var beard := ""
	var beards := offered_beards()
	if rng.randf() < 0.4 and beards.size() > 1:
		beard = str(beards[1 + rng.randi() % (beards.size() - 1)])
	appearance.set_part("beard", "" if appearance.is_woman() else beard)
	appearance.build = clampf(snappedf(rng.randfn(0.48, 0.20), 0.05), 0.0, 1.0)
	var mean := 1.76 - (WOMAN_SHORTER if appearance.is_woman() else 0.0)
	appearance.height = clampf(snappedf(rng.randfn(mean, 0.07), 0.01), HEIGHT_RANGE.x, HEIGHT_RANGE.y)
	# and a face, with its marks: the whole look is the lots'
	_roll_face(rng)
	_sync_controls()
	_focus(FIGURE)
	_apply_appearance()


## The face alone by chance (the Face page's lots): the sliders, the brows and marks, and the years
## within a span a new life starts at. Nothing else of the look changes.
func randomise_face(rng_seed: int = -1) -> void:
	var rng := RandomNumberGenerator.new()
	if rng_seed >= 0:
		rng.seed = rng_seed
	else:
		rng.randomize()
	_roll_face(rng)
	_sync_controls()
	_focus(FACE)
	_apply_appearance()


func _roll_face(rng: RandomNumberGenerator) -> void:
	_dress_for_calling()
	appearance.age = clampf(snappedf(rng.randfn(0.32, 0.14), 0.05), 0.05, 0.8)
	appearance.grey = -1.0
	appearance.roll_face(rng)
	appearance.roll_marks(rng)


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
		(_sliders[key] as HSlider).set_value_no_signal(_value_of(key))
		if _slider_labels.has(key):
			(_slider_labels[key] as Label).text = _value_text(key, _value_of(key))
	for key in _mark_choosers:
		var pair: Array = _mark_choosers[key]
		(pair[0] as OptionButton).select(maxi((pair[1] as Array).find(str(appearance.get(key))), 0))
	_sync_adornment()
	for pair in [["Skin", "skin"], ["Hair", "hair_colour"], ["Eyes", "eye_colour"], ["Shades", "hair_colour"]]:
		var row := _swatch_row(str(pair[0]))
		if row != null:
			_mark_swatches(row, str(pair[1]))
	_mark_body()


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
	var typed := player_name.strip_edges()
	GameState.reset_for_new_game(abs(("%s|%s" % [typed, calling_id]).hash()))
	GameState.set_flag("player_name", typed)
	GameState.set_flag("player_calling", calling_id)
	GameState.set_flag("player_appearance", appearance_dict())
	if not style_id.is_empty() and not StyleDef.opening_of(style_id).is_empty():
		# the style's own start, in its own town; the Hushline comes later (Openings)
		GameState.set_flag(StyleDef.FLAG, style_id)
		GameState.set_flag(Openings.STYLE_START, true)
		GameState.set_flag(Openings.STYLE_DUE, true)
	else:
		GameState.set_flag(Openings.NEW_GAME, true)


## What the loading caption says on the way into the world: the style's own line, or the Warden's.
func loading_line() -> String:
	var line := str(ContentDB.get_or_empty(style_id).get("loading_line", "")) if not style_id.is_empty() else ""
	return line if not line.is_empty() else LOADING_LINE


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
	UI.fade_to_black(0.5, loading_line())
	await get_tree().create_timer(0.55).timeout
	get_tree().change_scene_to_file(world_scene)


## Used by the review harness to show the screen part-way through being filled in.
func review_state(state := "default") -> void:
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
	_refresh_style()
	_apply_appearance()
	if state == "styles":
		show_page(PAGE_HOW)
	elif state == "face":
		# the Face page, a woman of middle years with a face of her own and a people's paint
		choose_body(1.0)
		appearance.age = 0.5
		for pair in [["jaw_width", -0.3], ["cheekbones", 0.6], ["nose_bridge", 0.4], ["eye_tilt", 0.3],
				["lip_fullness", 0.4], ["brow_height", 0.2]]:
			appearance.set_face(str(pair[0]), float(pair[1]))
		appearance.brows = "arched"
		appearance.paint = "reed_dots"
		appearance.moles = 0.4
		show_face_page(true)
		_apply_appearance()
	elif state == "adorn":
		# the Adornment page (triage 48): a woman with a knot on her cheek, hoops, a torc and braid rings
		choose_body(1.0)
		appearance.age = 0.4
		appearance.set_part("hair", "twin_braids")
		appearance.set_tattoos([{"design": "triple_knot", "on": "cheek_l", "ink": "woad", "fade": 0.25},
			{"design": "knotwork", "on": "forearm_r", "ink": "woad", "fade": 0.5}])
		appearance.set_jewellery([{"kind": "hoop", "on": "ears", "metal": "gold"}, {"kind": "nose_stud", "metal": "silver"},
			{"kind": "torc", "metal": "bronze"}, {"kind": "braid_rings", "metal": "silver"}])
		show_adorn_page(true)
		_apply_appearance()
