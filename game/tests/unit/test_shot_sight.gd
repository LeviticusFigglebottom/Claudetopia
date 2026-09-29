extends TestCase
## What a shot's camera will see, as cells (systems/cinematic/shot_sight.gd), on ground whose shape
## the test chooses: the country ahead of the camera and none behind it, full detail near and the far
## ring's further out, nothing past a ridge the trees on it would not show over, and the cells a pan
## turns to counted from the moment it turns to them.

## A ridge across the view, 400 to 440 m north of the origin, this tall; flat ground elsewhere.
var ridge := 0.0
var _streamer: WorldStreamer = null


func before_each() -> void:
	ridge = 0.0
	_streamer = WorldStreamer.new()


func after_each() -> void:
	_streamer.free()
	_streamer = null


func _ground(_x: float, z: float) -> float:
	return ridge if z < -400.0 and z > -440.0 else 0.0


func _places(id: String) -> Vector3:
	return Vector3.ZERO if id == "core:place/o" else Vector3.INF


## A shot from 20 m over the origin, looking along `from` and turning to `to` (bearings in degrees).
func _path(from: float, to: float, height := 20.0) -> CinematicPath:
	var keys := []
	for k in [[0.0, from], [1.0, to]]:
		keys.append({"t": k[0], "at": {"place": "core:place/o", "height": height},
				"look": {"place": "core:place/o", "bearing": k[1], "distance": 300.0, "height": height * 0.7}})
	return CinematicPath.resolve({"id": "test", "duration": 10.0, "fov": 50.0, "keys": keys},
			Callable(self, "_ground"), Callable(self, "_places"))


func _seen(path: CinematicPath) -> Dictionary:
	return ShotSight.seen(path, _streamer, Callable(self, "_ground"))


func test_a_camera_looking_north_wants_the_country_ahead_and_none_behind() -> void:
	var seen := _seen(_path(0.0, 0.0))
	var here := _streamer.cell_of(Vector3.ZERO)
	var far_ahead := _streamer.cell_of(Vector3(0.0, 0.0, -900.0))
	var behind := _streamer.cell_of(Vector3(0.0, 0.0, 700.0))
	assert_true(seen.has(here), "the ground under the camera is wanted")
	assert_true(seen.has(far_ahead), "and the ground 900 m ahead, past the streamer's own rings (%d cells)" % seen.size())
	assert_false(seen.has(behind), "but not the ground behind it")
	assert_eq(int(seen[_streamer.cell_of(Vector3(0.0, 0.0, -150.0))][0]), 1, "near ground is wanted at full detail")
	assert_eq(int(seen[far_ahead][0]), 2, "far ground at the far ring's")
	assert_false(seen.has(_streamer.cell_of(Vector3(0.0, 0.0, -1400.0))), "nothing past the reach")


func test_a_ridge_hides_the_country_behind_it() -> void:
	ridge = 120.0
	var seen := _seen(_path(0.0, 0.0))
	assert_true(seen.has(_streamer.cell_of(Vector3(0.0, 0.0, -420.0))), "the ridge itself is seen")
	assert_false(seen.has(_streamer.cell_of(Vector3(0.0, 0.0, -900.0))), "the ground behind it is not")


func test_a_pan_wants_what_it_turns_to_from_when_it_turns() -> void:
	var seen := _seen(_path(0.0, 90.0))
	var east := _streamer.cell_of(Vector3(800.0, 0.0, 0.0))
	assert_true(seen.has(east), "the pan's end is wanted")
	assert_true(float(seen[east][1]) > 0.5, "and first seen late in the shot (%.2f)" % float(seen[east][1]))
	var opening := ShotSight.rings(seen, 0.3)
	assert_false(opening.has(east), "so a shot's opening does not wait for it")
	assert_true(opening.has(_streamer.cell_of(Vector3(0.0, 0.0, -800.0))), "but does wait for what it opens on")


func test_merged_wants_each_cell_at_the_nearer_ring() -> void:
	var m := ShotSight.merged({Vector2i(1, 1): 2, Vector2i(2, 2): 1}, {Vector2i(1, 1): 1, Vector2i(3, 3): 2})
	assert_eq(m, {Vector2i(1, 1): 1, Vector2i(2, 2): 1, Vector2i(3, 3): 2})
