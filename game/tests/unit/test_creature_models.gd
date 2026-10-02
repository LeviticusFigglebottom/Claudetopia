extends TestCase
## The common foes the forge has made bodies for (tools/forge/creature_forge.py, CreatureModel): a
## foe whose def says `"rig": "custom"` wears its forged body, never a PlaceholderBody box; the body
## has every clip its def declares and every clip its attacks and its reactions ask for, each attack
## with its wind-up (`cocked`) before its blow (`hit_start`); it walks, trots and runs at its ground
## speed; Death keeps its last frame; and a blow lands where the body is, the head as well as the trunk.

## The foes forged so far (this grows to every custom-rigged foe and boss).
const FORGED: Array[String] = ["core:enemy/down_wolf", "core:enemy/crag_wolf", "core:enemy/thornhound",
	"core:enemy/leech_hound", "core:enemy/old_grey_bitch", "core:enemy/weaver", "core:enemy/stone_thrall", "core:enemy/bristleback",
	"core:enemy/sallowjaw", "core:enemy/gutter_drake", "core:enemy/warden"]
const REACTIONS: Array[String] = ["Hit_Light", "Hit_Light_L", "Stagger", "Stagger_B", "Knockdown", "Get_Up", "Death_A",
	"Idle", "Idle_Combat", "Walk", "Run"]

var _nodes: Array[Node] = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()


func _foe(id: String) -> Enemy:
	var e := Enemy.new()
	e.configure(id)
	_tree().root.add_child(e)
	_nodes.append(e)
	e.perception.enabled = false
	e.set_physics_process(false)
	return e


func test_custom_foes_wear_their_forged_bodies() -> void:
	for id in FORGED:
		var e := _foe(id)
		assert_true(e.anim.model is CreatureModel, "%s wears its forged body" % id)
		assert_true(e.anim.placeholder == null, "%s builds no PlaceholderBody" % id)
		assert_eq(e.find_children("*", "PlaceholderBody", true, false).size(), 0, "%s has no box anywhere" % id)


func test_every_clip_the_foe_uses_is_there() -> void:
	for id in FORGED:
		var e := _foe(id)
		var m := e.anim.model as CreatureModel
		if m == null:
			fail("%s has no forged body" % id)
			continue
		for c in e.def.get("clips", []):
			assert_true(m.has_clip(str(c)), "%s has its declared clip %s" % [id, c])
		for c in REACTIONS:
			assert_false(m.clip_timing(c).is_empty(), "%s can play %s" % [id, c])
		for a in e.attacks:
			var clip := str((a as Dictionary).get("clip", "Attack_1"))
			var t := m.clip_timing(clip)
			var times := {}
			for ev in t.get("events", []):
				times[str(ev["name"])] = float(ev["t"])
			assert_has(times, "hit_start", "%s %s has its blow" % [id, clip])
			assert_has(times, "cocked", "%s %s has its wind-up" % [id, clip])
			if times.has("cocked") and times.has("hit_start"):
				assert_true(float(times["cocked"]) < float(times["hit_start"]), "%s %s winds up before it strikes" % [id, clip])


func test_it_runs_at_its_pace_and_dies_held() -> void:
	for id in FORGED:
		var e := _foe(id)
		var m := e.anim.model as CreatureModel
		if m == null:
			continue
		m.set_locomotion(Vector2(0.0, e.speed), false)
		await _tree().process_frame
		await _tree().process_frame
		assert_eq(m.current_clip(), "Run", "%s runs at its chasing speed %.1f" % [id, e.speed])
		m.set_locomotion(Vector2(0.0, 1.0), false)
		await _tree().process_frame
		assert_true(m.current_clip() in ["Walk", "Trot"], "%s goes at a walk or a trot at 1 m/s (%s)" % [id, m.current_clip()])
		e.anim.play_intent("Death_A")
		var t := 0.0
		while t < 3.0:
			await _tree().process_frame
			t += _tree().root.get_process_delta_time()
			e.anim._physics_process(1.0 / 30.0)
		assert_eq(m.current_intent(), "Death_A", "%s lies dead, the clip held" % id)
		assert_true(e.anim.is_playing("Death_A"), "the driver holds the death too")


func test_a_blow_lands_on_the_head_and_the_quarters() -> void:
	for id in FORGED:
		var e := _foe(id)
		var m := e.anim.model as CreatureModel
		if m == null:
			continue
		var shapes := e.hurtbox.find_children("*", "CollisionShape3D", false, false)
		assert_gt(shapes.size(), 1, "%s is hit as a trunk and a head" % id)
		# the head stands well ahead of the actor's middle, toward its forward (-Z)
		var reach_fwd := -INF
		var reach_back := INF
		for s in shapes:
			var cs := s as CollisionShape3D
			var half := 0.0
			if cs.shape is CapsuleShape3D:
				half = (cs.shape as CapsuleShape3D).height * 0.5
			elif cs.shape is SphereShape3D:
				half = (cs.shape as SphereShape3D).radius
			for end in [cs.transform * Vector3(0.0, half, 0.0), cs.transform * Vector3(0.0, -half, 0.0)]:
				reach_fwd = maxf(reach_fwd, -(end as Vector3).z)
				reach_back = minf(reach_back, -(end as Vector3).z)
		var family := str((m.meta.get("params", {}) as Dictionary).get("family", ""))
		if family == "biped":
			# a giant on two legs is struck from its knees to its skull
			var top := -INF
			for s in shapes:
				var cs := s as CollisionShape3D
				var r := (cs.shape as CapsuleShape3D).height * 0.5 if cs.shape is CapsuleShape3D else (cs.shape as SphereShape3D).radius
				top = maxf(top, cs.position.y + r)
			assert_gt(top, e.capsule_height * 0.8, "%s can be struck on its head" % id)
			continue
		# the actor's forward is -Z: its head reaches ahead of its middle, its quarters behind
		assert_gt(reach_fwd, 0.3 * e.body_scale, "%s can be struck on its head" % id)
		assert_gt(-reach_back, 0.25 * e.body_scale, "%s can be struck on its quarters" % id)


func test_a_thralls_limbs_come_off_and_it_crawls() -> void:
	var e := _foe("core:enemy/stone_thrall")
	var m := e.anim.model as CreatureModel
	if m == null:
		fail("the stone-thrall has no forged body")
		return
	var parts := ["StoneThrall_ArmR", "StoneThrall_ArmL", "StoneThrall_LegL"]
	for p in parts:
		assert_false(m._part_meshes(p).is_empty(), "the thrall's %s is a mesh of its own" % p)
	for i in parts.size():
		e._break_next_limb()
		await _tree().process_frame
		for mi in m._part_meshes(parts[i]):
			assert_false((mi as MeshInstance3D).visible, "%s is gone once broken" % parts[i])
	assert_true(m._crawl, "with no arms and one leg it crawls")
	assert_eq(m.resolve("Walk"), "Crawl", "it comes on along the ground")
	assert_true(m.has_clip("Attack_5"), "and sweeps from there")
	for c in e.get_tree().current_scene.find_children("FallenLimb", "RigidBody3D", false, false) if e.get_tree().current_scene != null else []:
		c.queue_free()
