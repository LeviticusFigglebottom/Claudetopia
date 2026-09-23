extends TestCase
## The country after dark. Nights used to be dark rather than lit: the windows were black
## boxes, the lanterns the lakefolk and the reedfolk set out and the pilgrims' braziers were
## props with no light in them, and the only lamps in eight kilometres were the few the points
## of interest hung up. These pin the three halves of the fix: the panes that glow, the sources
## every settlement registers, and the pool of real lights that follows the eye.

## Merrowby, wherever the map puts it (docs/COORDINATES.md).
var CENTRE := at_place("core:place/merrowby", 56.0)


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

func _pane_colours(lit: float) -> PackedColorArray:
	var fabric := FabricMesh.new()
	fabric.pane("joinery", Transform3D.IDENTITY, Vector3(0.8, 0.84, 0.024), lit)
	var holder := Node3D.new()
	var mi := fabric.commit(holder, "joinery", FabricMesh.joinery_material(), "Joinery")
	var colours: PackedColorArray = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	holder.free()
	return colours


## The lit window is painted from the pane's own coordinates -- glazing bars, the hearth's glow
## low in the glass -- and those ride in the vertex colour's red and green, with how brightly
## the room is lit in its alpha. A pane written as one flat colour glowed as a white lightbox.
func test_a_pane_carries_its_coordinates_and_its_light_in_its_colour() -> void:
	var colours := _pane_colours(0.7)
	var lo := Vector2(1.0, 1.0)
	var hi := Vector2(0.0, 0.0)
	# a vertex colour is stored at eight bits a channel: 0.7 comes back as 178/255
	for c in colours:
		assert_near(c.a, 0.7, 1.0 / 255.0, "every corner of a pane carries its room's light")
		lo = Vector2(minf(lo.x, c.r), minf(lo.y, c.g))
		hi = Vector2(maxf(hi.x, c.r), maxf(hi.y, c.g))
	assert_near(lo.x, 0.0, 0.001, "the pane's left edge is u = 0")
	assert_near(hi.x, 1.0, 0.001, "and its right edge u = 1")
	assert_near(lo.y, 0.0, 0.001, "its foot is v = 0")
	assert_near(hi.y, 1.0, 0.001, "and its head v = 1")
	for c in _pane_colours(0.0):
		assert_near(c.a, 0.0, 0.001, "a dark room is still glass")
	for c in _pane_colours(3.0):
		assert_true(c.a < 0.995, "a pane lit as brightly as it goes must not read as timber (alpha 1)")
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


## A point of interest's fire or lamp used to be an OmniLight3D of its own, always on, and nothing
## counted those against the pool: six along the Long Stride and eight from the pool passed the
## twelve lights Compatibility draws on one object. It is a source now, with its own energy and
## reach, and no light node is left standing in the dressing.
func test_a_poi_light_is_a_source_not_a_light_of_its_own() -> void:
	var root := Node3D.new()
	_tree().root.add_child(root)
	var kit := PoiKit.new(root, Vector3.ZERO, 20.0, "core:region/brightwater", false, "core:poi/test_lamp")
	kit.light(Vector3(1.0, 2.0, 3.0), Color(1.0, 0.6, 0.3), 2.8, 13.0)
	assert_empty(root.find_children("*", "OmniLight3D", true, false), "a POI light stood its own OmniLight3D")
	var mine := NightLights.sources_of(root)
	assert_eq(mine.size(), 1, "the light was not registered")
	if mine.size() == 1:
		var s: Array = mine[0]
		assert_eq(str(s[1]), "poi")
		assert_near(float(s[3]), 2.8, 0.001, "the builder's energy is kept")
		assert_near(float(s[4]), 13.0, 0.001, "and its reach")
	_drop(root)
	assert_empty(NightLights.sources_of(root), "a dressing that left kept its light")


## By day the pool lights only what always burned -- a point of interest's fires and lamps --
## and never more than it has, which is at most eight: the other four of Compatibility's twelve
## are a Hearthstone's flame or two, the player's lantern and an Echo.
func test_by_day_the_pool_lights_only_what_always_burned() -> void:
	var st := _stage()
	var lights: NightLights = st[2]
	var owner: Node3D = st[3]
	var eye := Vector3(5000.0, 10.0, 5000.0)
	NightLights.add(owner, [eye + Vector3(2.0, 0.0, 0.0)], "lantern")
	NightLights.add(owner, [eye + Vector3(4.0, 0.0, 0.0)], "poi", Color(1, 0.6, 0.3, 1), 2.0, 9.0)
	lights.assign(0.0)
	assert_eq(lights.lit.size(), 1, "by day only the point of interest's fire is lit")
	if lights.lit.size() == 1:
		assert_eq(str(lights.lit[0][1]), "poi")
	var many: Array = []
	for i in 30:
		many.append(eye + Vector3(1.0 + float(i), 0.0, 1.0))
	NightLights.add(owner, many, "poi")
	lights.assign(1.0)
	assert_true(lights.lit.size() <= NightLights.MAX_POOL, "the pool lit %d lights" % lights.lit.size())
	lights._size_pool(99)
	assert_eq(lights.pool_size, NightLights.MAX_POOL, "the setting cannot raise the pool past its cap")
	_drop(st[0])


func test_the_costs_are_counted() -> void:
	var st := _stage()
	var lights: NightLights = st[2]
	NightLights.reset_stats()
	lights.rebuild_glow()
	lights.assign(1.0)
	assert_eq(int(NightLights.stats["rebuilds"]), 1, "a rebuild went uncounted")
	assert_eq(int(NightLights.stats["assigns"]), 1, "an assignment went uncounted")
	assert_eq(int(NightLights.stats["rebuild_sources"]), NightLights.count(), "the rebuild drew a different registry")
	_drop(st[0])


func test_every_source_is_one_glow_in_one_draw() -> void:
	var st := _stage()
	var lights: NightLights = st[2]
	var owner: Node3D = st[3]
	NightLights.add(owner, [Vector3(1, 2, 3), Vector3(4, 5, 6)], "fire", Color(0.4, 0.9, 0.8))
	lights.rebuild_glow()
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


## The glow MultiMesh is filled from one buffer made of each owner's chunk, written once when the
## owner registers. A chunk is sixteen floats a source in the MultiMesh's own layout: the scaled
## basis in rows with the origin at the end of each, then the colour and the glow's strength.
## When the owner leaves, its chunk goes with it.
func test_a_glow_is_written_once_in_the_multimesh_layout() -> void:
	var st := _stage()
	var lights: NightLights = st[2]
	var owner: Node3D = st[3]
	NightLights.add(owner, [Vector3(1, 2, 3), Vector3(4, 5, 6)], "brazier", Color(0.4, 0.9, 0.8))
	var chunk: PackedFloat32Array = NightLights._chunks[owner.get_instance_id()]
	var n := (NightLights.sources_of(owner)).size()
	assert_eq(chunk.size(), n * 16, "sixteen floats a source")
	var size := float(NightLights.KINDS["brazier"]["size"])
	var last := (n - 1) * 16
	assert_near(chunk[last + 0], size, 0.0001, "the basis is the kind's size")
	assert_near(chunk[last + 5], size, 0.0001)
	assert_near(chunk[last + 10], size, 0.0001)
	assert_near(chunk[last + 3], 4.0, 0.0001, "the origin closes each row: x")
	assert_near(chunk[last + 7], 5.0, 0.0001, "y")
	assert_near(chunk[last + 11], 6.0, 0.0001, "z")
	assert_near(chunk[last + 13], 0.9, 0.0001, "then the colour")
	assert_near(chunk[last + 15], float(NightLights.KINDS["brazier"]["glow"]), 0.0001, "and the strength")
	lights.rebuild_glow()
	var total := 0
	for id in NightLights._chunks:
		total += (NightLights._chunks[id] as PackedFloat32Array).size() / 16
	assert_eq(total, NightLights.count(), "every source has its place in the buffer, and only once")
	var id := owner.get_instance_id()
	NightLights.remove(id)
	assert_false(NightLights._chunks.has(id), "a departed owner takes its glows with it")
	_drop(st[0])
