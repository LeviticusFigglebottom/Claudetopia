extends TestCase
## The arrow goes where the crosshair is (playtest 09-30: "aiming slightly above straight ahead makes
## the arrow fly way above the crosshair"). The aim ray ended 150 m out when it met nothing, and the
## arc that comes down 150 m off from a hunting bow went up at 35 degrees for a crosshair 5 degrees
## above level. Now the arrow is sent to the crosshair's point (Player.arrow_target), on an arc lifted
## no more than ARROW_LIFT_MOST above the line (Player.arrow_direction), and the projectile steps along
## the true arc.
##
## On a real body with a real bow, from a platform high over the ground so a view 30 degrees down
## still has 60 m in it: a board is stood square to the view on the crosshair's ray at 5 to 60 m, at
## pitches from 30 degrees down to 45 up, and every arrow must land within HIT_RADIUS of the point
## the crosshair was on. In the third-person view, walking drawn, and in the first person. A shot at
## the open sky runs along the crosshair's line to the bow's reach, and only drops past it.

const BOW := "core:item/hunting_bow"
const IRON_ARROW := "core:item/iron_arrow"
const FRAME := 1.0 / 60.0
## How far off the crosshair's point an arrow may land (m): a full draw has no scatter, and the arrow
## is a hand's width across; this is well inside a man-sized mark at every range.
const HIT_RADIUS := 0.3
const HEIGHT := 60.0

var root: Node3D
var player: Player
var _board: StaticBody3D
var _landed: Array = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	GameState.set_flag("new_game", false)
	root = Node3D.new()
	root.name = "HighButts"
	_tree().root.add_child(root)
	# the stand: a platform on a pillar, the ground far below
	_box(Vector3(1.6, 1.0, 1.6), Vector3(0.0, HEIGHT - 0.5, 0.0))
	_box(Vector3(400.0, 1.0, 400.0), Vector3(0.0, -0.5, 0.0))
	player = (load("res://actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(player)
	player.global_position = Vector3(0.0, HEIGHT + 0.02, 0.0)
	player.camera_rig.yaw = 0.0
	player.camera_rig.pitch = 0.0
	player.equip_weapon(BOW)
	(player.get_node("Inventory") as Inventory).add(IRON_ARROW, 99)


func after_each() -> void:
	for a in Player.ACTIONS:
		Input.action_release(a)
	for a in ["move_forward", "move_back", "move_left", "move_right"]:
		Input.action_release(a)
	if is_instance_valid(root):
		root.free()
	root = null
	player = null


func _box(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	root.add_child(body)
	body.global_position = at
	return body


func _frames(n: int) -> void:
	for i in maxi(n, 1):
		await _tree().physics_frame


func _until(predicate: Callable, timeout: float) -> bool:
	for i in int(timeout / FRAME):
		if bool(predicate.call()):
			return true
		await _tree().physics_frame
	return bool(predicate.call())


## A board 2.5 m square, stood square to the view on the crosshair's ray, `range` metres past the
## body (the ray's own start is level with the chest).
func _stand_board(range_m: float) -> Vector3:
	if _board != null and is_instance_valid(_board):
		_board.free()
	var cam := player.camera_rig.camera_position()
	var dir := player.camera_rig.aim_direction()
	var chest := player.global_position + Vector3.UP * 1.4
	var at := cam + dir * (maxf((chest - cam).dot(dir), 0.0) + range_m)
	_board = _box(Vector3(2.5, 2.5, 0.2), at)
	_board.look_at(at + dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.FORWARD)
	return at


func _shoot() -> Dictionary:
	Input.action_press("attack_light")
	await _until(func() -> bool: return player.bow_draw() >= 1.0, 3.0)
	await _frames(8)
	var aim := player.aim_point()
	var target := player.arrow_target()
	var before := _arrows()
	Input.action_release("attack_light")
	await _frames(2)
	var shot: Projectile = null
	for a in _arrows():
		if not before.has(a):
			shot = a
	_landed.clear()
	var path: Array = []
	if shot != null:
		shot.landed.connect(_on_landed)
		for i in 240:
			if not is_instance_valid(shot) or bool(shot.get("_stuck")):
				break
			path.append(shot.global_position)
			await _tree().physics_frame
	await _until(func() -> bool: return player.state == Player.State.FREE, 2.0)
	await _frames(6)
	return {"aim": aim, "target": target, "flew": shot != null, "hit": _landed.duplicate(), "path": path}


func _on_landed(point: Vector3, _stuck: bool) -> void:
	_landed.append(point)


func _arrows() -> Array[Projectile]:
	var out: Array[Projectile] = []
	for n in root.get_children():
		if n is Projectile:
			out.append(n as Projectile)
	if _tree().current_scene != null:
		for n in _tree().current_scene.get_children():
			if n is Projectile:
				out.append(n as Projectile)
	return out


func _rig_built() -> bool:
	return ResourceLoader.exists(HumanoidModel.RIG_PATH) and player.anim.model != null


## Every pitch and range: the arrow in within HIT_RADIUS of the crosshair's point.
func _grid(label: String, pitches: Array, ranges: Array, walk := false) -> void:
	var worst := 0.0
	for pitch_deg in pitches:
		for r in ranges:
			if walk:
				Input.action_release("move_forward")
				player.global_position = Vector3(0.0, HEIGHT + 0.02, 0.0)
				player.velocity = Vector3.ZERO
			player.camera_rig.pitch = deg_to_rad(float(pitch_deg))
			await _frames(12)
			_stand_board(float(r))
			await _frames(3)
			if walk:
				Input.action_press("move_forward")
			var shot := await _shoot()
			Input.action_release("move_forward")
			var where := "%s, %+d degrees, %d m" % [label, int(pitch_deg), int(r)]
			assert_true(bool(shot["flew"]), "%s: an arrow flew" % where)
			if (shot["hit"] as Array).is_empty():
				assert_true(false, "%s: the arrow landed nowhere" % where)
				continue
			var off := ((shot["hit"] as Array)[0] as Vector3).distance_to(shot["aim"] as Vector3)
			worst = maxf(worst, off)
			assert_lt(off, HIT_RADIUS, "%s: in %.2f m off the crosshair" % [where, off])
	print("    %s: the worst of %d shots %.3f m off the crosshair" % [label, pitches.size() * ranges.size(), worst])


func test_the_arrow_lands_on_the_crosshair_at_every_pitch_and_range() -> void:
	if not _rig_built():
		return
	await _frames(5)
	await _grid("third person", [-30, -10, 0, 5, 10, 25, 45], [5, 15, 30, 60])


func test_first_person_and_walking_drawn_land_on_it_too() -> void:
	if not _rig_built():
		return
	await _frames(5)
	# walking drawn, from a longer stand so the steps stay on it
	_box(Vector3(1.6, 1.0, 12.0), Vector3(0.0, HEIGHT - 0.5, -5.0))
	await _grid("walking drawn", [-10, 5, 20], [15, 40], true)
	player.global_position = Vector3(0.0, HEIGHT + 0.02, 0.0)
	player.camera_rig.set_first_person(true)
	await _frames(20)
	await _grid("first person", [-30, 0, 5, 45], [5, 30, 60])


## Aimed at nothing, a few degrees above level: the arrow runs along the crosshair's line, over it
## by no more than a little on the way, crosses it at the bow's reach and only then falls away. It
## went up at 35 degrees.
func test_a_shot_at_the_sky_follows_the_crosshair() -> void:
	if not _rig_built():
		return
	await _frames(5)
	for pitch_deg in [5.0, 12.0]:
		player.camera_rig.pitch = deg_to_rad(pitch_deg)
		await _frames(12)
		var cam := player.camera_rig.camera_position()
		var dir := player.camera_rig.aim_direction()
		var shot := await _shoot()
		var path: Array = shot["path"]
		assert_gt(path.size(), 20, "the arrow flew a while")
		var most_over := 0.0
		var at_reach := INF
		for pv in path:
			var p: Vector3 = pv
			var along := (p - cam).dot(dir)
			if along < 3.0:
				continue
			var on_line := cam + dir * along
			var over := p.y - on_line.y
			if along < Player.ARROW_ZERO:
				most_over = maxf(most_over, over)
			if absf(along - Player.ARROW_ZERO) < 2.0:
				at_reach = minf(at_reach, p.distance_to(on_line))
		print("    sky at %+d degrees: at most %.2f m over the crosshair's line, %.2f m off it at %d m"
				% [int(pitch_deg), most_over, at_reach, int(Player.ARROW_ZERO)])
		assert_lt(most_over, 1.0, "the arrow keeps near the crosshair's line (%.2f m over it)" % most_over)
		assert_lt(at_reach, 0.4, "and is on it at the bow's reach (%.2f m off)" % at_reach)


## The arc is never lifted more than ARROW_LIFT_MOST over the line: a mark out of reach is shot at
## on the lifted line and the arrow falls short of it, which is what a bow does.
func test_the_arc_is_never_a_lob() -> void:
	var from := Vector3.ZERO
	for to in [Vector3(0, 0, -150), Vector3(0, 13, -149), Vector3(0, -40, -30), Vector3(0, 30, -30)]:
		var d := Player.arrow_direction(from, to, 42.0, 9.81)
		var lift := (to - from).normalized().angle_to(d)
		assert_lt(lift, Player.ARROW_LIFT_MOST + 0.001, "%s: lifted %.1f degrees" % [str(to), rad_to_deg(lift)])
	var near := Player.arrow_direction(from, Vector3(0, 0, -30), Player.ARROW_SPEED, 9.81)
	assert_lt(rad_to_deg(near.angle_to(Vector3(0, 0, -1))), 3.0, "30 m off, a full draw is all but flat")


func assert_lt(a: float, b: float, msg := "") -> void:
	assert_true(a < b, "%s (%.3f is not under %.3f)" % [msg, a, b])


func assert_gt(a: float, b: float, msg := "") -> void:
	assert_true(a > b, "%s (%.3f is not over %.3f)" % [msg, a, b])
