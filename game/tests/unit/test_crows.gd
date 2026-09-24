extends TestCase
## The crows about the Stair Head: sat on what stands up in the camp, put up by anybody coming near,
## wheeling over it, and back down to sit once they are left alone.

const PERCHES: Array[Vector3] = [Vector3(4.0, 4.4, 0.0), Vector3(-4.0, 4.4, 0.0), Vector3(0.0, 2.0, 6.0)]


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _crows(count: int) -> Crows:
	var c := Crows.new()
	_tree().root.add_child(c)
	c.set_process(false)
	c.spooked_by = "test_crow_spooker"
	c.setup(PERCHES, Vector3.ZERO, count, 7)
	return c


func _walker(at: Vector3) -> Node3D:
	var n := Node3D.new()
	n.add_to_group("test_crow_spooker")
	_tree().root.add_child(n)
	n.global_position = at
	return n


func _drop(n: Node) -> void:
	_tree().root.remove_child(n)
	n.free()


func _run(c: Crows, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		c.step(1.0 / 30.0)
		t += 1.0 / 30.0


func test_they_sit_on_the_camp_and_wheel_over_it() -> void:
	var c := _crows(5)
	assert_eq(c.count(), 5, "five crows")
	assert_eq(c.sitting(), PERCHES.size(), "one on each perch and the rest in the air")
	for i in PERCHES.size():
		assert_true(c.position_of(i).distance_to(PERCHES[i]) < 0.01, "crow %d sits on its perch" % i)
	_run(c, 3.0)
	for i in range(PERCHES.size(), c.count()):
		var p := c.position_of(i)
		assert_eq(c.state_of(i), Crows.State.WHEELING, "crow %d wheels" % i)
		assert_gt(p.y, 8.0, "high over the camp (%.1f m)" % p.y)
	_drop(c)


func test_somebody_coming_near_puts_them_up_and_they_come_back_when_left_alone() -> void:
	var c := _crows(3)
	var up := [0]
	c.put_up.connect(func(_i: int) -> void: up[0] += 1)
	var walker := _walker(Vector3(5.0, 0.0, -2.0))
	_run(c, 0.5)
	assert_eq(c.state_of(0), Crows.State.TAKING_OFF, "the crow on the pole a couple of paces away is put up")
	assert_eq(up[0], 1, "and says so")
	assert_eq(c.state_of(1), Crows.State.SITTING, "the one on the far pole stays sat")
	assert_eq(c.state_of(2), Crows.State.SITTING, "and so does the one on the signpost")
	_run(c, Crows.TAKE_OFF_SECONDS + 0.5)
	assert_eq(c.state_of(0), Crows.State.WHEELING, "and wheels over the camp")
	assert_gt(c.position_of(0).y, 8.0, "up off the ground")
	# while somebody stands by its perch it does not come down to it
	_run(c, Crows.WHEEL_SECONDS.y + 15.0)
	assert_true(c.state_of(0) == Crows.State.WHEELING or c.position_of(0).distance_to(PERCHES[0]) > 1.0,
			"it does not sit down beside somebody")
	walker.global_position = Vector3(200.0, 0.0, 200.0)
	_run(c, Crows.WHEEL_SECONDS.y + 20.0 + Crows.COME_DOWN_SECONDS)
	assert_eq(c.sitting(), 3, "left alone, they are all sat again (%d)" % c.sitting())
	_drop(walker)
	_drop(c)
