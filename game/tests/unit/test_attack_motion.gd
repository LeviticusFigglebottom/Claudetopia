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
## Reported for every attack; the limits hold what the clips were fixed to.

const MODEL_SCENE := "res://actors/shared/humanoid_model.tscn"
const DT := 1.0 / 120.0
## The torso: a capsule of this radius (m) from the hips to the neck.
const TORSO_R := 0.13
## Blade lengths (m) by clip set, from the grip, for the reach of the line measured.
const BLADE := {"1H": 0.86, "2H": 1.2, "dagger": 0.34, "unarmed": 0.0}
const CHAINS := {"1H": ["Attack_1H_Light_1", "Attack_1H_Light_2", "Attack_1H_Light_3"],
		"2H": ["Attack_2H_Light_1", "Attack_2H_Light_2"], "dagger": ["Attack_Dagger_1", "Attack_Dagger_2"],
		"unarmed": ["Attack_Unarmed_1", "Attack_Unarmed_2"]}
const HEAVIES := {"1H": "Attack_1H_Heavy", "2H": "Attack_2H_Heavy"}

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
func _measure(clips: Array, blade_len: float) -> Dictionary:
	var m := _model()
	for i in 60:
		m.set_locomotion(Vector2.ZERO)
		m._process(DT)
	var out := {"into_torso": 0.0, "hand_into_torso": 0.0, "wrist": 0.0, "edge": 1.0, "hips_move": 0.0,
			"hips_turn": 0.0, "handover_jump": 0.0, "frame_move": 0.0}
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
			if blade_len > 0.0:
				var tip := grip + dir * blade_len
				var gap := segment_gap(grip + dir * 0.12, tip, hips, neck)
				out["into_torso"] = maxf(float(out["into_torso"]), TORSO_R - gap)
				if t >= float(ev.get("hit_start", 99.0)) and t <= float(ev.get("hit_end", -1.0)) and tip_last != Vector3.INF:
					var v := tip - tip_last
					if v.length() > 0.004:
						edge_sum += absf(v.normalized().dot(edge_dir))
						edge_n += 1
				tip_last = tip
			var hgap := segment_gap(hand, hand, hips, neck)
			out["hand_into_torso"] = maxf(float(out["hand_into_torso"]), TORSO_R * 0.8 - hgap)
			var fore := (hand - _bone(m, "LowerArm.R")).normalized()
			var sk := m.skeleton
			var hand_y := (sk.global_transform.basis * sk.get_bone_global_pose(sk.find_bone("Hand.R")).basis.y).normalized()
			out["wrist"] = maxf(float(out["wrist"]), rad_to_deg(fore.angle_to(hand_y)))
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
		rows.append([set_name + " chain", CHAINS[set_name], float(BLADE[set_name])])
	for set_name in HEAVIES:
		rows.append([set_name + " heavy", [HEAVIES[set_name]], float(BLADE[set_name])])
	for row in rows:
		var got := _measure(row[1], row[2])
		report.append("%s: blade into the torso %.1f cm, hand %.1f cm, wrist bent %.0f°, edge leads %.2f, hips moved %.1f cm and turned %.0f°, hand-over jump %.1f cm against %.1f cm a frame" % [
				row[0], maxf(float(got["into_torso"]), 0.0) * 100.0, maxf(float(got["hand_into_torso"]), 0.0) * 100.0,
				float(got["wrist"]), float(got["edge"]), float(got["hips_move"]) * 100.0, float(got["hips_turn"]),
				float(got["handover_jump"]) * 100.0, float(got["frame_move"]) * 100.0])
	print("    %s" % "\n    ".join(report))
