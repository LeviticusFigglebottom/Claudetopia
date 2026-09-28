extends TestCase
## Triage 48: tattoos and jewellery. The record keeps them clean, the dice roll them by people, body,
## years and means on dice of their own (no roll made before them moves), a def pins them, a save keeps
## them, and the model draws the tattoos only where there are some and wears the jewellery as one
## merged mesh that goes with the face's sliders.

const MODEL_SCENE := "res://actors/shared/humanoid_model.tscn"
const RIG_GLB := "res://assets/models/characters/humanoid_rig/humanoid_rig.glb"
const BODIES := ["res://assets/models/characters/humanoid_rig/humanoid_rig.glb",
	"res://assets/models/characters/bodies/woman/woman.glb", "res://assets/models/characters/bodies/heavy/heavy.glb",
	"res://assets/models/characters/bodies/slight/slight.glb", "res://assets/models/characters/bodies/child/child.glb"]

var _root: Node


func after_each() -> void:
	if _root != null and is_instance_valid(_root):
		_root.free()
	_root = null


func _make_model() -> HumanoidModel:
	if not ResourceLoader.exists(RIG_GLB):
		return null
	_root = Node3D.new()
	Engine.get_main_loop().root.add_child(_root)
	var m := (load(MODEL_SCENE) as PackedScene).instantiate() as HumanoidModel
	_root.add_child(m)
	return m


# -- the record -------------------------------------------------------------------------------------

## Unknown designs, places, kinds and stuffs are dropped or put right; one tattoo to a place, two on
## the face and four on the body at most; one piece to a spot, a ring to each hand.
func test_the_record_keeps_them_clean() -> void:
	var a := CharacterAppearance.new()
	a.set_tattoos([{"design": "knotwork", "on": "forearm_l", "ink": "woad", "fade": 1.7},
		{"design": "no_such", "on": "back"}, {"design": "leaf", "on": "no_such"},
		{"design": "leaf", "on": "forearm_l"}, {"design": "dots", "on": "cheek_l", "ink": "purple"},
		{"design": "dots", "on": "cheek_r"}, {"design": "dots", "on": "chin"},
		{"design": "bands", "on": "back"}, {"design": "bands", "on": "hand_l"}, {"design": "bands", "on": "hand_r"},
		{"design": "bands", "on": "upper_arm_r"}, "prose"])
	assert_eq(a.tattoos.size(), 6, str(a.tattoos))
	assert_eq(a.face_tattoos().size(), 2)
	assert_eq(a.body_tattoos().size(), 4)
	assert_near(float(a.tattoo_at("forearm_l")["fade"]), 1.0)
	assert_eq(str(a.tattoo_at("forearm_l")["design"]), "knotwork", "a second tattoo took the first one's place")
	assert_eq(str(a.tattoo_at("cheek_l")["ink"]), "soot")
	a.set_jewellery([{"kind": "hoop", "metal": "gold"}, {"kind": "stud", "on": "ear_l"}, {"kind": "torc", "metal": "tin"},
		{"kind": "beads"}, {"kind": "ring", "on": "hand_l"}, {"kind": "ring", "on": "hand_r"}, {"kind": "ring", "on": "hands"},
		{"kind": "crown"}])
	var kinds: Array = a.jewellery.map(func(j: Dictionary) -> String: return "%s@%s" % [j["kind"], j["on"]])
	assert_eq(kinds, ["hoop@ears", "torc@neck", "ring@hand_l", "ring@hand_r"], str(a.jewellery))
	assert_eq(str(a.jewel_of(["torc"])["metal"]), "bronze")


## Every value survives a save: the record, through JSON, and back; and a record from before them has
## none.
func test_they_round_trip_through_a_save() -> void:
	var a := CharacterAppearance.new()
	a.set_tattoos([{"design": "antlers", "on": "upper_arm_r", "ink": "green", "fade": 0.35},
		{"design": "ash_rings", "on": "brow", "ink": "ash", "fade": 0.8}])
	a.set_jewellery([{"kind": "drop", "on": "ear_r", "metal": "glass"}, {"kind": "circlet", "metal": "gold"},
		{"kind": "bracelet", "on": "wrists", "metal": "bone"}])
	var back := CharacterAppearance.new(JSON.parse_string(JSON.stringify(a.to_dict())))
	assert_eq(back.tattoos, a.tattoos)
	assert_eq(back.jewellery, a.jewellery)
	var old := CharacterAppearance.new({"skin": "fair", "hair_colour": 3})
	assert_true(old.tattoos.is_empty() and old.jewellery.is_empty())


## A def pins them over the dice: a list replaces the roll, "none" takes it off, prose is left alone.
func test_a_def_pins_them() -> void:
	var a := CharacterAppearance.random(31, "clans", 0.0)
	a.pin({"tattoos": [{"design": "triple_knot", "on": "neck", "ink": "woad", "fade": 0.5}],
		"jewellery": [{"kind": "torc", "metal": "gold"}]})
	assert_eq(a.tattoos.size(), 1)
	assert_eq(str(a.tattoos[0]["on"]), "neck")
	assert_eq(str(a.jewel_of(["torc"])["metal"]), "gold")
	a.pin({"tattoos": "none", "jewellery": "none"})
	assert_true(a.tattoos.is_empty() and a.jewellery.is_empty())
	a.pin({"jewellery": "a silver ring her mother wore"})
	assert_true(a.jewellery.is_empty(), "prose was taken for jewellery")


## Adornment is on dice of its own: a person rolled rich and poor is the same person but for it, and
## the height still comes off the first dice as it always did.
func test_no_old_roll_moves() -> void:
	for seed in range(1, 60):
		var culture: String = CharacterAppearance.CULTURES[seed % CharacterAppearance.CULTURES.size()]
		var poor := CharacterAppearance.random(seed, culture, -1.0, 0.0).to_dict()
		var rich := CharacterAppearance.random(seed, culture, -1.0, 1.0).to_dict()
		var plain := CharacterAppearance.random(seed, culture).to_dict()
		for d in [poor, rich, plain]:
			d.erase("tattoos")
			d.erase("jewellery")
		assert_eq(poor, rich, "seed %d: the means moved something besides the jewellery" % seed)
		assert_eq(poor, plain, "seed %d: the adornment moved another roll" % seed)
	var a := CharacterAppearance.random(4242, "vale", 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	rng.randf()
	assert_near(a.height, 1.62 + rng.randf() * 0.24 - 0.07, 0.0001, "the height's dice moved")


## The dice ink the Clans, the Reedfolk, the Woodfolk and the pilgrims far more than the Vale and the
## Lakefolk, each in their own designs; nobody young; the better off wear more; the rings on a braid
## go on braided hair only.
func test_the_dice_adorn_by_people_years_and_means() -> void:
	var inked := {}
	for culture in CharacterAppearance.CULTURES:
		var n := 0
		var ways: Dictionary = CharacterAppearance.TATTOO_WAYS[culture]
		for seed in 300:
			var a := CharacterAppearance.random(seed * 7 + 1, culture)
			if not a.tattoos.is_empty():
				n += 1
			for t in a.tattoos:
				assert_true((ways["designs"] as Array).has(t["design"]), "%s wear %s" % [culture, t["design"]])
				assert_true(a.age >= 0.18, "a %.2f-year-old is inked" % a.age)
			for j in a.jewellery:
				if str(j["kind"]) == "braid_rings":
					assert_true(CharacterAppearance.BRAIDED_HAIR.has(a.part("hair")), "braid rings on %s" % a.part("hair"))
		inked[culture] = n
	assert_gt(int(inked["clans"]), int(inked["vale"]) * 3, str(inked))
	assert_gt(int(inked["reedfolk"]), int(inked["lakefolk"]) * 2, str(inked))
	var poor := 0
	var rich := 0
	for seed in 300:
		poor += CharacterAppearance.random(seed, "lakefolk", -1.0, 0.1).jewellery.size()
		rich += CharacterAppearance.random(seed, "lakefolk", -1.0, 0.9).jewellery.size()
	assert_gt(rich, poor, "the rich wear no more than the poor (%d, %d)" % [rich, poor])
	assert_gt(CharacterAppearance.wealth_of(["merchant"]), CharacterAppearance.wealth_of(["farmer"]))


# -- the model --------------------------------------------------------------------------------------

## Every body carries its rest position (CUSTOM0) for the tattoos to be placed by.
func test_every_body_carries_its_rest_position() -> void:
	var checked := 0
	for path in BODIES:
		if not ResourceLoader.exists(path):
			continue
		var inst := (load(path) as PackedScene).instantiate()
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			if not str(mi.name).begins_with("Body"):
				continue
			var mesh := (mi as MeshInstance3D).mesh
			assert_true((mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_CUSTOM0) != 0, "%s has no rest coordinates" % path)
			var arr := mesh.surface_get_arrays(0)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var c: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM0]
			assert_near(Vector3(c[40], c[41], c[42]).distance_to(v[10]), 0.0, 0.0005, "%s: CUSTOM0 is not the rest position" % path)
			checked += 1
		inst.free()
	assert_gt(checked, 3)


## A body with tattoos has the overlay, with a frame for each, and one without has none; a face tattoo
## is the head's overlay.
func test_tattoos_are_drawn_only_where_there_are_some() -> void:
	var m := _make_model()
	if m == null:
		return
	var a := CharacterAppearance.new()
	a.set_part("head", "default")
	m.apply_appearance(a.to_dict())
	var body := m.worn_mesh("body")
	assert_true(body != null and body.material_overlay == null, "an uninked body pays for an overlay")
	a.set_tattoos([{"design": "knotwork", "on": "forearm_l"}, {"design": "leaf", "on": "back"},
		{"design": "dots", "on": "cheek_r", "ink": "indigo"}])
	m.apply_appearance(a.to_dict())
	body = m.worn_mesh("body")
	var ov := body.material_overlay as ShaderMaterial
	assert_true(ov != null and ov.shader == Adornment.BODY_MARKS_SHADER, "the body's tattoos are not drawn")
	if ov != null:
		assert_eq(int(ov.get_shader_parameter("design0")), CharacterAppearance.TATTOO_DESIGNS.find("knotwork"))
		assert_eq(int(ov.get_shader_parameter("design1")), CharacterAppearance.TATTOO_DESIGNS.find("leaf"))
		assert_eq(int(ov.get_shader_parameter("design2")), 0)
		# the forearm's frame is on the left forearm, well out from the body
		var f := Transform3D(ov.get_shader_parameter("frame0") as Projection).affine_inverse()
		assert_gt(f.origin.x, 0.3, "the left forearm's tattoo is not on the left forearm: %s" % f.origin)
	var head := m.worn_mesh("head")
	var hov := head.material_overlay as ShaderMaterial
	assert_true(hov != null and int(hov.get_shader_parameter("tattoo0")) == CharacterAppearance.TATTOO_DESIGNS.find("dots"),
			"the cheek's tattoo is not drawn")
	a.set_tattoos([])
	m.apply_appearance(a.to_dict())
	assert_true(m.worn_mesh("body").material_overlay == null, "the overlay outlived the tattoos")


## All of a person's jewellery is one skinned mesh, drawn no further than SEEN_TO; an earring moves
## with the ear's slider; with none there is no mesh, and under a hood no earrings.
func test_jewellery_is_one_mesh_that_goes_with_the_face() -> void:
	var m := _make_model()
	if m == null:
		return
	var a := CharacterAppearance.new()
	a.set_part("head", "default")
	a.set_part("hair", "braid")
	a.set_jewellery([{"kind": "hoop", "metal": "gold"}, {"kind": "torc", "metal": "bronze"}, {"kind": "ring", "on": "hands"},
		{"kind": "bracelet", "on": "wrist_l"}, {"kind": "nose_stud"}, {"kind": "beads", "metal": "glass"}])
	a.set_face("ear_size", 0.8)
	m.apply_appearance(a.to_dict())
	var list: Array = m._part_meshes.get(Adornment.SLOT, [])
	assert_eq(list.size(), 1, "the jewellery is not one mesh")
	if list.is_empty():
		return
	var j := list[0] as MeshInstance3D
	assert_true(j.skin != null and j.mesh.get_surface_count() == 1, "the jewellery is not one skinned surface")
	assert_near(j.visibility_range_end, Adornment.SEEN_TO, 0.01)
	var ear := j.find_blend_shape_by_name(&"face_ear_size")
	assert_true(ear >= 0, "the earrings do not go with the ears")
	if ear >= 0:
		assert_near(j.get_blend_shape_value(ear), 0.8, 0.001)
	assert_true(j.find_blend_shape_by_name(&"grip_L") >= 0, "the rings do not go with the hand")
	var verts := (j.mesh as ArrayMesh).surface_get_array_len(0)
	# a hood over the head takes the earrings off
	a.set_part("back", "hooded_cloak")
	m.apply_appearance(a.to_dict())
	var hooded: Array = m._part_meshes.get(Adornment.SLOT, [])
	assert_true(not hooded.is_empty() and (hooded[0].mesh as ArrayMesh).surface_get_array_len(0) < verts, "earrings through a hood")
	a.set_jewellery([])
	m.apply_appearance(a.to_dict())
	assert_true(m._part_meshes.get(Adornment.SLOT, []).is_empty(), "the jewellery outlived the record's")
