extends TestCase
## Pressing the Naming's controls and asking the body underneath.
##
## The screen drew six swatches, three choosers, two sliders and a preview, and every one of them
## did nothing: it kept its own vocabulary (swatch indices, `height_m`, a face named after a
## culture) and handed that to the model, which reads `CharacterAppearance` and none of it. So
## these find each control, press it, and ask the model — its record, its parts, its materials,
## its scale — whether anything happened, and then press Be named and read what the world will.

const SCREEN := preload("res://ui/character/naming.tscn")
const ASHWALKER := "core:calling/ashwalker"

var naming: Control


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	naming = SCREEN.instantiate()
	# the press must stop at the flags: a scene change here would tear the test runner down
	naming.set("world_scene", "")
	_tree().root.add_child(naming)


func after_each() -> void:
	if naming != null and is_instance_valid(naming):
		naming.queue_free()
	naming = null
	GameState.reset_for_new_game(1)


# --- finding the controls by what a player sees -------------------------------------------------

## First match in the order the screen reads, top to bottom.
func _walk(root: Node, pred: Callable) -> Node:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if bool(pred.call(n)):
			return n
		var kids := n.get_children()
		for i in range(kids.size() - 1, -1, -1):
			stack.append(kids[i])
	return null


func _button(text: String) -> Button:
	return _walk(naming, func(n: Node) -> bool: return n is Button and (n as Button).text == text) as Button


func _swatch(label_text: String, tone: String) -> Button:
	var label := _walk(naming, func(n: Node) -> bool: return n is Label and (n as Label).text == label_text)
	if label == null:
		return null
	return _walk(label.get_parent(), func(n: Node) -> bool:
			return n is Button and n.has_meta("tone") and str(n.get_meta("tone")) == tone) as Button


func _chooser(slot: String) -> OptionButton:
	return _walk(naming, func(n: Node) -> bool:
			return n is OptionButton and str(n.get_meta("slot", "")) == slot) as OptionButton


func _slider(key: String) -> HSlider:
	return _walk(naming, func(n: Node) -> bool:
			return n is HSlider and str(n.get_meta("key", "")) == key) as HSlider


func _card(calling: String) -> Button:
	return _walk(naming, func(n: Node) -> bool:
			return n is Button and str(n.get_meta("calling", "")) == calling) as Button


func _model() -> HumanoidModel:
	return naming.get("_model") as HumanoidModel


func _look() -> CharacterAppearance:
	return naming.get("appearance") as CharacterAppearance


## The colour a part has been given: a cloth or hair part's albedo, or a skin's tint (skin wears
## the skin shader, not a StandardMaterial3D).
func _override_albedo(mi: MeshInstance3D) -> Color:
	return HumanoidModel.skin_tint_of(mi)


func _forge_built() -> bool:
	return _model() != null and _model().skeleton != null


# --- the swatches ---------------------------------------------------------------------------------

func test_a_skin_swatch_recolours_the_body() -> void:
	var swatch := _swatch("Skin", "ebony")
	assert_true(swatch != null, "no ebony swatch in the Skin row")
	if swatch == null:
		return
	swatch.pressed.emit()
	assert_eq(_look().skin, "ebony", "the record did not take the swatch")
	if not _forge_built():
		return
	assert_eq(_model().appearance.skin, "ebony", "the model did not take the swatch")
	var body: MeshInstance3D = _model()._default_meshes.get("body")
	assert_true(body != null, "the rig has no body mesh")
	var want := CharacterAppearance.new({"skin": "ebony"}).skin_tint()
	assert_true(_override_albedo(body).is_equal_approx(want), "the body's skin is not tinted ebony")
	assert_true(want.r < 0.5, "ebony over the wheat bake must darken it, not lighten it")


func test_a_hair_swatch_tints_the_hair_shell() -> void:
	var swatch := _swatch("Hair", "white")
	assert_true(swatch != null, "no white swatch in the Hair row")
	if swatch == null or not _forge_built():
		return
	swatch.pressed.emit()
	assert_eq(_model().appearance.hair_colour, "white")
	var shells: Array = _model()._part_meshes.get("hair", [])
	assert_gt(shells.size(), 0, "no hair shell on the model to tint")
	if shells.is_empty():
		return
	var want := CharacterAppearance.new({"hair_colour": "white"}).hair_tint()
	assert_true(_override_albedo(shells[0]).is_equal_approx(want), "the hair shell is not tinted white")
	assert_true(want.r > 1.5, "white over the brown bake must lighten it well past one")


func test_the_eye_swatch_reaches_the_iris_and_only_the_iris() -> void:
	var swatch := _swatch("Eyes", "blue")
	assert_true(swatch != null, "no blue swatch in the Eyes row")
	if swatch == null or not _forge_built():
		return
	swatch.pressed.emit()
	assert_eq(_model().appearance.eye_colour, "blue")
	var eyes: Array = _model()._default_eyes
	assert_eq(eyes.size(), 2, "the rig has two eyes")
	var want := CharacterAppearance.new({"eye_colour": "blue"}).iris_tint()
	for eye in eyes:
		var m := (eye as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial
		assert_true(m != null, "an eye is not wearing the iris shader")
		if m != null:
			var tint: Vector3 = m.get_shader_parameter("iris_tint")
			assert_true(tint.is_equal_approx(Vector3(want.r, want.g, want.b)), "the iris is not tinted blue")


func test_every_swatch_names_a_tone_the_record_knows() -> void:
	var seen := 0
	for pair in [["Skin", CharacterAppearance.SKIN_TONES], ["Hair", CharacterAppearance.HAIR_COLOURS],
			["Eyes", CharacterAppearance.EYE_COLOURS]]:
		for tone in pair[1]:
			assert_true(_swatch(str(pair[0]), str(tone)) != null, "no %s swatch for %s" % [pair[0], tone])
			seen += 1
	assert_eq(seen, CharacterAppearance.SKIN_TONES.size() + CharacterAppearance.HAIR_COLOURS.size()
			+ CharacterAppearance.EYE_COLOURS.size())


# --- the choosers -------------------------------------------------------------------------------

func test_choosing_a_hair_style_changes_the_part_on_the_body() -> void:
	var o := _chooser("hair")
	assert_true(o != null, "no hair chooser")
	if o == null or not _forge_built():
		return
	var before: Mesh = (_model()._part_meshes.get("hair", [null])[0] as MeshInstance3D).mesh
	o.select(3)
	o.item_selected.emit(3)
	assert_eq(_look().part("hair"), CharacterAppearance.HAIR_STYLES[3])
	assert_eq(_model().appearance.part("hair"), CharacterAppearance.HAIR_STYLES[3])
	var after: Mesh = (_model()._part_meshes.get("hair", [null])[0] as MeshInstance3D).mesh
	assert_true(after != null and after != before, "the hair mesh on the skeleton did not change")


## Every face is a head part now, the even one included: the rig's own head is an older skull
## than the parts and stays hidden under whichever face is chosen. One head and one pair of eyes
## show at a time, and choosing a face swaps them.
func test_choosing_a_face_swaps_the_head_and_its_eyes() -> void:
	var o := _chooser("head")
	assert_true(o != null, "no face chooser")
	if o == null or not _forge_built():
		return
	var rig_head: MeshInstance3D = _model()._default_meshes.get("head")
	assert_true(_model()._part_meshes.has("head"), "the even face should be a head part too")
	assert_true(rig_head == null or not rig_head.visible, "the rig's own head is showing under the head part")
	var before: Mesh = (_model()._part_meshes["head"][0] as MeshInstance3D).mesh
	o.select(1)
	o.item_selected.emit(1)
	assert_eq(_model().appearance.part("head"), CharacterAppearance.HEADS[1])
	var after: Mesh = (_model()._part_meshes["head"][0] as MeshInstance3D).mesh
	assert_true(after != before, "choosing another face left the same head on")
	for eye in _model()._default_eyes:
		assert_false((eye as MeshInstance3D).visible, "the rig's own eyes are showing under the chosen face")
	var eyes := 0
	for mi in _model()._part_meshes["head"]:
		if _model()._is_eye(mi):
			eyes += 1
			assert_true((mi as MeshInstance3D).get_surface_override_material(0) is ShaderMaterial
					and ((mi as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial).shader
					== HumanoidModel.IRIS_SHADER, "a swapped face's eye is not wearing the iris shader")
	assert_eq(eyes, 2, "the chosen face brings exactly one pair of eyes")
	o.select(0)
	o.item_selected.emit(0)
	assert_true(rig_head == null or not rig_head.visible, "going back to the even face brought the old skull back")


func test_every_part_a_chooser_offers_has_been_forged() -> void:
	if not _forge_built():
		return
	var offered := 0
	for pair in [["hair", CharacterAppearance.HAIR_STYLES], ["head", CharacterAppearance.HEADS],
			["beard", CharacterAppearance.BEARD_STYLES]]:
		var o := _chooser(str(pair[0]))
		assert_true(o != null, "no %s chooser" % pair[0])
		for part in pair[1]:
			if part == "default":
				continue
			var path: String = _model()._part_path(str(pair[0]), str(part))
			assert_true(ResourceLoader.exists(path), "the Naming offers %s and the forge has not built it (%s)" % [part, path])
			offered += 1
	assert_gt(offered, 10)


# --- the sliders ----------------------------------------------------------------------------------

func test_the_height_slider_scales_the_rig() -> void:
	var s := _slider("height")
	assert_true(s != null, "no height slider")
	if s == null or not _forge_built():
		return
	s.value = 1.90
	assert_near(_look().height, 1.90, 0.001)
	assert_near(_model()._rig_root.scale.y, 1.90 / 1.78, 0.001, "the rig did not grow with the slider")
	s.value = 1.60
	assert_near(_model()._rig_root.scale.y, 1.60 / 1.78, 0.001, "the rig did not shrink with the slider")


## The build slider has to change the body at every step of its travel. It used to do nothing
## across its middle third: the body variant only changes at 0.30 and 0.68, and a variant body was
## never widened. The girth it asks for is now one continuous line, and the rig makes up the
## difference between that and the girth of whichever body is worn, so the width never jumps
## where the variant changes and is never counted twice.
func test_the_build_slider_changes_the_body() -> void:
	var s := _slider("build")
	assert_true(s != null, "no build slider")
	if s == null or not _forge_built():
		return
	var last := -1.0
	var worn: Array[String] = []
	var height := -1.0
	for i in 21:
		s.value = i * 0.05
		var girth: float = _model()._rig_root.scale.x / _model()._rig_root.scale.y \
				* float(HumanoidModel.VARIANT_GIRTH.get(_model().body_variant_worn, 1.0))
		assert_near(girth, HumanoidModel.girth_for(i * 0.05), 0.001,
				"at build %.2f the body is not the girth the slider asks for" % (i * 0.05))
		assert_true(girth > last, "the build slider did not widen the body between %.2f and %.2f" % [(i - 1) * 0.05, i * 0.05])
		if last > 0.0:
			assert_true(girth - last < 0.03, "the width jumps at build %.2f" % (i * 0.05))
		last = girth
		if height < 0.0:
			height = _model()._rig_root.scale.y
		assert_near(_model()._rig_root.scale.y, height, 0.0001, "build must not change height")
		if not worn.has(_model().body_variant_worn):
			worn.append(_model().body_variant_worn)
	# A variant body is only worn under clothes cut for it (HumanoidModel._garments_fit); where
	# the clothes are not, the rig's girth does all of the widening and no skin shows through.
	var fitted: bool = _model()._garments_fit("heavy") and _model()._garments_fit("slight")
	if fitted:
		assert_true(worn.size() >= 2, "the build slider never changed the body mesh: %s" % [worn])
	else:
		assert_eq(worn, [""] as Array[String], "a variant body was worn under clothes not cut for it")


## Every beard the chooser offers draws something. Three of the four once shipped as a skeleton
## with no mesh in it, and "Long" drew nothing at all.
func test_every_beard_offered_has_a_mesh() -> void:
	var o := _chooser("beard")
	assert_true(o != null, "no beard chooser")
	if o == null:
		return
	var offered: Array = naming.call("offered_beards")
	assert_eq(o.item_count, offered.size(), "the chooser and the list it was built from disagree")
	assert_eq(str(offered[0]), "", "the first beard is no beard")
	for style in offered.slice(1):
		var packed := load("res://assets/models/characters/beards/%s/%s.glb" % [style, style]) as PackedScene
		var inst := packed.instantiate()
		assert_gt(inst.find_children("*", "MeshInstance3D", true, false).size(), 0,
				"the Naming offers the beard '%s' and it has nothing to draw" % style)
		inst.free()


# --- the Calling ----------------------------------------------------------------------------------

func test_a_calling_card_dresses_you_for_its_people() -> void:
	var card := _card(ASHWALKER)
	assert_true(card != null, "no Ashwalker card")
	if card == null:
		return
	card.pressed.emit()
	assert_eq(str(naming.get("calling_id")), ASHWALKER)
	assert_eq(_look().culture, "ash_pilgrims", "the Ashwalker is raised among the Ash-Pilgrims")
	assert_eq(_look().part("torso"), "robe", "Ash-Pilgrims wear the robe (WORLD_BIBLE §3.6)")
	if _forge_built():
		assert_eq(_model().appearance.part("torso"), "robe")
		assert_true(_model()._part_meshes.has("torso"), "no robe on the preview body")


func test_a_card_for_every_calling_in_the_pack() -> void:
	for def in ContentDB.all("calling"):
		assert_true(_card(str(def["id"])) != null, "no card for %s" % def["id"])


# --- the name -------------------------------------------------------------------------------------

func test_a_name_is_needed_before_be_named_lights() -> void:
	var edit: LineEdit = naming.get("_name_edit")
	var be_named := _button("Be named")
	assert_true(edit != null and be_named != null)
	if edit == null or be_named == null:
		return
	edit.text = "   "
	edit.text_changed.emit("   ")
	assert_true(be_named.disabled, "Be named lit with nothing but spaces for a name")
	edit.text = "Tam"
	edit.text_changed.emit("Tam")
	assert_false(be_named.disabled, "Be named stayed dark with a name in the field")
	assert_eq(str(naming.get("player_name")), "Tam")


func test_other_names_rolls_a_fresh_three() -> void:
	var again := _walk(naming, func(n: Node) -> bool:
			return n is Button and (n as Button).tooltip_text == "other names") as Button
	assert_true(again != null, "no 'other names' button")
	if again == null:
		return
	var row: Node = naming.get("_suggest_row")
	var before := PackedStringArray()
	for c in row.get_children():
		if c is Button and not (c as Button).text.is_empty():
			before.append((c as Button).text)
	assert_eq(before.size(), 3, "three names are offered")
	again.pressed.emit()
	await _tree().process_frame
	var after := PackedStringArray()
	for c in row.get_children():
		if c is Button and not (c as Button).text.is_empty():
			after.append((c as Button).text)
	assert_eq(after.size(), 3)
	assert_ne(after, before, "the roll offered the same three names")
	var pick: Button = null
	for c in row.get_children():
		if c is Button and not (c as Button).text.is_empty():
			pick = c
			break
	pick.pressed.emit()
	assert_eq(str(naming.get("player_name")), pick.text, "picking an offered name did not take it")


# --- Be named -------------------------------------------------------------------------------------

func test_be_named_writes_the_record_the_world_reads() -> void:
	var edit: LineEdit = naming.get("_name_edit")
	edit.text = "Wren of the Hushline"
	edit.text_changed.emit(edit.text)
	_swatch("Skin", "umber").pressed.emit()
	_swatch("Hair", "grey").pressed.emit()
	_card(ASHWALKER).pressed.emit()
	_slider("height").value = 1.66
	var scene_before := _tree().current_scene
	_button("Be named").pressed.emit()
	await _tree().process_frame
	assert_eq(str(GameState.get_flag("player_name", "")), "Wren of the Hushline")
	assert_eq(str(GameState.get_flag("player_calling", "")), ASHWALKER)
	# a pack with fighting styles begins the chosen style's start; one without, the wake
	if StyleDef.all_styles().is_empty():
		assert_true(GameState.has_flag("new_game"), "a new game was not flagged")
	else:
		assert_true(GameState.has_flag(Openings.STYLE_DUE), "a styled new game was not flagged")
		assert_eq(str(GameState.get_flag(StyleDef.FLAG, "")), str(naming.get("style_id")), "with the style the Naming had chosen")
	var written: Variant = GameState.get_flag("player_appearance", null)
	assert_true(written is Dictionary, "the appearance was not written as a record")
	if not (written is Dictionary):
		return
	var look := CharacterAppearance.new(written)
	assert_eq(look.skin, "umber")
	assert_eq(look.hair_colour, "grey")
	assert_eq(look.culture, "ash_pilgrims")
	assert_eq(look.part("torso"), "robe")
	assert_near(look.height, 1.66)
	assert_true(look.skin in CharacterAppearance.SKIN_TONES, "the record must use the body's own vocabulary")
	assert_eq(_tree().current_scene, scene_before, "the test seam must keep the scene where it is")


## A player can change five things before the screen draws once (a preset does), and the
## probe does. Every part must still be drawable afterwards, and a face must still have eyes
## wearing the iris shader rather than skin.
func test_a_whole_look_made_in_one_frame_leaves_every_part_drawable() -> void:
	if not _forge_built():
		return
	for i in 3:
		_swatch("Skin", CharacterAppearance.SKIN_TONES[i + 2]).pressed.emit()
		_swatch("Hair", CharacterAppearance.HAIR_COLOURS[i + 1]).pressed.emit()
		_swatch("Eyes", CharacterAppearance.EYE_COLOURS[i + 3]).pressed.emit()
		for slot in ["head", "hair", "beard"]:
			var o := _chooser(slot)
			o.select((i + 2) % o.item_count)
			o.item_selected.emit(o.selected)
		_slider("build").value = [0.1, 0.5, 0.9][i]
		await _tree().process_frame
		await _tree().process_frame
	var eyes := 0
	for slot in _model()._part_meshes:
		for mi in _model()._part_meshes[slot]:
			var m := mi as MeshInstance3D
			assert_true(is_instance_valid(m) and m.is_inside_tree(), "a %s mesh is not in the tree" % slot)
			assert_true(m.mesh != null, "a %s mesh has nothing to draw" % slot)
			if _model()._is_eye(m):
				eyes += 1
				var mat := m.get_surface_override_material(0) as ShaderMaterial
				assert_true(mat != null and mat.shader == HumanoidModel.IRIS_SHADER, "an eye is not wearing the iris shader")
				# with no texture the shader samples plain white, and an eye is a blank disc
				assert_true(mat != null and mat.get_shader_parameter("albedo_tex") != null,
						"an eye's iris material has no eye texture: it draws as a white disc")
	assert_eq(eyes, 2, "the face has lost its eyes")
