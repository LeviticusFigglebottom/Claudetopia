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


## The Tide Mouth's ground under the Hushline, drawn plain: a shelf at 4 m, a cliff rising from 16 m
## to its south (-z), and a bay of the sea 30 m to its west-north-west, so the nearest water is not
## the way out from the cliff.
class CliffFoot extends TerrainProvider:
	func get_height(x: float, z: float) -> float:
		if z < -16.0:
			return 4.0 + minf((-16.0 - z) * 8.0, 100.0)
		if x < -30.0 and z > 5.0:
			return -3.0
		return 4.0


func test_a_cave_on_a_shelf_backs_into_the_cliff_over_it() -> void:
	var ground := CliffFoot.new()
	var id := "core:poi/test_cave"
	var entry := {"place_id": id, "pos": [0.0, 4.0, 0.0], "radius_flat_m": 18.0}
	var def := {"id": id, "name": "Cave", "kind": "cave", "region": "core:region/cinderlea",
			"unique_feature": "a sea-cave in the cliff foot, low to the water", "encounter": ""}
	var d := PoiDressing.raise(entry, def, false, ground, [])
	host.add_child(d)
	var mouth := _marker(d, "the_mouth")
	var end := d.find_child("ThroatEnd", true, false) as MeshInstance3D
	assert_true(mouth != null and end != null, "a mouth, and the end of its throat")
	if mouth != null and end != null:
		var run := end.mesh.get_aabb().get_center() - mouth.position
		var bearing := rad_to_deg(atan2(run.x, run.z))
		assert_true(absf(absf(bearing) - 180.0) < 20.0,
				"the throat runs into the cliff, not along its foot to the water (bearing %.0f, the cliff at 180)" % bearing)
	var pool := d.find_child("TidePool", true, false) as MeshInstance3D
	if pool != null and mouth != null:
		assert_gt(pool.mesh.get_aabb().get_center().z, mouth.position.z, "the tide's pool out in front, away from the cliff")
	ground.free()


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


## Whoever works at a farmstead stands clear of it. HouseKit puts a door on the wall's face, and
## the farm's door spot stood there, so the batch 3 world had all twelve farms' keepers half inside
## their houses. The spot is out on the yard now, still at the door, and the chopping block, the
## barrow, the barrel and the fork are kept off it.
func test_a_farmsteads_people_stand_clear_of_its_house_and_things() -> void:
	var person := CapsuleShape3D.new()
	person.radius = 0.3
	person.height = 1.6
	var reach := SphereShape3D.new()
	reach.radius = 1.6
	var doors := 0
	var n := 0
	for region in ["core:region/hearthvale", "core:region/skerrow", "core:region/briarwold", "core:region/cinderlea"]:
		for brief in ["a door-quern by the house door", "a dovecote over the yard, and the jobs board at its gate"]:
			n += 1
			var id := "core:poi/test_farm_%d" % n
			var entry := {"place_id": id, "pos": [float(n) * 200.0, 50.0, 0.0], "radius_flat_m": 26.0}
			var def := {"id": id, "name": "Farm %d" % n, "kind": "farmstead", "region": region,
					"unique_feature": brief, "encounter": ""}
			var d := PoiDressing.raise(entry, def, false, null, [])
			host.add_child(d)
			for i in 2:
				await _tree().physics_frame
			var space := d.get_world_3d().direct_space_state
			for m in d.find_children("*", "Marker3D", true, false):
				if not m.is_in_group(NpcRegistry.SPOT_GROUP):
					continue
				var q := PhysicsShapeQueryParameters3D.new()
				q.shape = person
				q.collision_mask = 1 << 0
				q.transform = Transform3D(Basis.IDENTITY, (m as Node3D).global_position + Vector3(0.0, 0.95, 0.0))
				assert_true(space.intersect_shape(q, 1).is_empty(), "%s (%s): whoever works at '%s' stands inside something" % [id, region, m.name])
				if m.name == "the_door":
					doors += 1
					q.shape = reach
					assert_false(space.intersect_shape(q, 1).is_empty(), "%s: the door's spot is still at the house" % id)
			d.free()
	assert_eq(doors, n, "every farm has its door's spot")


## A circle's stones are whole stones, of the stone its sentence names. Briarwold keeps two stumps
## (0.8 m and 0.4 m) beside its 2.2 m stone, and a circle given one stood knee-high. The Greyline is
## "a line of chalk stones" out on Cinderlea's ash, where a region borrowing stone by its geology
## would cut it from granite.
func test_a_stone_circle_stands_whole_stones_of_the_stone_it_names() -> void:
	for n in 6:
		var id := "core:poi/test_circle_%d" % n
		var entry := {"place_id": id, "pos": [float(n) * 200.0, 50.0, 400.0], "radius_flat_m": 20.0}
		var def := {"id": id, "name": "Circle %d" % n, "kind": "standing_stones", "region": "core:region/briarwold",
				"unique_feature": "three leaning granite stones in a clearing where the wardens gather", "encounter": ""}
		var d := PoiDressing.raise(entry, def, false, null, [])
		host.add_child(d)
		var stones := 0
		for c in d.get_children():
			var scene := str((c as Node).scene_file_path)
			if scene.contains("standing_stone"):
				stones += 1
				assert_gt(PoiKit.height_of(scene), 2.0, "%s: a whole stone, not a stump (%s)" % [id, scene.get_file()])
		assert_eq(stones, 3, "%s: three stones" % id)
	var grey := _dress("standing_stones", "core:region/skerrow", "a line of chalk stones marking where the grey begins")
	var chalk := 0
	for c in grey.get_children():
		var scene := str((c as Node).scene_file_path)
		if scene.contains("standing_stone"):
			assert_true(scene.contains("hearthvale_standing_stone"), "the chalk stones are the Vale's chalk (%s)" % scene.get_file())
			chalk += 1
	assert_gt(chalk, 0, "the line has its stones")


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
			var ground := d.kit.on_ground(0.0, 0.0).y
			var top := drum.mesh.get_aabb().end.y - ground
			# the drum stands on the ground, all the way up (a crown laid into the drum's own mesh
			# once dropped the drum and left the merlons in the air)
			assert_true(drum.mesh.get_aabb().position.y - ground < 0.5, "%s: the drum reaches the ground (far %s)" % [brief, far])
			assert_gt(top, 9.5, "%s: the drum stands its ten metres (far %s)" % [brief, far])
			var beacon := str(brief).contains("beacon")
			if not beacon:
				var crown := d.find_child("Crown", true, false) as MeshInstance3D
				assert_true(crown != null, "a watch's merlons (far %s)" % far)
				if crown != null:
					top = maxf(top, crown.mesh.get_aabb().end.y - ground)
			if beacon:
				var cage := d.find_child("Cage", true, false) as MeshInstance3D
				assert_true(cage != null, "a beacon's iron cage (far %s)" % far)
				if cage != null:
					top = maxf(top, cage.mesh.get_aabb().end.y - d.kit.on_ground(0.0, 0.0).y)
			assert_true(top >= 10.0 and top <= 12.5, "%s stands %.1f m with its crown (far %s)" % [brief, top, far])


## A block and a drum's courses laid into one mesh both reach it: the courses are laid with no
## index, and a box with one dropped them (a watch's drum vanished under its merlons, a
## colonnade's columns under its steps).
func test_a_block_and_a_drum_share_a_mesh() -> void:
	var d := _dress("waystone")
	var m := d.masonry
	var alone := m.begin()
	m.drum(alone, Transform3D(), 2.0, 6.0, 0.0, NAN, false)
	var drum_arrays: Array = (alone.commit() as ArrayMesh).surface_get_arrays(0)
	var drum_only: int = (drum_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var st := m.begin()
	m.block(st, Transform3D(), Vector3.ONE)
	m.drum(st, Transform3D(), 2.0, 6.0, 0.0, NAN, false)
	m.block(st, Transform3D(Basis(), Vector3(0.0, 7.0, 0.0)), Vector3.ONE)
	var mixed := st.commit() as ArrayMesh
	var aabb := mixed.get_aabb()
	assert_gt(aabb.size.x, 3.9, "the drum's four metres across are in the mesh (%.1f)" % aabb.size.x)
	assert_true(aabb.position.y < 0.0 and aabb.end.y > 7.0, "and the blocks below and above it")
	var arrays := mixed.surface_get_arrays(0)
	var idx: Variant = arrays[Mesh.ARRAY_INDEX]
	var points := (idx as PackedInt32Array).size() if idx != null and (idx as PackedInt32Array).size() > 0 \
			else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var tris := floori(points / 3.0)
	assert_true(tris >= floori(drum_only / 3.0) + 24, "every triangle of the drum and of both blocks is drawn (%d)" % tris)


## A fall's face is the forge's cliff ledges, stacked in columns that step back in ledges: no cliff
## slab and no boulder pressed flat (they read as boxes and as cloud), every ledge standing on the
## one below it or on the ground (nothing floating), the channel lower than its neighbours with
## the lip at its top, moss on the ledges and the water going over.
func test_a_falls_face_is_ledges_of_bedded_rock_stepping_back() -> void:
	for region in ["core:region/hearthvale", "core:region/briarwold", "core:region/skerrow"]:
		var d := _dress("waterfall", region, "a river dropping off the scarp in a single white sheet")
		assert_true(d.find_children("*cliff_slab*", "MultiMeshInstance3D", true, false).is_empty(), "%s: no cliff slabs" % region)
		assert_false(d.find_children("*cliff_ledge*", "MultiMeshInstance3D", true, false).is_empty(), "%s: cliff ledges" % region)
		var columns: Array = d.get_meta("rock_columns", [])
		assert_gt(columns.size(), 2, "%s: columns across the face" % region)
		var tops: Array[float] = []
		for c in columns.size():
			var stack: Array = columns[c]
			assert_gt(stack.size(), 1, "%s: column %d is stacked" % [region, c])
			for i in stack.size():
				var piece: Dictionary = stack[i]
				var bottom := float(piece["bottom"])
				if i == 0:
					var f: Vector2 = piece["front"]
					assert_true(bottom <= d.kit.on_ground(f.x, f.y).y, "%s: column %d stands in the ground" % [region, c])
				else:
					var below: Dictionary = stack[i - 1]
					assert_true(bottom <= float(below["top"]) + 0.01, "%s: ledge %d of column %d stands on the one below" % [region, i, c])
			tops.append(float((stack[-1] as Dictionary)["top"]))
		var mid := int(columns.size() / 2.0)
		assert_true(tops[mid] < tops[mid - 1] and tops[mid] < tops[mid + 1], "%s: the channel is lower than its neighbours" % region)
		var lip := _marker(d, "lip")
		assert_true(lip != null and absf(lip.position.y - tops[mid]) < 0.3, "%s: the lip is the channel's top" % region)
		assert_false(d.find_children("*moss_patch*", "MultiMeshInstance3D", true, false).is_empty(), "%s: moss on the ledges" % region)
		assert_true(d.find_child("MouthDark", true, false) == null, "%s: no black board behind the water" % region)
		var fall := d.find_child("Fall", true, false) as MeshInstance3D
		assert_true(fall != null, "%s: the water going over" % region)
		if fall != null:
			assert_gt(fall.mesh.get_aabb().size.y, 7.0, "%s: a fall of %.1f m" % [region, fall.mesh.get_aabb().size.y])


## A fall's face is the front of a hill, not a wall stood on level ground with the sky behind it:
## the batch 3 shots had every fall between towers of blocks, and the Three Sisters as a stepped
## pyramid in the river. Until the land carves a step where a fall stands, the dressing raises the
## hill itself: a tableland behind the face at its crest, the stream across it to the lip, the
## ground falling away behind it and round its ends. And no column beside the channel stands more
## than a couple of metres over the lip.
func test_a_falls_face_is_the_front_of_a_hill() -> void:
	for spec in [["core:region/hearthvale", "a river dropping off the scarp in a single white sheet", "lip", true],
			["core:region/cinderlea", "a dry fall of black glass, still and polished", "lip", true],
			["core:region/skerrow", "three falls one above the other, a terrace to each", "lip2", false]]:
		var region: String = spec[0]
		var d := _dress("waterfall", region, str(spec[1]))
		for i in 2:
			await _tree().physics_frame
		var brow := d.find_child("Brow", true, false) as MeshInstance3D
		assert_true(brow != null, "%s: the hill behind the face" % region)
		var lip := _marker(d, str(spec[2]))
		assert_true(lip != null, "%s: its lip" % region)
		if brow == null or lip == null:
			continue
		assert_true(d.find_child("Stream", true, false) != null, "%s: the stream across the top to the lip" % region)
		# the face's frame, off the column whose top is at the lip
		var columns: Array = d.get_meta("rock_columns", [])
		var facing := Vector2.ZERO
		var near := INF
		var lip2 := Vector2(lip.position.x, lip.position.z)
		for stack in columns:
			var top_piece: Dictionary = (stack as Array)[-1]
			var o: Vector3 = (top_piece["xform"] as Transform3D).origin
			var f: Vector2 = top_piece["front"]
			if f.distance_to(lip2) < near:
				near = f.distance_to(lip2)
				facing = (f - Vector2(o.x, o.z)).normalized()
		var perp := Vector2(-facing.y, facing.x)
		var space := d.get_world_3d().direct_space_state
		var ground_at := func(p: Vector2) -> float:
			var from := d.to_global(Vector3(p.x, lip.position.y + 30.0, p.y))
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from - Vector3(0.0, 80.0, 0.0)))
			return NAN if hit.is_empty() else d.to_local(hit["position"]).y
		# on the tableland seven metres back from the lip, about as high as the lip
		var back: float = ground_at.call(lip2 - facing * 7.0)
		assert_false(is_nan(back), "%s: ground behind the lip" % region)
		if not is_nan(back):
			assert_true(absf(back - lip.position.y) < 1.4, "%s: the tableland behind the lip at %.1f, the lip at %.1f" % [region, back, lip.position.y])
		# beside the face's end, the hill's side: higher than the ground, lower than the crest
		var reach := 0.0
		var crest := -INF
		for stack in columns:
			var top_piece: Dictionary = (stack as Array)[-1]
			var o: Vector3 = (top_piece["xform"] as Transform3D).origin
			reach = maxf(reach, absf((Vector2(o.x, o.z) - lip2).dot(perp)))
			crest = maxf(crest, float(top_piece["top"]))
		var side_y: float = ground_at.call(lip2 - perp * (reach + 2.4 + 4.0) - facing * 1.0)
		assert_false(is_nan(side_y), "%s: the hill's side past the face's end" % region)
		if not is_nan(side_y):
			assert_true(side_y > 0.5 and side_y < crest, "%s: the side at %.1f, between the ground and the crest %.1f" % [region, side_y, crest])
		# and far behind, down to the ground again
		var far_y: float = ground_at.call(lip2 - facing * 60.0)
		assert_true(is_nan(far_y) or far_y < 0.3, "%s: the hill comes down to the ground behind (%.1f)" % [region, far_y])
		if bool(spec[3]):
			for stack in columns:
				var top_piece: Dictionary = (stack as Array)[-1]
				assert_true(float(top_piece["top"]) < lip.position.y + 2.3, "%s: no column stands %.1f m over the lip" % [region, float(top_piece["top"]) - lip.position.y])


## The hill behind a fall is drawn in the ground's own texture at the terrain's own scale and value,
## so it reads as the ground it rises from.
func test_a_brow_is_the_grounds_own_texture_at_its_scale() -> void:
	var builders := load(PoiDressing.BUILDERS_PATH) as GDScript
	var mine: Dictionary = builders.get_script_constant_map()["GROUND_SLOTS"]
	var terrain := load("res://tools_gd/import_terrain.gd") as GDScript
	var theirs: Dictionary = {}
	for slot in terrain.get_script_constant_map()["SLOTS"]:
		theirs[str((slot as Dictionary)["name"])] = slot
	for slot_name in mine:
		assert_true(theirs.has(slot_name), "%s is a terrain slot" % slot_name)
		if not theirs.has(slot_name):
			continue
		var spec: Array = mine[slot_name]
		assert_eq(float(spec[0]), float(theirs[slot_name]["tile_m"]), "%s: the terrain's tile size" % slot_name)
		assert_eq(float(spec[1]), float(theirs[slot_name]["value"]), "%s: the terrain's albedo value" % slot_name)
		assert_true(ResourceLoader.exists("res://assets/textures/terrain/%s_albedo_height.png" % slot_name), "%s: its texture" % slot_name)
	for region in builders.get_script_constant_map()["REGION_GROUND"].values():
		assert_true(mine.has(str(region)), "a region's ground (%s) is one of them" % region)


## The Skerr Stone is "a broken waystone": a stump standing and its top fallen at its foot.
func test_a_broken_waystone_has_its_top_at_its_foot() -> void:
	var whole := _dress("waystone", "core:region/skerrow", "a pilgrims' waystone with notches and a bowl")
	assert_true(whole.find_child("FallenTop", true, false) == null, "a whole waystone has no fallen top")
	var d := _dress("waystone", "core:region/skerrow", "a broken waystone at the fells' foot, cut in Skerrish on one face")
	var top := d.find_child("FallenTop", true, false) as Node3D
	assert_true(top != null, "its top lies at its foot")
	if top != null:
		assert_true(absf(top.basis.y.normalized().y) < 0.3, "on its back, not standing")
	assert_true(_marker(d, "the_bowl") != null, "and the bowl is still there")


## What the atlas's sentences name is there to see: Hatchmoor's dovecote, Pennywort's door-quern,
## Southgate's trough, the Last Farm's lamp in the window, and Rudd Mill's turf roof.
func test_a_farmstead_builds_what_its_sentence_names() -> void:
	var plain := _dress("farmstead", "core:region/hearthvale", "a farm off the road")
	for part in ["DovecoteHoles", "Quern", "Trough"]:
		assert_true(plain.find_child(part, true, false) == null, "a plain farm has no %s" % part)
	var lit := 0
	for s in NightLights.sources_of(plain):
		if str(s[1]) == "window":
			lit += 1
	assert_gt(lit, 0, "a lived-in farm's windows are lit after dark")
	var cote := _dress("farmstead", "core:region/hearthvale", "a farm with a dovecote in its yard")
	assert_true(cote.find_child("DovecoteHoles", true, false) != null and _marker(cote, "the_dovecote") != null, "Hatchmoor's dovecote")
	var quern := _dress("farmstead", "core:region/hearthvale", "a farm with a door-quern by its door")
	assert_true(quern.find_child("Quern", true, false) != null, "Pennywort's door-quern")
	var trough := _dress("farmstead", "core:region/hearthvale", "a farm with a stone trough in the yard")
	assert_true(trough.find_child("Trough", true, false) != null and trough.find_child("TroughWater", true, false) != null, "Southgate's trough, with water in it")
	var lamp := _dress("farmstead", "core:region/hearthvale", "the last farm, with a lamp in the window facing the grey")
	var lamps := 0
	for s in NightLights.sources_of(lamp):
		if str(s[1]) == "lantern":
			lamps += 1
	assert_eq(lamps, 1, "the Last Farm's lamp in the window")
	assert_false(bool(NightLights.KINDS["lantern"]["day"]), "lit at dusk, not at noon")
	var turf := _dress("mill", "core:region/skerrow", "a clan mill whose wheel is housed in a turf long-house")
	var thatch := _dress("mill", "core:region/skerrow", "a clan mill on the beck")
	var roof_of := func(d: Node) -> Color:
		var r := d.find_child("FabricRoof", true, false) as MeshInstance3D
		if r == null or not (r.material_override is ShaderMaterial):
			return Color.BLACK
		return (r.material_override as ShaderMaterial).get_shader_parameter("base_color")
	var green: Color = roof_of.call(turf)
	assert_true(green.g > green.r and green.g > green.b, "Rudd Mill's roof is turf (%s)" % green)
	assert_ne(roof_of.call(thatch), green, "and another mill's is not")
