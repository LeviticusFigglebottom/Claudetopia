extends TestCase
## The wild things between the places (world/wildlife/wildlife.gd): each kind where the country
## says it lives, the same flocks on every visit, and each going the way its kind goes when
## somebody walks up on it -- a heron off low to another stretch of shore, ducks up together and
## down on the water farther off, swans paddling away, crows up off a field and back down on it.

## Cells of the built world (CELL_M across) that hold each kind's ground, found from its maps.
const MARSH := Vector2i(-20, -4)        # Sedgemire: reed beds and still channels
const VALE_FIELD := Vector2i(-2, 8)     # Hearthvale: open ground
const MERE := Vector2i(2, -1)           # Brightwater: the Mere near its shore, level 8
const ASH := Vector2i(-23, 13)          # Cinderlea
const CRAGS := Vector2i(2, -24)         # Skerrow

var _provider: TerrainProvider = null


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _world_maps() -> TerrainProvider:
	if _provider == null:
		_provider = TerrainProvider.new()
		_provider.load_data()
	return _provider


static func _centre(cell: Vector2i) -> Vector3:
	return Vector3((float(cell.x) + 0.5) * Wildlife.CELL_M, 0.0, (float(cell.y) + 0.5) * Wildlife.CELL_M)


func _wildlife(at: Vector3, density := 1.0) -> Wildlife:
	var w := Wildlife.new()
	w.provider = _world_maps()
	w.spooked_by = "test_wild_walker"
	w.use_clock = false
	_tree().root.add_child(w)
	w.set_process(false)
	w.set_density(density)
	_fill(w, at)
	return w


func _fill(w: Wildlife, at: Vector3) -> void:
	for i in 200:
		w.update(at, 0.0)
		if w.settled():
			return


func _walker(at: Vector3) -> Node3D:
	var n := Node3D.new()
	n.add_to_group("test_wild_walker")
	_tree().root.add_child(n)
	n.global_position = at
	return n


func _drop(n: Node) -> void:
	_tree().root.remove_child(n)
	n.free()


func _run(w: Wildlife, eye: Vector3, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		w.update(eye, 0.1)
		t += 0.1


func _first(w: Wildlife, kind: String, near: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var bd := INF
	for f in w.flocks_of(kind):
		var d := Wildlife._flat(f["home"], near)
		if d < bd:
			bd = d
			best = f
	return best


func test_every_kind_is_a_body_the_shader_can_pose() -> void:
	for kind in Wildlife.KINDS:
		var m := WildlifeMeshes.mesh(kind)
		assert_true(m != null, "%s has a body" % kind)
		if m == null:
			continue
		var tris := WildlifeMeshes.triangles(kind)
		assert_true(tris >= 100 and tris <= 500, "%s is %d triangles: a shape, and cheap" % [kind, tris])
		var arrays := m.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		var left := 0
		var right := 0
		var neck := 0
		var root := INF
		for i in verts.size():
			if uv2[i].x > 0.0:
				left += 1
			elif uv2[i].x < 0.0:
				right += 1
			elif uv2[i].y > 0.0:
				neck += 1
			if uv2[i].x != 0.0:
				root = minf(root, absf(verts[i].x))
		assert_true(left > 0 and left == right, "%s has two wings alike (%d, %d)" % [kind, left, right])
		assert_true(neck > 0, "%s has a head the shader can move" % kind)
		var rig: Dictionary = WildlifeMeshes.RIGS[kind]
		assert_near(root, (rig["root"] as Vector2).x, 0.002, "%s's wings hinge where the shader turns them" % kind)


func test_the_survey_reads_the_country() -> void:
	var w := Wildlife.new()
	w.provider = _world_maps()
	w._start()
	var marsh := w.survey(MARSH)
	assert_eq(str(marsh["region"]), "core:region/sedgemire", "the marsh cell is Sedgemire")
	assert_gt((marsh["reeds"] as Array).size(), 10, "with reed and mud shore for herons")
	var field := w.survey(VALE_FIELD)
	assert_eq(str(field["region"]), "core:region/hearthvale", "the Vale cell is the Vale")
	assert_gt((field["field"] as Array).size(), 100, "and open ground")
	var mere := w.survey(MERE)
	assert_gt((mere["near_water"] as Array).size() + (mere["open_water"] as Array).size(), 100, "the Mere is still water")
	assert_false(bool(mere["sea"]), "and not the sea")
	for p in mere["near_water"]:
		assert_near((p as Vector3).y, 8.0, 0.35, "at the Mere's level")
		break
	w.free()


func test_each_kind_is_where_it_lives() -> void:
	# at three times the setting every cell that has a kind's ground has its flock
	var marsh := _wildlife(_centre(MARSH), 3.0)
	assert_gt(marsh.count("heron"), 0, "herons in the marsh")
	assert_gt(marsh.count("duck"), 0, "ducks on its channels")
	for f in marsh.flocks_of("heron"):
		var at: Vector3 = f["birds"][0]["pos"]
		var level := marsh.provider.nearest_water_level(at.x, at.z)
		assert_true(at.y >= level - 0.2 and at.y <= level + 2.5, "a heron stands at the water's edge (%.2f over %.2f)" % [at.y, level])
	for f in marsh.flocks_of("duck"):
		for b in f["birds"]:
			var at: Vector3 = b["pos"]
			assert_true(marsh.provider.is_water(at.x, at.z), "a duck is on the water")
			assert_near(at.y, marsh.provider.nearest_water_level(at.x, at.z), 0.05, "at its level")
	assert_eq(marsh.count("crow"), 0, "no crows gleaning in the marsh")
	_drop(marsh)
	var vale := _wildlife(_centre(VALE_FIELD), 3.0)
	assert_gt(vale.count("crow"), 0, "crows on the Vale's fields")
	assert_eq(vale.count("raven"), 0, "no ravens over the Vale")
	_drop(vale)
	var ash := _wildlife(_centre(ASH), 3.0)
	assert_eq(ash.count("crow") + ash.count("duck") + ash.count("heron") + ash.count("swan"), 0,
			"the ash has none of the Vale's birds or the Mere's")
	_drop(ash)
	var crags := _wildlife(_centre(CRAGS), 3.0)
	assert_gt(crags.count("raven"), 0, "ravens over Skerrow's crags")
	for f in crags.flocks_of("raven"):
		for b in f["birds"]:
			var at: Vector3 = b["pos"]
			assert_gt(at.y - crags.provider.get_height(at.x, at.z), 15.0, "a raven is high over the ground")
	_drop(crags)


func test_the_same_flocks_on_every_visit() -> void:
	var a := _wildlife(_centre(MARSH))
	var b := _wildlife(_centre(MARSH))
	assert_gt(a.count(), 0, "the marsh has birds")
	assert_eq(a.count(), b.count(), "as many the second time")
	for i in mini(a.flocks.size(), b.flocks.size()):
		assert_eq(a.flocks[i]["kind"], b.flocks[i]["kind"], "the same kinds")
		assert_true((a.flocks[i]["home"] as Vector3).is_equal_approx(b.flocks[i]["home"]), "in the same places")
	_drop(a)
	_drop(b)


func test_the_setting_is_how_many() -> void:
	var none := _wildlife(_centre(MARSH), 0.0)
	assert_eq(none.count(), 0, "none at 0")
	assert_eq(none.rises(), 0, "and no fish rising")
	_drop(none)
	var half := _wildlife(_centre(MARSH), 0.5)
	var full := _wildlife(_centre(MARSH), 1.0)
	assert_true(half.flocks.size() <= full.flocks.size(), "fewer flocks at half (%d, %d)" % [half.flocks.size(), full.flocks.size()])
	assert_gt(full.rises(), 0, "fish rising in the marsh")
	# the setting changed live empties the ring and peoples it again
	full.set_density(0.0)
	_fill(full, _centre(MARSH))
	assert_eq(full.count(), 0, "set to none, they are gone")
	_drop(half)
	_drop(full)


func test_a_heron_walked_up_on_flies_off_low_and_lands_away() -> void:
	var w := _wildlife(_centre(MARSH), 3.0)
	var f := _first(w, "heron", _centre(MARSH))
	assert_false(f.is_empty(), "a heron to walk up on")
	if f.is_empty():
		_drop(w)
		return
	var heron: Dictionary = f["birds"][0]
	var start: Vector3 = heron["pos"]
	var walker := _walker(start + Vector3(12.0, 0.0, 0.0))
	_run(w, start, 1.0)
	assert_eq(int(heron["state"]), Wildlife.State.AIR, "twelve metres off, it goes")
	var highest := 0.0
	var tucked := 0.0
	for i in 400:
		_run(w, start, 0.1)
		var p: Vector3 = heron["pos"]
		highest = maxf(highest, p.y - w._floor_at(p))
		tucked = maxf(tucked, float(heron["tuck"]))
		if int(heron["state"]) == Wildlife.State.SIT:
			break
	assert_eq(int(heron["state"]), Wildlife.State.SIT, "and comes down again")
	assert_true(highest < 16.0, "flying low (%.1f m up at most)" % highest)
	assert_gt(tucked, 0.8, "its neck drawn in and its legs trailed on the way")
	assert_gt(Wildlife._flat(heron["pos"], walker.global_position), 40.0, "well away from the walker")
	_drop(walker)
	_drop(w)


func test_ducks_go_up_together_and_come_down_on_the_water_farther_off() -> void:
	var w := _wildlife(_centre(MARSH), 3.0)
	var f := _first(w, "duck", _centre(MARSH))
	assert_false(f.is_empty(), "ducks to walk up on")
	if f.is_empty():
		_drop(w)
		return
	var home: Vector3 = f["home"]
	var ups := [0]
	w.put_up.connect(func(kind: String, _at: Vector3) -> void:
		if kind == "duck":
			ups[0] += 1)
	var walker := _walker(home + Vector3(8.0, 0.0, 0.0))
	_run(w, home, 1.5)
	for b in f["birds"]:
		assert_eq(int(b["state"]), Wildlife.State.AIR, "every duck of the flock goes up")
	assert_gt(ups[0], 0, "and says so")
	walker.global_position = home + Vector3(8.0, 0.0, 0.0)
	_run(w, home, 60.0)
	var down := 0
	for b in f["birds"]:
		if int(b["state"]) == Wildlife.State.SIT:
			down += 1
			var at: Vector3 = b["pos"]
			assert_true(w.provider.is_water(at.x, at.z), "down on the water")
			assert_gt(Wildlife._flat(at, walker.global_position), Wildlife.CLEAR_M - 10.0, "away from the walker")
	assert_eq(down, (f["birds"] as Array).size(), "all down again within the minute (%d)" % down)
	_drop(walker)
	_drop(w)


func test_crows_go_up_off_a_field_and_settle_on_it_again() -> void:
	var w := _wildlife(_centre(VALE_FIELD), 3.0)
	var f := _first(w, "crow", _centre(VALE_FIELD))
	assert_false(f.is_empty(), "crows to walk up on")
	if f.is_empty():
		_drop(w)
		return
	var home: Vector3 = f["home"]
	var walker := _walker(home + Vector3(6.0, 0.0, 0.0))
	_run(w, home, 1.5)
	var up := 0
	var highest := 0.0
	for b in f["birds"]:
		up += int(int(b["state"]) == Wildlife.State.AIR)
	assert_eq(up, (f["birds"] as Array).size(), "the whole flock goes up")
	walker.global_position = home + Vector3(500.0, 0.0, 500.0)
	for i in 600:
		_run(w, home, 0.1)
		for b in f["birds"]:
			var p: Vector3 = b["pos"]
			highest = maxf(highest, p.y - w.provider.get_height(p.x, p.z))
	assert_gt(highest, 6.0, "wheeling well up over the field")
	var down := 0
	for b in f["birds"]:
		if int(b["state"]) == Wildlife.State.SIT:
			down += 1
			var at: Vector3 = b["pos"]
			assert_false(w.provider.is_water(at.x, at.z), "down on dry ground")
			assert_near(at.y, w.provider.get_height(at.x, at.z), 0.1, "on it, not over it")
	assert_eq(down, (f["birds"] as Array).size(), "left alone, they are all down again (%d)" % down)
	_drop(walker)
	_drop(w)


func test_swans_keep_their_distance_on_the_water() -> void:
	var w := _wildlife(_centre(MERE), 8.0)
	var f := _first(w, "swan", _centre(MERE))
	if f.is_empty():
		# the Mere cell may have no swans' water; try the marsh
		_drop(w)
		w = _wildlife(_centre(MARSH), 8.0)
		f = _first(w, "swan", _centre(MARSH))
	assert_false(f.is_empty(), "swans to walk up on")
	if f.is_empty():
		_drop(w)
		return
	var swan: Dictionary = f["birds"][0]
	var start: Vector3 = swan["pos"]
	var walker := _walker(start + Vector3(10.0, 0.0, 0.0))
	var before := Wildlife._flat(start, walker.global_position)
	_run(w, start, 8.0)
	assert_eq(int(swan["state"]), Wildlife.State.SIT, "a swan does not go up")
	var at: Vector3 = swan["pos"]
	assert_true(w.provider.is_water(at.x, at.z), "it stays on the water")
	assert_gt(Wildlife._flat(at, walker.global_position), before + 1.0, "and paddles away")
	_drop(walker)
	_drop(w)


func test_a_kind_is_one_draw_culled_by_the_ring_round_the_eye() -> void:
	var eye := _centre(MARSH) + Vector3(0.0, 20.0, 0.0)
	var w := _wildlife(eye, 3.0)
	_run(w, eye, 0.2)
	var drawn := 0
	for kind in Wildlife.KINDS:
		var inst := w.instance_of(kind)
		assert_true(inst != null, "%s is drawn by one MultiMesh" % kind)
		if inst == null:
			continue
		var mm := inst.multimesh
		drawn += mm.visible_instance_count
		assert_eq(inst.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s casts no shadow" % kind)
		var box := inst.custom_aabb
		assert_true(box.has_point(eye), "the %s draw's box holds the eye" % kind)
		var at: PackedVector3Array = w.drawn.get(kind, PackedVector3Array())
		assert_eq(at.size(), mm.visible_instance_count, "as many %s put in it as it draws" % kind)
		for p in at:
			assert_true(box.has_point(p), "and every %s in it (%s in %s)" % [kind, str(p), str(box)])
	assert_gt(drawn, 0, "birds drawn")
	var sitting_far := 0
	for f in w.flocks:
		for b in f["birds"]:
			if int(b["state"]) == Wildlife.State.SIT and Wildlife._flat(b["pos"], eye) > Wildlife.SITTING_SEEN_M:
				sitting_far += 1
	assert_eq(drawn, w.count() - sitting_far, "every bird drawn but those sat too far off to see")
	_drop(w)


func test_the_ring_follows_the_eye() -> void:
	var w := _wildlife(_centre(MARSH))
	var before := w.count()
	assert_gt(before, 0, "birds round the marsh")
	var away := _centre(ASH)
	_fill(w, away)
	for f in w.flocks:
		var cell: Vector2i = f["cell"]
		var c := _centre(cell)
		assert_true(Vector2(c.x - away.x, c.z - away.z).length() <= Wildlife.LIVE_M + 1.0, "no flock is left behind")
	_drop(w)
