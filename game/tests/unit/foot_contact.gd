extends RefCounted
## Where a foot bears on the ground, for the tests that measure feet sliding.
##
## Each foot bears on its heel and on its ball, the points the forge turns it about
## (ClipBuilder.ankle_target): the heel on the ground 6 cm behind the ankle, and the ball at the
## toe joint. A foot rolling about its heel or its ball keeps that point still, so only a foot
## that slides moves a point that is down. A point is down within 1 cm of the height it stands at.

const HEEL_BACK := 0.06
const DOWN_WITHIN := 0.01


## The heel and the ball of each foot of `sk`, in the world, the skeleton placed by `xf` (its
## global transform): {"L_heel": Vector3, "L_ball": ..., "R_heel": ..., "R_ball": ...}.
static func soles(sk: Skeleton3D, xf: Transform3D) -> Dictionary:
	var out := {}
	for side in ["L", "R"]:
		var foot := sk.find_bone("Foot." + side)
		var rest := sk.get_bone_global_rest(foot)
		var heel := rest.affine_inverse() * Vector3(rest.origin.x, 0.0, rest.origin.z - HEEL_BACK)
		out[side + "_heel"] = xf * (sk.get_bone_global_pose(foot) * heel)
		out[side + "_ball"] = xf * sk.get_bone_global_pose(sk.find_bone("Toe." + side)).origin
	return out


## How many feet of `s` (a soles()) have a point down on ground at height `ground_y`.
static func feet_down(sk: Skeleton3D, ground_y: float, s: Dictionary) -> int:
	var ball_height := sk.get_bone_global_rest(sk.find_bone("Toe.L")).origin.y
	var n := 0
	for side in ["L", "R"]:
		var heel: Vector3 = s[side + "_heel"]
		var ball: Vector3 = s[side + "_ball"]
		if heel.y < ground_y + DOWN_WITHIN or ball.y < ground_y + ball_height + DOWN_WITHIN:
			n += 1
	return n


## The most (m) any point of the feet moved between `a` and `b` (two soles()), down or not.
static func most_moved(a: Dictionary, b: Dictionary) -> float:
	var most := 0.0
	for key in a:
		most = maxf(most, (a[key] as Vector3).distance_to(b[key] as Vector3))
	return most


## How far (m, along the ground) the points that were down in both `a` and `b` (two soles())
## slid between them, on ground at height `ground_y`.
static func slid(sk: Skeleton3D, ground_y: float, a: Dictionary, b: Dictionary) -> float:
	var ball_height := sk.get_bone_global_rest(sk.find_bone("Toe.L")).origin.y
	var d := 0.0
	for key in a:
		var p: Vector3 = a[key]
		var q: Vector3 = b[key]
		var stands := ground_y + (ball_height if str(key).ends_with("ball") else 0.0) + DOWN_WITHIN
		if p.y < stands and q.y < stands:
			d += Vector2(q.x - p.x, q.z - p.z).length()
	return d
