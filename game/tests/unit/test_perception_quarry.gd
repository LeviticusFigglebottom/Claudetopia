extends TestCase
## Who a foe's eyes can be on (actors/enemy/perception.gd). A body out of the tree -- the player in
## the frames between the world and an interior -- is nobody to look at: the eyes kept the last
## candidate for a scan and asked where it stood, which is an engine error a frame (fourteen of them
## in one run of the suite, from the footsteps test's walk into Weaverdeep).

var host: Node3D


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	host = Node3D.new()
	host.name = "PerceptionQuarryHost"
	_tree().root.add_child(host)


func after_each() -> void:
	_tree().root.remove_child(host)
	host.free()


func test_a_body_out_of_the_tree_is_no_quarry() -> void:
	var foe := Node3D.new()
	host.add_child(foe)
	var eyes := Perception.new()
	foe.add_child(eyes)
	eyes.setup(foe, {})
	var body := Node3D.new()
	body.add_to_group("player")
	host.add_child(body)
	assert_true(eyes.call("_is_live_quarry", body, "player"), "somebody standing there is somebody to see")
	host.remove_child(body)
	assert_false(eyes.call("_is_live_quarry", body, "player"), "and nobody while they are between the world and a door")
	body.free()
