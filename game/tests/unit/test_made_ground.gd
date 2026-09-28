extends TestCase
## A town's made ground (its setts, flags and beaten earth) lies over the terrain everywhere, not
## only at its corners: triage 15, "the ground textures of several towns, i.e. their roads/stone,
## clip in several areas showing the terrain underneath". A patch drawn flat between its corners
## had the terrain standing up through its middle where the ground bent under it, at a pad's lip
## (tools_gd/paving_probe.gd measured 0.38 m at Kharrow Hold). Settlement._fit_quad now splits and
## lifts a patch there, and leaves one on level ground as it was.

var _world: World = null
var _was_world: World = null
var _provider: TerrainProvider = null
var _town: Settlement = null


## A pad level at 10 m for x < 0, and its lip falling away at one in two past it.
class PadLip extends TerrainProvider:
	func get_height(x: float, _z: float) -> float:
		return 10.0 - maxf(x, 0.0) * 0.5


func before_each() -> void:
	_provider = PadLip.new()
	_world = World.new()
	_world.provider = _provider
	_was_world = World.instance
	World.instance = _world
	# a camp builds no fabric of its own, so the test lays the only made ground there is
	_town = Settlement.raise_at("core:place/test_made_ground", "camp", "core:region/hearthvale",
			Vector3(0.0, 10.0, 0.0), 40.0, [], [])
	(Engine.get_main_loop() as SceneTree).root.add_child(_town)


func after_each() -> void:
	if World.instance == _world:
		World.instance = _was_world
	_town.queue_free()
	_world.free()
	_provider.free()


## The upward faces of a patch laid over `corners`, in world space.
func _laid(corners: PackedVector2Array) -> PackedVector3Array:
	var fabric := FabricMesh.new()
	_town._lay(fabric, "paving", corners, Color.WHITE)
	var mi := fabric.commit(_town, "paving", null, "Paving")
	var out := PackedVector3Array()
	var faces: PackedVector3Array = mi.mesh.get_faces()
	for f in range(0, faces.size(), 3):
		var a := faces[f] + _town.global_position
		var b := faces[f + 1] + _town.global_position
		var c := faces[f + 2] + _town.global_position
		if (c - a).cross(b - a).normalized().y > 0.5:
			out.append_array([a, b, c])
	return out


func _square(x0: float, z0: float, side: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, z0), Vector2(x0 + side, z0), Vector2(x0 + side, z0 + side),
			Vector2(x0, z0 + side)])


func test_made_ground_over_a_pads_lip_stands_over_the_ground_everywhere() -> void:
	var tris := _laid(_square(-1.7, 0.0, 6.0))       # its first corners on the level, its last down the lip
	var lowest := INF
	var highest := -INF
	for f in range(0, tris.size(), 3):
		for i in range(7):
			for j in range(7 - i):
				var q: Vector3 = tris[f] + (tris[f + 1] - tris[f]) * (float(i) / 6.0) + (tris[f + 2] - tris[f]) * (float(j) / 6.0)
				var over := q.y - _provider.get_height(q.x, q.z)
				lowest = minf(lowest, over)
				highest = maxf(highest, over)
	assert_true(lowest > 0.0, "the ground stands %.2f m up through the made ground at the lip" % -lowest)
	assert_true(highest < 0.2, "the made ground stands %.2f m off the ground at the lip" % highest)


func test_made_ground_on_the_level_is_not_cut_finer() -> void:
	# 6 m square in 3 m cells: four quads, eight triangles, as it always was
	assert_eq(_laid(_square(-30.0, 0.0, 6.0)).size() / 3, 8, "level ground laid in more pieces than its cells")


## A pad cut level into rising ground at 10 m for x < -3, its bank rising at one in two past it.
class PadCut extends TerrainProvider:
	func get_height(x: float, _z: float) -> float:
		return 10.0 + maxf(x + 3.0, 0.0) * 0.5


## Triage 27: a few hundred metres off, the terrain's clipmap draws a vertex only every 8 m, and its
## triangle from the pad's middle to the top of the bank cuts over the level. A patch there carries
## what it must stand up by on that ring (UV.y), which its shader adds only that far off; close up it
## lies where it did.
func test_made_ground_carries_its_lift_over_the_far_rings() -> void:
	var cut := PadCut.new()
	_world.provider = cut
	var fabric := FabricMesh.new()
	_town._lay(fabric, "paving", _square(-7.0, 0.0, 3.0), Color.WHITE)
	_town._lay(fabric, "paving", _square(-30.0, 0.0, 3.0), Color.WHITE)
	var arrays := fabric.commit(_town, "paving", null, "Paving").mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	_world.provider = _provider
	cut.free()
	assert_eq(uv.size(), verts.size(), "the made ground's vertices carry no lift")
	for i in verts.size():
		var y := verts[i].y + _town.global_position.y
		assert_true(absf(y - 10.05) < 0.001, "made ground on the level laid at %.2f, not 10.05" % y)
		var x := verts[i].x + _town.global_position.x
		if x < -20.0:
			assert_true(uv[i].length() < 0.001 and absf(uv2[i].x) < 0.001, "made ground far from the bank lifted by %s" % str(uv[i]))
		else:
			# the 8 m ring's triangle to the bank's top (11.5 m at x = 0) stands 0.75 m over x = -4
			assert_true(uv[i].x < 0.001, "lifted %.2f m on the 4 m ring, which is level here" % uv[i].x)
			assert_true(uv[i].y > 0.7 and uv[i].y < 0.8, "lifted %.2f m on the 8 m ring" % uv[i].y)
			assert_true(uv2[i].x > uv[i].y, "lifted less on the 16 m ring (%.2f m) than the 8 m" % uv2[i].x)


## Triage 31: a drystone wall along the foot of that bank goes as deep into the far rings as the
## paving did (Skarlow's 4.4 m against its crag). Its every stone carries the ring's lift (CUSTOM0),
## and one out on the level carries none.
func test_a_wall_by_the_bank_carries_its_lift_over_the_far_rings() -> void:
	var cut := PadCut.new()
	_world.provider = cut
	var fabric := FabricMesh.new()
	for key in Settlement.GROUND_FOLLOWERS:
		fabric.carry_ground_lift(key)
	_town._wall(fabric, Vector2(-4.0, 0.0), Vector2(-4.0, 6.0), 1.05)
	_town._wall(fabric, Vector2(-30.0, 0.0), Vector2(-30.0, 6.0), 1.05)
	var arrays := fabric.commit(_town, "drystone", null, "Drystone").mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var lift: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
	_world.provider = _provider
	cut.free()
	assert_eq(lift.size(), verts.size() * 3, "the wall's vertices carry no lift")
	for i in verts.size():
		var x := verts[i].x + _town.global_position.x
		var by := Vector3(lift[i * 3], lift[i * 3 + 1], lift[i * 3 + 2])
		if x < -20.0:
			assert_true(by.length() < 0.001, "a wall on the level lifted by %s" % str(by))
		else:
			# the 8 m ring's triangle to the bank's top stands over the wall's foot by as much as
			# over the paving there (0.75 m at x = -4), and a little more on the wall's far side
			assert_true(by.y > 0.7 and by.y < 1.0, "a wall by the bank lifted %.2f m on the 8 m ring" % by.y)
			assert_true(by.z > by.y, "lifted less on the 16 m ring (%.2f m) than the 8 m" % by.z)
