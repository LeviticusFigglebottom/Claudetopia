extends TestCase
## The player walks up the built country on Terrain3D's own collision, from real keys, where a
## new game begins: the heath round the Stair Head at the steepest walkable pitches found there,
## and the marked way north toward the Choir. (tests/unit/test_walking_uphill.gd holds the same
## on planar ramps of measured slope; this is the same body on the land as it is built.)
##
## Needs the built world (`./run.sh world`) and Terrain3D; without either it says so and skips.

const WORLD_SCENE := "res://world/world.tscn"
const START := "core:poi/stair_head"
const KEYS: Array[Key] = [KEY_W, KEY_SHIFT, KEY_ALT]
## Slopes looked for on the heath (degrees), each ±2.5°, held steady over the run.
const WANTED: Array[float] = [5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0]
const RUN_M := 7.0
const SEARCH_M := 260.0
## How far round the Stair Head's fire the camp stands, with its carts and tents.
const CAMP_M := 25.0

var _w: World = null
var player: Player = null


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	GameState.reset_for_new_game(7)
	SaveSystem.pending.clear()
	Settings.load_settings()
	Settings._load_binding_defs()
	Settings.apply_bindings()
	Settings.data["gameplay"]["play_opening"] = false


func after_each() -> void:
	for k in KEYS:
		_key(k, false)
	if _w != null and is_instance_valid(_w):
		_tree().root.remove_child(_w)
		_w.queue_free()
	_w = null
	player = null
	Settings.load_settings()
	Settings.apply_bindings()
	GameState.reset_for_new_game(7)


func _key(code: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code as Key
	ev.physical_keycode = code as Key
	ev.key_label = code as Key
	ev.pressed = pressed
	ev.shift_pressed = pressed and code == KEY_SHIFT
	ev.alt_pressed = pressed and code == KEY_ALT
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _ticks(n: int) -> void:
	for i in n:
		await _tree().physics_frame


## The world with its body, on Terrain3D; false (and a note) when that cannot be had here.
func _stand_up() -> bool:
	if not FileAccess.file_exists("res://world/generated/world_manifest.json"):
		skip("no built world: run ./run.sh world; skipped")
		return false
	_w = (load(WORLD_SCENE) as PackedScene).instantiate() as World
	_tree().root.add_child(_w)
	await _w.world_ready
	if _w.terrain_mode != "terrain3d":
		skip("Terrain3D is not drawing this world (%s); skipped" % _w.terrain_mode)
		return false
	player = _w.get_node("PlayerSpawn").get("player") as Player
	if player == null:
		return false
	# the body is stood up where it spawns a few seconds after the world is ready: until then a
	# teleport is undone and nothing stands on the ground
	for i in 1200:
		if player.is_on_floor():
			break
		await _tree().physics_frame
	await _ticks(30)
	return true


## Puts the body at `at` (xz) on the ground facing `yaw`, and waits for Terrain3D to build its
## collision round the body's camera and for the body to stand on it.
func _put(at: Vector2, yaw: float) -> bool:
	var y := World.get_height(at.x, at.y)
	player.teleport(Vector3(at.x, y + 0.05, at.y), yaw)
	# Terrain3D builds collision round the camera over some frames, and slower on a loaded machine
	for i in 300:
		await _tree().physics_frame
		if player.is_on_floor():
			await _ticks(4)
			return true
	return false


## The steepest way up at a point, and how steep (degrees), over `across` metres.
static func _uphill(at: Vector2, across := 4.0) -> Array:
	var best := Vector2.ZERO
	var slope := -1.0
	for a in range(0, 360, 15):
		var d := Vector2(cos(deg_to_rad(a)), sin(deg_to_rad(a)))
		var rise := World.get_height(at.x + d.x * across * 0.5, at.y + d.y * across * 0.5) \
				- World.get_height(at.x - d.x * across * 0.5, at.y - d.y * across * 0.5)
		var s := rad_to_deg(atan2(rise, across))
		if s > slope:
			slope = s
			best = d
	return [best, slope]


## A spot on the heath near `centre` whose slope is `deg` (±2.5°) and stays so for a run of RUN_M
## up it: [start, direction], or [] when there is none.
func _find_slope(centre: Vector2, deg: float) -> Array:
	var provider := World.terrain()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(deg * 97.0) + 11
	for i in 900:
		var r := sqrt(rng.randf()) * SEARCH_M
		var a := rng.randf_range(0.0, TAU)
		var p := centre + Vector2(cos(a), sin(a)) * r
		if provider.is_water(p.x, p.y):
			continue
		var up: Array = _uphill(p)
		if absf(float(up[1]) - deg) > 2.5:
			continue
		var d: Vector2 = up[0]
		var steady := true
		for t: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
			var q: Vector2 = p + d * (RUN_M + 2.0) * t
			if provider.is_water(q.x, q.y):
				steady = false
				break
			var along := World.get_height(q.x + d.x, q.y + d.y) - World.get_height(q.x - d.x, q.y - d.y)
			if absf(rad_to_deg(atan2(along, 2.0)) - deg) > 4.0:
				steady = false
				break
		if steady:
			return [p, d]
	return []


## Holds W (and a gait's key) for `seconds`, and measures from `settle` seconds in: {along m/s,
## level m/s, rise m, on_floor share}.
func _jog_up(seconds: float, settle: float, gait_keys: Array) -> Dictionary:
	for k in gait_keys:
		_key(k, true)
	var hz := float(Engine.physics_ticks_per_second)
	var out := {"along": 0.0, "level": 0.0, "rise": 0.0, "on_floor": 0.0}
	var last := player.global_position
	var first := last
	var n := 0
	for i in int(seconds * hz):
		await _tree().physics_frame
		var p := player.global_position
		if float(i) / hz >= settle:
			if n == 0:
				first = last
			out["along"] = float(out["along"]) + p.distance_to(last)
			out["level"] = float(out["level"]) + Vector2(p.x - last.x, p.z - last.z).length()
			out["on_floor"] = float(out["on_floor"]) + (1.0 if player.is_on_floor() else 0.0)
			n += 1
		last = p
	for k in gait_keys:
		_key(k, false)
	var t := maxf(float(n) / hz, 0.001)
	out["rise"] = last.y - first.y
	out["along"] = float(out["along"]) / t
	out["level"] = float(out["level"]) / t
	out["on_floor"] = float(out["on_floor"]) / maxf(float(n), 1.0)
	await _ticks(20)
	return out


func test_jogging_up_the_heath_by_the_stair_head_on_terrain3d_collision() -> void:
	if not await _stand_up():
		return
	var head := WorldProbe.xz_of(ContentDB.get_or_empty(START))
	var report: Array[String] = []
	var found := 0
	for deg in WANTED:
		var spot := _find_slope(head, deg)
		if spot.is_empty():
			report.append("%.0f° none within %.0f m" % [deg, SEARCH_M])
			continue
		found += 1
		var at: Vector2 = spot[0]
		var d: Vector2 = spot[1]
		if not await _put(at, atan2(-d.x, -d.y)):
			report.append("%.0f° no collision under (%.0f, %.0f)" % [deg, at.x, at.y])
			assert_true(false, "Terrain3D built no collision to stand on at (%.0f, %.0f)" % [at.x, at.y])
			continue
		var got := await _jog_up(1.6, 0.6, [KEY_W])
		var share := float(got["along"]) / Player.JOG_SPEED
		report.append("%.0f° at (%.0f, %.0f): %.0f%% of a jog, rose %.2f m, on the collider %.0f%%" % [
				deg, at.x, at.y, share * 100.0, float(got["rise"]), float(got["on_floor"]) * 100.0])
		assert_true(share > 0.85, "a jog up %.0f° at (%.0f, %.0f) made %.2f m/s along the ground" % [deg, at.x, at.y, float(got["along"])])
		assert_true(float(got["rise"]) > 0.0, "a jog up %.0f° at (%.0f, %.0f) did not climb" % [deg, at.x, at.y])
		assert_true(float(got["on_floor"]) > 0.9, "a jog up %.0f° at (%.0f, %.0f) stood on the collider %.0f%% of the way" % [
				deg, at.x, at.y, float(got["on_floor"]) * 100.0])
	print("    the heath by the Stair Head: %s" % "; ".join(report))
	assert_gt(found, 3, "the heath has too few slopes to walk up: %s" % "; ".join(report))


## The marked way north from the camp, the start's road grade: jogged from its first waystone
## toward each next one in turn, the body keeps its pace along the ground up and down it.
func test_jogging_the_marked_way_north_on_terrain3d_collision() -> void:
	if not await _stand_up():
		return
	var path: Dictionary = ContentDB.get_or_empty(START).get("path", {})
	var points: Array = WorldProbe.road_points(str(path.get("built_road", "")))
	if points.size() < 2:
		points = path.get("via", [])
	var via: Array[Vector2] = []
	# The way is jogged from where it leaves the camp: the camp's own dressing stands on its first
	# metres (on the atlas world a cart stands on it 12 m from the fire), which a player walks round.
	var head := WorldProbe.xz_of(ContentDB.get_or_empty(START))
	for p in points:
		var q := Vector2(float(p[0]), float(p[1]))
		if via.is_empty() and q.distance_to(head) < CAMP_M:
			continue
		via.append(q)
	assert_gt(via.size(), 3, "the Stair Head marks no way")
	if via.size() < 4:
		return
	var first := via[0]
	var toward := (via[1] - first).normalized()
	if not await _put(first, atan2(-toward.x, -toward.y)):
		assert_true(false, "no collision under the first waystone")
		return
	_key(KEY_W, true)
	var hz := float(Engine.physics_ticks_per_second)
	var next := 1
	var along := 0.0
	var level := 0.0
	var climbed := 0.0
	var floor_ticks := 0
	var n := 0
	var last := player.global_position
	var slowest := INF
	var window: Array[float] = []
	for i in int(24.0 * hz):
		var here := Vector2(player.global_position.x, player.global_position.z)
		while next < via.size() - 1 and here.distance_to(via[next]) < 4.0:
			next += 1
		var to := (via[next] - here).normalized()
		player.camera_rig.yaw = atan2(-to.x, -to.y)
		await _tree().physics_frame
		var p := player.global_position
		var step := p.distance_to(last)
		if i >= int(0.6 * hz):
			along += step
			level += Vector2(p.x - last.x, p.z - last.z).length()
			climbed += maxf(p.y - last.y, 0.0)
			floor_ticks += 1 if player.is_on_floor() else 0
			n += 1
			window.append(step * hz)
			if window.size() > int(hz):
				window.pop_front()
				var mean := 0.0
				for v in window:
					mean += v / window.size()
				slowest = minf(slowest, mean)
		last = p
		if next >= via.size() - 1 and here.distance_to(via[-1]) < 4.0:
			break
	_key(KEY_W, false)
	var t := float(n) / hz
	var pace := along / maxf(t, 0.001)
	print("    the marked way: %.0f m along the ground in %.1f s, %.2f m/s (%.0f%% of a jog), the slowest second %.2f m/s, %.1f m climbed, on the collider %.0f%%" % [
			along, t, pace, pace / Player.JOG_SPEED * 100.0, slowest, climbed, float(floor_ticks) / maxf(float(n), 1.0) * 100.0])
	assert_true(pace > 0.9 * Player.JOG_SPEED, "jogging the marked way made %.2f m/s along the ground" % pace)
	# the turns at the waystones cost some pace; a slope the body cannot climb costs all of it
	assert_true(slowest > 0.5 * Player.JOG_SPEED, "a second of the marked way went at %.2f m/s" % slowest)
