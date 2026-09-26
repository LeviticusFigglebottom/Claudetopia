extends TestCase
## The furniture of the roads and the field walls (world/wayside.gd, world/fingerpost.gd,
## world/road_network.gd): signposts whose arms name the places down the roads they point along,
## gate posts with gates in them, and Skerrow's drystone walls standing as walls rather than as a
## row of stubs with daylight between them.

const HERE := Vector2(1000.0, 1000.0)


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	RoadNetwork.forget()


## A straight road from `a` to `b`, as roads.json has it.
func _road(id: String, a: Vector2, b: Vector2) -> Dictionary:
	var pts := PackedVector2Array()
	for i in range(21):
		pts.append(a.lerp(b, float(i) / 20.0))
	return {"id": id, "points": pts}


## Three roads out of a town at HERE: to Eastby, to Northam and to Southwick, and the town's own
## street across it.
func _junction() -> void:
	var east := HERE + Vector2(900.0, 0.0)
	var north := HERE + Vector2(0.0, -700.0)
	var south := HERE + Vector2(100.0, 800.0)
	RoadNetwork.use([
		_road("core:road/here_eastby", HERE, east),
		_road("core:road/northam_here", north, HERE),
		_road("core:road/here_southwick", HERE, south),
		_road("core:road/here_street", HERE + Vector2(-60.0, -60.0), HERE + Vector2(60.0, 60.0)),
	], [
		{"id": "core:place/here", "name": "Here", "at": HERE},
		{"id": "core:place/eastby", "name": "Eastby", "at": east},
		{"id": "core:place/northam", "name": "Northam", "at": north},
		{"id": "core:place/southwick", "name": "Southwick", "at": south},
	])


# --- fingerposts ------------------------------------------------------------------------------------

func test_a_fingerpost_names_the_places_down_its_roads() -> void:
	_junction()
	var ways := RoadNetwork.destinations(HERE + Vector2(9.0, 6.0))
	var names: Array[String] = []
	for w in ways:
		names.append(str(w["name"]))
	names.sort()
	assert_eq(names, ["Eastby", "Northam", "Southwick"] as Array[String], "the arms say %s" % [names])
	for w in ways:
		var dir: Vector2 = w["dir"]
		match str(w["name"]):
			"Eastby":
				assert_gt(dir.dot(Vector2.RIGHT), 0.95, "the Eastby arm points %s" % dir)
			"Northam":
				assert_gt(dir.dot(Vector2(0.0, -1.0)), 0.95, "the Northam arm points %s" % dir)


func test_a_town_s_own_street_and_its_own_name_are_not_ways_out() -> void:
	_junction()
	for w in RoadNetwork.destinations(HERE + Vector2(9.0, 6.0)):
		assert_ne(str(w["name"]), "Here", "a fingerpost in the square pointing at the square")


func test_on_the_road_a_post_points_both_ways() -> void:
	_junction()
	var ways := RoadNetwork.destinations(HERE + Vector2(450.0, 3.0))
	var names: Array[String] = []
	for w in ways:
		names.append(str(w["name"]))
	names.sort()
	assert_eq(names, ["Eastby", "Here"] as Array[String], "half way to Eastby the post says %s" % [names])


func test_a_distance_is_cut_in_quarter_miles() -> void:
	assert_eq(RoadNetwork.miles(50.0), "¼", "never less than a quarter")
	assert_eq(RoadNetwork.miles(800.0), "½")
	assert_eq(RoadNetwork.miles(1609.0), "1")
	assert_eq(RoadNetwork.miles(2000.0), "1¼")
	assert_eq(RoadNetwork.miles(3620.0), "2¼")


func test_an_arm_says_its_place_and_how_far() -> void:
	_junction()
	for w in RoadNetwork.destinations(HERE + Vector2(9.0, 6.0)):
		if str(w["name"]) == "Eastby":
			# 900 m to Eastby from the square, less the few metres the post stands off it
			assert_eq(Fingerpost._says(w), "Eastby  ½")


func test_a_road_to_a_point_of_interest_is_signed_to_it() -> void:
	# the roads to the Three Sisters and the Narrows Bridge end at points of interest, which are
	# places a road goes to as much as a town is
	var falls := HERE + Vector2(0.0, 900.0)
	RoadNetwork.use([_road("core:road/here_falls", HERE, falls)], [
		{"id": "core:place/here", "name": "Here", "at": HERE},
		{"id": "core:poi/the_falls", "name": "The Falls", "at": falls},
	])
	var names: Array[String] = []
	for w in RoadNetwork.destinations(HERE + Vector2(3.0, 450.0)):
		names.append(str(w["name"]))
	names.sort()
	assert_eq(names, ["Here", "The Falls"] as Array[String])


func test_a_fingerpost_is_built_with_an_arm_and_a_name_for_each_way() -> void:
	_junction()
	var host := Node3D.new()
	_tree().root.add_child(host)
	var post := Fingerpost.new()
	post.position = Vector3(HERE.x + 9.0, 0.0, HERE.y + 6.0)
	host.add_child(post)
	assert_eq(post.names().size(), 3)
	var labels := post.find_children("*", "Label3D", false, false)
	assert_eq(labels.size(), 6, "two faces an arm, each with its place's name")
	for l in labels:
		# the place, and how far along the road it is ("Eastby  ½")
		var said := str((l as Label3D).text)
		assert_true(said.get_slice("  ", 0) in ["Eastby", "Northam", "Southwick"], "an arm says %s" % said)
		assert_ne(said.get_slice("  ", 1), "", "an arm with no distance: %s" % said)
	assert_true(post.get_node_or_null("Timber") is MeshInstance3D, "a post with no timber")
	host.free()


func test_the_forge_signpost_gives_way_to_a_fingerpost() -> void:
	_junction()
	var cell := Node3D.new()
	cell.position = Vector3(HERE.x, 0.0, HERE.y)
	_tree().root.add_child(cell)
	var post := "res://assets/models/props/hearthvale_signpost_a/hearthvale_signpost_a.glb"
	var oak := "res://assets/models/trees/hearthvale_oak/hearthvale_oak.glb"
	var out := Wayside.prepare({post: [[HERE.x + 9.0, 0.0, HERE.y + 6.0, 81.0, 1.0, "#ffffff"]],
			oak: [[HERE.x + 30.0, 0.0, HERE.y, 0.0, 1.0, "#ffffff"]]}, cell, true)
	assert_false(out.has(post), "the nameless signpost is still drawn")
	assert_true(out.has(oak), "the rest of the scatter went with it")
	assert_eq(cell.find_children("*", "Fingerpost", false, false).size(), 1)
	var far := Wayside.prepare({post: [[HERE.x + 9.0, 0.0, HERE.y + 6.0, 81.0, 1.0, "#ffffff"]]}, cell, false)
	assert_false(far.has(post), "the far ring draws no signpost either")
	cell.free()


# --- gates ------------------------------------------------------------------------------------------

## A run of hedge along +x from a metre past the post: the gap, and the gate, are toward -x.
func _hedge_east_of(at: Vector2, yaw := 0.0) -> Array:
	var rows: Array = []
	for i in range(5):
		rows.append([at.x + 1.3 + 2.2 * float(i), 0.0, at.y, yaw, 1.0, "#ffffff"])
	return rows


func test_a_gate_hangs_across_the_gap_along_the_hedge() -> void:
	var at := Vector2(10.0, 20.0)
	assert_eq(Wayside.gate_line(at, _hedge_east_of(at)), Vector2(-1.0, 0.0), "the gate hangs into the hedge")
	# the same hedge laid the other way round (yaw 180) is the same line
	var back := Wayside.gate_line(at, _hedge_east_of(at, 180.0))
	assert_near(back.x, -1.0, 0.001)
	assert_eq(Wayside.gate_line(at, [[60.0, 0.0, 60.0, 0.0, 1.0, "#ffffff"]]), Vector2.ZERO,
			"a post in no hedge got a gate")


func test_a_cell_s_gates_are_one_mesh() -> void:
	var cell := Node3D.new()
	_tree().root.add_child(cell)
	var hedge := "res://assets/models/props/hearthvale_hedge_segment_a/hearthvale_hedge_segment_a.glb"
	var post := "res://assets/models/props/hearthvale_gate_post_a/hearthvale_gate_post_a.glb"
	var a := Vector2(10.0, 20.0)
	var b := Vector2(80.0, 20.0)
	var rows := _hedge_east_of(a) + _hedge_east_of(b)
	var out := Wayside.prepare({hedge: rows, post: [[a.x, 0.0, a.y, 33.0, 1.0, "#ffffff"], [b.x, 0.0, b.y, 12.0, 1.0, "#ffffff"]]}, cell, true)
	assert_true(out.has(post), "the gate post itself is still drawn")
	assert_true(out.has(hedge))
	var gates := cell.get_node_or_null("Gates") as MeshInstance3D
	assert_true(gates != null, "two gate posts and no gate")
	assert_gt(int(gates.mesh.get_faces().size() / 3.0), 2 * 8 * 12 - 1, "two gates of stiles, bars and a brace")
	cell.free()


# --- drystone walls ---------------------------------------------------------------------------------

const WALL_A := "res://assets/models/props/skerrow_drystone_wall_a/skerrow_drystone_wall_a.glb"
const WALL_END := "res://assets/models/props/skerrow_drystone_wall_end_a/skerrow_drystone_wall_end_a.glb"


## A boundary along +x laid the way the build laid Skerrow's: a piece every 2.4 m (and one 4 m
## gap), every third piece a wall *end*, each scaled at random.
func _run() -> Dictionary:
	var walls: Array = []
	var ends: Array = []
	var x := 0.0
	for i in range(12):
		var s: float = [0.88, 1.18, 1.0, 0.92][i % 4]
		var row := [x, 0.0, 5.0, 0.0, s, "#ffffff"]
		if i % 3 == 2 and i < 11:
			ends.append(row)
		else:
			walls.append(row)
		x += 4.0 if i == 6 else 2.4
	# and a real end, finishing the run at the shoulder of a gap: wall on one side of it only
	ends.append([x, 0.0, 5.0, 0.0, 1.0, "#ffffff"])
	return {WALL_A: walls, WALL_END: ends}


func test_a_drystone_run_is_a_wall_and_not_a_row_of_stubs() -> void:
	var cell := Node3D.new()
	var out := Wayside.prepare(_run(), cell, false)
	var walls: Array = out.get(WALL_A, [])
	assert_eq(walls.size(), 12, "the end pieces standing in the run were not turned into wall")
	# every piece reaches the next: no daylight along the run
	walls.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i in range(walls.size() - 1):
		var a: Array = walls[i]
		var b: Array = walls[i + 1]
		var reach_a := Wayside.WALL_MODULE_M * float((a[8] as Array)[0]) * 0.5
		var reach_b := Wayside.WALL_MODULE_M * float((b[8] as Array)[0]) * 0.5
		assert_true(float(a[0]) + reach_a >= float(b[0]) - reach_b - 0.01,
				"a gap in the wall between %.1f and %.1f" % [float(a[0]), float(b[0])])
		# and a steady height
		assert_near(float((a[8] as Array)[1]), 1.0, 0.06, "a wall stepping up and down")
	cell.free()


func test_an_end_at_the_shoulder_of_a_gap_stays_an_end() -> void:
	var cell := Node3D.new()
	var out := Wayside.prepare(_run(), cell, false)
	var ends: Array = out.get(WALL_END, [])
	assert_eq(ends.size(), 1, "the end at the gap became wall, or the stubs stayed stubs")
	cell.free()


func test_a_row_can_be_scaled_in_its_own_axes() -> void:
	var xf := WorldStreamer.instance_transform([10.0, 2.0, 30.0, 90.0, 1.3, "#ffffff", 0.0, 0.0, [1.6, 1.0, 1.0]], Vector3.ZERO)
	assert_near(xf.basis.x.length(), 1.6, 0.001, "stretched along its own length")
	assert_near(xf.basis.y.length(), 1.0, 0.001, "and not taller for it")
	var plain := WorldStreamer.instance_transform([10.0, 2.0, 30.0, 90.0, 1.3, "#ffffff"], Vector3.ZERO)
	assert_near(plain.basis.y.length(), 1.3, 0.001, "a plain row keeps its uniform scale")


## A boundary on the diagonal came out of the build two texels thick, and a wall was laid along
## each: two walls a few metres apart where a field has one. One of them gives way.
func test_a_wall_laid_twice_along_a_diagonal_is_one_wall() -> void:
	var t := Vector2(1.0, 1.0).normalized()
	var across := Vector2(-t.y, t.x)
	var yaw := rad_to_deg(atan2(-t.y, t.x))
	var rows: Array = []
	for i in range(6):
		var p := t * (2.6 * float(i))
		rows.append([p.x, 0.0, p.y, yaw, 1.0, "#ffffff"])
		var q := p + across * 3.6
		# the twin laid the other way round, as the build's gradient sign left it
		rows.append([q.x, 0.0, q.y, yaw + 180.0, 1.0, "#ffffff"])
	var cell := Node3D.new()
	var out := Wayside.prepare({WALL_A: rows}, cell, false)
	var kept: Array = out.get(WALL_A, [])
	assert_eq(kept.size(), 6, "the doubled wall came out as %d pieces" % kept.size())
	var lines := {}
	for r in kept:
		lines[snappedf(Vector2(float(r[0]), float(r[2])).dot(across), 0.5)] = true
	assert_eq(lines.size(), 1, "both walls of the pair are still standing")
	cell.free()


## CONTRACTS §6: the seventh and eighth fields are the builder's lean, and a stretched piece's
## scale in its own axes is the ninth, so neither is read as the other.
func test_a_rows_lean_and_its_stretch_are_fields_of_their_own() -> void:
	var stretched := WorldStreamer.instance_transform([0.0, 0.0, 0.0, 0.0, 1.0, "#ffffff", 0.0, 0.0, [1.6, 1.0, 1.0]], Vector3.ZERO)
	assert_near(stretched.basis.x.length(), 1.6, 0.001, "the ninth field stretches the piece along its own x")
	assert_near(stretched.basis.y.length(), 1.0, 0.001, "and leaves its height")
	assert_near(stretched.basis.y.normalized().y, 1.0, 0.001, "and a zero lean stands it upright")
	var leaning := WorldStreamer.instance_transform([0.0, 0.0, 0.0, 0.0, 1.0, "#ffffff", 20.0, 0.0], Vector3.ZERO)
	assert_near(rad_to_deg(acos(leaning.basis.y.normalized().y)), 20.0, 0.1, "a leaning tree leans its twenty degrees")
	assert_gt(leaning.basis.y.x, 0.0, "toward +x, where 0 degrees points")
	var plain := WorldStreamer.instance_transform([0.0, 0.0, 0.0, 0.0, 1.3], Vector3.ZERO)
	assert_near(plain.basis.x.length(), 1.3, 0.001, "a short row keeps its uniform scale")


## Playtest 4: a road's post-and-rail had its rails nowhere near its poles. The build's modules are
## gathered into runs and built post to post: every rail's two ends sit on a post (within 5 cm, at
## the post's own ground height plus the rail's), and the posts keep one line though each module
## stood its own distance off the road.
func test_a_roadside_rail_runs_post_to_post() -> void:
	var rows: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# a frontage along +x, a module every 2.35 m, each 3.2 to 4.0 m off the road and a little turned,
	# on ground that rises
	for i in 12:
		var x := 100.0 + float(i) * 2.35
		rows.append([x, 20.0 + float(i) * 0.15, 50.0 + rng.randf_range(3.2, 4.0), rng.randf_range(-3.0, 3.0), 1.0])
	# and a second run, on the other side, well away
	for i in 5:
		rows.append([100.0 + float(i) * 2.35, 20.0, 30.0 - 3.6, 180.0, 1.0])
	var runs := Wayside.rail_runs(rows)
	assert_eq(runs.size(), 2, "two runs, one each side of the road")
	for run in runs:
		var posts: Array = run
		for i in range(posts.size() - 1):
			var p0: Vector3 = posts[i]
			var p1: Vector3 = posts[i + 1]
			assert_true(Vector2(p1.x - p0.x, p1.z - p0.z).length() < 3.0, "posts a module apart")
			for seg in Wayside.rail_segments(p0, p1):
				var a: Vector3 = seg[0]
				var b: Vector3 = seg[1]
				assert_true(Vector2(a.x - p0.x, a.z - p0.z).length() < 0.05 and Vector2(b.x - p1.x, b.z - p1.z).length() < 0.05,
						"a rail's ends sit on its two posts")
				assert_true(a.y - p0.y > 0.3 and a.y - p0.y < RAIL_TOP and b.y - p1.y > 0.3 and b.y - p1.y < RAIL_TOP,
						"at the posts' own height over their ground")
		# one line: no post more than a few centimetres further off the road than its neighbours
		for i in range(1, posts.size() - 1):
			var mid := ((posts[i - 1] as Vector3) + (posts[i + 1] as Vector3)) * 0.5
			assert_true(absf((posts[i] as Vector3).z - mid.z) < 0.35, "the run keeps its line at post %d" % i)


## The seat audit on w4096d: a frontage round a bend was put out of order (sorted along its first
## module's line), and its rails spanned the bend's chord up to 4.6 m in the air. Round a half
## circle every post is a module from the next, in order.
func test_a_rail_run_round_a_bend_is_in_order() -> void:
	var rows: Array = []
	var r := 30.0
	var n := int(PI * r / 2.35)
	for i in n + 1:
		var a := PI * float(i) / float(n)
		var x := 200.0 + cos(a) * r
		var z := 80.0 + sin(a) * r
		# the module lies along the circle: its +X along the tangent (-sin a, cos a)
		var yaw := rad_to_deg(atan2(-cos(a), -sin(a)))
		rows.append([x, 10.0, z, yaw, 1.0])
	rows.shuffle()
	var runs := Wayside.rail_runs(rows)
	assert_eq(runs.size(), 1, "one run round the bend")
	var posts: Array = runs[0]
	for i in range(1, posts.size() - 2):
		var p0: Vector3 = posts[i]
		var p1: Vector3 = posts[i + 1]
		assert_true(Vector2(p1.x - p0.x, p1.z - p0.z).length() < 3.0, "post %d is a module from the next" % i)


const RAIL_TOP := 1.25


## A frontage run that comes onto a carriageway stops at its edge, each piece ending at a post, and
## a run too short to be a fence (a module the rest of its run was lost from) is left out: the
## playtest's roadside fences "randomly placed, missing, clipping".
func test_a_rail_run_stops_at_a_carriageway_and_no_lone_length_stands() -> void:
	var pts := PackedVector2Array([Vector2(110.0, 0.0), Vector2(110.0, 200.0)])
	RoadNetwork.use([{"id": "core:road/crossing", "points": pts, "width": 5.0}])
	var rows: Array = []
	# a run along +x at z 50, crossing the road at x 110
	for i in 16:
		rows.append([100.0 + float(i) * 2.35, 20.0, 50.0, 0.0, 1.0])
	# and a lone module well away
	rows.append([200.0, 20.0, 80.0, 0.0, 1.0])
	var runs := Wayside.off_the_road(Wayside.rail_runs(rows))
	assert_eq(runs.size(), 2, "the run either side of the road, and no lone length")
	for run in runs:
		var posts: Array = run
		assert_true(posts.size() >= Wayside.MIN_RUN_POSTS, "a fence of several posts")
		for p_v in posts:
			var p: Vector3 = p_v
			assert_true(RoadNetwork.edge_distance(Vector2(p.x, p.z)) >= Wayside.ROAD_CLEAR_M, "no post on the carriageway (%.1f)" % p.x)
