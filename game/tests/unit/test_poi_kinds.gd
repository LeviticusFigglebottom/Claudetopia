extends TestCase
## The kinds of place the drawn map asked for next (docs/ATLAS.md, section 10), each dressed from a
## POI def of its kind on level ground, as a new point of interest of that kind would be: a cave, a
## farmstead, a mill, a waystone, a market field, a quarry, a shieling, a vista. What each must have
## is what its line in the atlas says it is.

var host: Node3D


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	host = Node3D.new()
	host.name = "PoiKindsHost"
	_tree().root.add_child(host)


func after_each() -> void:
	_tree().root.remove_child(host)
	host.free()


## A dressing of `kind` in `region` standing on level ground at y 50, built.
func _dress(kind: String, region := "core:region/hearthvale", brief := "", encounter := "", far := false) -> PoiDressing:
	var id := "core:poi/test_%s" % kind
	var entry := {"place_id": id, "pos": [0.0, 50.0, 0.0], "radius_flat_m": 30.0}
	var def := {"id": id, "name": kind.capitalize(), "kind": kind, "region": region,
			"unique_feature": brief, "encounter": encounter}
	var d := PoiDressing.raise(entry, def, far, null, [])
	host.add_child(d)
	return d


func _meshes(d: Node, prefix: String) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	for n in d.find_children(prefix + "*", "GeometryInstance3D", true, false):
		out.append(n as GeometryInstance3D)
	return out


func _tris(mi: MeshInstance3D) -> int:
	var n := 0
	for s in mi.mesh.get_surface_count():
		var arr: Array = mi.mesh.surface_get_arrays(s)
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		var points := (idx as PackedInt32Array).size() if idx != null and (idx as PackedInt32Array).size() > 0 \
				else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		n += int(points / 3.0)
	return n


func _marker(d: Node, marker_name: String) -> Marker3D:
	return d.find_child(marker_name, true, false) as Marker3D


## A wheel's axle lies level: a wheel on an upright axle is a roundabout.
func _assert_level(axle: Vector3) -> void:
	assert_true(absf(axle.normalized().y) < 0.05, "the axle lies level (%s)" % str(axle))


func test_every_kind_the_map_asked_for_has_a_builder() -> void:
	for kind in ["cave", "farmstead", "mill", "waystone", "market_field", "quarry", "shieling", "vista"]:
		assert_true(PoiDressing.KINDS.has(kind), "%s is a kind a POI can be" % kind)
		assert_true(PoiDressing.KINDS_BUILT.has(kind), "and a kind the kit builds: %s" % kind)
		var warned := Log.warning_count
		var d := _dress(kind)
		assert_true(d.built, "%s was dressed" % kind)
		assert_eq(Log.warning_count, warned, "%s was dressed without a warning" % kind)
		assert_gt(d.find_children("*", "GeometryInstance3D", true, false).size(), 3, "%s is more than a pad" % kind)
		assert_gt(d.body_count(), 0, "%s has something to bump into" % kind)


func test_a_waystone_is_notched_and_keeps_a_bowl_of_coins() -> void:
	var d := _dress("waystone", "core:region/cinderlea", "the ninth stone the pilgrims count")
	var notches := d.find_child("Notches", true, false) as MeshInstance3D
	assert_true(notches != null and _tris(notches) >= 7 * 2 * 12, "a tally cut into both faces")
	assert_true(d.find_child("Bowl", true, false) != null, "a bowl at its foot")
	assert_true(d.find_child("Coins", true, false) != null, "with what the walkers left in it")
	assert_true(_marker(d, "the_bowl") != null, "and somewhere to stand and leave one")


func test_a_vista_turns_its_bench_to_the_view_and_a_cairn_stands_alone() -> void:
	var d := _dress("vista", "core:region/hearthvale", "the bench at the Larkmouth where the Vale opens")
	var benches := d.find_children("*bench*", "Node3D", true, false)
	assert_false(benches.is_empty(), "a bench")
	assert_true(_marker(d, "the_view") != null, "and a place to stand and look")
	assert_false(_meshes(d, "*boulder").is_empty(), "and the cairn walkers add a stone to")
	# seen at ten metres: the bench stands on a plinth of flags, clear of the grass, with a length
	# of drystone wall at its back, in a worn clearing
	assert_true(d.find_child("Plinth", true, false) != null, "a plinth for the bench")
	assert_true(d.find_child("FabricDrystone", true, false) != null, "a wall at its back")
	assert_true(d.find_child("Clearing", true, false) != null, "a clearing round it")
	if not benches.is_empty():
		var b := benches[0] as Node3D
		assert_gt(b.position.y - d.kit.on_ground(b.position.x, b.position.z).y, 0.12, "the bench stands up on the flags")
	var c := _dress("vista", "core:region/skerrow", "a cairn on the Last Look")
	assert_true(c.find_children("*bench*", "Node3D", true, false).is_empty(), "a cairn with no bench, where the sentence says cairn")
	assert_true(_marker(c, "the_view") != null, "and its place to look from")


func test_a_cave_goes_dark_ten_metres_into_the_hill() -> void:
	var d := _dress("cave", "core:region/skerrow", "a limestone mouth in the scar")
	# The crag it is cut into is the region's own rock, and all of it boulders: two leaning slabs
	# read as a tent, and a slab across the top as a doorway. Each piece of it has its foot in the
	# slope, and none but the capstones on the roof stands on anything else (a forge asset is known
	# by its scene, since two of one name are renamed by the tree).
	var slabs := 0
	var boulders := 0
	var sunk := 0
	for c in d.get_children():
		var scene := str((c as Node).scene_file_path)
		if scene.contains("cliff_slab"):
			slabs += 1
		elif scene.contains("skerrow_boulder"):
			boulders += 1
			var at := (c as Node3D).position
			if at.y < d.kit.on_ground(at.x, at.z).y:
				sunk += 1
	assert_eq(slabs, 0, "no slabs stood on the slope")
	assert_gt(boulders, 11, "boulders for its cheeks, its capstones, its brow, its roof and its flanks")
	# the cheeks, the brow and the flanks have their feet in the slope (the capstones and the rocks
	# over the passage rest on its roof instead)
	assert_gt(sunk, 10, "the crag's feet in the slope (%d of %d)" % [sunk, boulders])
	# light thrown back into the mouth, so its rock does not go black with the sun behind the hill
	var bounce := 0
	for s in NightLights.sources_of(d):
		if str(s[1]) == "bounce":
			bounce += 1
	assert_eq(bounce, 1, "a bounce light at the mouth")
	assert_eq(float(NightLights.KINDS["bounce"]["size"]), 0.0, "and nothing drawn for it, since nothing there burns")
	var mouth := _marker(d, "the_mouth")
	var end := d.find_child("ThroatEnd", true, false) as MeshInstance3D
	assert_true(mouth != null and end != null, "a mouth, and the end of its throat")
	if mouth != null and end != null:
		var front := (end.mesh.get_aabb().get_center() - mouth.position)
		assert_gt(Vector2(front.x, front.z).length(), 6.5, "the black is ten metres in from the mouth (%.1f past the den)" % Vector2(front.x, front.z).length())
	var bright: Array[float] = []
	for i in 5:
		var ring := d.find_child("Throat%d" % i, true, false) as MeshInstance3D
		assert_true(ring != null, "ring %d of the throat" % i)
		if ring != null:
			bright.append(((ring.material_override as StandardMaterial3D).albedo_color).v)
	for i in range(1, bright.size()):
		assert_true(bright[i] < bright[i - 1], "each ring darker than the one before")
	var wood := _dress("cave", "core:region/briarwold", "a root-cave under the old oak")
	assert_true(wood.find_child("Roots", true, false) != null, "a root-cave has its roots over the mouth")
	var sea := _dress("cave", "core:region/cinderlea", "a sea-cave under the Hushline, where the tide comes in")
	assert_true(sea.find_child("TidePool", true, false) != null, "a sea-cave has the tide in its mouth")
	var sand := sea.find_child("ShellSand", true, false) as MeshInstance3D
	assert_true(sand != null, "and the pale sand the tide leaves, to be seen by on the black ash")
	if sand != null:
		var pale: Color = (sand.material_override as ShaderMaterial).get_shader_parameter("base_color")
		assert_gt(pale.v, 0.6, "sand paler than the ash (%.2f)" % pale.v)


func test_a_quarry_has_its_face_its_spoil_and_its_crane() -> void:
	var d := _dress("quarry", "core:region/hearthvale", "the chalk pit where the Vale's lime came from")
	for part in ["Face", "Blocks", "Spoil", "Crane", "Lifted"]:
		assert_true(d.find_child(part, true, false) != null, "a quarry's %s" % part)
	var face := d.find_child("Face", true, false) as MeshInstance3D
	if face != null:
		var base: Color = (face.material_override as ShaderMaterial).get_shader_parameter("base_color")
		assert_gt(base.v, 0.8, "the Vale's face is white chalk")
		# the spoil is the rock broken small with its earth: a heap, not a hill, and not the face's white
		var spoil := d.find_child("Spoil", true, false) as MeshInstance3D
		if spoil != null:
			var size := spoil.mesh.get_aabb().size
			assert_true(maxf(size.x, size.z) < 7.0, "a heap, not a hill (%.1f m across)" % maxf(size.x, size.z))
			assert_true(size.y < 1.8, "and low (%.1f m)" % size.y)
			var heap: Color = (spoil.material_override as ShaderMaterial).get_shader_parameter("base_color")
			assert_true(heap.v < base.v - 0.15, "greyer than the fresh-cut face")
	assert_true(_marker(d, "the_face") != null, "and somewhere a quarryman stands")


func test_a_shieling_is_a_turf_hut_and_a_fold_with_sheep() -> void:
	var d := _dress("shieling", "core:region/skerrow", "a summer hut above the Oskel")
	assert_true(d.find_child("TurfRoof", true, false) != null, "a roof of turf")
	assert_true(d.find_child("FabricDrystone", true, false) != null, "on walls of drystone, with the fold's")
	var flock := d.find_child("Flock", true, false) as Livestock
	assert_true(flock != null and flock.beasts.size() >= 4, "the flock in its fold")
	assert_true(_marker(d, "the_hut") != null, "and a door somebody stands at")


func test_a_farmstead_is_a_house_and_a_barn_round_a_walled_yard() -> void:
	var d := _dress("farmstead", "core:region/hearthvale", "a cob farm with a dog that barks at nothing", "none; jobs")
	for part in ["FabricWall", "FabricRoof", "FabricJoinery"]:
		assert_true(d.find_child(part, true, false) != null, "a farmstead's %s" % part)
	assert_gt(d.find_children("Puffs", "GPUParticles3D", true, false).size(), 0, "smoke from the house")
	assert_false(d.find_children("*well*", "Node3D", true, false).is_empty(), "a well in the yard")
	var yard := d.find_child("Yard", true, false) as Livestock
	assert_true(yard != null and not yard.beasts.is_empty(), "hens in the yard")
	assert_true(d.find_child("JobBoard", true, false) != null, "the notice post, where its sentence says there is work")
	assert_true(_marker(d, "the_yard") != null and _marker(d, "the_door") != null, "the yard, and the house's door on it")


func test_a_mill_turns_its_wheel_in_its_leat_and_a_windmill_its_sails() -> void:
	var d := _dress("mill", "core:region/hearthvale", "the mill on the Larkbourne")
	var wheel := d.find_child("Wheel", true, false) as Turning
	assert_true(wheel != null, "a wheel")
	assert_true(d.find_child("Leat", true, false) != null and d.find_child("LeatWater", true, false) != null, "in a leat with water in it")
	if wheel != null:
		var before := wheel.basis
		wheel.turn(1.0)
		assert_false(wheel.basis.y.is_equal_approx(before.y), "and it goes round")
		assert_true(wheel.basis.z.is_equal_approx(before.z), "about its axle")
		_assert_level(wheel.basis.z)
	assert_true(_marker(d, "the_wheel") != null and _marker(d, "the_door") != null, "the wheel and the mill's door")
	var w := _dress("mill", "core:region/brightwater", "a windmill with four sails on the ridge")
	assert_true(w.find_child("Sails", true, false) is Turning, "a windmill's sails go round")
	assert_true(w.find_child("Tower", true, false) != null and w.find_child("Cap", true, false) != null, "on a tower with its cap")


func test_a_market_field_opens_on_market_day() -> void:
	var d := _dress("market_field", "core:region/skerrow", "Kharrow Foot, where the drovers meet")
	assert_true(d.find_child("BellPost", true, false) != null and _marker(d, "the_bell") != null, "the bell-post that opens the market")
	var market := d.find_child("MarketDay", true, false) as MarketDays
	assert_true(market != null, "what stands there on market day")
	if market == null:
		return
	assert_gt(market.get_child_count(), 3, "the stalls and the carts")
	var open_day := -1
	var shut_day := -1
	for day in range(1, 8):
		if market.is_market_day(day):
			open_day = day
		else:
			shut_day = day
	assert_true(open_day > 0 and shut_day > 0, "one day of the week and not the others")
	market.show_for(open_day)
	assert_true(market.visible and market.process_mode != Node.PROCESS_MODE_DISABLED, "stalls up on market day")
	market.show_for(shut_day)
	assert_false(market.visible, "packed away the rest of the week")
	assert_eq(market.process_mode, Node.PROCESS_MODE_DISABLED, "and their bodies out of the world")
	EventBus.new_day.emit(open_day + 7)
	assert_true(market.visible, "and up again when market day comes round")


func test_the_far_ring_keeps_the_shapes_and_leaves_the_rest() -> void:
	for kind in ["farmstead", "mill", "cave", "quarry"]:
		var d := _dress(kind, "core:region/hearthvale", "", "", true)
		assert_gt(d.find_children("*", "GeometryInstance3D", true, false).size(), 0, "%s has a silhouette in the far ring" % kind)
		assert_true(d.find_children("*", "Marker3D", true, false).is_empty(), "%s puts no markers down far off" % kind)
		assert_true(d.find_children("*", "Livestock", true, false).is_empty(), "%s keeps no beasts far off" % kind)


func test_a_wheel_turns_only_while_somebody_can_see_it() -> void:
	var wheel := Turning.new()
	host.add_child(wheel)
	var cam := Camera3D.new()
	host.add_child(cam)
	cam.make_current()
	cam.global_position = Vector3(0.0, 2.0, 10.0)
	var before := wheel.basis
	for i in 4:
		await _tree().process_frame
	assert_false(wheel.basis.is_equal_approx(before), "it goes round with a camera near")
	cam.global_position = Vector3(0.0, 2.0, Turning.AWAKE_M + 50.0)
	var far_basis := wheel.basis
	for i in 4:
		await _tree().process_frame
	assert_true(wheel.basis.is_equal_approx(far_basis), "and stands still with nobody near")
	assert_eq(wheel.physics_interpolation_mode, Node.PHYSICS_INTERPOLATION_MODE_OFF, "moved outside the physics ticks, so out of their interpolation")


## A plain watch or a beacon carries on the skyline past a kilometre and a half (the sightlines
## credit a tower with ten metres): eleven to twelve metres with its crown, the watch's merlons or
## the beacon's iron cage, and the far ring's silhouette the same height as the near one.
func test_a_watch_and_a_beacon_stand_ten_to_twelve_metres_with_a_crown() -> void:
	for brief in ["a watch over the ford", "a beacon on the headland, its fire-bowl lit"]:
		for far in [false, true]:
			var d := _dress("tower", "core:region/hearthvale", brief, "", far)
			var drum := d.find_child("Drum", true, false) as MeshInstance3D
			assert_true(drum != null, "%s has its drum (far %s)" % [brief, far])
			if drum == null:
				continue
			var top := drum.mesh.get_aabb().end.y - d.kit.on_ground(0.0, 0.0).y
			var beacon := str(brief).contains("beacon")
			if beacon:
				var cage := d.find_child("Cage", true, false) as MeshInstance3D
				assert_true(cage != null, "a beacon's iron cage (far %s)" % far)
				if cage != null:
					top = maxf(top, cage.mesh.get_aabb().end.y - d.kit.on_ground(0.0, 0.0).y)
			assert_true(top >= 10.0 and top <= 12.5, "%s stands %.1f m with its crown (far %s)" % [brief, top, far])
