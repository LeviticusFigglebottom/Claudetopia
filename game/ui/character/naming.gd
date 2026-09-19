extends Control
## The Naming (DESIGN §5.1). Character creation is in the fiction: a Warden is standing over
## you asking what you are called, and what you were before you were pulled out of the Hush.
##
## Writes three GameState flags and nothing else:
##   player_name        String
##   player_calling     a `calling` id
##   player_appearance  {skin, hair_style, hair_colour, eyes, build, height_m, voice, head}
## Begin sets the flag "new_game" and changes to the world scene.

const WORLD_SCENE := "res://world/world.tscn"
const MENU_SCENE := "res://ui/menus/main_menu.tscn"
const MODEL_SCENE := "res://actors/shared/humanoid_model.tscn"

const SKINS := [Color("#f0d3bb"), Color("#e0b894"), Color("#c99a72"), Color("#a97848"),
	Color("#7d5432"), Color("#543722")]
const HAIRS := [Color("#2a2119"), Color("#4a3423"), Color("#7a5230"), Color("#a97b3c"),
	Color("#c9a24a"), Color("#8c3a24"), Color("#b9b2a6"), Color("#efe7d2")]
const EYES := [Color("#4a6a3c"), Color("#3f6f8a"), Color("#6b4a2c"), Color("#2f4a25"),
	Color("#8a7a4a"), Color("#5d6470")]
const HAIR_STYLES := ["Cropped", "Braided", "Tied back", "Loose", "Shorn", "Topknot", "Plaited crown", "Wild"]
const HEADS := ["Vale", "Lakefolk", "Reedborn", "Cragborn", "Woodfolk", "Ash-Pilgrim"]
const VOICES := ["Low and slow", "Quick and dry", "Warm", "Quiet"]

var appearance := {
	"skin": 1, "hair_style": 0, "hair_colour": 1, "eyes": 0,
	"build": 0.5, "height_m": 1.78, "voice": 0, "head": 0,
}
var calling_id := ""
var player_name := ""

var _name_edit: LineEdit
var _suggest_row: HBoxContainer
var _calling_box: VBoxContainer
var _calling_detail: VBoxContainer
var _preview: SubViewport
var _mannequin: Node3D
var _model: Node = null
var _begin: Button
var _spin := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	UI.apply_theme(self)
	UI.close_all()
	UI.hide_hud()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var callings := ContentDB.all("calling")
	if not callings.is_empty():
		calling_id = str(callings[0].get("id", ""))
	player_name = ValishNames.suggestions(1, 20260919)[0]
	_build()
	_refresh_calling()
	_apply_appearance()


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
	frame.offset_left = 44.0
	frame.offset_top = 26.0
	frame.offset_right = -44.0
	frame.offset_bottom = -26.0
	add_child(frame)
	var body: VBoxContainer = page["body"]

	body.add_child(UiKit.label("The Naming", "Title", HORIZONTAL_ALIGNMENT_CENTER))
	var blurb := UiKit.label(
		"You came up the Hushline Stair with nothing. A Warden is asking what you are called, " +
		"and she is not going to guess.", "Journal", HORIZONTAL_ALIGNMENT_CENTER)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(blurb)
	body.add_child(UiKit.divider())

	var columns := UiKit.row(18)
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
	holder.custom_minimum_size = Vector2(252, 0)

	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = Vector2(248, 420)
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.add_child(container)

	_preview = SubViewport.new()
	_preview.size = Vector2i(248, 420)
	_preview.transparent_bg = true
	_preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview.msaa_2d = Viewport.MSAA_2X
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
	camera.look_at_from_position(Vector3(0.0, 1.15, 3.2), Vector3(0.0, 1.0, 0.0), Vector3.UP)
	world.add_child(camera)

	_mannequin = Node3D.new()
	world.add_child(_mannequin)
	if ResourceLoader.exists(MODEL_SCENE):
		_model = (load(MODEL_SCENE) as PackedScene).instantiate()
		_mannequin.add_child(_model)
	else:
		_build_stand_in()

	var caption := UiKit.label("A stand-in, until the forge has made you.", "Tiny", HORIZONTAL_ALIGNMENT_CENTER)
	caption.visible = _model == null
	holder.add_child(caption)
	return holder


## A lit wooden mannequin: what a tailor would stand in the corner until the real thing exists.
func _build_stand_in() -> void:
	# [position, radius, height, tilt degrees]
	var parts := {
		"hips": [Vector3(0, 0.93, 0), 0.125, 0.30, 0.0],
		"chest": [Vector3(0, 1.26, 0), 0.150, 0.46, 0.0],
		"neck": [Vector3(0, 1.50, 0), 0.052, 0.13, 0.0],
		"arm_l": [Vector3(-0.205, 1.22, 0), 0.054, 0.62, 6.0],
		"arm_r": [Vector3(0.205, 1.22, 0), 0.054, 0.62, -6.0],
		"leg_l": [Vector3(-0.085, 0.46, 0), 0.072, 0.92, 2.0],
		"leg_r": [Vector3(0.085, 0.46, 0), 0.072, 0.92, -2.0],
	}
	for name: String in parts:
		var mesh := MeshInstance3D.new()
		mesh.name = name
		var capsule := CapsuleMesh.new()
		capsule.radius = float(parts[name][1])
		capsule.height = maxf(float(parts[name][2]), float(parts[name][1]) * 2.05)
		mesh.mesh = capsule
		mesh.position = parts[name][0]
		mesh.rotation_degrees = Vector3(0, 0, float(parts[name][3]))
		mesh.material_override = _skin_material()
		_mannequin.add_child(mesh)

	var head := MeshInstance3D.new()
	head.name = "head"
	var skull := SphereMesh.new()
	skull.radius = 0.104
	skull.height = 0.236
	head.mesh = skull
	head.position = Vector3(0, 1.62, 0)
	head.material_override = _skin_material()
	_mannequin.add_child(head)

	var hair := MeshInstance3D.new()
	hair.name = "hair"
	var cap := SphereMesh.new()
	cap.radius = 0.110
	cap.height = 0.20
	hair.mesh = cap
	hair.position = Vector3(0, 1.655, -0.006)
	hair.material_override = StandardMaterial3D.new()
	_mannequin.add_child(hair)

	var base := MeshInstance3D.new()
	base.name = "base"
	var disc := CylinderMesh.new()
	disc.top_radius = 0.26
	disc.bottom_radius = 0.30
	disc.height = 0.05
	base.mesh = disc
	base.position = Vector3(0, 0.025, 0)
	var base_material := StandardMaterial3D.new()
	base_material.albedo_color = Color(0.29, 0.21, 0.14)
	base_material.roughness = 0.9
	base.material_override = base_material
	_mannequin.add_child(base)


func _skin_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.roughness = 0.72
	return material


func _build_middle() -> Control:
	var col := UiKit.column(8)
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
	col.add_child(_swatches("Skin", SKINS, "skin"))
	col.add_child(_swatches("Hair", HAIRS, "hair_colour"))
	col.add_child(_swatches("Eyes", EYES, "eyes"))
	col.add_child(_chooser("Hair", HAIR_STYLES, "hair_style"))
	col.add_child(_chooser("Face", HEADS, "head"))
	col.add_child(_chooser("Voice", VOICES, "voice"))
	col.add_child(_slider("Build", "build", 0.0, 1.0, 0.05))
	col.add_child(_slider("Height", "height_m", 1.55, 1.95, 0.01))
	return UiKit.scroll(col)


func _labelled(text: String, control: Control) -> HBoxContainer:
	var row := UiKit.row(10)
	var label := UiKit.label(text, "Small")
	label.custom_minimum_size = Vector2(76, 0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	return row


func _swatches(text: String, colours: Array, key: String) -> HBoxContainer:
	var row := UiKit.row(4)
	for i in colours.size():
		var b := Button.new()
		b.theme_type_variation = &"FlatButton"
		b.custom_minimum_size = Vector2(28, 28)
		b.tooltip_text = "%s %d" % [text, i + 1]
		var swatch := ColorRect.new()
		swatch.color = colours[i]
		swatch.set_anchors_preset(Control.PRESET_FULL_RECT)
		swatch.offset_left = 4.0
		swatch.offset_top = 4.0
		swatch.offset_right = -4.0
		swatch.offset_bottom = -4.0
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(swatch)
		var index := i
		b.pressed.connect(func() -> void:
				appearance[key] = index
				_apply_appearance())
		row.add_child(b)
	return _labelled(text, row)


func _chooser(text: String, options: Array, key: String) -> HBoxContainer:
	var o := OptionButton.new()
	for name in options:
		o.add_item(str(name))
	o.selected = clampi(int(appearance[key]), 0, options.size() - 1)
	o.item_selected.connect(func(index: int) -> void:
			appearance[key] = index
			_apply_appearance())
	return _labelled(text, o)


func _slider(text: String, key: String, low: float, high: float, step: float) -> HBoxContainer:
	var row := UiKit.row(8)
	var s := HSlider.new()
	s.min_value = low
	s.max_value = high
	s.step = step
	s.value = float(appearance[key])
	s.custom_minimum_size = Vector2(150, 20)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value_label := UiKit.label("", "Tiny")
	value_label.custom_minimum_size = Vector2(56, 0)
	value_label.text = _value_text(key, float(appearance[key]))
	s.value_changed.connect(func(v: float) -> void:
			appearance[key] = v
			value_label.text = _value_text(key, v)
			_apply_appearance())
	row.add_child(s)
	row.add_child(value_label)
	return _labelled(text, row)


func _value_text(key: String, value: float) -> String:
	if key == "height_m":
		return "%.2f m" % value
	return ["slight", "lean", "even", "solid", "broad"][clampi(int(value * 4.999), 0, 4)]


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
	var col := UiKit.column(8)
	col.custom_minimum_size = Vector2(300, 0)
	col.add_child(UiKit.label("What were you, before?", "Heading"))
	_calling_box = UiKit.column(4)
	col.add_child(_calling_box)
	_calling_detail = UiKit.column(4)
	col.add_child(UiKit.divider())
	col.add_child(_calling_detail)

	var buttons: Array[Control] = []
	for def in ContentDB.all("calling"):
		var id := str(def.get("id", ""))
		var b := UiKit.button("", "FlatButton")
		b.custom_minimum_size = Vector2(0, 46)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_meta("calling", id)
		b.pressed.connect(func() -> void:
				calling_id = id
				_refresh_calling())
		var card := UiKit.row(10)
		card.set_anchors_preset(Control.PRESET_FULL_RECT)
		card.offset_left = 10.0
		card.offset_right = -10.0
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(card)
		card.add_child(UiKit.icon_rect(_calling_icon(def), 24))
		var words := UiKit.column(0)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(words)
		words.add_child(UiKit.label(str(def.get("name", id)), "Emphasis"))
		words.add_child(UiKit.label(str(def.get("culture", "")), "Tiny"))
		_calling_box.add_child(b)
		buttons.append(b)
	UiKit.focus_chain(buttons)
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
	_calling_detail.add_child(UiKit.wrapped(str(def.get("description", "")), "Journal"))
	var bonuses: Dictionary = def.get("skill_bonuses", {})
	if not bonuses.is_empty():
		_calling_detail.add_child(UiKit.label("You already know something of", "Small"))
		for skill: String in bonuses:
			var skill_def := ContentDB.get_or_empty("core:skill/" + skill)
			var row := UiKit.row(8)
			row.add_child(UiKit.icon_rect("book", 18))
			row.add_child(UiKit.label("%s  +%d" % [str(skill_def.get("name", skill)), int(bonuses[skill])], "Body"))
			_calling_detail.add_child(row)
	var signature := str(def.get("signature_item", ""))
	if signature != "":
		var item := ContentDB.get_or_empty(signature)
		var row := UiKit.row(8)
		row.add_child(UiKit.icon_rect(UiKit.item_icon_name(item), 18))
		row.add_child(UiKit.wrapped("You still have %s." % str(item.get("name", "something")), "Journal"))
		_calling_detail.add_child(row)
	UiKit.ink_in(_calling_detail, 0.0, 0.26)
	_update_begin()


func _update_begin() -> void:
	if _begin:
		_begin.disabled = player_name.strip_edges().is_empty() or calling_id.is_empty()


# --- the body ----------------------------------------------------------------------------------

func _apply_appearance() -> void:
	if _model and is_instance_valid(_model) and _model.has_method("apply_appearance"):
		_model.call("apply_appearance", appearance_dict())
		return
	if _mannequin == null:
		return
	var skin: Color = SKINS[clampi(int(appearance["skin"]), 0, SKINS.size() - 1)]
	var hair_colour: Color = HAIRS[clampi(int(appearance["hair_colour"]), 0, HAIRS.size() - 1)]
	var build := float(appearance["build"])
	var height := float(appearance["height_m"])
	for child in _mannequin.get_children():
		if not (child is MeshInstance3D):
			continue
		var mesh := child as MeshInstance3D
		var material: StandardMaterial3D = mesh.material_override
		if material == null:
			continue
		if mesh.name == "hair":
			material.albedo_color = hair_colour
			material.roughness = 0.65
		elif mesh.name != "base":
			material.albedo_color = skin.lerp(Color(0.55, 0.45, 0.35), 0.12)
	_mannequin.scale = Vector3(0.90 + build * 0.24, height / 1.78, 0.90 + build * 0.24)


func _process(delta: float) -> void:
	if _mannequin:
		_spin += delta * 0.22
		_mannequin.rotation.y = sin(_spin) * 0.55


# --- writing it down -----------------------------------------------------------------------------

func appearance_dict() -> Dictionary:
	var out := appearance.duplicate(true)
	out["skin_colour"] = SKINS[clampi(int(appearance["skin"]), 0, SKINS.size() - 1)].to_html(false)
	out["hair_colour_hex"] = HAIRS[clampi(int(appearance["hair_colour"]), 0, HAIRS.size() - 1)].to_html(false)
	out["eye_colour_hex"] = EYES[clampi(int(appearance["eyes"]), 0, EYES.size() - 1)].to_html(false)
	out["hair_style_name"] = HAIR_STYLES[clampi(int(appearance["hair_style"]), 0, HAIR_STYLES.size() - 1)]
	out["head_name"] = HEADS[clampi(int(appearance["head"]), 0, HEADS.size() - 1)]
	out["voice_name"] = VOICES[clampi(int(appearance["voice"]), 0, VOICES.size() - 1)]
	return out


func _begin_game() -> void:
	GameState.set_flag("player_name", player_name.strip_edges())
	GameState.set_flag("player_calling", calling_id)
	GameState.set_flag("player_appearance", appearance_dict())
	GameState.set_flag("new_game", true)
	if not ResourceLoader.exists(WORLD_SCENE):
		EventBus.emit_notify("Named, but the world is not built yet.", "warning")
		return
	UI.fade_to_black(0.5)
	await get_tree().create_timer(0.55).timeout
	get_tree().change_scene_to_file(WORLD_SCENE)


## Used by the review harness to show the screen part-way through being filled in.
func review_state() -> void:
	_name_edit.text = "Wren of the Hushline"
	player_name = _name_edit.text
	var callings := ContentDB.all("calling")
	if callings.size() > 2:
		calling_id = str(callings[2].get("id", ""))
	appearance["skin"] = 3
	appearance["hair_colour"] = 5
	appearance["build"] = 0.65
	appearance["height_m"] = 1.71
	_refresh_calling()
	_apply_appearance()
