extends TestCase
## Where a body is put down, and what the ground under it follows.
##
## Two faults stood a new player in the sea under the land. The opening place is one 8 m pad at
## sea level with 20 m of water round it and the cliffs 130 m off, and the spawn put the body on
## it as it was. And the spawn handed the streamer the player but never told Terrain3D, which
## kept building its clipmap and its collision around the world's fly camera -- a camera that
## went on flying on the player's own keys. These hold the landing and the hand-over.

const OPENING := "core:opening/new_game"


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## A sea south of z = -100 m with cliffs rising north of it, and one lone pad at the origin.
class FakeCoast:
	extends RefCounted

	func get_height(x: float, z: float) -> float:
		if Vector2(x, z).length() < 6.0:
			return 0.2
		return -20.0 if z > -100.0 else 40.0 + (-100.0 - z) * 0.05

	func is_water(x: float, z: float) -> bool:
		return get_height(x, z) < 0.0

	func nearest_water_level(_x: float, _z: float) -> float:
		return 0.0


class FakeTerrain3D:
	extends Node3D
	var camera: Camera3D = null

	func set_camera(c: Camera3D) -> void:
		camera = c


func test_a_new_game_never_begins_on_a_pad_in_the_sea() -> void:
	var coast := FakeCoast.new()
	var ashore := PlayerSpawn.dry_ground_near(coast, Vector3.ZERO)
	assert_false(coast.is_water(ashore.x, ashore.z), "the body comes ashore, not onto the water")
	assert_true(ashore.z < -100.0, "on the land past the cliffs' foot (z %.1f)" % ashore.z)
	assert_true(Vector2(ashore.x, ashore.z).length() < 140.0, "and the nearest land, not somewhere far (%.0f m)" % Vector2(ashore.x, ashore.z).length())
	assert_near(ashore.y, coast.get_height(ashore.x, ashore.z), 0.01, "standing on the ground there")


func test_dry_ground_is_left_where_it_is() -> void:
	var coast := FakeCoast.new()
	var inland := Vector3(30.0, 0.0, -300.0)
	var got := PlayerSpawn.dry_ground_near(coast, inland)
	assert_near(got.x, inland.x, 0.001, "dry ground is not moved")
	assert_near(got.z, inland.z, 0.001, "dry ground is not moved")


func test_the_real_opening_comes_ashore_on_the_built_map() -> void:
	var provider := TerrainProvider.new()
	if not provider.load_data():
		provider.free()
		return        # no built world in this checkout: the other tests cover the rule
	var place := str(ContentDB.get_or_empty(OPENING).get("place", ""))
	var xz: Array = ContentDB.get_or_empty(place).get("position", [])
	assert_eq(xz.size(), 2, "the opening names a place with a position")
	if xz.size() == 2:
		var start := Vector3(float(xz[0]), 0.0, float(xz[1]))
		var ashore := PlayerSpawn.dry_ground_near(provider, start)
		assert_true(PlayerSpawn._dry_at(provider, ashore.x, ashore.z),
				"the story opens on dry, walkable ground (%s)" % str(ashore.round()))
		assert_true(Vector2(ashore.x - start.x, ashore.z - start.z).length() < 400.0,
				"near the place it names (%.0f m off)" % Vector2(ashore.x - start.x, ashore.z - start.z).length())
	provider.free()


func test_following_a_body_gives_terrain3d_its_camera_and_grounds_the_fly_camera() -> void:
	# never entered into the tree: follow() needs none of the world's own setup, and entering it
	# would build a real terrain over the fake one
	var world := World.new()
	var terrain := FakeTerrain3D.new()
	world.terrain_node = terrain
	var fly := FlyCamera.new()
	fly.set_process(true)
	fly.set_process_unhandled_input(true)
	fly.current = true
	world.fly_camera = fly
	world.target = fly
	var body := Node3D.new()
	var arm := Node3D.new()
	var eye := Camera3D.new()
	arm.add_child(eye)
	body.add_child(arm)
	world.follow(body)
	assert_eq(world.target, body, "the world follows the body")
	assert_eq(terrain.camera, eye, "Terrain3D builds its ground and collision round the body's own camera")
	assert_false(fly.is_processing(), "the fly camera no longer flies on the player's keys")
	assert_false(fly.is_processing_unhandled_input(), "nor takes the mouse or Tab")
	assert_false(fly.current, "nor is anyone's eye")
	body.free()
	fly.free()
	terrain.free()
	world.free()
