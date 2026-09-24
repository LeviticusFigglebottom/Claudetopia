extends TestCase
## A conversation turns the camera onto whoever is speaking (CameraRig.frame_speaker).
##
## The flow's picture of the first conversation was the player's back: the follow camera looked on
## over the player's shoulder, and the Warden stood behind the player's head. The two-shot puts her
## face in the middle of the picture with the player's head and shoulder beside it, on the side
## Settings' camera side picks. It eases back to the follow camera on goodbye, does nothing in first
## person, and never moves where the player aims.

const FRAME := 1.0 / 60.0

var _side_was: Variant = 1


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	_side_was = Settings.get_value("controls", "camera_side", 1)


func after_each() -> void:
	Settings.set_value("controls", "camera_side", _side_was, false)


## A body at the origin looking north, its rig, and somebody a pace and a half to the east: beside
## the player, out of the follow camera's middle.
func _scene(side: int) -> Dictionary:
	Settings.set_value("controls", "camera_side", side, false)
	var stage := Node3D.new()
	_tree().root.add_child(stage)
	var body := Node3D.new()
	stage.add_child(body)
	var rig := CameraRig.new()
	body.add_child(rig)
	var speaker := Node3D.new()
	stage.add_child(speaker)
	speaker.global_position = Vector3(1.5, 0.0, 0.0)
	return {"stage": stage, "rig": rig, "speaker": speaker}


func _run(rig: CameraRig, seconds: float) -> void:
	for i in int(seconds / FRAME):
		rig._process(FRAME)


func _drop(scene: Dictionary) -> void:
	var stage: Node = scene["stage"]
	_tree().root.remove_child(stage)
	stage.free()


func _face(scene: Dictionary) -> Vector3:
	return (scene["speaker"] as Node3D).global_position + Vector3(0.0, CameraRig.TALK_FACE_HEIGHT, 0.0)


## Degrees between the camera's view and the way to `point`.
func _off_view(cam: Camera3D, point: Vector3) -> float:
	return rad_to_deg((-cam.global_transform.basis.z).angle_to((point - cam.global_position).normalized()))


func test_a_conversation_frames_the_speaker_beside_the_player() -> void:
	for side: int in [1, -1]:
		var scene := _scene(side)
		var rig: CameraRig = scene["rig"]
		_run(rig, 0.2)
		var before := rig.aim_direction()
		rig.frame_speaker(scene["speaker"])
		_run(rig, 1.5)
		var cam := rig.camera
		var face := _face(scene)
		var head := rig.global_position
		assert_true(rig.is_framing_speaker(), "talking, the camera frames the speaker")
		assert_lt_deg(_off_view(cam, face), 8.0, "their face is near the middle of the picture (side %d)" % side)
		var apart := rad_to_deg((face - cam.global_position).normalized().angle_to((head - cam.global_position).normalized()))
		assert_gt(apart, 8.0, "and the player's head is beside it, not in front of it: %.1f degrees apart (side %d)" % [apart, side])
		# the line from the player to the speaker runs east; its right hand is south (+z)
		var out := (cam.global_position - head).dot(Vector3(0.0, 0.0, 1.0))
		assert_gt(out * float(side), 0.5, "the camera is over the shoulder the camera side picks (%d): %.2f m out" % [side, out])
		assert_gt(rig.aim_direction().dot(before), 0.999, "and where the player aims has not moved")
		rig.release_speaker()
		_run(rig, 2.0)
		assert_false(rig.is_framing_speaker(), "on goodbye it eases back to the follow camera")
		assert_lt_deg(rad_to_deg((-cam.global_transform.basis.z).angle_to(before)), 0.5, "looking where it looked before (side %d)" % side)
		_drop(scene)


func test_first_person_looks_through_the_eyes_and_is_left_alone() -> void:
	var scene := _scene(1)
	var rig: CameraRig = scene["rig"]
	rig.set_first_person(true)
	_run(rig, 0.2)
	var before := -rig.camera.global_transform.basis.z
	rig.frame_speaker(scene["speaker"])
	_run(rig, 1.5)
	assert_false(rig.is_framing_speaker(), "in first person nothing is framed")
	assert_lt_deg(rad_to_deg((-rig.camera.global_transform.basis.z).angle_to(before)), 0.5, "and the view stays the player's")
	_drop(scene)


func assert_lt_deg(value: float, limit: float, msg: String) -> void:
	assert_gt(limit, value, "%s (%.1f degrees)" % [msg, value])
