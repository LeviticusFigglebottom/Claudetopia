extends TestCase
## Swimming in the built world, from the keys (playtest 6: "the player walks along the lake bed
## with the surface overhead"). The player is stood on the shore of Lark Pool and walked into it on
## the move key: the water slows the wade past the knee and the waist, and past the chest the body
## floats with its head at the surface and its feet clear of the bed. It swims out over the deep
## water, dives on the sneak key and comes up again, can swing nothing, and swims back until it
## wades out onto the shore. In the sea below the Stair Head it swims into a steep bank whose top
## is within reach and climbs out onto it.
##
## The places are the w4096 build's, from the water agent: Lark Pool's west shore at (170, 2492),
## shelving to 4.5 m deep 30 m east of it under a surface at 46.0 m; and the Mere's steep bank by
## Tollmere near (-262, -330), found where the test stands (the way the ground leaves the water
## soonest, with water over 2 m deep behind it). The test reads the surface and the ground where it
## stands, and says so and passes over a world where either place is dry.

const WORLD_SCENE := "res://world/world.tscn"
const FRAME := 1.0 / 60.0
const LARK_DEEP := Vector2(200.0, 2492.0)
const LARK_OUT := Vector2(-1.0, 0.0)         # from the deep water to the west shore
const LARK_SHORE_M := 30.0
const MERE_BANK := Vector2(-262.0, -330.0)

var _world: World = null
var _player: Player = null


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "sneak", "jump", "attack_light", "sprint"]:
		Input.action_release(a)
	if _world != null and is_instance_valid(_world):
		_tree().root.remove_child(_world)
		_world.free()
	_world = null
	_player = null


func _frames(n: int) -> void:
	for i in maxi(n, 1):
		await _tree().physics_frame


func _load() -> bool:
	_world = (load(WORLD_SCENE) as PackedScene).instantiate() as World
	_tree().root.add_child(_world)
	await _world.world_ready
	var spawn: Node = _world.get_node_or_null("PlayerSpawn")
	_player = spawn.get("player") as Player if spawn != null else null
	assert_true(_player != null, "somebody stands in the world")
	return _player != null


func _ground(x: float, z: float) -> float:
	return World.terrain().get_height(x, z)


## Stands the player at (x, z) on the ground, the view and the move key turned along `facing`.
func _stand(at: Vector2, facing: Vector2, drop := 0.0) -> void:
	var y := _ground(at.x, at.y)
	var s := Swimmer.water_surface_y(Vector3(at.x, y, at.y))
	if drop > 0.0 and not is_nan(s):
		y = maxf(y + 0.2, s - drop)
	_player.global_position = Vector3(at.x, y, at.y)
	_player.velocity = Vector3.ZERO
	_face(facing)


func _face(facing: Vector2) -> void:
	var yaw := atan2(-facing.x, -facing.y)
	_player.camera_rig.yaw = yaw
	_player.rotation.y = yaw


## The height of the head (the skull's base) on the forge's body, or NAN on a placeholder.
func _head_y() -> float:
	var m: Node = _player.anim.model
	if m == null or not ("skeleton" in m):
		return NAN
	var sk: Skeleton3D = m.get("skeleton")
	var i := sk.find_bone("Head")
	return (sk.global_transform * sk.get_bone_global_pose(i).origin).y if i >= 0 else NAN


func test_into_a_lake_on_the_keys_afloat_and_out_on_the_shore() -> void:
	if not await _load():
		return
	var deep := LARK_DEEP
	var surface := Swimmer.water_surface_y(Vector3(deep.x, _ground(deep.x, deep.y), deep.y))
	if is_nan(surface) or surface - _ground(deep.x, deep.y) < 2.0:
		print("    Lark Pool is not deep water in this world (surface %s); nothing to swim in" % surface)
		return
	var shore := deep + LARK_OUT * (LARK_SHORE_M + 3.0)
	_stand(shore, -LARK_OUT)
	await _frames(20)
	assert_false(_player.is_swimming(), "stood on the shore, the body is not swimming")
	# walk in: the wade slows past the knee, then the body floats
	Input.action_press("move_forward")
	var wade := {}          # depth band -> fastest pace
	var swam_at := -1
	var head_off: Array[float] = []
	var feet_clear := INF
	var f := 0
	while f < 60 * 30:
		await _tree().physics_frame
		f += 1
		var p := _player.global_position
		var sw := _player.swimmer
		if not _player.is_swimming():
			var pace := Vector2(_player.velocity.x, _player.velocity.z).length()
			var band := "dry" if sw.submersion < 0.05 else ("to the knee" if sw.submersion < Swimmer.KNEE_M else \
					("to the waist" if sw.submersion < Swimmer.WAIST_M else "to the chest"))
			wade[band] = maxf(float(wade.get(band, 0.0)), pace)
		else:
			if swam_at < 0:
				swam_at = f
			if f - swam_at > 60 and not sw.under():
				var h := _head_y()
				if not is_nan(h):
					head_off.append(h - sw.surface_y)
				feet_clear = minf(feet_clear, p.y - _ground(p.x, p.z))
		if Vector2(p.x, p.z).distance_to(deep) < 6.0:
			break
	Input.action_release("move_forward")
	print("    walked in: fastest pace %s; swimming from frame %d" % [str(wade), swam_at])
	assert_true(swam_at > 0, "walked into deep water, the body swims")
	assert_true(float(wade.get("dry", 0.0)) > float(wade.get("to the waist", 99.0)) + 0.5,
			"the water past the waist slows the wade (%s)" % str(wade))
	head_off.sort()
	if not head_off.is_empty():
		print("    swimming, the head stands %.2f..%.2f m against the surface; the soles at least %.2f m off the bed" % [
				head_off[0], head_off[head_off.size() - 1], feet_clear])
		assert_true(head_off[0] > -0.3 and head_off[head_off.size() - 1] < 0.45, "the head rides at the surface")
	assert_true(feet_clear >= 0.1, "the feet never touch the bed while swimming (%.2f m)" % feet_clear)
	# nothing to swing: a press of the attack key while afloat
	var drawn_before := _player.weapon_drawn
	Input.action_press("attack_light")
	await _frames(3)
	Input.action_release("attack_light")
	await _frames(30)
	assert_true(_player.is_swimming(), "an attack pressed afloat does not leave the water (%s)" % _player.state_name())
	assert_false(_player.weapon_drawn, "the weapon stays on the hip afloat (was %s)" % drawn_before)
	# a dive on the sneak key, and up again on it
	var top := _player.global_position.y
	Input.action_press("sneak")
	await _frames(2)
	Input.action_release("sneak")
	await _frames(150)
	var dived := top - _player.global_position.y
	var bed_gap := _player.global_position.y - _ground(_player.global_position.x, _player.global_position.z)
	Input.action_press("sneak")
	await _frames(2)
	Input.action_release("sneak")
	await _frames(240)
	var back_up := _player.global_position.y - (top - dived)
	print("    dived %.2f m (%.2f m off the bed), came %.2f m back up" % [dived, bed_gap, back_up])
	assert_gt(dived, 1.0, "the sneak key dives")
	assert_true(bed_gap >= 0.1, "a dive keeps off the bed")
	assert_true(absf(_player.global_position.y - top) < 0.15, "and the body comes back to the surface")
	# the camera over the water
	await _frames(10)
	var cam := _player.camera_rig.camera.global_position
	var cam_water := Swimmer.water_surface_y(cam)
	if not is_nan(cam_water):
		assert_true(cam.y >= cam_water + CameraRig.WATER_CLEARANCE - 0.02, "the camera stays over the water (%.2f over)" % (cam.y - cam_water))
	# swim back to the shore and wade out
	_face(LARK_OUT)
	Input.action_press("move_forward")
	var out_at := -1
	f = 0
	while f < 60 * 40:
		await _tree().physics_frame
		f += 1
		if not _player.is_swimming() and _player.swimmer.submersion < 0.05:
			out_at = f
			break
	Input.action_release("move_forward")
	print("    back on dry ground after %.1f s" % (float(out_at) / 60.0))
	assert_gt(out_at, 0, "the body swims back and walks out onto the shore")


func test_a_steep_bank_within_reach_is_climbed_out_onto() -> void:
	if not await _load():
		return
	# the way the ground leaves the water soonest from the bank's point, with deep water behind
	var best := {}
	for k in 32:
		var a := TAU * float(k) / 32.0
		var dir := Vector2(cos(a), sin(a))
		var back := MERE_BANK - dir * 6.0
		var w := Swimmer.water_at(Vector3(back.x, 0.0, back.y))
		if not bool(w.get("has", false)) or float(w["depth"]) < 2.0:
			continue
		var s := float(w["y"])
		for i in 24:
			var at := back + dir * (0.5 * float(i))
			if _ground(at.x, at.y) > s + 0.1:
				if best.is_empty() or float(i) * 0.5 < float(best["run"]):
					best = {"dir": dir, "back": back, "run": float(i) * 0.5, "surface": s}
				break
	if best.is_empty():
		print("    no deep water beside a bank at the Mere in this world; nothing to climb out of")
		return
	var s: float = best["surface"]
	print("    the Mere's bank: %.1f m from water %.1f m deep to ground over the surface" % [
			float(best["run"]), s - _ground(Vector2(best["back"]).x, Vector2(best["back"]).y)])
	_stand(best["back"], best["dir"], Swimmer.FLOAT_M)
	await _frames(30)
	assert_true(_player.is_swimming(), "put in the Mere, the body swims (%s)" % _player.state_name())
	Input.action_press("move_forward")
	var climbed := false
	var f := 0
	while f < 60 * 12:
		await _tree().physics_frame
		f += 1
		if not _player.is_swimming() and _player.state != Player.State.MANTLE and _player.swimmer.submersion < 0.1 \
				and _player.global_position.y >= s - 0.05:
			climbed = true
			break
	Input.action_release("move_forward")
	await _frames(30)
	var p := _player.global_position
	print("    out of the Mere after %.1f s, standing %.2f m over its surface (%s, the ground %.2f m under the soles, %.1f m from the start)" % [
			float(f) / 60.0, p.y - s, _player.state_name(), p.y - _ground(p.x, p.z), Vector2(p.x, p.z).distance_to(best["back"])])
	assert_true(climbed, "swimming into the bank, the body climbs out onto it")
	assert_true(p.y >= s - 0.05, "and stands on it, out of the water")
