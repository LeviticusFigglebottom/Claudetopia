extends TestCase
## The country after dark. Nights used to be dark rather than lit: the windows were black
## boxes, the lanterns the lakefolk and the reedfolk set out and the pilgrims' braziers were
## props with no light in them, and the only lamps in eight kilometres were the few the points
## of interest hung up. These pin the three halves of the fix: the panes that glow, the sources
## every settlement registers, and the pool of real lights that follows the eye.

const CENTRE := Vector3(900.0, 56.0, 2350.0)


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _raise(kind: String, region: String, id: String) -> Settlement:
	var s := Settlement.raise_at(id, kind, region, CENTRE, 90.0, [], [])
	_tree().root.add_child(s)
	return s


func _drop(n: Node) -> void:
	_tree().root.remove_child(n)
	n.queue_free()


# --- the panes -----------------------------------------------------------------------------------

func test_a_pane_carries_how_brightly_it_is_lit_in_its_alpha() -> void:
	var dark := Color(0.085, 0.08, 0.075)
	assert_near(FabricMesh.pane_colour(dark, 0.7).a, 0.7, 0.001)
	assert_near(FabricMesh.pane_colour(dark, 0.0).a, 0.0, 0.001, "a dark room is still glass")
	assert_true(FabricMesh.pane_colour(dark, 3.0).a < 0.995,
			"a pane lit as brightly as it goes must not read as timber (alpha 1)")
	assert_true(FabricMesh.joinery_material() is ShaderMaterial, "the joinery glows through its own shader")


func test_a_village_has_lit_windows_and_timber_that_is_not() -> void:
	var s := _raise("village", "core:region/hearthvale", "core:place/test_lit_village")
	var joinery: MeshInstance3D = s.get_node("Joinery")
	var colours: PackedColorArray = joinery.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var timber := 0
	var lit := 0
	var dark := 0
	for c in colours:
		if c.a > 0.995:
			timber += 1
		elif c.a > 0.01:
			lit += 1
		else:
			dark += 1
	assert_gt(timber, 0, "no timber left in the joinery")
	assert_gt(lit, 0, "no window in the village is lit")
	assert_gt(dark, 0, "every window in the village is lit, which nobody's is")
	_drop(s)


# --- the sources ---------------------------------------------------------------------------------

func test_a_settlement_registers_its_windows_doors_and_lamps() -> void:
	var before_w := NightLights.count("window")
	var before_l := NightLights.count("lantern")
	var before_b := NightLights.count("brazier")
	var lake := _raise("town", "core:region/brightwater", "core:place/test_lit_town")
	var ash := _raise("village", "core:region/cinderlea", "core:place/test_lit_ash")
	assert_gt(NightLights.count("window"), before_w, "no lit window was registered")
	assert_gt(NightLights.count("door"), 0, "no door lamp was registered")
	assert_gt(NightLights.count("lantern"), before_l, "the lakefolk's lanterns give no light")
	assert_gt(NightLights.count("brazier"), before_b, "the pilgrims' braziers give no light")
	_drop(lake)
	_drop(ash)
	assert_eq(NightLights.count("lantern"), before_l, "a settlement that left the tree left its lanterns behind")
	assert_eq(NightLights.count("brazier"), before_b)


## Nobody lives in a ruin, so none of its windows is lit and no door has a lamp. (Its props may
## still hold a brazier somebody left; only the houses have to be dark.)
func test_a_ruin_is_dark() -> void:
	var windows := NightLights.count("window")
	var doors := NightLights.count("door")
	var ruin := _raise("ruin_village", "core:region/cinderlea", "core:place/test_dark_ruin")
	assert_eq(NightLights.count("window"), windows, "a ruin has lit windows")
	assert_eq(NightLights.count("door"), doors, "a ruin has a lamp over a door")
	_drop(ruin)


func test_the_same_village_is_lit_the_same_every_time() -> void:
	var a := _raise("village", "core:region/hearthvale", "core:place/test_lit_twice")
	var first := NightLights.sources().size()
	_drop(a)
	var gone := NightLights.sources().size()
	var b := _raise("village", "core:region/hearthvale", "core:place/test_lit_twice")
	assert_eq(NightLights.sources().size() - gone, first - gone, "a village lit differently on a second visit")
	_drop(b)


# --- the pool ------------------------------------------------------------------------------------

func _stage() -> Array:
	var holder := Node3D.new()
	_tree().root.add_child(holder)
	var cam := Camera3D.new()
	holder.add_child(cam)
	cam.position = Vector3(5000.0, 10.0, 5000.0)
	cam.current = true
	var lights := NightLights.new()
	holder.add_child(lights)
	var owner := Node3D.new()
	holder.add_child(owner)
	return [holder, cam, lights, owner]


func test_the_pool_lights_the_nearest_lamps_at_night_and_none_by_day() -> void:
	var st := _stage()
	var lights: NightLights = st[2]
	var owner: Node3D = st[3]
	var eye := Vector3(5000.0, 10.0, 5000.0)
	var near_points: Array = []
	for i in 12:
		near_points.append(eye + Vector3(3.0 + float(i) * 3.5, 0.0, 0.0))
	NightLights.add(owner, near_points, "lantern")
	NightLights.add(owner, [eye + Vector3(0.0, 0.0, 400.0)], "brazier")
	NightLights.add(owner, [eye + Vector3(1.0, 0.0, 0.0)], "window")
	lights.assign(1.0)
	assert_eq(lights.lit.size(), mini(lights.pool_size, 12), "the pool is spent on the lamps in reach")
	if lights.lit.size() > 0:
		var first: Vector3 = lights.lit[0][0]
		assert_true(first.distance_to(eye) < 4.0, "the nearest lamp is lit first")
	for s in lights.lit:
		assert_true(str(s[1]) != "window", "a window is a glow, never one of the pool's lights")
		assert_true((s[0] as Vector3).distance_to(eye) < NightLights.REAL_REACH_M, "a lamp out of reach took a light")
	lights.assign(0.0)
	assert_eq(lights.lit.size(), 0, "lamps lit by day")
	for c in lights.get_children():
		if c is OmniLight3D:
			assert_false((c as OmniLight3D).visible, "%s is on in daylight" % c.name)
	_drop(st[0])


func test_every_source_is_one_glow_in_one_draw() -> void:
	var st := _stage()
	var lights: NightLights = st[2]
	var owner: Node3D = st[3]
	NightLights.add(owner, [Vector3(1, 2, 3), Vector3(4, 5, 6)], "fire", Color(0.4, 0.9, 0.8))
	lights._process(0.0)
	var glow := lights.get_node("Glows") as MultiMeshInstance3D
	assert_eq(glow.multimesh.instance_count, NightLights.count(), "one glow per source")
	assert_eq(glow.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "a glow casts no shadow")
	# (the headless renderer keeps no per-instance buffers, so the colour is read off the
	# registry the MultiMesh is built from rather than off the MultiMesh)
	var mine := 0
	for s in NightLights.sources():
		var c: Color = s[2]
		if str(s[1]) == "fire" and is_equal_approx(c.g, 0.9) and is_equal_approx(c.r, 0.4):
			mine += 1
	assert_eq(mine, 2, "a fire that knows its colour keeps it")
	_drop(st[0])
