extends TestCase
## The Sunken Choir's colossi are solid as they are drawn (TRIAGE 75: "its spires have no
## collision"). The forge's collision was a cone round the robe alone, so the ash banked against
## each figure, the stone broken off round its foot, b's snapped forearm and c's fallen drums were
## walked through. The streamer now gives a colossus its own coarsest level as a trimesh
## (WorldStreamer.COLLIDES_AS_DRAWN). Each of the three figures is stood up the way a cell stands
## it (WorldStreamer._build_scene), and rays are cast at it from all round, at a body's heights
## and from above over the rubble: where a ray meets the drawn stone it meets the collision within
## a hand of the stone's surface, and where it misses the stone it meets nothing (no invisible wall).

const MODELS := [
	"res://assets/models/landmarks/cinderlea_choir_colossus_a/cinderlea_choir_colossus_a.glb",
	"res://assets/models/landmarks/cinderlea_choir_colossus_b/cinderlea_choir_colossus_b.glb",
	"res://assets/models/landmarks/cinderlea_choir_colossus_c/cinderlea_choir_colossus_c.glb",
]
## How far the collision may stand off the drawn surface along a ray (the coarsest level is the
## finest decimated: its faces are a metre or two across on a sixty-metre figure).
const NEAR_M := 0.6


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func test_a_colossus_collides_where_it_is_drawn() -> void:
	var streamer := WorldStreamer.new()
	var parent := Node3D.new()
	_tree().root.add_child(parent)
	var x := 0.0
	var stood: Array = []
	for path: String in MODELS:
		if not ResourceLoader.exists(path):
			continue
		assert_true(WorldStreamer.collides_as_drawn(path), "%s collides as drawn" % path.get_file())
		var before := parent.get_child_count()
		streamer._build_scene(parent, {"scene": path, "pos": [x, 0.0, 0.0], "yaw": 0.0,
				"collision": path.replace(".glb", "_col.glb")})
		if parent.get_child_count() > before:
			stood.append([path, parent.get_child(parent.get_child_count() - 1), x])
		x += 200.0
	await _tree().physics_frame
	await _tree().physics_frame
	var space := parent.get_world_3d().direct_space_state
	assert_eq(stood.size(), MODELS.size(), "every figure stands")
	for s in stood:
		var inst: Node3D = s[1]
		var cx: float = s[2]
		var name := (s[0] as String).get_file().get_basename()
		var body := inst.get_node_or_null("Collision")
		assert_true(body != null, "%s has a static body" % name)
		# the drawn surface: the finest level, as triangles in the world
		var faces := PackedVector3Array()
		for mi_v in inst.find_children("*", "MeshInstance3D", true, false):
			var mi := mi_v as MeshInstance3D
			if LandmarkLod.level_of(mi.name) == 0 and mi.mesh != null:
				var xf := mi.global_transform
				for v in mi.mesh.get_faces():
					faces.append(xf * v)
		var drawn := TriangleMesh.new()
		assert_true(drawn.create_from_faces(faces), "%s's drawn surface is read" % name)
		var hits := 0
		var far := 0
		var walls := 0
		var rays := 0
		# round it, at a body's heights over the ash line and up the robe
		for y in [0.4, 1.0, 1.8, 4.0, 12.0]:
			for i in 36:
				var a := TAU * float(i) / 36.0
				var from := Vector3(cx + sin(a) * 60.0, y, cos(a) * 60.0)
				var to := Vector3(cx, y, 0.0)
				var r := _compare(space, drawn, from, to)
				rays += 1
				hits += int(r == 1)
				far += int(r == 2)
				walls += int(r == 3)
		# down onto the ash bank and the rubble round the foot
		var rng := RandomNumberGenerator.new()
		rng.seed = 75
		for i in 160:
			var a := rng.randf() * TAU
			var rr := rng.randf_range(6.0, 22.0)
			var at := Vector3(cx + sin(a) * rr, 0.0, cos(a) * rr)
			var r := _compare(space, drawn, at + Vector3(0.0, 80.0, 0.0), at + Vector3(0.0, -6.0, 0.0))
			rays += 1
			hits += int(r == 1)
			far += int(r == 2)
			walls += int(r == 3)
		print("CHOIR %s: %d rays, %d meet the stone and the collision together, %d too far apart, %d invisible walls" % [name, rays, hits, far, walls])
		assert_true(hits > 60, "%s: the rays meet it (%d)" % [name, hits])
		assert_true(far <= rays / 50, "%s: the collision follows the drawn stone (%d of %d off by more than %.1f m)" % [name, far, rays, NEAR_M])
		assert_true(walls <= rays / 100, "%s: nothing solid where nothing is drawn (%d)" % [name, walls])
	parent.queue_free()
	streamer.free()
	await _tree().process_frame


## 0 both miss, 1 both meet within NEAR_M, 2 both meet further apart or the stone is met and the
## collision is not, 3 the collision is met where no stone is drawn.
func _compare(space: PhysicsDirectSpaceState3D, drawn: TriangleMesh, from: Vector3, to: Vector3) -> int:
	var seen: Dictionary = drawn.intersect_segment(from, to)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var hit := space.intersect_ray(q)
	if seen.is_empty() and hit.is_empty():
		return 0
	if hit.is_empty():
		return 2
	var at: Vector3 = hit["position"]
	if seen.is_empty():
		# a coarse face may stand a hand proud of a fine one at a silhouette's edge
		return 3 if _nearest_on(drawn, at) > NEAR_M else 1
	# how far the collision met stands off the drawn stone, square to it: a ray grazing the ash
	# banked at a figure's foot meets the two a metre or two apart along it where they are a hand
	# apart in height
	return 1 if _nearest_on(drawn, at) <= NEAR_M else 2


## Roughly how far `p` is from the drawn surface: the nearest of twenty-six short rays through it
## (the axes, the face diagonals and the corners).
func _nearest_on(drawn: TriangleMesh, p: Vector3) -> float:
	var best := INF
	for x in [-1, 0, 1]:
		for y in [-1, 0, 1]:
			for z in [-1, 0, 1]:
				if x == 0 and y == 0 and z == 0:
					continue
				var d := Vector3(x, y, z).normalized()
				var h: Dictionary = drawn.intersect_segment(p - d * 2.0, p + d * 2.0)
				if not h.is_empty():
					best = minf(best, p.distance_to(h["position"] as Vector3))
	return best
