extends TestCase
## A tent is an A: two sheets of canvas from a ridge down to the ground, with its mouth in front.
##
## The playtest's second report on the new start was the Wardens' tents at the Stair Head,
## "nonsensical models (inverted tent edges)". The forge had made each side's sheet at the middle of
## its slope, moved it there a second time and tilted it a right angle off, so the two sheets stood
## out over the ridge pole like a pair of wings, pale in the sun, and never reached the ground. It had
## also built the tent along its X axis with the mouth at one end, where a prop's front is +Z
## (docs/CONTRACTS.md §1): every camp turns a tent's front to its fire with a bedroll in the mouth, and
## got it side-on. Every camp takes its tents from the same models (PoiKit.prop("tent") answers any
## region's), so every camp had both. This reads the built models the way the game loads them.

const PROPS := "res://assets/models/props"
## How far outside the A (as a share of the tent's height and half-width) anything may stand: the
## canvas is thick, sags, and overlaps its ridge by a little, and the poles stand a hand above it.
const SLACK := 0.12


func _tents() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(PROPS)
	if dir == null:
		return out
	for sub in dir.get_directories():
		if sub.contains("_tent_"):
			var glb := "%s/%s/%s.glb" % [PROPS, sub, sub]
			if ResourceLoader.exists(glb):
				out.append(glb)
	return out


## Every triangle of every mesh in the model, three corners each, in the model's own space.
func _faces(glb: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	var scene := load(glb) as PackedScene
	if scene == null:
		return out
	var root := scene.instantiate() as Node3D
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var to_root := Transform3D.IDENTITY
		var up: Node = mi
		while up != null and up != root:
			if up is Node3D:
				to_root = (up as Node3D).transform * to_root
			up = up.get_parent()
		for p in mi.mesh.get_faces():
			out.append(to_root * p)
	root.free()
	return out


func test_every_tent_is_canvas_from_its_ridge_to_the_ground() -> void:
	var tents := _tents()
	if tents.is_empty():
		return  # the forge has not landed in this checkout
	for glb in tents:
		var pts := _faces(glb)
		assert_gt(pts.size(), 30, "%s has a mesh to look at" % glb.get_file())
		if pts.size() <= 30:
			continue
		var top := 0.0
		var half := 0.0
		for p in pts:
			top = maxf(top, p.y)
			half = maxf(half, absf(p.x))
		# the A, across the tent (its x): a point of the canvas is as far below the top as it is out
		# from the ridge, and nothing stands outside that
		var worst := 0.0
		var worst_at := Vector3.ZERO
		for p in pts:
			var outside := absf(p.x) / half + p.y / top - 1.0
			if outside > worst:
				worst = outside
				worst_at = p
		assert_gt(SLACK, worst, "%s: nothing stands out over the ridge (worst at %s, %.0f%% outside the A)"
				% [glb.get_file(), worst_at, worst * 100.0])
		# the widest of it is at the ground, and the highest of it is over the middle
		var widest_high := 0.0
		var highest_wide := 0.0
		for p in pts:
			if absf(p.x) > 0.8 * half:
				widest_high = maxf(widest_high, p.y)
			if p.y > 0.8 * top:
				highest_wide = maxf(highest_wide, absf(p.x))
		assert_gt(0.25 * top, widest_high, "%s: its sides come down to the ground (the widest of it stands %.2f m up, of %.2f m)"
				% [glb.get_file(), widest_high, top])
		assert_gt(0.25 * half, highest_wide, "%s: its top is its ridge (the highest of it is %.2f m out, of %.2f m)"
				% [glb.get_file(), highest_wide, half])


func test_every_tent_has_its_mouth_in_front() -> void:
	var tents := _tents()
	if tents.is_empty():
		return
	for glb in tents:
		var tris := _faces(glb)
		# canvas facing along the tent's length: the closed end behind (-Z), nothing in front (+Z)
		# but the pole and the lines, which are thin
		var behind := 0.0
		var in_front := 0.0
		for i in range(0, tris.size() - 2, 3):
			var a := tris[i]
			var b := tris[i + 1]
			var c := tris[i + 2]
			var cross := (b - a).cross(c - a)
			var area := cross.length() * 0.5
			if area < 1e-6 or absf(cross.normalized().z) < 0.9:
				continue
			if (a.z + b.z + c.z) < 0.0:
				behind += area
			else:
				in_front += area
		assert_gt(behind, 0.5, "%s: its closed end is behind it, -Z (%.2f m² of canvas across its length there)"
				% [glb.get_file(), behind])
		assert_gt(behind * 0.25, in_front, "%s: and its mouth is open in front, +Z, where a camp turns it to the fire (%.2f m² across it there)"
				% [glb.get_file(), in_front])
