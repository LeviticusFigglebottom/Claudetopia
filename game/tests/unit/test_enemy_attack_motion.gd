extends TestCase
## The humanoid foes' attacks read the way the player's are held to (test_attack_motion), each with
## the weapon its attack names in the hand, and each on the timeline its def gives it:
##
##   * a clear wind-up: no foe's wind-up plays slower than AnimationDriver.WINDUP_SLOWEST. A
##     telegraph longer than the clip's own wind-up is held at the clip's cocked frame instead of
##     played in slow motion (the audit found the bell-bearer's crushing step at 0.26 of its speed,
##     the cutpurse's gutting turn at 0.27, the drowned's drag at 0.27);
##   * the blow is seen where it lands: the clip's own hit_start comes on the timeline's, within a
##     frame;
##   * no clipping and a leading edge: the weapon's line and the hands stay out of the torso, the
##     wrist bends as a wrist can, and a blade's edge leads its cut.

const FRAME := 1.0 / 60.0
const ATTACK_MOTION := "res://tests/unit/test_attack_motion.gd"
## Weapon classes with an edge to lead, and how much of the cut it must lead (as the player's).
const EDGED := {"sword": 0.8, "greatsword": 0.8, "axe": 0.8, "scythe": 0.6, "rapier": 0.4, "dagger": 0.4}
const MOST_INTO_TORSO := 0.005
const MOST_WRIST_DEG := 95.0
## Clips that thrust rather than cut: the point leads them, not an edge.
const THRUSTS: Array[String] = ["Attack_Dagger_1"]


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## Every attack a humanoid foe or boss makes with a clip the rig has a blow in:
## [foe id, attack def, clip].
func _attacks() -> Array:
	var out := []
	for kind in ["enemy", "boss"]:
		for def in ContentDB.all(kind):
			var d: Dictionary = def
			if str(d.get("rig", "humanoid")) != "humanoid":
				continue
			var sets: Array = [d.get("attacks", [])]
			for ph in d.get("phases", []):
				sets.append((ph as Dictionary).get("attacks", []))
			for s: Array in sets:
				for a in s:
					var ad: Dictionary = a
					var clip := str(ad.get("clip", "Attack_1"))
					var t := HumanoidModel.sidecar_timing(clip)
					if t.is_empty():
						continue
					for e in t.get("events", []):
						if str(e["name"]) == "hit_start":
							out.append([str(d["id"]), ad, clip, d])
							break
	return out


static func _rig_event(clip: String, name: String) -> float:
	for e in HumanoidModel.sidecar_timing(clip).get("events", []):
		if str(e["name"]) == name:
			return float(e["t"])
	return -1.0


## The rig's time at each 60 Hz frame of the wind-up, as the driver plays a foe's: [slowest speed
## outside the hold, the rig's time when the timeline's blow lands, the plan].
static func _play_windup(ours: float, theirs: float, cocked: float) -> Array:
	var plan := AnimationDriver.windup_plan(ours, theirs, cocked)
	var rig_t := 0.0
	var slowest := INF
	var t := 0.0
	while t < ours - 0.00001:
		var dt := minf(FRAME, ours - t)
		var speed := clampf(theirs / ours, AnimationDriver.MODEL_SPEED_MIN, AnimationDriver.MODEL_SPEED_MAX)
		var held := false
		if not plan.is_empty():
			held = t >= float(plan["cocked"]) and t < float(plan["strike_at"])
			speed = float(plan["creep"]) if held else 1.0
		if not held:
			slowest = minf(slowest, speed)
		rig_t += speed * dt
		t += dt
	return [slowest, rig_t, plan]


func test_every_foes_wind_up_reads_and_its_blow_lands_where_it_is_seen() -> void:
	var report: Array[String] = []
	var n := 0
	for row: Array in _attacks():
		var a: Dictionary = row[1]
		var clip: String = row[2]
		var timing := Enemy.attack_timing(a)
		var ours := -1.0
		for e in timing["events"]:
			if str(e["name"]) == "hit_start":
				ours = float(e["t"])
		if ours <= 0.0:
			continue
		var theirs := _rig_event(clip, "hit_start")
		var cocked := _rig_event(clip, "cocked")
		var got := _play_windup(ours, theirs, cocked)
		var plan: Dictionary = got[2]
		n += 1
		var name := "%s %s (%s)" % [Ids.name_of(str(row[0])), str(a.get("name", "")), clip]
		if not plan.is_empty():
			report.append("%s: telegraph %.2f s against the clip's %.2f: drawn back by %.2f s, held %.2f s, struck at its own speed" % [
					name, ours, theirs, cocked, float(plan["hold"])])
		assert_true(float(got[0]) >= AnimationDriver.WINDUP_SLOWEST - 0.001 or theirs / ours > 1.0,
				"%s winds up at %.2f of its speed" % [name, float(got[0])])
		assert_near(float(got[1]), theirs, FRAME, "%s: the clip's blow comes %.3f s off the timeline's" % [name, float(got[1]) - theirs])
	print("    %d humanoid foe attacks; held wind-ups:\n      %s" % [n, "\n      ".join(report)])
	assert_gt(n, 20, "too few humanoid attacks found to audit")


func test_every_foes_attack_with_its_weapon_in_hand_within_the_limits() -> void:
	if not ResourceLoader.exists(HumanoidModel.RIG_PATH):
		return
	var probe: Object = (load(ATTACK_MOTION) as GDScript).new()
	var done := {}
	var report: Array[String] = []
	for row: Array in _attacks():
		var a: Dictionary = row[1]
		var clip: String = row[2]
		if not clip.begins_with("Attack_"):
			continue
		var item := _held_by(row[3])
		var cls := str((item.get("weapon", {}) as Dictionary).get("class", "")) if item.get("weapon") is Dictionary else ""
		var key := "%s/%s" % [clip, cls]
		if done.has(key):
			continue
		done[key] = true
		var length := _blade_length(item)
		var got: Dictionary = probe.call("_measure", [clip], length)
		var edge := float(got["edge"])
		report.append("%s with a %s (%.2f m): blade into the torso %.1f cm, hand %.1f cm, wrist %.0f°, edge %.2f" % [
				clip, cls if not cls.is_empty() else "bare hand", length, maxf(float(got["into_torso"]), 0.0) * 100.0,
				maxf(float(got["hand_into_torso"]), 0.0) * 100.0, float(got["wrist"]), edge])
		assert_true(float(got["into_torso"]) <= MOST_INTO_TORSO, "%s: the %s goes %.1f cm into the torso (at %s)" % [clip, cls, float(got["into_torso"]) * 100.0, got["into_torso_at"]])
		assert_true(float(got["hand_into_torso"]) <= MOST_INTO_TORSO, "%s: the hand goes %.1f cm into the torso" % [clip, float(got["hand_into_torso"]) * 100.0])
		assert_true(float(got["wrist"]) <= MOST_WRIST_DEG, "%s: the wrist bends %.0f°" % [clip, float(got["wrist"])])
		if EDGED.has(cls) and edge >= 0.0 and not THRUSTS.has(clip):
			assert_true(edge >= float(EDGED[cls]), "%s with a %s leads with its edge only %.2f of the cut" % [clip, cls, edge])
	if probe is Object and probe.has_method("after_each"):
		probe.call("after_each")
	print("    %s" % "\n    ".join(report))


## What a foe is seen holding, as Enemy._dress_hands chooses it: its `holds`, else the first of its
## attacks' weapon classes the forge makes; {} for a bare hand.
static func _held_by(def: Dictionary) -> Dictionary:
	var holds := str(def.get("holds", ""))
	if not holds.is_empty():
		return HeldItems.for_class(holds.trim_prefix("class:")) if holds.begins_with("class:") else ContentDB.get_or_empty(holds)
	for a in def.get("attacks", []):
		var item := HeldItems.for_class(str((a as Dictionary).get("weapon_class", "")))
		if not item.is_empty():
			return item
	return {}


## How far a held item's forged model reaches from the grip (m); 0 for a bare hand.
func _blade_length(item: Dictionary) -> float:
	if item.is_empty():
		return 0.0
	var node := HeldItems.instance(item)
	if node == null:
		return 0.0
	_tree().root.add_child(node)
	var length := WeaponTrail.blade_length(node)
	node.free()
	return length


## And in the game: the bell-bearer's crushing step (a 1.6 s telegraph over a 0.41 s wind-up) draws
## back at full speed, holds creeping, and strikes at full speed, and its hit_start still comes on
## the telegraph's frame.
func test_a_long_telegraph_is_held_at_the_cocked_weapon_in_the_game() -> void:
	if not ResourceLoader.exists(HumanoidModel.RIG_PATH):
		return
	var root := Node3D.new()
	_tree().root.add_child(root)
	var e := Enemy.new()
	e.configure("core:enemy/bell_bearer")
	root.add_child(e)
	e.perception.enabled = false
	e.set_physics_process(false)
	for i in 3:
		await _tree().physics_frame
	var attack := {}
	for a in e.attacks:
		if str((a as Dictionary).get("name", "")) == "crushing_step":
			attack = a
	assert_false(attack.is_empty(), "the bell-bearer has no crushing step")
	assert_true(e.anim.hold_windup, "a foe's driver does not hold its wind-ups")
	var timing := Enemy.attack_timing(attack)
	var tel := float(attack.get("telegraph", 0.6))
	var speeds: Array[float] = []
	var seen := {"hit": -1}
	var f0 := Engine.get_physics_frames()
	var on_event := func(n: String) -> void:
		if n == "hit_start" and int(seen["hit"]) < 0:
			seen["hit"] = Engine.get_physics_frames() - f0
	e.anim.clip_event.connect(on_event)
	e.anim.play_intent(str(attack["clip"]), timing)
	for i in int(tel * 60.0) + 4:
		await _tree().physics_frame
		speeds.append(e.anim.model_speed())
	e.anim.clip_event.disconnect(on_event)
	root.free()
	var hit_frame := int(seen["hit"])
	var held := speeds.filter(func(s: float) -> bool: return s > 0.0 and s < 0.5).size()
	var full := speeds.filter(func(s: float) -> bool: return is_equal_approx(s, 1.0)).size()
	print("    the crushing step: %d frames at full speed, %d held; hit_start on frame %d of a %.2f s telegraph" % [full, held, hit_frame, tel])
	assert_gt(held, 40, "the wind-up was not held")
	assert_gt(full, 10, "the wind-up never played at its own speed")
	assert_true(absi(hit_frame - roundi(tel * 60.0)) <= 1, "hit_start came on frame %d, not the telegraph's %d" % [hit_frame, roundi(tel * 60.0)])
