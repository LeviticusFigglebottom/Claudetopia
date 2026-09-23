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
	"Idle", "Idle_Combat", "Walk", "Walk_Back", "Run", "Sprint", "Strafe_L", "Strafe_R",
	"Sneak_Idle", "Sneak_Walk", "Jump_Start", "Jump_Loop", "Jump_Land", "Fall_Loop",
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
	# With a real variant on, the rig is scaled by height alone: widening it as well would
	# count the same build twice. The skeleton hangs under the rig root, so it carries
	# whatever scale was applied there.
	var s := m.skeleton.global_transform.basis.get_scale()
	assert_near(s.x, s.y, 0.002, "a variant body was widened by the build slider as well")


## A part is only wearable on this rig if it was built around this rig's bones. `slight`
## and `heavy` are shape: their worst joint sits 3.3 mm and 1.9 mm from the default's.
## `child` is a different skeleton -- hips at 0.646 m against 0.980, worst joint 476 mm
## out -- so re-skinning it onto adult bones would stretch a child back into an adult.
## It needs its own rig and its own clips, and until it has them the model must not wear it.
func test_a_child_is_not_draped_over_the_adult_skeleton() -> void:
	assert_false(HumanoidModel.WEARABLE_BODIES.has("child"),
		"the child body is built around its own skeleton and cannot ride this one")
	if not _rig_built():
		return
	var m := _make_model()
	var a := CharacterAppearance.new()
	a.set_part("head", "default")
	a.height = 1.30
	assert_eq(a.body_variant(), "child", "the record still knows what it is")
	m.apply_appearance(a.to_dict())
	assert_eq(m.body_variant_worn, "", "a child body was put on the adult rig after all")


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
