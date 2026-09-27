extends TestCase
## The attack clips as the eye meets them, with the weapon in the hand: measured frame by frame on
## the rig at 120 Hz, the way test_locomotion_blend measures the feet.
##
##   * the blade (and the hand) against the body: how deep the blade's line or the hand goes into
##     the torso, a capsule from the hips to the neck;
##   * the wrist: how far the hand bends off the line of the forearm;
##   * the edge: in the blow, how squarely the blade's edge leads its own motion (1 edge-on, 0 the
##     flat), for the cuts;
##   * the weight: how far the hips travel and turn;
##   * the chain: how far the body jumps in the one frame one blow of a chain hands over to the
##     next, against how far it moves in a frame of the blows themselves.
##
## Reported for every attack, and held to the limits below.

const MODEL_SCENE := "res://actors/shared/humanoid_model.tscn"
const DT := 1.0 / 120.0
## The torso: a capsule of this radius (m) from the hips to the neck.
const TORSO_R := 0.13
## Blade lengths (m) by clip set, from the grip, for the reach of the line measured.
const BLADE := {"1H": 0.86, "2H": 1.2, "dagger": 0.34, "unarmed": 0.0}
## How far behind the grip the longest weapon swung with each set reaches (m, off the forged
## models): a long axe's haft for 1H, a long spear's butt for 2H (the spears and staffs swing the 2H
## clips). The butt end is held out of the torso as the blade is: the 2H swings once drove a spear's
## butt through it (DECISIONS).
const BUTT := {"1H": 0.16, "2H": 1.18, "dagger": 0.09, "unarmed": 0.0}
const CHAINS := {"1H": ["Attack_1H_Light_1", "Attack_1H_Light_2", "Attack_1H_Light_3"],
		"2H": ["Attack_2H_Light_1", "Attack_2H_Light_2"], "dagger": ["Attack_Dagger_1", "Attack_Dagger_2"],
		"unarmed": ["Attack_Unarmed_1", "Attack_Unarmed_2"]}
const HEAVIES := {"1H": "Attack_1H_Heavy", "2H": "Attack_2H_Heavy"}
const CRITS: Array[String] = ["Riposte", "Backstab"]
## How far ahead of the hips a crit's point must reach while its blow is live (m): the player closes
## to 1.2 m of the foe before it (Player._tick_riposte), and the foe's back or chest is a body's
## radius nearer.
const CRIT_REACH := 0.95

## The limits, set a little outside what the clips were fixed to (in brackets below; the commit
## that re-baked them gives the before and after).
## The blade's line and the hand stay out of the torso (0.0 cm everywhere).
const MOST_INTO_TORSO := 0.005
## The wrist bends no further than a wrist can (43-89 degrees; the old solve folded it 144-176).
const MOST_WRIST_DEG := 95.0
## A cut leads with its edge (swords and axes 0.85-0.93; the dagger's stab and slash 0.49).
const LEAST_EDGE := {"1H": 0.8, "2H": 0.8, "dagger": 0.4}
## One blow hands over to the next without a visible jump (0.0-4.0 cm).
const MOST_HANDOVER_JUMP := 0.05

var _root: Node3D = null


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	if _root != null and is_instance_valid(_root):
		_root.free()
	_root = null


func _rig_built() -> bool:
	return ResourceLoader.exists(HumanoidModel.RIG_PATH)


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


## The weapon socket's grip point and blade direction, in the world.
func _blade(m: HumanoidModel) -> Array:
	var sk := m.skeleton
	var xf := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Socket.WeaponR"))
	return [xf.origin, xf.basis.y.normalized(), xf.basis.z.normalized()]


## The closest two points of segments p0-p1 and q0-q1: their distance.
static func segment_gap(p0: Vector3, p1: Vector3, q0: Vector3, q1: Vector3) -> float:
	var pts := Geometry3D.get_closest_points_between_segments(p0, p1, q0, q1)
	return (pts[0] as Vector3).distance_to(pts[1] as Vector3)


## One clip played through on a standing body (and, for a chain, the next started at this one's
## cancel_ok, as the player does): the worst of each measure.
func _measure(clips: Array, blade_len: float, butt_len := 0.0) -> Dictionary:
	var m := _model()
	for i in 60:
		m.set_locomotion(Vector2.ZERO)
		m._process(DT)
	var out := {"into_torso": 0.0, "hand_into_torso": 0.0, "wrist": 0.0, "edge": 1.0, "hips_move": 0.0,
			"hips_turn": 0.0, "handover_jump": 0.0, "frame_move": 0.0, "into_torso_at": "", "hand_at": "",
			"wrist_at": ""}
	var hips0 := _bone(m, "Hips")
	var yaw0 := m.skeleton.get_bone_global_pose(m.skeleton.find_bone("Hips")).basis.get_euler().y
	var edge_sum := 0.0
	var edge_n := 0
	var moves: Array[float] = []
	for ci in clips.size():
		var clip: String = clips[ci]
		if not m.has_clip(clip):
			continue
		var timing := HumanoidModel.sidecar_timing(clip)
		var ev := {}
		for e in timing.get("events", []):
			ev[str(e["name"])] = float(e["t"])
		var until := float(ev.get("cancel_ok", timing.get("length", 1.0))) if ci < clips.size() - 1 \
				else float(timing.get("length", 1.0))
		var before := _points(m)
		m.play_intent(clip)
		m._process(DT)
		var after := _points(m)
		if ci > 0:
			out["handover_jump"] = maxf(float(out["handover_jump"]), _most_moved(before, after))
		var t := DT
		var last := after
		var tip_last := Vector3.INF
		while t < until:
			m._process(DT)
			t += DT
			var now := _points(m)
			moves.append(_most_moved(last, now))
			last = now
			var b := _blade(m)
			var grip: Vector3 = b[0]
			var dir: Vector3 = b[1]
			var edge_dir: Vector3 = b[2]
			var hips := _bone(m, "Hips")
			var neck := _bone(m, "Neck")
			var hand := _bone(m, "Hand.R")
			# The first clip's cross-fade in from the standing legs is the mixer's pose and not the
			# clip's: a 2H swing's first frames, half blended into the idle, carry a spear's butt
			# 6-8 cm into the chest for two frames. It used to pass because the clip was not moving
			# during the fade (and a clip played a second time did not play at all:
			# test_clips_play_again); the blade, the butt and the hands are held to the clip itself.
			var fading := ci == 0 and t < HumanoidModel.ONE_SHOT_BLEND_IN
			if blade_len > 0.0 and not fading:
				var tip := grip + dir * blade_len
				var gap := segment_gap(grip + dir * 0.12, tip, hips, neck)
				if TORSO_R - gap > float(out["into_torso"]):
					out["into_torso"] = TORSO_R - gap
					out["into_torso_at"] = "%s %.2f s" % [clip, t]
				if t >= float(ev.get("hit_start", 99.0)) and t <= float(ev.get("hit_end", -1.0)):
					out["reach"] = maxf(float(out.get("reach", 0.0)), tip.z - hips0.z)
				if t >= float(ev.get("hit_start", 99.0)) and t <= float(ev.get("hit_end", -1.0)) and tip_last != Vector3.INF:
					var v := tip - tip_last
					if v.length() > 0.004:
						edge_sum += absf(v.normalized().dot(edge_dir))
						edge_n += 1
				tip_last = tip
			# what is behind the grip: a pommel, a haft, a spear's butt (the first 13 cm is the hands)
			if butt_len > 0.13 and not fading:
				var bgap := segment_gap(grip - dir * 0.13, grip - dir * butt_len, hips, neck)
				if TORSO_R - bgap > float(out.get("butt_into_torso", 0.0)):
					out["butt_into_torso"] = TORSO_R - bgap
					out["butt_at"] = "%s %.2f s" % [clip, t]
			for h: Vector3 in ([] if fading else [hand, _bone(m, "Hand.L")]):
				var hgap := segment_gap(h, h, hips, neck)
				if TORSO_R * 0.8 - hgap > float(out["hand_into_torso"]):
					out["hand_into_torso"] = TORSO_R * 0.8 - hgap
					out["hand_at"] = "%s %.2f s" % [clip, t]
			var sk := m.skeleton
			var hi := sk.find_bone("Hand.R")
			# the wrist's bend: how far the hand's own axis turns from its rest line on the forearm
			# (its twist about that axis is the forearm's to make, and is left out)
			var rel := sk.get_bone_rest(hi).basis.get_rotation_quaternion().inverse() * sk.get_bone_pose_rotation(hi)
			var bend := rad_to_deg(Vector3.UP.angle_to(rel * Vector3.UP))
			if bend > float(out["wrist"]):
				out["wrist"] = bend
				out["wrist_at"] = "%s %.2f s" % [clip, t]
			var hv := Vector2(hips.x - hips0.x, hips.z - hips0.z).length()
			out["hips_move"] = maxf(float(out["hips_move"]), hv)
			var yaw := sk.get_bone_global_pose(sk.find_bone("Hips")).basis.get_euler().y
			out["hips_turn"] = maxf(float(out["hips_turn"]), absf(rad_to_deg(wrapf(yaw - yaw0, -PI, PI))))
	moves.sort()
	out["frame_move"] = moves[int(moves.size() * 0.9)] if not moves.is_empty() else 0.0
	out["edge"] = edge_sum / edge_n if edge_n > 0 else -1.0
	after_each()
	return out


## Where the joints that show are: the hands, forearms, head, chest and hips.
func _points(m: HumanoidModel) -> Dictionary:
	var out := {}
	for b in ["Hand.R", "Hand.L", "LowerArm.R", "LowerArm.L", "Head", "Chest", "Hips"]:
		out[b] = _bone(m, b)
	return out


static func _most_moved(a: Dictionary, b: Dictionary) -> float:
	var most := 0.0
	for k in a:
		most = maxf(most, (a[k] as Vector3).distance_to(b[k] as Vector3))
	return most


func test_the_attacks_measured_with_the_weapon_in_the_hand() -> void:
	if not _rig_built():
		return
	var report: Array[String] = []
	var rows := []
	for set_name in CHAINS:
		rows.append([set_name + " chain", CHAINS[set_name], float(BLADE[set_name]), float(BUTT[set_name])])
	for set_name in HEAVIES:
		rows.append([set_name + " heavy", [HEAVIES[set_name]], float(BLADE[set_name]), float(BUTT[set_name])])
	# the crits, thrusts with a sword: held to the same limits but no edge
	for clip in CRITS:
		rows.append([str(clip).to_lower(), [clip], float(BLADE["1H"]), float(BUTT["1H"])])
	for row in rows:
		var got := _measure(row[1], row[2], row[3])
		report.append("%s: blade into the torso %.1f cm, butt %.1f cm, hands %.1f cm, wrist bent %.0f°, edge leads %.2f, hips moved %.1f cm and turned %.0f°, hand-over jump %.1f cm against %.1f cm a frame" % [
				row[0], maxf(float(got["into_torso"]), 0.0) * 100.0, maxf(float(got.get("butt_into_torso", 0.0)), 0.0) * 100.0,
				maxf(float(got["hand_into_torso"]), 0.0) * 100.0,
				float(got["wrist"]), float(got["edge"]), float(got["hips_move"]) * 100.0, float(got["hips_turn"]),
				float(got["handover_jump"]) * 100.0, float(got["frame_move"]) * 100.0])
		report.append("      (worst: blade at %s, hand at %s, wrist at %s)" % [got["into_torso_at"], got["hand_at"], got["wrist_at"]])
		var set_name: String = str(row[0]).get_slice(" ", 0)
		assert_true(float(got["into_torso"]) <= MOST_INTO_TORSO,
				"%s: the blade goes %.1f cm into the torso (at %s)" % [row[0], float(got["into_torso"]) * 100.0, got["into_torso_at"]])
		assert_true(float(got.get("butt_into_torso", 0.0)) <= MOST_INTO_TORSO,
				"%s: the butt end goes %.1f cm into the torso (at %s)" % [row[0], float(got.get("butt_into_torso", 0.0)) * 100.0, got.get("butt_at", "")])
		assert_true(float(got["hand_into_torso"]) <= MOST_INTO_TORSO,
				"%s: a hand goes %.1f cm into the torso (at %s)" % [row[0], float(got["hand_into_torso"]) * 100.0, got["hand_at"]])
		assert_true(float(got["wrist"]) <= MOST_WRIST_DEG,
				"%s: the wrist bends %.0f degrees (at %s)" % [row[0], float(got["wrist"]), got["wrist_at"]])
		if LEAST_EDGE.has(set_name):
			assert_true(float(got["edge"]) >= float(LEAST_EDGE[set_name]),
					"%s: the edge leads only %.2f of the cut" % [row[0], float(got["edge"])])
		if CRITS.has(str(row[1][0])):
			report.append("      (its point reaches %.2f m ahead while it is live)" % float(got.get("reach", 0.0)))
			assert_true(float(got.get("reach", 0.0)) >= CRIT_REACH, "%s's point reaches only %.2f m ahead" % [row[0], float(got.get("reach", 0.0))])
		assert_true(float(got["handover_jump"]) <= MOST_HANDOVER_JUMP,
				"%s: the hand-over jumps %.1f cm" % [row[0], float(got["handover_jump"]) * 100.0])
	print("    %s" % "\n    ".join(report))


## One physics frame at 60 Hz.
const STEP := 1.0 / 60.0


## A greatsword swings the sword's two-handed clips at 0.7 of their pace (WeaponInstance.timing_for),
## and the rig used to be stretched evenly to fit: the whole swing, the blow too, in slow motion. On
## film the greatsword's chop hung overhead for half a second and its blade stood in front of the
## chest for a fifth of one. The timeline is kept (§5.3), but the picture now draws back at the
## weapon's pace, holds a moment at the cocked blade, and strikes at the clip's own pace
## (AnimationDriver.weighty_plan). A charged heavy waits at that cocked blade (`strike`).
func test_a_slow_weapon_holds_its_cocked_blade_and_strikes_at_the_clips_pace() -> void:
	if not _rig_built():
		return
	var report: Array[String] = []
	for row in [["core:item/iron_greatsword", "light", "Attack_2H_Light_1"], ["core:item/reeves_bell_hammer", "heavy", "Attack_2H_Heavy"],
			["core:item/iron_sword", "light", "Attack_1H_Light_1"]]:
		var w := WeaponInstance.new()
		w.configure(ContentDB.get_or_empty(str(row[0])), str(row[0]))
		var timing := w.timing_for(str(row[1]), 0)
		var speed := w.speed
		w.free()
		_root = Node3D.new()
		_tree().root.add_child(_root)
		var pivot := Node3D.new()
		_root.add_child(pivot)
		var d := AnimationDriver.new()
		_root.add_child(d)
		d.setup(pivot, "humanoid", Color.WHITE)
		d.set_physics_process(false)
		var clip: String = row[2]
		var rig_ev := {}
		for e in HumanoidModel.sidecar_timing(clip).get("events", []):
			rig_ev[str(e["name"])] = float(e["t"])
		d.play_intent(clip, timing)
		var ours := float(d.event_times["hit_start"])
		var charge_at := d.timeline_at_rig_event("strike", -1.0)
		var rig_t := 0.0
		var at_full := 0
		var held := 0
		var slowest_moving := INF
		var t := 0.0
		while t < ours - 0.00001:
			var s := d.model_speed()
			rig_t += s * STEP
			if is_equal_approx(s, 1.0):
				at_full += 1
			elif s < 0.5:
				held += 1
			else:
				slowest_moving = minf(slowest_moving, s)
			d._physics_process(STEP)
			t += STEP
		after_each()
		var strike_frames := int((float(rig_ev["hit_start"]) - float(rig_ev["strike"])) / STEP)
		report.append("%s (speed %.2f) %s: the blow at %.3f s on the timeline, the rig's at %.3f s after %.3f s of it; %d frames at the clip's pace, %d held; a charge waits at %.3f s" % [
				Ids.name_of(str(row[0])), speed, clip, ours, float(rig_ev["hit_start"]), rig_t, at_full, held, charge_at])
		assert_near(rig_t, float(rig_ev["hit_start"]), 2.0 * STEP, "%s: the rig's blow is %.3f s off the timeline's" % [clip, rig_t - float(rig_ev["hit_start"])])
		assert_true(charge_at > 0.0 and charge_at < ours - 0.05, "%s: a charge waits at %.3f s, its blow is at %.3f s" % [clip, charge_at, ours])
		if speed < 0.999:
			assert_gt(at_full, strike_frames, "%s: the strike is not played at the clip's own pace" % clip)
			assert_gt(held, 2, "%s: the cocked blade is never held" % clip)
			assert_true(slowest_moving >= AnimationDriver.WEIGHTY_SLOWEST - 0.001, "%s draws back at %.2f of its pace" % [clip, slowest_moving])
		else:
			assert_eq(held, 0, "%s: a swing at its clip's pace is held" % clip)
	print("    %s" % "\n    ".join(report))
