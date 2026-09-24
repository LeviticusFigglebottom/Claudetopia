extends TestCase
## The flinches and staggers a struck body plays, held to limits the way test_attack_motion holds
## the attacks: measured frame by frame on the rig at 120 Hz from the combat guard.
##
##   * the body goes the way the blow threw it: the hips travel along the push, not across it;
##   * nothing pops: no joint that shows moves further in one 60 Hz frame than a limb flung by a
##     blow can (the old Hit_Light's hand jumped 26 cm in its first frame, the Stagger's 49 cm);
##   * the hands stay out of the torso, and the clip ends in the guard it started from;
## and the game picks the reaction by where the blow came from.

const MODEL_SCENE := "res://actors/shared/humanoid_model.tscn"
const DT := 1.0 / 120.0
const TORSO_R := 0.13
## The way each clip throws the body, in the model's frame (it faces +Z, its left is +X).
const PUSH := {
	"Hit_Light": Vector3(0, 0, -1), "Hit_Light_B": Vector3(0, 0, 1), "Hit_Light_L": Vector3(-1, 0, 0), "Hit_Light_R": Vector3(1, 0, 0),
	"Stagger": Vector3(0, 0, -1), "Stagger_B": Vector3(0, 0, 1), "Stagger_L": Vector3(-1, 0, 0), "Stagger_R": Vector3(1, 0, 0),
	"Hit_Heavy": Vector3(0, 0, -1),
}
## The most any shown joint may move in one 60 Hz frame (m): a flinch, and a blow that throws.
const MOST_FRAME_LIGHT := 0.12
const MOST_FRAME_HEAVY := 0.18
## How far the hips must be carried along the push (m), and how much of that may go across it.
const LEAST_ALONG_LIGHT := 0.03
const LEAST_ALONG_HEAVY := 0.08
const MOST_ACROSS_SHARE := 0.45
const MOST_INTO_TORSO := 0.005
## How near the guard the clip ends (m, at the hands and head).
const MOST_END_OFF := 0.02

var _root: Node3D = null


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	if _root != null and is_instance_valid(_root):
		_root.free()
	_root = null


func _model() -> HumanoidModel:
	_root = Node3D.new()
	_tree().root.add_child(_root)
	var m := (load(MODEL_SCENE) as PackedScene).instantiate() as HumanoidModel
	_root.add_child(m)
	m.anim_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	return m


func _bone(m: HumanoidModel, name: String) -> Vector3:
	var sk := m.skeleton
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(name)).origin


func _points(m: HumanoidModel) -> Dictionary:
	var out := {}
	for b in ["Hand.R", "Hand.L", "LowerArm.R", "LowerArm.L", "Head", "Chest", "Hips"]:
		out[b] = _bone(m, b)
	return out


func _measure(clip: String) -> Dictionary:
	var m := _model()
	if not m.has_clip(clip):
		return {}
	m.play_intent("Idle_Combat")
	for i in 90:
		m._process(DT)
	var start := _points(m)
	var hips0: Vector3 = start["Hips"]
	var push: Vector3 = PUSH[clip]
	var out := {"along": 0.0, "across": 0.0, "frame": 0.0, "frame_at": "", "into": 0.0}
	m.play_intent(clip)
	var length := m.clip_length(clip)
	var last := start
	var t := 0.0
	var i := 0
	while t < length:
		m._process(DT)
		t += DT
		i += 1
		var now := _points(m)
		if t + DT >= length:
			last = now
		if i % 2 == 0:
			for b in now:
				var d := (now[b] as Vector3).distance_to(last[b])
				if d > float(out["frame"]):
					out["frame"] = d
					out["frame_at"] = "%s at %.3f s" % [b, t]
			last = now
		var hips: Vector3 = now["Hips"]
		var dv := Vector3(hips.x - hips0.x, 0.0, hips.z - hips0.z)
		out["along"] = maxf(float(out["along"]), dv.dot(push))
		out["across"] = maxf(float(out["across"]), absf(dv.dot(push.cross(Vector3.UP))))
		var neck := _bone(m, "Neck")
		for h in ["Hand.R", "Hand.L"]:
			var pts := Geometry3D.get_closest_points_between_segments(now[h], now[h], hips, neck)
			out["into"] = maxf(float(out["into"]), TORSO_R * 0.8 - (pts[0] as Vector3).distance_to(pts[1]))
	# its last frame, against the combat guard it was played from
	var end := last
	var off := 0.0
	for b in ["Hand.R", "Hand.L", "Head"]:
		off = maxf(off, (end[b] as Vector3).distance_to(start[b]))
	out["end_off"] = off
	after_each()
	return out


func test_every_reaction_is_thrown_the_way_of_its_blow_within_the_limits() -> void:
	if not ResourceLoader.exists(HumanoidModel.RIG_PATH):
		return
	var report: Array[String] = []
	for clip: String in PUSH:
		var got := _measure(clip)
		assert_false(got.is_empty(), "the rig has no %s" % clip)
		if got.is_empty():
			continue
		var heavy := clip.begins_with("Stagger") or clip == "Hit_Heavy"
		report.append("%s: hips %.1f cm along the push and %.1f across; biggest frame %.1f cm (%s); hand into the torso %.1f cm; ends %.1f cm off the guard" % [
				clip, float(got["along"]) * 100.0, float(got["across"]) * 100.0, float(got["frame"]) * 100.0, got["frame_at"],
				maxf(float(got["into"]), 0.0) * 100.0, float(got["end_off"]) * 100.0])
		assert_true(float(got["along"]) >= (LEAST_ALONG_HEAVY if heavy else LEAST_ALONG_LIGHT),
				"%s carries the hips only %.1f cm the way it was thrown" % [clip, float(got["along"]) * 100.0])
		assert_true(float(got["across"]) <= float(got["along"]) * MOST_ACROSS_SHARE + 0.01,
				"%s goes %.1f cm across the push for %.1f along it" % [clip, float(got["across"]) * 100.0, float(got["along"]) * 100.0])
		assert_true(float(got["frame"]) <= (MOST_FRAME_HEAVY if heavy else MOST_FRAME_LIGHT),
				"%s pops: %.1f cm in one frame (%s)" % [clip, float(got["frame"]) * 100.0, got["frame_at"]])
		assert_true(float(got["into"]) <= MOST_INTO_TORSO, "%s puts a hand %.1f cm into the torso" % [clip, float(got["into"]) * 100.0])
		assert_true(float(got["end_off"]) <= MOST_END_OFF, "%s ends %.1f cm off the guard" % [clip, float(got["end_off"]) * 100.0])
	print("    %s" % "\n    ".join(report))


func test_a_foe_flinches_away_from_where_the_blow_came_from() -> void:
	if not ResourceLoader.exists(HumanoidModel.RIG_PATH):
		return
	_root = Node3D.new()
	_tree().root.add_child(_root)
	var e := Enemy.new()
	e.configure("core:enemy/roadside_bandit")
	_root.add_child(e)
	e.perception.enabled = false
	e.set_physics_process(false)
	for i in 3:
		await _tree().physics_frame
	if not (e.anim.model != null and e.anim.model.has_method("has_clip")):
		return
	var f := e.forward()
	var left := Vector3.UP.cross(f)
	var seen := {}
	for row: Array in [["", f], ["B", -f], ["L", left], ["R", -left]]:
		assert_eq(Impact.way_of(f, row[1]), row[0], "a blow from %s is read as %s" % [row[1], Impact.way_of(f, row[1])])
		seen[row[0]] = e.reaction_clip("Hit_Light", e.global_position + (row[1] as Vector3) * 1.5)
	print("    the bandit's flinches: %s" % str(seen))
	assert_eq(seen[""], "Hit_Light")
	assert_eq(seen["B"], "Hit_Light_B")
	assert_eq(seen["L"], "Hit_Light_L")
	assert_eq(seen["R"], "Hit_Light_R")
	# and a real blow from behind plays it
	var hit := HitData.new()
	hit.amount = 1.0
	hit.poise_damage = 0.1
	hit.kind = "slash"
	hit.origin = e.global_position - f * 1.5
	e.take_hit(hit)
	await _tree().physics_frame
	assert_eq(e.anim.current_clip, "Hit_Light_B", "a blow from behind played %s" % e.anim.current_clip)


## A backstab throws its victim forward, the way it was struck (Stagger_B), and a riposte from in
## front rocks it back (Hit_Heavy): a crit's reaction follows the blow as a flinch does.
func test_a_crit_from_behind_throws_the_victim_forward() -> void:
	if not ResourceLoader.exists(HumanoidModel.RIG_PATH):
		return
	_root = Node3D.new()
	_tree().root.add_child(_root)
	var seen := {}
	for row: Array in [["backstab", -1.0, "Stagger_B"], ["riposte", 1.0, "Hit_Heavy"]]:
		var e := Enemy.new()
		e.configure("core:enemy/roadside_bandit")
		_root.add_child(e)
		e.perception.enabled = false
		e.set_physics_process(false)
		for i in 3:
			await _tree().physics_frame
		var hit := HitData.new()
		hit.amount = 1.0
		hit.kind = "pierce"
		hit.crit_kind = str(row[0])
		hit.crit_mult = 3.0
		hit.blockable = false
		hit.parryable = false
		hit.dodgeable = false
		hit.origin = e.global_position + e.forward() * float(row[1]) * 1.2
		e.take_hit(hit)
		await _tree().physics_frame
		seen[row[0]] = e.anim.current_clip
		assert_eq(e.anim.current_clip, str(row[2]), "a %s played %s" % [row[0], e.anim.current_clip])
		e.free()
	print("    a backstab's victim plays %s, a riposte's %s" % [seen.get("backstab", "?"), seen.get("riposte", "?")])


## A foe that did not know it was in a fight is roused by the blow it takes, and it still takes the
## blow. A backstab's victim is thrown forward, and a blow that kills it leaves it dying. Before,
## entering the fight played the combat idle over whatever the blow had started, in the timeline and
## in the picture. So the backstab, the sneak attack and the ambush's first blow were never seen to
## land, and a foe killed unaware stood back up. The test above gives its blows no attacker, so the
## foe was never roused.
func test_a_blow_that_rouses_a_foe_is_still_seen_to_land() -> void:
	if not ResourceLoader.exists(HumanoidModel.RIG_PATH):
		return
	_root = Node3D.new()
	_tree().root.add_child(_root)
	var attacker := Node3D.new()
	_root.add_child(attacker)
	for row: Array in [["backstab", 1.0, "Stagger_B"], ["", 1000.0, "Death_A"]]:
		var e := Enemy.new()
		e.configure("core:enemy/roadside_bandit")
		_root.add_child(e)
		e.perception.enabled = false
		e.set_physics_process(false)
		for i in 3:
			await _tree().physics_frame
		assert_true(e.brain.state != Brain.COMBAT, "the foe was already fighting before the blow")
		attacker.global_position = e.global_position - e.forward() * 1.2
		var hit := HitData.new()
		hit.attacker = attacker
		hit.amount = float(row[1])
		hit.kind = "pierce"
		hit.crit_kind = str(row[0])
		hit.crit_mult = 3.0 if not str(row[0]).is_empty() else 1.0
		hit.blockable = false
		hit.parryable = false
		hit.dodgeable = false
		hit.origin = attacker.global_position
		e.take_hit(hit)
		for i in 6:
			await _tree().physics_frame
		var want := str(row[2])
		assert_eq(e.brain.state, Brain.COMBAT, "the blow did not rouse the foe")
		assert_eq(e.anim.current_clip, want, "roused by a blow, the foe's timeline plays %s, not %s" % [e.anim.current_clip, want])
		var body := e.anim.model as HumanoidModel
		if body != null:
			var shown := body.current_intent() if body.holding_pose().is_empty() else body.holding_pose()
			assert_eq(shown, want, "roused by a blow, the foe is seen to play %s, not %s" % [shown, want])
		e.free()
