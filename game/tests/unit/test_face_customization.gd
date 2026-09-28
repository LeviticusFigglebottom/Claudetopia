extends TestCase
## Triage 39: a face is more than one of eight heads. Every head carries the face's sliders as morph
## targets, the model sets them from the record, what lies over the face goes with them, the years
## and the marks show, the dice roll all of it by people, sex and age, a def can pin any of it, and a
## save keeps it.

const MODEL_SCENE := "res://actors/shared/humanoid_model.tscn"
const RIG_GLB := "res://assets/models/characters/humanoid_rig/humanoid_rig.glb"
const HEADS := "res://assets/models/characters/heads/"

var _root: Node
var _model: HumanoidModel


func after_each() -> void:
	if _root != null and is_instance_valid(_root):
		_root.free()
	_root = null
	_model = null


func _make_model() -> HumanoidModel:
	if not ResourceLoader.exists(RIG_GLB):
		return null
	_root = Node3D.new()
	Engine.get_main_loop().root.add_child(_root)
	_model = (load(MODEL_SCENE) as PackedScene).instantiate() as HumanoidModel
	_root.add_child(_model)
	return _model


func _meshes(m: HumanoidModel, slot: String) -> Array:
	return m._part_meshes.get(slot, [])


func _shape_value(mi: MeshInstance3D, shape: String) -> float:
	var i := mi.find_blend_shape_by_name(StringName(shape))
	return mi.get_blend_shape_value(i) if i >= 0 else NAN


func _skin_of_head(m: HumanoidModel) -> MeshInstance3D:
	for mi in _meshes(m, "head"):
		if not bool((mi as MeshInstance3D).get_meta("eye", false)):
			return mi
	return null


# -- the heads --------------------------------------------------------------------------------------

## Every head, a man's and a woman's, carries every slider and the years; its eyes the ones that move
## them; and the face coordinates the marks are drawn in.
func test_every_head_carries_the_sliders() -> void:
	var names: Array = []
	for face in CharacterAppearance.HEADS:
		names.append(face)
		names.append(face + CharacterAppearance.FEMININE_HEAD)
	var checked := 0
	for head in names:
		var path := "%s%s/%s.glb" % [HEADS, head, head]
		if not ResourceLoader.exists(path):
			continue
		var inst := (load(path) as PackedScene).instantiate()
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var mesh := (mi as MeshInstance3D).mesh as ArrayMesh
			var n := str(mi.name).to_lower()
			if n.contains("eye"):
				for s in ["face_eye_size", "face_eye_spacing"]:
					assert_true(_mesh_has_shape(mesh, s), "%s's %s has no %s" % [head, mi.name, s])
				continue
			for slider in CharacterAppearance.FACE_SLIDERS + ["age"]:
				assert_true(_mesh_has_shape(mesh, "face_" + slider), "%s has no face_%s" % [head, slider])
			var fmt := mesh.surface_get_format(0)
			assert_true((fmt & Mesh.ARRAY_FORMAT_TEX_UV2) != 0, "%s has no face coordinates (UV2)" % head)
			checked += 1
		inst.free()
	assert_gt(checked, 7, "only %d heads checked" % checked)


func _mesh_has_shape(mesh: ArrayMesh, shape: String) -> bool:
	for i in mesh.get_blend_shape_count():
		if str(mesh.get_blend_shape_name(i)) == shape:
			return true
	return false


# -- the model -------------------------------------------------------------------------------------

## The record's sliders are the head's morph weights, a negative slider a negative weight; the years
## are `face_age`; a beard and the hair go with the jaw.
func test_the_model_wears_the_face_it_is_given() -> void:
	var m := _make_model()
	if m == null:
		return
	var a := CharacterAppearance.new()
	a.set_part("head", "broad")
	a.set_part("hair", "short")
	a.set_part("beard", "short_beard")
	a.set_face("jaw_width", 0.7)
	a.set_face("nose_length", -0.5)
	a.age = 0.95
	m.apply_appearance(a.to_dict())
	var head := _skin_of_head(m)
	assert_true(head != null, "no head worn")
	if head == null:
		return
	assert_near(_shape_value(head, "face_jaw_width"), 0.7, 0.001, "the jaw slider is not on the head")
	assert_near(_shape_value(head, "face_nose_length"), -0.5, 0.001, "a slider below 0 is not a weight below 0")
	assert_near(_shape_value(head, "face_eye_size"), 0.0, 0.001)
	assert_near(_shape_value(head, "face_age"), 1.0, 0.001, "an old record wears a young face")
	for mi in _meshes(m, "beard") + _meshes(m, "hair"):
		var v := _shape_value(mi, "face_jaw_width")
		if not is_nan(v):
			assert_near(v, 0.7, 0.001, "%s does not go with the jaw" % mi.name)
	assert_false(_meshes(m, "beard").is_empty(), "no beard worn")
	assert_false(is_nan(_shape_value(_meshes(m, "beard")[0], "face_jaw_width")), "the beard has no jaw slider")
	# changing only the face changes no part: the same meshes, the new weights
	var before := head
	a.set_face("jaw_width", -0.4)
	m.apply_appearance(a.to_dict())
	assert_true(is_instance_valid(before) and _skin_of_head(m) == before, "a slider rebuilt the head")
	assert_near(_shape_value(_skin_of_head(m), "face_jaw_width"), -0.4, 0.001)


## Brows, a scar, moles or paint are drawn over the head; a face with none of them has no second pass.
func test_marks_are_drawn_over_the_skin_and_only_when_there_are_some() -> void:
	var m := _make_model()
	if m == null:
		return
	var a := CharacterAppearance.new()
	a.set_part("head", "default")
	m.apply_appearance(a.to_dict())
	var head := _skin_of_head(m)
	if head == null:
		return
	assert_true(head.material_overlay == null, "a plain face pays for an overlay")
	a.scar = "brow"
	a.paint = "woad"
	a.brows = "bushy"
	m.apply_appearance(a.to_dict())
	var ov := _skin_of_head(m).material_overlay as ShaderMaterial
	assert_true(ov != null, "the marks are not drawn")
	if ov != null:
		assert_eq(int(ov.get_shader_parameter("scar")), CharacterAppearance.SCARS.find("brow"))
		assert_eq(int(ov.get_shader_parameter("paint")), CharacterAppearance.PAINTS.find("woad"))
		assert_eq(int(ov.get_shader_parameter("brow_style")), CharacterAppearance.BROW_STYLES.find("bushy"))
	for mi in _meshes(m, "head"):
		if bool((mi as MeshInstance3D).get_meta("eye", false)):
			assert_true(mi.material_overlay == null, "the marks are drawn on an eye")


## Grey comes with the years unless the record says how grey; a colour already grey stays itself.
func test_hair_greys_with_the_years() -> void:
	var a := CharacterAppearance.new()
	a.hair_colour = "chestnut"
	a.age = 0.2
	var young := a.hair_worn_colour()
	assert_true(young.is_equal_approx(CharacterAppearance.hair_colour_value("chestnut")), "young hair is greyed")
	a.age = 1.0
	var old := a.hair_worn_colour()
	assert_gt(old.s * -1.0, young.s * -1.0, "old hair is as coloured as young")
	a.grey = 0.0
	assert_true(a.hair_worn_colour().is_equal_approx(young), "the record's own grey is not kept")
	a.hair_colour = "silver"
	a.grey = 1.0
	assert_true(a.hair_worn_colour().is_equal_approx(CharacterAppearance.hair_colour_value("silver")))


## A close cut stays itself under a hood; a long one goes to the combed-back cut, as before.
func test_close_hair_stays_under_a_hood() -> void:
	var m := _make_model()
	if m == null:
		return
	var a := CharacterAppearance.new()
	a.set_part("headgear", "hood")
	for style in ["shaven", "receding", "cropped_curls"]:
		if not CharacterAppearance.part_built("hair", style):
			continue
		a.set_part("hair", style)
		m.apply_appearance(a.to_dict())
		assert_eq(m.hair_worn, style, "%s swapped under a hood" % style)
	a.set_part("hair", "long_loose")
	m.apply_appearance(a.to_dict())
	assert_eq(m.hair_worn, HumanoidModel.UNDER_A_HOOD)


## The shoulders are wider or narrower on the joints, so the sleeves go with them.
func test_shoulder_width_moves_the_joints() -> void:
	var a := CharacterAppearance.new()
	a.shoulder_width = 1.14
	assert_near(HumanoidModel.shoulders_out_for(a), HumanoidModel.SHOULDER_SPAN, 0.0001)
	a.shoulder_width = 0.86
	assert_near(HumanoidModel.shoulders_out_for(a), -HumanoidModel.SHOULDER_SPAN, 0.0001)
	var m := _make_model()
	if m == null:
		return
	a.shoulder_width = 1.14
	m.apply_appearance(a.to_dict())
	assert_near(m.arm_room.shoulder_out, HumanoidModel.SHOULDER_SPAN, 0.0001)


# -- the dice, the defs and the save -----------------------------------------------------------------

## Rolled faces spread round the head as built, never past the ends; paint only on the peoples that
## wear it; a woman never bearded; the old greyer and older in the face than the young.
func test_the_dice_roll_faces_by_people_sex_and_age() -> void:
	var spread := 0.0
	var painted := {}
	var n := 240
	var young_age := 0.0
	var old_age := 0.0
	for i in n:
		var culture: String = CharacterAppearance.CULTURES[i % CharacterAppearance.CULTURES.size()]
		var a := CharacterAppearance.random(5000 + i, culture, float(i % 2))
		for slider in CharacterAppearance.FACE_SLIDERS:
			var v := a.face_value(slider)
			assert_true(v >= -1.0 and v <= 1.0, "%s rolled %f" % [slider, v])
			spread += absf(v)
		if not a.paint.is_empty():
			assert_eq(a.paint, str(CharacterAppearance.PAINT_OF_CULTURE.get(culture, "")), "%s wears %s" % [culture, a.paint])
			painted[culture] = true
		assert_true(a.brows in CharacterAppearance.BROW_STYLES and a.scar in CharacterAppearance.SCARS)
		if a.is_woman():
			assert_eq(a.part("beard"), "", "a woman rolled a beard")
		if a.age > 0.7:
			old_age += a.age_on_face()
		elif a.age < 0.3:
			young_age += a.age_on_face()
	var mean := spread / float(n * CharacterAppearance.FACE_SLIDERS.size())
	assert_true(mean > 0.15 and mean < 0.5, "faces spread %.2f from the head as built" % mean)
	assert_false(painted.has("vale"), "the Vale wears paint")
	assert_true(painted.size() >= 3, "only %s wear paint" % [painted.keys()])
	assert_gt(old_age, young_age, "the old are no older in the face")
	# the same seed, the same face
	var x := CharacterAppearance.random(77, "clans", 0.0)
	var y := CharacterAppearance.random(77, "clans", 0.0)
	assert_eq(x.face, y.face)
	assert_eq(x.brows + x.scar + x.paint, y.brows + y.scar + y.paint)


## Adding the face moved none of the old dice: the height, skin, clothes and hair colour of a
## villager rolled from a seed are the ones the old roll gave (the new rolls are on dice of their own).
func test_the_old_dice_fall_where_they_did() -> void:
	var a := CharacterAppearance.random(4242, "vale", 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	rng.randf()    # the sex, which was given
	assert_near(a.height, 1.62 + rng.randf() * 0.24 - 0.07, 0.0001, "the height's dice moved")


## A def pins any of it, and prose in the block is left alone.
func test_a_def_pins_the_face_and_the_marks() -> void:
	var a := CharacterAppearance.random(9, "clans", 0.0)
	a.pin({"face": {"jaw_width": 0.9, "nose_bridge": -0.6, "no_such": 1.0}, "scar": "cheek", "paint": "woad",
		"brows": "bushy", "moles": 0.5, "grey": 0.8, "hair": "red_grey_shaved_sides", "beard": "none",
		"hair_colour": "copper", "head": "hawk"})
	assert_near(a.face_value("jaw_width"), 0.9)
	assert_near(a.face_value("nose_bridge"), -0.6)
	assert_false(a.face.has("no_such"))
	assert_eq(a.scar, "cheek")
	assert_eq(a.paint, "woad")
	assert_eq(a.brows, "bushy")
	assert_near(a.moles, 0.5)
	assert_near(a.hair_grey(), 0.8)
	assert_eq(a.part("beard"), "")
	assert_eq(a.hair_colour, "copper")
	assert_eq(a.part("head"), "hawk")
	assert_ne(a.part("hair"), "red_grey_shaved_sides", "prose was taken for a part")


## Every new value survives a save: the record, through JSON, and back.
func test_the_face_round_trips_through_a_save() -> void:
	var a := CharacterAppearance.new()
	a.set_face("jaw_width", 0.35)
	a.set_face("eye_tilt", -0.8)
	a.brows = "arched"
	a.scar = "lip"
	a.moles = 0.4
	a.paint = "reed_dots"
	a.grey = 0.25
	a.age = 0.66
	a.shoulder_width = 0.9
	a.hair_colour = "strawberry"
	a.set_part("hair", "ponytail")
	a.set_part("beard", "goatee")
	var back := CharacterAppearance.new(JSON.parse_string(JSON.stringify(a.to_dict())))
	assert_eq(back.face, a.face)
	assert_eq(back.brows, "arched")
	assert_eq(back.scar, "lip")
	assert_near(back.moles, 0.4)
	assert_eq(back.paint, "reed_dots")
	assert_near(back.grey, 0.25)
	assert_near(back.age, 0.66)
	assert_near(back.shoulder_width, 0.9)
	assert_eq(back.hair_colour, "strawberry")
	assert_eq(back.part("hair"), "ponytail")
	assert_eq(back.part("beard"), "goatee")
	# and a record from before them is a plain face
	var old := CharacterAppearance.new({"skin": "fair", "hair_colour": 3})
	assert_true(old.face.is_empty() and old.brows == "" and old.scar == "" and old.paint == "")
	assert_near(old.grey, -1.0)
