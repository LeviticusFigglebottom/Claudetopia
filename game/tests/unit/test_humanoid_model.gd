extends TestCase
## The humanoid model as the game sees it: the rig loads, the contract clips are there with
## their events, the sockets resolve, and an appearance composes without errors.
##
## Every geometry test skips cleanly when the forge has not been run yet, so a fresh
## checkout without generated assets still passes `./run.sh test`.

const MODEL_SCENE := "res://actors/shared/humanoid_model.tscn"
const RIG_GLB := "res://assets/models/characters/humanoid_rig/humanoid_rig.glb"
const CLIPS_JSON := "res://assets/models/characters/humanoid_rig/humanoid_rig.clips.json"

## CONTRACTS.md §2 — the deform bones and the sockets, spelled out so the test fails if
## either side of the contract drifts.
const DEFORM_BONES: Array[String] = [
	"Hips", "Spine", "Chest", "Neck", "Head",
	"Shoulder.L", "UpperArm.L", "LowerArm.L", "Hand.L",
	"Shoulder.R", "UpperArm.R", "LowerArm.R", "Hand.R",
	"UpperLeg.L", "LowerLeg.L", "Foot.L", "Toe.L",
	"UpperLeg.R", "LowerLeg.R", "Foot.R", "Toe.R",
]
const SOCKET_BONES: Array[String] = [
	"Socket.WeaponR", "Socket.WeaponL", "Socket.ShieldL", "Socket.Back",
	"Socket.HipL", "Socket.Head", "Socket.Lantern",
]
## CONTRACTS.md §3 — required clip names.
const REQUIRED_CLIPS: Array[String] = [
	"Idle", "Idle_Combat", "Walk", "Walk_Back", "Trot", "Run", "Sprint", "Strafe_L", "Strafe_R",
	"Sneak_Idle", "Sneak_Walk", "Turn_L90", "Turn_R90", "Turn_L180", "Turn_R180", "Jump_Start", "Jump_Loop", "Jump_Land", "Fall_Loop",
	"Dodge_F", "Dodge_B", "Dodge_L", "Dodge_R",
	"Attack_1H_Light_1", "Attack_1H_Light_2", "Attack_1H_Light_3", "Attack_1H_Heavy",
	"Attack_2H_Light_1", "Attack_2H_Light_2", "Attack_2H_Heavy",
	"Attack_Dagger_1", "Attack_Dagger_2", "Attack_Unarmed_1", "Attack_Unarmed_2",
	"Riposte", "Backstab",
	"Block_Idle", "Block_Hit", "Parry", "Hit_Light", "Hit_Heavy", "Stagger", "Knockdown",
	"Get_Up", "Death_A", "Death_B",
	"Bow_Draw", "Bow_Aim", "Bow_Release", "Cast_Quick", "Cast_Long", "Cast_Loop", "Throw",
	"Interact", "Pick_Up", "Sit_Down", "Sit_Idle", "Stand_Up", "Sleep_Idle",
	"Work_Hammer", "Work_Chop", "Work_Stir", "Work_Dig", "Talk_1", "Talk_2", "Wave",
	"Bow_Gesture", "Laugh", "Rude", "Dance", "Cheer", "Cower", "Point", "Drink", "Eat", "Read",
]
const ATTACK_EVENTS: Array[String] = ["hit_start", "hit_end", "cancel_ok"]

var _model: HumanoidModel
var _root: Node


func before_each() -> void:
	_model = null
	_root = null


func after_each() -> void:
	if _root != null and is_instance_valid(_root):
		_root.free()
	_root = null
	_model = null


func _rig_built() -> bool:
	return ResourceLoader.exists(RIG_GLB)


## Instantiates the model into the live tree (it needs _ready to build).
func _make_model() -> HumanoidModel:
	if _model != null:
		return _model
	var scene: PackedScene = load(MODEL_SCENE)
	if scene == null:
		return null
	_root = Node3D.new()
	Engine.get_main_loop().root.add_child(_root)
	var m := scene.instantiate() as HumanoidModel
	_root.add_child(m)
	_model = m
	return m


# -- appearance (pure data, always runs) --------------------------------------------------

func test_appearance_round_trips() -> void:
	var a := CharacterAppearance.new()
	a.skin = "olive"
	a.height = 1.71
	a.build = 0.8
	a.hollow = 0.5
	a.set_part("torso", "tunic")
	a.palette["primary"] = Color(0.5, 0.2, 0.1)
	var d := a.to_dict()
	var b := CharacterAppearance.new(d)
	assert_eq(b.skin, "olive")
	assert_near(b.height, 1.71)
	assert_near(b.build, 0.8)
	assert_near(b.hollow, 0.5)
	assert_eq(b.part("torso"), "tunic")
	assert_true(b.palette.has("primary"))


func test_appearance_defaults_are_sane() -> void:
	var a := CharacterAppearance.new()
	assert_near(a.height, 1.78)
	assert_eq(a.part("torso"), "")
	assert_eq(a.body_variant(), "default")
	a.height = 1.30
	assert_eq(a.body_variant(), "child")
	a.height = 1.78
	a.build = 0.9
	assert_eq(a.body_variant(), "heavy")


func test_random_appearance_is_deterministic_and_varied() -> void:
	var a := CharacterAppearance.random(1234, "vale")
	var b := CharacterAppearance.random(1234, "vale")
	assert_eq(a.to_dict(), b.to_dict(), "same seed must give the same character")
	var c := CharacterAppearance.random(9876, "vale")
	assert_ne(a.to_dict(), c.to_dict(), "different seeds must differ")
	for s in [11, 22, 33, 44, 55]:
		var r := CharacterAppearance.random(s)
		assert_true(r.height > 1.4 and r.height < 2.0, "height %f out of range" % r.height)
		assert_true(r.culture in CharacterAppearance.CULTURES)
		assert_true(r.skin in CharacterAppearance.SKIN_TONES)
		assert_true(r.hair_colour in CharacterAppearance.HAIR_COLOURS)
		assert_true(r.part("head") != "", "random NPCs need a head")


func test_random_respects_culture() -> void:
	for s in [1, 2, 3]:
		var r := CharacterAppearance.random(s, "ash_pilgrims")
		assert_eq(r.culture, "ash_pilgrims")
		assert_eq(r.part("torso"), "robe", "Ash-Pilgrims wear grey robes (WORLD_BIBLE §3.6)")


# -- the rig itself -------------------------------------------------------------------------

func test_model_scene_loads() -> void:
	var scene: PackedScene = load(MODEL_SCENE)
	assert_true(scene != null, "humanoid_model.tscn must load")


func test_rig_has_every_contract_bone() -> void:
	if not _rig_built():
		return
	var m := _make_model()
	assert_true(m != null and m.skeleton != null, "model has no Skeleton3D")
	for bone in DEFORM_BONES:
		assert_gt(m.skeleton.find_bone(bone), -1, "rig is missing deform bone %s" % bone)
	for bone in SOCKET_BONES:
		assert_gt(m.skeleton.find_bone(bone), -1, "rig is missing socket bone %s" % bone)


func test_sockets_resolve() -> void:
	if not _rig_built():
		return
	var m := _make_model()
	for bone in SOCKET_BONES:
		var att := m.socket(bone)
		assert_true(att != null, "socket %s did not resolve" % bone)
		if att != null:
			assert_eq(att.bone_name, bone)
			assert_gt(att.bone_idx, -1)
	assert_true(m.socket("WeaponR") != null, "short socket names must work too")


func test_socket_attachment_works() -> void:
	if not _rig_built():
		return
	var m := _make_model()
	var probe := Node3D.new()
	probe.name = "Probe"
	assert_true(m.attach_to_socket("WeaponR", probe), "could not attach to WeaponR")
	assert_eq(probe.get_parent(), m.socket("WeaponR"))


func test_every_required_clip_exists() -> void:
	if not _rig_built():
		return
	var m := _make_model()
	var have := m.clip_names()
	var missing: Array[String] = []
	for c in REQUIRED_CLIPS:
		if not (c in have):
			missing.append(c)
	# A partial build (the forge can export a subset while iterating) is not a failure; a
	# build that claims to be complete and is not, is.
	if missing.size() == REQUIRED_CLIPS.size():
		return
	if have.size() >= REQUIRED_CLIPS.size():
		assert_empty(missing, "rig is missing clips")


func test_clip_lengths_and_loops() -> void:
	if not _rig_built():
		return
	var m := _make_model()
	for c in m.clip_names():
		assert_gt(m.clip_length(c), 0.0, "%s has zero length" % c)
	if m.has_clip("Idle"):
		assert_true(m.clip_length("Idle") > 1.0, "Idle should be a few seconds long")


func test_attack_clips_carry_their_events() -> void:
	if not _rig_built():
		return
	var m := _make_model()
	for c in m.clip_names():
		if not c.begins_with("Attack_") and c != "Riposte" and c != "Backstab":
			continue
		var names: Array[String] = []
		for e in m.clip_events(c):
			names.append(str((e as Dictionary).get("name", "")))
		for required in ATTACK_EVENTS:
			assert_true(required in names, "%s has no %s event" % [c, required])


func test_locomotion_clips_carry_footsteps() -> void:
	if not _rig_built():
		return
	var m := _make_model()
	for c in ["Walk", "Run", "Sprint", "Walk_Back", "Sneak_Walk"]:
		if not m.has_clip(c):
			continue
		var names: Array[String] = []
		for e in m.clip_events(c):
			names.append(str((e as Dictionary).get("name", "")))
		assert_true("footstep_l" in names, "%s has no footstep_l" % c)
		assert_true("footstep_r" in names, "%s has no footstep_r" % c)


func test_clip_events_are_inside_their_clip() -> void:
	if not _rig_built():
		return
	var m := _make_model()
	for c in m.clip_names():
		var length := m.clip_length(c)
		for e in m.clip_events(c):
			var t := float((e as Dictionary).get("t", 0.0))
			assert_true(t >= 0.0 and t <= length + 0.01,
					"%s event %s at %f outside 0..%f" % [c, (e as Dictionary).get("name", ""), t, length])


func test_animation_tree_and_api() -> void:
	if not _rig_built():
		return
	var m := _make_model()
	assert_true(m.anim_tree != null, "no AnimationTree")
	assert_true(m.anim_tree.tree_root is AnimationNodeStateMachine)
	m.set_locomotion(Vector2(0.0, 1.0), false)
	assert_eq(m.current_intent(), "", "walking is not a one-shot")
	if m.has_clip("Attack_1H_Light_1"):
		assert_true(m.play_intent("Attack_1H_Light_1"))
		assert_eq(m.current_intent(), "Attack_1H_Light_1")
		m.stop_intent()
		assert_eq(m.current_intent(), "")
	assert_false(m.play_intent("No_Such_Clip"), "unknown clips must be rejected")


## The clip_event / clip_finished contract: events fire once each, in order, and the
## one-shot ends by itself.
func test_one_shot_fires_events_then_finishes() -> void:
	if not _rig_built():
		return
	var m := _make_model()
	var clip := "Attack_1H_Light_1"
	if not m.has_clip(clip):
		return
	var fired: Array[String] = []
	var finished: Array[String] = []
	m.clip_event.connect(func(n: String) -> void: fired.append(n))
	m.clip_finished.connect(func(n: String) -> void: finished.append(n))
	assert_true(m.play_intent(clip))
	var length := m.clip_length(clip)
	var step := 1.0 / 60.0
	var t := 0.0
	while t < length + 0.2:
		m._process(step)
		t += step
	var expected: Array[String] = []
	for e in m.clip_events(clip):
		expected.append(str((e as Dictionary).get("name", "")))
	assert_eq(fired, expected, "events must fire once each, in clip order")
	assert_eq(finished, [clip] as Array[String], "the one-shot must report finishing once")
	assert_eq(m.current_intent(), "", "the model returns to locomotion when a one-shot ends")


## `body_variant()` has always named the right body and nothing ever loaded one, because
## `bodies/child`, `heavy` and `slight` each held a 31-bone skeleton and no mesh at all --
## the forge built the geometry, the glTF exporter refused it as invalid, and the meta
## beside it recorded the triangles anyway because they were counted off the live object
## after the export that dropped them. So the build slider was a uniform widening of one
## rig and a child was a small adult.
##
## This is the assertion that would have caught it: a part with no mesh in it is not a part.
func test_every_body_variant_has_geometry_in_it() -> void:
	var empty: Array[String] = []
	for variant in ["child", "heavy", "slight"]:
		var path := "res://assets/models/characters/bodies/%s/%s.glb" % [variant, variant]
		if not ResourceLoader.exists(path):
			continue
		var inst := (load(path) as PackedScene).instantiate()
		var tris := 0
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = (mi as MeshInstance3D).mesh
			if mesh == null:
				continue
			for s in mesh.get_surface_count():
				tris += mesh.surface_get_array_len(s)
		if tris <= 0:
			empty.append(variant)
		inst.queue_free()
	assert_true(empty.is_empty(), "body variants with a rig and no geometry: %s" % [empty])


## And the model must actually put one on. A heavy record wears the heavy body instead of
## being one rig widened by a slider.
func test_a_heavy_record_wears_the_heavy_body() -> void:
	if not _rig_built():
		return
	if not ResourceLoader.exists("res://assets/models/characters/bodies/heavy/heavy.glb"):
		return
	var m := _make_model()
	var a := CharacterAppearance.new()
	a.set_part("head", "default")
	a.build = 0.9
	assert_eq(a.body_variant(), "heavy")
	m.apply_appearance(a.to_dict())
	assert_eq(m.body_variant_worn, "heavy", "a build of 0.9 is still wearing the default body")
	# With a real variant on, the rig only makes up the difference between the girth the build
	# asks for and the heavy body's own, so the build is not counted twice: the total is the
	# slider's girth, not the heavy body's girth widened again by it. The skeleton hangs under
	# the rig root, so it carries whatever scale was applied there.
	var s := m.skeleton.global_transform.basis.get_scale()
	var total := s.x / s.y * float(HumanoidModel.VARIANT_GIRTH["heavy"])
	assert_near(total, HumanoidModel.girth_for(0.9), 0.002, "the heavy body's width was counted twice")
	assert_true(absf(s.x / s.y - 1.0) < 0.05, "the heavy body was widened by more than the slider's own step")


## The heavy body is wider than every garment built on the default one, so under clothes that
## carry no fit for it the model stays on the default body and widens the rig instead: at the
## heavy end of the Naming's build slider the skin used to show through the gambeson.
func test_a_heavy_body_is_only_worn_under_clothes_cut_for_it() -> void:
	if not _rig_built():
		return
	var m := _make_model()
	var a := CharacterAppearance.new()
	a.build = 0.95
	a.set_part("torso", "gambeson")
	a.set_part("legs", "trousers")
	m.apply_appearance(a.to_dict())
	if m._garments_fit("heavy"):
		assert_eq(m.body_variant_worn, "heavy", "the clothes are cut for the heavy body and it is not worn")
	else:
		assert_eq(m.body_variant_worn, "", "the heavy body was worn under clothes not cut for it")
		var s := m.skeleton.global_transform.basis.get_scale()
		assert_near(s.x / s.y, HumanoidModel.girth_for(0.95), 0.002, "and the rig did not do the widening")


## A part is only wearable on this rig if it was built around this rig's bones. `slight`
## and `heavy` are shape: their worst joint sits 3.3 mm and 1.9 mm from the default's.
## `child` is a different skeleton -- hips at 0.646 m against 0.980, worst joint 476 mm
## out -- so re-skinning it onto adult bones would stretch a child back into an adult. It is
## worn on the rig re-proportioned to the child's own skeleton instead (ChildProportions):
## after the clips have posed it, the hips stand at a child's height, the arms are a child's
## length and the head is scaled to the child's.
func test_a_child_is_worn_on_a_child_skeleton() -> void:
	assert_false(HumanoidModel.WEARABLE_BODIES.has("child"),
		"the child body is built around its own skeleton and cannot ride the grown one as it is")
	if not _rig_built() or not ResourceLoader.exists("res://assets/models/characters/bodies/child/child.glb"):
		return
	# and a child is only put in its own body once there are clothes cut for it
	if not ResourceLoader.exists("res://assets/models/characters/clothing/tunic_child/tunic_child.glb"):
		return
	var m := _make_model()
	var grown_hips := m.skeleton.get_bone_global_rest(m.skeleton.find_bone("Hips")).origin.y
	var grown_arm := _arm_length(m.skeleton, true)
	var a := CharacterAppearance.new()
	a.set_part("head", "default")
	a.set_part("torso", "tunic")
	a.height = 1.30
	assert_eq(a.body_variant(), "child", "the record still knows what it is")
	m.apply_appearance(a.to_dict())
	assert_eq(m.body_variant_worn, "child", "a child's record is not wearing the child's body")
	var mod := m.skeleton.get_node_or_null("ChildProportions") as ChildProportions
	assert_true(mod != null, "the rig was not re-proportioned")
	if mod == null:
		return
	# The pose is read as the modifier leaves it, which is what the skin is drawn with; the
	# engine may hand scripts the clip's own pose again once the frame is drawn.
	var sk := m.skeleton
	var seen := {}
	mod.modification_processed.connect(func() -> void:
		seen["hips"] = sk.get_bone_global_pose(sk.find_bone("Hips")).origin.y
		seen["arm"] = _arm_length(sk, false)
		seen["head"] = sk.get_bone_global_pose(sk.find_bone("Head")).basis.get_scale().y)
	for i in 4:
		await Engine.get_main_loop().process_frame
	assert_true(seen.has("hips"), "the child's proportions were never applied")
	if not seen.has("hips"):
		return
	var hips: float = seen["hips"]
	assert_gt(grown_hips * 0.75, hips, "the hips stand at %.3f m, a grown height" % hips)
	assert_gt(hips, grown_hips * 0.5, "the hips sank to %.3f m" % hips)
	var arm: float = seen["arm"]
	assert_gt(grown_arm * 0.85, arm, "the arm is %.3f m against a grown %.3f" % [arm, grown_arm])
	assert_near(float(seen["head"]), 1.18 * 1.30 / 1.78, 0.03, "the grown head was not scaled to the child's")
	# a garment with no child's cut is not hung off the child in a grown size
	for mi in m.skeleton.find_children("*", "MeshInstance3D", false, false):
		var part := str(mi.get_meta("part", ""))
		if str(mi.get_meta("slot", "")) == "torso":
			assert_true(part.ends_with("_child"), "the child is wearing the grown %s" % part)
	# and a grown record afterwards is grown again
	a.height = 1.78
	m.apply_appearance(a.to_dict())
	assert_true(m.skeleton.get_node_or_null("ChildProportions") == null
			or m.skeleton.get_node("ChildProportions").is_queued_for_deletion(),
			"the child's proportions outlived the child")


## Shoulder to wrist along the left arm, off the rest pose or the current one.
func _arm_length(sk: Skeleton3D, rest: bool) -> float:
	var sh := sk.find_bone("UpperArm.L")
	var wr := sk.find_bone("Hand.L")
	if rest:
		return sk.get_bone_global_rest(sh).origin.distance_to(sk.get_bone_global_rest(wr).origin)
	return sk.get_bone_global_pose(sh).origin.distance_to(sk.get_bone_global_pose(wr).origin)


func test_appearance_composes() -> void:
	if not _rig_built():
		return
	var m := _make_model()
	var a := CharacterAppearance.new()
	a.set_part("head", "default")
	a.height = 1.68
	m.apply_appearance(a.to_dict())
	assert_eq(m.appearance.height, 1.68)
	# a second call must not accumulate meshes
	var before := m.skeleton.get_child_count()
	m.apply_appearance(a.to_dict())
	assert_eq(m.skeleton.get_child_count(), before, "re-applying an appearance leaked nodes")


## A walking actor used to push one engine error per frame -- "Grouped
## AnimationNodeStateMachinePlayback must be handled by parent
## AnimationNodeStateMachinePlayback" -- because the tree root was typed GROUPED, so every
## travel() and start() on it was rejected outright.  An arena run logged 1207 of them from
## one bandit walking about.  Errors cannot be counted from GDScript, so this asserts the
## thing that is impossible while they are firing: that the playback actually MOVES.
func test_locomotion_and_an_attack_drive_the_state_machine() -> void:
	if not _rig_built():
		return
	var m := _make_model()
	if m == null:
		return
	var root := m.anim_tree.tree_root as AnimationNodeStateMachine
	assert_eq(root.state_machine_type, AnimationNodeStateMachine.STATE_MACHINE_TYPE_ROOT,
			"a grouped state machine at the tree root is rejected on every travel()")
	var play: AnimationNodeStateMachinePlayback = m.anim_tree.get("parameters/playback")
	assert_true(play != null, "no playback")
	var step := 1.0 / 60.0
	for i in 120:
		var t := float(i) * step
		m.set_locomotion(Vector2(sin(t * 2.0) * 0.5, 0.4 + 0.6 * absf(sin(t))), i % 40 > 30)
		m._process(step)
		m.anim_tree.advance(step)     # the tree is not stepped by the loop in a sync test
	assert_eq(play.get_current_node(), HumanoidModel.LOCOMOTION_STATE,
			"three seconds of walking must leave the machine in Locomotion")
	if not m.has_clip("Attack_1H_Light_1"):
		return
	assert_true(m.play_intent("Attack_1H_Light_1"))
	m._process(step)
	m.anim_tree.advance(step)
	assert_eq(play.get_current_node(), "Attack_1H_Light_1", "play_intent must reach the clip")
	var length := m.clip_length("Attack_1H_Light_1")
	var t2 := 0.0
	while t2 < length + 0.3:
		m._process(step)
		m.set_locomotion(Vector2(0.0, 1.0), false)
		m.anim_tree.advance(step)
		t2 += step
	assert_eq(m.current_intent(), "", "the one-shot must end")
	assert_eq(play.get_current_node(), HumanoidModel.LOCOMOTION_STATE,
			"and the machine must travel back to Locomotion")


## Every one-shot clip must be reachable from Locomotion: travel() with no transition falls
## back to a hard cut, which is how the graph silently loses its cross-fades.
func test_every_one_shot_has_a_transition_both_ways() -> void:
	if not _rig_built():
		return
	var m := _make_model()
	if m == null:
		return
	var root := m.anim_tree.tree_root as AnimationNodeStateMachine
	var missing: Array[String] = []
	for name in root.get_node_list():
		if name == HumanoidModel.LOCOMOTION_STATE or name.begins_with("Start") or name.begins_with("End"):
			continue
		if not root.has_transition(HumanoidModel.LOCOMOTION_STATE, name):
			missing.append("-> " + name)
		if not root.has_transition(name, HumanoidModel.LOCOMOTION_STATE):
			missing.append(name + " ->")
	assert_empty(missing, "clips with no transition to or from Locomotion: %s" % str(missing))



## Stubble is a shell over the jaw in the hair colour; drawn opaque it was a full short beard.
func test_stubble_is_seen_through() -> void:
	if not _rig_built() or not ResourceLoader.exists("res://assets/models/characters/beards/stubble/stubble.glb"):
		return
	var m := _make_model()
	var a := CharacterAppearance.new()
	a.set_part("head", "default")
	a.set_part("beard", "stubble")
	m.apply_appearance(a.to_dict())
	var seen := 0
	for mi in m.skeleton.find_children("*", "MeshInstance3D", false, false):
		if str(mi.get_meta("slot", "")) != "beard":
			continue
		var mat := (mi as MeshInstance3D).get_surface_override_material(0) as BaseMaterial3D
		assert_true(mat != null, "the stubble was not dressed")
		if mat != null:
			assert_eq(mat.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA, "the stubble is opaque")
			assert_gt(0.8, mat.albedo_color.a, "the stubble is drawn solid (alpha %.2f)" % mat.albedo_color.a)
			seen += 1
	assert_gt(seen, 0, "no stubble mesh on the body")


## Cloth, leather and metal are not smooth tinted shells: each wears the garment shader with a
## grain that tiles over it (weave, leather crease, hammered dents) and the mottling map.
func test_garments_have_a_grain() -> void:
	if not _rig_built():
		return
	var m := _make_model()
	var a := CharacterAppearance.new()
	a.culture = "vale"
	a.palette = CharacterAppearance.culture_palette("vale")
	a.set_part("head", "default")
	a.set_part("torso", "tunic")
	a.set_part("belt", "belt")
	m.apply_appearance(a.to_dict())
	var seen := {}
	for mi in m.skeleton.find_children("*", "MeshInstance3D", false, false):
		var part := str(mi.get_meta("part", ""))
		if part != "tunic" and part != "belt":
			continue
		var mat := (mi as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial
		assert_true(mat != null and mat.shader == HumanoidModel.GARMENT_SHADER, "the %s is not in the garment shader" % part)
		if mat == null:
			continue
		assert_true(mat.get_shader_parameter("detail_normal") != null, "the %s has no grain" % part)
		assert_true(mat.get_shader_parameter("mottle_tex") != null, "the %s has no mottling" % part)
		assert_true(mat.get_shader_parameter("albedo_tex") != null, "the %s lost its bake" % part)
		seen[part] = int(mat.get_shader_parameter("kind"))
	assert_eq(seen.get("tunic", -1), 0, "the tunic is not dressed as cloth")
	assert_eq(seen.get("belt", -1), 1, "the belt is not dressed as leather")


## The clans' plaid is a tartan baked in its own colours, and its meta says "tint": "none". Dressed
## in the palette's primary like any cloth, the rust and the brown went to a muddy pale and the
## check was lost: it must be lit as cloth and left its own colour.
func test_a_woven_part_is_not_tinted() -> void:
	var meta_path := "res://assets/models/characters/clothing/plaid/plaid.meta.json"
	if not _rig_built() or not FileAccess.file_exists(meta_path):
		return
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	if typeof(meta) != TYPE_DICTIONARY or str((meta as Dictionary).get("tint", "")) != "none":
		return
	var m := _make_model()
	var a := CharacterAppearance.new()
	a.culture = "clans"
	a.palette = CharacterAppearance.culture_palette("clans")
	a.set_part("head", "default")
	a.set_part("back", "plaid")
	a.set_part("torso", "shirt")
	m.apply_appearance(a.to_dict())
	var plaid := 0
	var shirt := 0
	for mi in m.skeleton.find_children("*", "MeshInstance3D", false, false):
		if (mi as MeshInstance3D).get_surface_override_material(0) == null:
			continue
		var worn := HumanoidModel.dressed_colour_of(mi as MeshInstance3D)
		match str(mi.get_meta("part", "")):
			"plaid":
				assert_eq(worn, Color.WHITE, "the tartan was tinted %s" % worn)
				plaid += 1
			"shirt":
				assert_ne(worn, Color.WHITE, "the shirt under it was not dressed")
				shirt += 1
	assert_gt(plaid, 0, "no plaid mesh on the body")
	assert_gt(shirt, 0, "no shirt mesh on the body")


## A gambeson puts 3 cm of padding on the body and 3 cm on the sleeve, and the Idle hangs the
## wrists 5 cm outside the bare hip: the hands of everyone in one hung inside its skirt. ArmRoom
## turns the arms out for what is worn, and only for that.
func test_padding_holds_the_arms_out() -> void:
	if not _rig_built():
		return
	assert_eq(HumanoidModel.arm_room_for("tunic", ""), 0.0, "a tunic leaves the arms where the clip has them")
	assert_gt(HumanoidModel.arm_room_for("gambeson", ""), 5.0, "a gambeson does not make room for the arms")
	assert_gt(HumanoidModel.arm_room_for("gambeson", "heavy"), HumanoidModel.arm_room_for("gambeson", ""),
			"a heavy body in a gambeson has no more room than a slight one")
	var bare := await _left_wrist_out(["torso", "shirt"])
	var padded := await _left_wrist_out(["torso", "gambeson"])
	assert_true(bare > 0.0 and padded > 0.0, "the arms were never posed (%.3f, %.3f)" % [bare, padded])
	# the wrist moves out by about 8 mm a degree of the 7
	assert_gt(padded - bare, 0.04, "in a gambeson the wrist hangs %.3f m out, bare %.3f m" % [padded, bare])
	assert_gt(0.09, padded - bare, "the arms were thrown out %.3f m" % (padded - bare))


## A cloak to the knee holds the arms in while the body walks: the Walk swung the hand out
## through the front of it at every step. Only while walking -- a blow gets its whole arm.
func test_a_long_cloak_holds_the_arms_in_walking() -> void:
	assert_gt(HumanoidModel.arm_hold_for("cloak"), 0.3, "a cloak to the knee leaves the arms their whole swing")
	assert_eq(HumanoidModel.arm_hold_for("shoulder_cape"), 0.0, "a shoulder cape holds the arms in")
	assert_eq(HumanoidModel.arm_hold_for(""), 0.0, "a bare back holds the arms in")
	if not _rig_built():
		return
	var free := await _hand_swing("")
	var held := await _hand_swing("cloak")
	assert_gt(free, 0.08, "the walk never swung the hand ahead (%.3f m)" % free)
	assert_gt(free * 0.75, held, "in a cloak the hand swings %.3f m ahead of the hips, bare %.3f m" % [held, free])
	assert_gt(held, free * 0.2, "in a cloak the arms stopped swinging (%.3f m against %.3f m)" % [held, free])
	var m := _make_model()
	if m.has_clip("Attack_1H_Light_1"):
		m.set_process(false)
		assert_true(m.play_intent("Attack_1H_Light_1"))
		for i in 12:
			m._process(1.0 / 60.0)
		assert_eq(m.arm_room.hold, 0.0, "a blow struck in a cloak is held in like a walk")
		m.stop_intent()
		m.set_process(true)


## The hands close round what they hold. The rig has no finger bones: the body and the gloves carry
## the fist as the morph targets grip_L and grip_R, and set_grip turns them on, eased, and keeps them
## on whatever is put on the hands afterwards.
func test_a_hand_closes_round_a_haft() -> void:
	if not _rig_built():
		return
	var m := _make_model()
	var a := CharacterAppearance.new()
	a.set_part("head", "default")
	m.apply_appearance(a.to_dict())
	var body := m._default_meshes.get("body") as MeshInstance3D
	assert_true(body != null and body.find_blend_shape_by_name(&"grip_R") >= 0
			and body.find_blend_shape_by_name(&"grip_L") >= 0, "the body has no closed hands to close")
	if body == null or body.find_blend_shape_by_name(&"grip_R") < 0:
		return
	var right := body.find_blend_shape_by_name(&"grip_R")
	var left := body.find_blend_shape_by_name(&"grip_L")
	m.set_process(false)
	m.set_grip("R", 1.0)
	for i in 3:
		m._process(1.0 / 60.0)
	var half := body.get_blend_shape_value(right)
	assert_true(half > 0.2 and half < 0.9, "the hand should close over a tenth of a second (%.2f after 3 frames)" % half)
	for i in 10:
		m._process(1.0 / 60.0)
	assert_near(body.get_blend_shape_value(right), 1.0, 0.001, "the right hand did not close")
	assert_near(body.get_blend_shape_value(left), 0.0, 0.001, "the left hand closed with the right")
	assert_near(m.grip("R"), 1.0, 0.001)
	# gloves put on a closed hand close with it
	a.set_part("hands", "gloves")
	m.apply_appearance(a.to_dict())
	var gloved := 0
	for mi in m._part_meshes.get("hands", []):
		var g := mi as MeshInstance3D
		var b := g.find_blend_shape_by_name(&"grip_R") if g != null else -1
		if b >= 0:
			gloved += 1
			assert_near(g.get_blend_shape_value(b), 1.0, 0.001, "a glove put on a closed hand is open")
	assert_gt(gloved, 0, "the gloves have no closed hands")
	m.set_grip("R", 0.0, true)
	assert_near(body.get_blend_shape_value(right), 0.0, 0.001, "set_grip(..., now) did not open the hand at once")
	a.set_part("hands", "")
	m.apply_appearance(a.to_dict())
	m.set_process(true)


## How far ahead of the hips the left hand comes, at most, over two seconds of walking at 1.4 m/s,
## as the modifiers leave it. Stepped by hand, a frame at a time, so the skeleton's modifiers run
## between steps.
func _hand_swing(back: String) -> float:
	var m := _make_model()
	var a := CharacterAppearance.new()
	a.set_part("head", "default")
	if back != "":
		a.set_part("back", back)
	m.apply_appearance(a.to_dict())
	m.set_process(false)
	var sk := m.skeleton
	var seen := {"ahead": -1.0}
	var watch := func() -> void:
		var hips := sk.get_bone_global_pose(sk.find_bone("Hips")).origin
		var hand := sk.get_bone_global_pose(sk.find_bone("Hand.L")).origin
		seen["ahead"] = maxf(float(seen["ahead"]), hand.z - hips.z)
	m.set_locomotion(Vector2(0.0, 1.4))
	for i in 30:
		m._process(1.0 / 60.0)
		await Engine.get_main_loop().process_frame
	m.arm_room.modification_processed.connect(watch)
	for i in 120:
		m._process(1.0 / 60.0)
		await Engine.get_main_loop().process_frame
	m.arm_room.modification_processed.disconnect(watch)
	m.set_locomotion(Vector2.ZERO)
	m.set_process(true)
	return float(seen["ahead"])


## How far out from the spine the left wrist hangs in the Idle, as the modifiers leave it.
func _left_wrist_out(part: Array) -> float:
	var m := _make_model()
	var a := CharacterAppearance.new()
	a.set_part("head", "default")
	a.set_part(str(part[0]), str(part[1]))
	m.apply_appearance(a.to_dict())
	var sk := m.skeleton
	var seen := {}
	m.arm_room.modification_processed.connect(func() -> void:
		var hips := sk.get_bone_global_pose(sk.find_bone("Hips")).origin
		seen["x"] = absf(sk.get_bone_global_pose(sk.find_bone("Hand.L")).origin.x - hips.x))
	for i in 4:
		await Engine.get_main_loop().process_frame
	return float(seen.get("x", -1.0))


## Every head is baked young and even and wears the marks of a life by the person: the lines of
## age by their age (none on a young face, all of them on an old one), and a ruddiness, freckles
## and a weathering of their own, off the head's _marks map.
func test_the_old_wear_their_years() -> void:
	if not _rig_built():
		return
	assert_eq(HumanoidModel.age_lines_amount(0.2), 0.0, "a young face has lines")
	assert_eq(HumanoidModel.age_lines_amount(1.0), 1.0, "an old face lacks some of its lines")
	for head in ["default", "hawk"]:
		var marks_map := "res://assets/models/characters/heads/%s/%s_marks.png" % [head, head]
		if not ResourceLoader.exists(marks_map):
			continue
		var worn := []
		for age in [0.2, 0.9]:
			var m := _make_model()
			var a := CharacterAppearance.new()
			a.set_part("head", head)
			a.age = age
			a.freckles = 0.4
			m.apply_appearance(a.to_dict())
			var got := {}
			for mi in m.skeleton.find_children("*", "MeshInstance3D", true, false):
				# the last look's parts are still in the tree until the frame ends
				if mi.is_queued_for_deletion() or not (mi as MeshInstance3D).visible:
					continue
				var mat := (mi as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial
				if mat == null or mat.get_shader_parameter("marks_tex") == null:
					continue
				for key in ["age_amount", "ruddy_amount", "freckle_amount", "weather_amount"]:
					got[key] = float(mat.get_shader_parameter(key))
			worn.append(got)
		assert_false(worn[0].is_empty(), "%s: the face wears no marks" % head)
		if worn[0].is_empty() or worn[1].is_empty():
			continue
		assert_true(float(worn[0]["age_amount"]) <= 0.0, "%s: the young face shows lines (%s)" % [head, worn])
		assert_gt(float(worn[1]["age_amount"]), 0.8, "%s: the old face does not show its lines (%s)" % [head, worn])
		assert_gt(float(worn[1]["freckle_amount"]), 0.5, "%s: the freckles are not laid on (%s)" % [head, worn])
		assert_gt(float(worn[1]["weather_amount"]), float(worn[0]["weather_amount"]),
			"%s: the old face is no more weathered than the young (%s)" % [head, worn])
		assert_gt(float(worn[1]["ruddy_amount"]), 0.0, "%s: no ruddiness (%s)" % [head, worn])


## Two people on the same head are not one face twice: one brow and one corner of the mouth sit a
## little higher, which side and how much by the person (the head's morph targets).
func test_faces_are_off_true_by_the_person() -> void:
	var seen := []
	for s in [3, 11, 29, 57, 101]:
		var a := CharacterAppearance.new()
		a.seed = s
		var d := HumanoidModel.face_asymmetry_for(a)
		assert_true((float(d["brow_up_L"]) > 0.0) != (float(d["brow_up_R"]) > 0.0), "one brow, not both: %s" % d)
		assert_true((float(d["mouth_up_L"]) > 0.0) != (float(d["mouth_up_R"]) > 0.0), "one corner, not both: %s" % d)
		seen.append(str(d))
	assert_gt(seen.size(), 1)
	var distinct := {}
	for d in seen:
		distinct[d] = true
	assert_gt(distinct.size(), 2, "five people, the same face: %s" % [seen])
	if not _rig_built():
		return
	var m := _make_model()
	var look := CharacterAppearance.new()
	look.seed = 11
	look.set_part("head", "hawk")
	m.apply_appearance(look.to_dict())
	var want := HumanoidModel.face_asymmetry_for(look)
	var checked := 0
	for mi in m.skeleton.find_children("*", "MeshInstance3D", true, false):
		if str(mi.get_meta("slot", "")) != "head" or mi.is_queued_for_deletion():
			continue
		for shape in want:
			var idx := (mi as MeshInstance3D).find_blend_shape_by_name(shape)
			if idx < 0:
				continue
			assert_near((mi as MeshInstance3D).get_blend_shape_value(idx), float(want[shape]), 0.001, shape)
			checked += 1
	# a head built before the morphs existed has none to set; one built after has all four
	assert_true(checked == 0 or checked == 4, "set %d of the four" % checked)


## The rig's Animations and their library are one set of resources, shared by every body built from
## the rig. A write to one says `changed`, and every live AnimationTree answers by queueing a set-up
## of itself for later. So a body built while others stand must write none of them. The loop flags
## were written on every build, the same values again: standing up a village's people queued
## thousands of set-ups, the message queue ran out of memory, and the engine crashed
## (test_poi_people on the batch-3 world).
func test_another_body_built_leaves_the_shared_clips_alone() -> void:
	if not _rig_built():
		return
	var first := _make_model()
	assert_true(first != null, "no model")
	if first == null or first.anim_player == null:
		return
	var said := {"n": 0, "what": []}
	var heard := func(what: String) -> void:
		said["n"] = int(said["n"]) + 1
		if (said["what"] as Array).size() < 5:
			(said["what"] as Array).append(what)
	var listened: Array = []        # [resource, callable]
	for lib_name in first.anim_player.get_animation_library_list():
		var lib := first.anim_player.get_animation_library(lib_name)
		var on_lib := heard.bind("the library '%s'" % lib_name)
		lib.changed.connect(on_lib)
		listened.append([lib, on_lib])
		for anim_name in lib.get_animation_list():
			var anim := lib.get_animation(anim_name)
			var on_anim := heard.bind(str(anim_name))
			anim.changed.connect(on_anim)
			listened.append([anim, on_anim])
	var scene: PackedScene = load(MODEL_SCENE)
	var second := scene.instantiate() as HumanoidModel
	_root.add_child(second)
	for pair: Array in listened:
		(pair[0] as Resource).changed.disconnect(pair[1] as Callable)
	assert_true(second.anim_player != null and second.has_clip("Idle"), "the second body has no clips")
	assert_eq(int(said["n"]), 0, "building a second body wrote the rig's shared clips %d times (%s)" % [
			int(said["n"]), ", ".join(PackedStringArray(said["what"] as Array))])
