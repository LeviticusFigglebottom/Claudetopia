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
