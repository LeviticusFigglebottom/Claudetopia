extends TestCase
## The camera's arithmetic, on ground whose shape the test chooses: where a key lands, that a move
## starts and ends at rest, that it passes through the keys between, and that the hand-over's last
## frame is the gameplay camera's own.

const FLAT := 10.0


func _ground(_x: float, _z: float) -> float:
	return FLAT


func _places(id: String) -> Vector3:
	match id:
		"core:place/a":
			return Vector3(100.0, 0.0, 200.0)
		"core:place/b":
			return Vector3(-50.0, 0.0, 0.0)
	return Vector3.INF


func _resolve(shot: Dictionary, player := Vector3.INF, camera := Transform3D()) -> CinematicPath:
	return CinematicPath.resolve(shot, Callable(self, "_ground"), Callable(self, "_places"), player, camera)


func _shot(keys: Array) -> Dictionary:
	return {"id": "test", "duration": 10.0, "keys": keys}


func _key(t: float, bearing: float, distance: float, height: float, look_place := "core:place/a") -> Dictionary:
	return {"t": t, "at": {"place": "core:place/a", "bearing": bearing, "distance": distance, "height": height},
			"look": {"place": look_place, "height": 3.0}}


func test_bearing_distance_and_height_put_a_key_where_a_compass_would() -> void:
	var ground := Callable(self, "_ground")
	var places := Callable(self, "_places")
	var north := CinematicPath.point_of({"place": "core:place/a", "bearing": 0, "distance": 50, "height": 5}, ground, places)
	assert_true(north.is_equal_approx(Vector3(100, 15, 150)), "north is -z: %s" % north)
	var east := CinematicPath.point_of({"place": "core:place/a", "bearing": 90, "distance": 50, "height": 5}, ground, places)
	assert_true(east.is_equal_approx(Vector3(150, 15, 200)), "east is +x: %s" % east)
	var south := CinematicPath.point_of({"place": "core:place/a", "bearing": 180, "distance": 50, "height": 5}, ground, places)
	assert_true(south.is_equal_approx(Vector3(100, 15, 250)), "south is +z: %s" % south)
	var nowhere := CinematicPath.point_of({"place": "core:place/nowhere", "height": 5}, ground, places)
	assert_eq(nowhere, Vector3.INF, "a place the world does not have is nowhere, not the origin")


func test_a_move_starts_and_ends_on_its_keys_and_at_rest() -> void:
	var path := _resolve(_shot([_key(0.0, 90, 100, 20), _key(1.0, 90, 40, 12)]))
	assert_true(path.is_playable())
	assert_true(path.position_at(0.0).is_equal_approx(Vector3(200, 30, 200)), "starts on the first key")
	assert_true(path.position_at(1.0).is_equal_approx(Vector3(140, 22, 200)), "ends on the last")
	var start_step := path.position_at(0.01).distance_to(path.position_at(0.0))
	var middle_step := path.position_at(0.51).distance_to(path.position_at(0.5))
	var end_step := path.position_at(1.0).distance_to(path.position_at(0.99))
	assert_true(start_step < middle_step * 0.05, "eased in: %.4f against %.4f" % [start_step, middle_step])
	assert_true(end_step < middle_step * 0.05, "eased out: %.4f against %.4f" % [end_step, middle_step])


func test_the_camera_looks_at_what_the_key_says() -> void:
	var path := _resolve(_shot([_key(0.0, 90, 100, 20), _key(1.0, 90, 40, 12)]))
	for u in [0.0, 0.37, 1.0]:
		var pose := path.pose(u)
		var want := (path.look_point_at(u) - pose.origin).normalized()
		assert_true((-pose.basis.z).is_equal_approx(want), "at %.2f the camera looks along %s, not %s" % [u, -pose.basis.z, want])
		assert_near(pose.basis.x.y, 0.0, 0.0001, "and the horizon is level")


func test_a_path_passes_through_the_keys_between_without_a_kink() -> void:
	var path := _resolve(_shot([_key(0.0, 90, 100, 20), _key(0.4, 0, 100, 30), _key(1.0, 270, 100, 20)]))
	# find the moment the eased time reaches the middle key
	var u := 0.0
	while path.eased(u) < 0.4 and u < 1.0:
		u += 0.0005
	assert_true(path.position_at(u).distance_to(Vector3(100, 40, 100)) < 0.5, "misses the middle key: %s" % path.position_at(u))
	var before := path.position_at(u) - path.position_at(u - 0.002)
	var after := path.position_at(u + 0.002) - path.position_at(u)
	assert_true(before.normalized().dot(after.normalized()) > 0.99, "turns a corner at the key")
	assert_near(before.length(), after.length(), before.length() * 0.1, "changes pace at the key")


func test_the_hand_over_ends_on_the_gameplay_camera_exactly() -> void:
	var feet := Vector3(10, 10, 20)
	var camera := CinematicPlayer.resting_camera(feet, 0.3)
	var shot := {"id": "end", "duration": 12.0, "handover": true, "keys": [
		{"t": 0.0, "at": {"place": "player", "bearing": 180, "distance": 60, "height": 20}, "look": {"place": "player", "height": 2}},
		{"t": 1.0, "at": "player_camera"}]}
	var path := _resolve(shot, feet, camera)
	assert_true(path.is_playable())
	var last := path.pose(1.0)
	assert_true(last.origin.is_equal_approx(camera.origin), "the last frame stands where the gameplay camera does")
	assert_true((-last.basis.z).is_equal_approx(-camera.basis.z), "and looks where it looks")
	assert_true(path.position_at(0.0).is_equal_approx(Vector3(10, 30, 80)), "and it began relative to the body")


func test_the_resting_camera_is_behind_and_above_the_right_shoulder() -> void:
	var feet := Vector3(0, 5, 0)
	var cam := CinematicPlayer.resting_camera(feet, 0.0)
	assert_gt(cam.origin.z, feet.z + 2.5, "behind a body facing north")
	assert_gt(cam.origin.y, feet.y + 1.5, "above its head")
	var side := 1.0 if int(Settings.get_value("controls", "camera_side", 1)) >= 0 else -1.0
	assert_gt(cam.origin.x * side, 0.3, "over the shoulder the settings choose")
	assert_true((-cam.basis.z).z < -0.9, "looking the way the body faces")


func test_a_key_at_a_place_the_world_does_not_have_is_not_played() -> void:
	var path := _resolve(_shot([_key(0.0, 90, 100, 20), _key(1.0, 90, 40, 12, "core:place/nowhere")]))
	assert_false(path.is_playable(), "a path with a key nowhere must be refused, not flown to the origin")
	assert_eq(path.unresolved.size(), 1)
