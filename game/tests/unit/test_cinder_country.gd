extends TestCase
## The ash country's vents and ground laid at runtime (world/cinder_country.gd, TRIAGE item 60): the
## same plan every time a cell streams in; every vent, crack, pool, shard, stand, stone, pillar and
## cairn on dry Cinderlea ground, off the roads and the pads, and the vents in hollows or on the
## flat; sensible numbers over the whole region (vents in a minority of cells, at most two a cell);
## the meshes near only, the far ring its glow; the lights NightLights' pool's; and one hiss that
## is started once and never restarted while the camera stands by a vent.

const GENERATED := "res://world/generated"

var provider: TerrainProvider = null
## The plans, kept across the file's tests (a plan is its cell's alone)
static var _plans: Dictionary = {}
var _holders: Array = []


func before_each() -> void:
	if not FileAccess.file_exists("%s/pois.json" % GENERATED):
		return
	provider = TerrainProvider.new()
	provider.load_data()
	if _plans.is_empty():
		RoadNetwork.forget()
		CinderCountry.forget_pads()


func after_each() -> void:
	for h in _holders:
		if h != null and is_instance_valid(h):
			(h as Node).free()
	_holders.clear()
	if provider != null and is_instance_valid(provider):
		provider.free()
	provider = null


func _le(a: Variant, b: Variant, msg := "") -> void:
	assert_true(a <= b, "%s (%s > %s)" % [msg, a, b])


func _between(a: Variant, lo: Variant, hi: Variant, msg := "") -> void:
	assert_true(a >= lo and a <= hi, "%s (%s not in %s..%s)" % [msg, a, lo, hi])


func _not_null(a: Variant, msg := "") -> void:
	assert_true(a != null, msg)


func _ready_or_skip() -> bool:
	if provider == null or not provider.has_runtime_maps():
		skip("world data missing: run ./run.sh world")
		return false
	return true


## Every cell with any Cinderlea ground in it.
func _cells() -> Array:
	var out: Array = []
	var size := float(provider.manifest.get("cell_size_m", 256))
	var n := int(provider.size_m / size)
	for cz in n:
		for cx in n:
			var lo := provider.origin + Vector2(cx, cz) * size
			var here := false
			for k in 16:
				var p := lo + Vector2((float(k % 4) + 0.5) * size / 4.0, (float(k / 4) + 0.5) * size / 4.0)
				if provider.region_id_at(p.x, p.y) == CinderCountry.REGION:
					here = true
					break
			if here:
				out.append(Vector2i(cx, cz))
	return out


func _plan(cell: Vector2i) -> Dictionary:
	if not _plans.has(cell):
		_plans[cell] = CinderCountry.plan(cell, provider, float(provider.manifest.get("cell_size_m", 256)))
	return _plans[cell]


func test_a_cell_is_planned_the_same_every_time() -> void:
	if not _ready_or_skip():
		return
	for cell in _cells().slice(0, 40):
		var a := CinderCountry.plan(cell, provider, 256.0)
		var b := CinderCountry.plan(cell, provider, 256.0)
		assert_eq(var_to_str(a), var_to_str(b), "cell %s planned twice the same" % cell)


func test_the_vents_are_in_a_minority_of_the_region_and_budgeted() -> void:
	if not _ready_or_skip():
		return
	var cells := _cells()
	assert_gt(cells.size(), 60, "Cinderlea spans many cells")
	var with_cracks := 0
	var vent_total := 0
	var kinds := {}
	for cell in cells:
		var p := _plan(cell)
		if not (p["cracks"] as Array).is_empty():
			with_cracks += 1
		vent_total += (p["vents"] as Array).size()
		_le((p["vents"] as Array).size(), 2, "at most two vents in cell %s" % cell)
		_le((p["pools"] as Array).size(), 3, "a vent's mouth each and one pool, cell %s" % cell)
		_le((p["cracks"] as Array).size(), 160, "cracks in cell %s within a mesh's worth" % cell)
		for s in p["sites"]:
			kinds[s[1]] = int(kinds.get(s[1], 0)) + 1
	var share := float(with_cracks) / float(cells.size())
	_between(share, 0.12, 0.7, "cracks in some of the region's cells, not all (%.2f)" % share)
	_between(vent_total, 15, 260, "vents region-wide, not everywhere (%d)" % vent_total)
	for kind in ["cluster", "crack", "vent", "pool", "shards", "drift", "stand", "stone", "pillar", "cairn"]:
		assert_gt(int(kinds.get(kind, 0)), 0, "the region has a %s somewhere (%s)" % [kind, kinds])
	print("  cinder country over %d cells: %s, %d vents; plans %s" % [cells.size(), kinds, vent_total, CinderCountry.stats])
	for cell in cells:
		var p := _plan(cell)
		if (p["vents"] as Array).size() >= 2:
			var at: Array = []
			for v in p["vents"]:
				at.append((v["at"] as Vector3).snapped(Vector3.ONE * 0.1))
			print("  two vents in %s: %s" % [cell, at])


func test_everything_stands_on_valid_ground() -> void:
	if not _ready_or_skip():
		return
	var pads := CinderCountry.pads(provider)
	var bad: Array = []
	for cell in _cells():
		var p := _plan(cell)
		var points: Array = []
		for c in p["cracks"]:
			points.append([c[0], "crack", 0.0])
		for v in p["vents"]:
			points.append([Vector2((v["at"] as Vector3).x, (v["at"] as Vector3).z), "vent", 0.0])
		for s in p["shards"]:
			points.append([Vector2((s[0] as Vector3).x, (s[0] as Vector3).z), "shard", 0.0])
		for path in p["rows"]:
			for row in p["rows"][path]:
				points.append([Vector2(float(row[0]), float(row[2])), str(path).get_file(), 0.0])
		for s in p["sites"]:
			points.append([s[0], "site " + str(s[1]), float(s[2])])
		for q in points:
			var at: Vector2 = q[0]
			var why := ""
			if provider.region_id_at(at.x, at.y) != CinderCountry.REGION:
				why = "outside Cinderlea"
			elif provider.is_water(at.x, at.y):
				why = "in water"
			elif RoadNetwork.edge_distance(at) < CinderCountry.ROAD_CLEAR - 0.01:
				why = "on a road (%.1f m)" % RoadNetwork.edge_distance(at)
			else:
				for pad in pads:
					if at.distance_to(pad[0]) < float(pad[1]) * CinderCountry.PAD_SHARE:
						why = "on a pad at %s" % pad[0]
						break
			if why != "":
				bad.append("%s at (%.0f, %.0f): %s" % [q[1], at.x, at.y, why])
	assert_eq(bad.size(), 0, "nothing on a road, a pad, water or another region: %s" % [bad.slice(0, 8)])


func test_vents_stand_in_hollows_or_on_the_flat_and_off_steep_ground() -> void:
	if not _ready_or_skip():
		return
	var steep: Array = []
	for cell in _cells():
		for s in _plan(cell)["sites"]:
			var at: Vector2 = s[0]
			var limit := CinderCountry.VENT_SLOPE if str(s[1]) in ["vent", "pool"] else CinderCountry.THING_SLOPE
			if str(s[1]) in ["crack", "cluster"]:
				limit = CinderCountry.CRACK_SLOPE
			if str(s[1]) == "drift":
				limit = 11.0
			var deg := rad_to_deg(provider.get_slope(at.x, at.y))
			if deg > limit + 0.01:
				steep.append("%s at (%.0f, %.0f) on %.0f degrees" % [s[1], at.x, at.y, deg])
	assert_eq(steep.size(), 0, "no site on ground steeper than its kind stands on: %s" % [steep.slice(0, 8)])


## A cell with vents, a pool, shards and a pillar or a cairn, for the build tests.
func _busy_cell() -> Vector2i:
	var best := Vector2i(-1, -1)
	var score := -1
	for cell in _cells():
		var p := _plan(cell)
		var s := (p["vents"] as Array).size() * 4 + (p["pillars"] as Array).size() * 2 + (p["cairns"] as Array).size() * 2 \
				+ mini((p["shards"] as Array).size(), 3) + mini((p["drifts"] as Array).size(), 2)
		if s > score:
			score = s
			best = cell
	return best


func _cell_node(cell: Vector2i) -> Node3D:
	var node := Node3D.new()
	var size := float(provider.manifest.get("cell_size_m", 256))
	node.position = Vector3(provider.origin.x + (float(cell.x) + 0.5) * size, 0.0,
			provider.origin.y + (float(cell.y) + 0.5) * size)
	(Engine.get_main_loop() as SceneTree).root.add_child(node)
	_holders.append(node)
	return node


func test_the_near_ring_draws_it_all_and_the_far_ring_only_its_glow() -> void:
	if not _ready_or_skip():
		return
	var cell := _busy_cell()
	var p := _plan(cell)
	assert_gt((p["vents"] as Array).size(), 0, "a cell with a vent to build")
	var near := _cell_node(cell)
	var solids: Array = []
	var holder := CinderCountry.build(near, p, provider, true, solids)
	_not_null(holder.get_node_or_null("Embers"), "the cracks are drawn")
	_not_null(holder.get_node_or_null("Pools"), "and the vents' mouths")
	var smoke := 0
	for c in holder.get_children():
		if c is GPUParticles3D:
			smoke += 1
			_between((c as GPUParticles3D).amount, 4, 24, "a thread of smoke is a few puffs")
			assert_gt((c as GPUParticles3D).visibility_range_end, 0.0, "and is culled at distance")
		elif c is MeshInstance3D:
			assert_gt((c as MeshInstance3D).visibility_range_end, 0.0, "%s is culled at distance" % c.name)
	assert_eq(smoke, (p["vents"] as Array).size(), "one thread a vent")
	assert_eq(solids.size(), (p["pillars"] as Array).size(), "a body walks into each pillar")
	var lit := NightLights.sources_of(holder)
	var vents_lit := 0
	for s in lit:
		assert_eq(str(s[1]), "vent", "a vent's light is a NightLights source of its own kind")
		vents_lit += 1
	_le(vents_lit, 3, "at most three lights a cell (two vents and a pool)")
	assert_true(CinderCountry.vents.has(holder.get_instance_id()), "its vents are heard")
	var far := _cell_node(cell)
	var far_holder := CinderCountry.build(far, p, provider, false, [])
	for c in far_holder.get_children():
		fail("the far ring builds no meshes or smoke, found %s" % c.name)
	assert_eq(NightLights.sources_of(far_holder).size(), vents_lit, "but its vents glow at night")
	var id := holder.get_instance_id()
	near.free()
	assert_false(CinderCountry.vents.has(id), "and go with their cell")


func test_the_rows_join_the_cells_own_without_writing_to_them() -> void:
	if not _ready_or_skip():
		return
	var cell := _busy_cell()
	var p := _plan(cell)
	var path: String = CinderCountry.STUMPS[0]
	var theirs: Array = [[0.0, 0.0, 0.0, 0.0, 1.0, "#ffffff"]]
	var instances := {path: theirs}
	CinderCountry.add_rows(instances, p)
	assert_eq(theirs.size(), 1, "the cell's parsed rows are never written to")
	var added := 0
	for k in p["rows"]:
		added += (p["rows"][k] as Array).size()
	var total := 0
	for k in instances:
		total += (instances[k] as Array).size()
	assert_eq(total, added + 1, "every planned row joins the cell's")


func test_the_hiss_starts_once_and_is_never_restarted_by_the_camera_standing_by() -> void:
	var node := CinderCountry.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(node)
	_holders.append(node)
	var id := 987654321
	CinderCountry.vents[id] = [Vector3(10.0, 5.0, 10.0), Vector3(30.0, 5.0, 10.0)]
	for i in 60:
		node.listen(Vector3(12.0 + 0.05 * float(i % 3), 6.0, 11.0))
	if not ResourceLoader.exists(CinderCountry.HISS):
		CinderCountry.vents.erase(id)
		fail("the vent hiss is generated (tools/audio/gen_ambience.py --only vent_hiss)")
		return
	assert_eq(node.hiss_starts, 1, "started once in sixty looks")
	assert_eq(node.hiss_moves, 1, "and never hopped")
	# halfway between the two vents it does not hop back and forth either
	for i in 40:
		node.listen(Vector3(19.5 + (0.6 if i % 2 == 0 else -0.6), 6.0, 10.0))
	assert_eq(node.hiss_moves, 1, "no hopping between two vents at the same distance")
	assert_eq(node.hiss_starts, 1, "nor a restart")
	node.listen(Vector3(500.0, 6.0, 500.0))
	CinderCountry.vents.erase(id)
	var player := node.get_node_or_null("VentHiss") as AudioStreamPlayer3D
	_not_null(player, "one player for every vent")
	assert_false(player.playing, "out of earshot of any vent it stops")
	var stream := player.stream as AudioStreamOggVorbis
	assert_true(stream != null and stream.loop, "the hiss is a loop, not a sound restarted")


func test_a_cinderlea_cell_streams_in_with_it() -> void:
	if not _ready_or_skip():
		return
	var cell := _busy_cell()
	var streamer := WorldStreamer.new()
	streamer.stand_up_foes = false
	streamer.solid_scatter = false
	(Engine.get_main_loop() as SceneTree).root.add_child(streamer)
	_holders.append(streamer)
	streamer.provider = provider
	streamer.cell_size = float(provider.manifest.get("cell_size_m", 256))
	var path := "%s/cells/%d_%d.json" % [GENERATED, cell.x, cell.y]
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var before := {}
	for k in data.get("instances", {}):
		before[k] = (data["instances"][k] as Array).size()
	streamer._build_cell(cell, 0, data)
	var node := streamer.get_node_or_null("Cell_%d_%d" % [cell.x, cell.y]) as Node3D
	_not_null(node, "the cell is built")
	_not_null(node.get_node_or_null("CinderCountry"), "with the ash country's ground")
	var after := {}
	for k in data.get("instances", {}):
		after[k] = (data["instances"][k] as Array).size()
	assert_eq(after, before, "and its parsed rows are as many as they were")
	_not_null(streamer.get_node_or_null("CinderCountry"), "and the hiss's node under the streamer")
