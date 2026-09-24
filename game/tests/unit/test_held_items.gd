extends TestCase
## What a body holds is drawn in its hands (HeldItems): every weapon and shield in the pack has a
## model the forge made, a weapon goes in the right hand along the socket's +Y, a bow in the
## left, a shield on the left forearm facing out, and a humanoid foe holds what it fights with.
## Out of a fight the player's weapon rides in its sheath, at the hip or across the back, clear of
## the body, and a fight puts it in the hand.
##
## Found by the attack audit: nothing was ever put in a hand. The player, the foes and the Wardens
## swung the attack clips' sword arcs with an empty, open hand.

const PLAYER := preload("res://actors/player/player.tscn")
## Items with no model yet, and why.
const NOT_YET := {"core:item/crossbow": "the forge has no crossbow yet"}

var player: Player = null
var _floor: StaticBody3D = null


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	Input.action_release("block")
	if player != null and is_instance_valid(player):
		player.queue_free()
	player = null
	if _floor != null and is_instance_valid(_floor):
		_floor.queue_free()
	_floor = null


func _rig_built() -> bool:
	return ResourceLoader.exists(HumanoidModel.RIG_PATH)


func _held_items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for def in ContentDB.all("item"):
		var d: Dictionary = def
		var tags: Array = d.get("tags", [])
		if d.get("weapon") is Dictionary or tags.has("shield"):
			out.append(d)
	return out


func test_every_weapon_and_shield_has_a_model() -> void:
	var missing: Array[String] = []
	var n := 0
	for item in _held_items():
		var id := str(item.get("id", ""))
		if NOT_YET.has(id):
			continue
		n += 1
		var model := HeldItems.model_for(item)
		if model.is_empty() or not ResourceLoader.exists(HeldItems.path_of(model)):
			missing.append("%s (%s)" % [id, model])
	assert_gt(n, 30, "the pack has its weapons")
	assert_true(missing.is_empty(), "drawn with nothing: %s" % ", ".join(missing))


func test_a_model_is_built_along_the_socket() -> void:
	for model in ["weapons/sword_iron", "weapons/greatsword_iron", "weapons/spear_iron", "weapons/bow_wood",
			"weapons/shield_iron"]:
		var path := HeldItems.path_of(model)
		if not ResourceLoader.exists(path):
			assert_true(false, "%s was not built" % path)
			continue
		var node := (load(path) as PackedScene).instantiate() as Node3D
		var box := _bounds(node)
		node.free()
		var size := box.size
		if model.contains("shield"):
			# a disc facing out along +X, standing off the forearm
			assert_true(size.x < size.y * 0.4 and size.x < size.z * 0.4, "%s is not a disc facing +X: %s" % [model, str(size)])
			assert_gt(box.get_center().x, 0.0, "%s sits inside the arm" % model)
		elif model.contains("bow"):
			# the stave up and down (the socket's ±Z), the arrow's way +Y, the string behind
			assert_true(size.z > size.y * 3.0, "%s's stave does not run along the socket's Z: %s" % [model, str(size)])
		else:
			assert_true(size.y > size.x * 4.0 and size.y > size.z * 2.5, "%s is not built along +Y: %s" % [model, str(size)])
			assert_true(box.end.y > -box.position.y, "%s's blade is not on +Y" % model)
			# the grip's middle is the origin: the hand holds it there
			assert_true(box.position.y < -0.03 and box.end.y > 0.2, "%s's grip does not run through the origin (%.2f to %.2f)" % [model, box.position.y, box.end.y])


## The union of every mesh's AABB under `n`, in n's frame.
func _bounds(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var xf := n.global_transform.affine_inverse() * m.global_transform if m.is_inside_tree() else _local_to(n, m)
		var b := xf * m.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


func _local_to(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _stand() -> void:
	# a floor to stand on: a guard is raised only on the ground
	_floor = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 1.0, 20.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	_floor.add_child(shape)
	_tree().root.add_child(_floor)
	player = PLAYER.instantiate() as Player
	_tree().root.add_child(player)
	player.teleport(Vector3(0.0, 0.02, 0.0), 0.0)
	for i in 4:
		await _tree().physics_frame


## Waits `n` physics ticks.
func _ticks(n: int) -> void:
	for i in n:
		await _tree().physics_frame


## Raises the guard for a tick, which draws the weapon, and lowers it.
func _draw() -> void:
	Input.action_press("block")
	await _ticks(3)
	Input.action_release("block")
	await _ticks(2)


## Lets the weapon go back to its sheath as if SHEATHE_AFTER_S had passed since the fight.
## (The parry the guard began has to finish first: the body must be free.)
func _let_it_rest() -> void:
	for i in 120:
		player._last_fight_act = Actor.now() - Player.SHEATHE_AFTER_S - 0.1
		await _ticks(1)
		if not player.weapon_drawn:
			break
	await _ticks(1)


func test_the_player_holds_what_is_equipped() -> void:
	if not _rig_built():
		return
	await _stand()
	var body := player.body_model()
	assert_true(body != null, "the player has no body")
	if body == null:
		return
	player.equip_weapon("core:item/iron_sword")
	await _ticks(1)
	assert_false(player.weapon_drawn, "the sword came out of its sheath with no fight")
	assert_eq(HeldItems.sheathed_by(body).get("HipL", ""), "core:item/iron_sword", "the sword is not at the left hip")
	assert_true(HeldItems.held_by(body).is_empty(), "a sheathed sword is also in a hand: %s" % str(HeldItems.held_by(body)))
	if body.has_method("grip"):
		assert_near(float(body.call("grip", "R")), 0.0, 0.01, "the right hand is closed on a sheathed sword")
	await _draw()
	assert_true(player.weapon_drawn, "raising the guard did not draw the sword")
	assert_eq(HeldItems.held_by(body).get("WeaponR", ""), "core:item/iron_sword", "the sword is not in the right hand")
	assert_true(HeldItems.sheathed_by(body).is_empty(), "the drawn sword is still in its sheath")
	player.equip_offhand("core:item/round_shield")
	await _ticks(1)
	var held := HeldItems.held_by(body)
	assert_eq(held.get("ShieldL", ""), "core:item/round_shield", "the shield is not on the left arm")
	assert_eq(held.get("WeaponR", ""), "core:item/iron_sword", "the shield took the sword away")
	if body.has_method("grip"):
		assert_near(float(body.call("grip", "R")), 1.0, 0.01, "the right hand is open round the sword")
	await _let_it_rest()
	assert_false(player.weapon_drawn, "the sword stayed out after the fight")
	assert_eq(HeldItems.sheathed_by(body).get("HipL", ""), "core:item/iron_sword", "the sword did not go back to the hip")
	assert_eq(HeldItems.held_by(body).get("ShieldL", ""), "core:item/round_shield", "sheathing the sword took the shield off the arm")
	player.equip_offhand("")
	player.equip_weapon("core:item/hunting_bow")
	await _ticks(1)
	assert_eq(HeldItems.sheathed_by(body).get("Back", ""), "core:item/hunting_bow", "the bow is not across the back")
	# a bow raises no guard, and drawing it needs arrows: put it in the hand as a fight would
	player.weapon_drawn = true
	player._last_fight_act = Actor.now()
	player._dress_hands()
	await _ticks(1)
	held = HeldItems.held_by(body)
	assert_eq(held.get("WeaponL", ""), "core:item/hunting_bow", "the bow is not in the left hand")
	assert_false(held.has("WeaponR"), "a bow left something in the right hand")
	player.equip_weapon("")
	await _ticks(1)
	assert_true(HeldItems.held_by(body).is_empty(), "the hands still hold %s" % str(HeldItems.held_by(body)))
	assert_true(HeldItems.sheathed_by(body).is_empty(), "the sheaths still hold %s" % str(HeldItems.sheathed_by(body)))


## A sheathed weapon hangs where it should, clear of the body standing: a blade at the left hip
## with its grip up and forward and its point down and back, a greatsword and a bow across the
## back, and nothing of any of them inside the torso or the left thigh.
func test_a_sheathed_weapon_hangs_clear_of_the_body() -> void:
	if not _rig_built():
		return
	await _stand()
	var body := player.body_model() as HumanoidModel
	if body == null:
		return
	var sk := body.skeleton
	var at := func(bone: String) -> Vector3: return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone)).origin
	var up := Vector3.UP
	var left: Vector3 = (at.call("Hand.L") as Vector3) - (at.call("Hand.R") as Vector3)
	left = Vector3(left.x, 0.0, left.z).normalized()
	var fwd := left.cross(up).normalized()
	var cases := [["core:item/iron_sword", "HipL", 0.86], ["core:item/iron_greatsword", "Back", 1.2],
			["core:item/hunting_bow", "Back", 0.0]]
	for c: Array in cases:
		var id: String = c[0]
		if not ContentDB.has(id):
			continue
		player.equip_weapon(id)
		await _ticks(2)
		var sheath: String = c[1]
		assert_eq(HeldItems.sheathed_by(body).get(sheath, ""), id, "%s is not in the %s sheath" % [id, sheath])
		var node: Node3D = null
		for n in body.socket(sheath).get_children():
			if n.has_meta(HeldItems.TAG):
				node = n
		if node == null:
			continue
		var xf := node.global_transform
		var grip := xf.origin
		var blade := xf.basis.y.normalized()
		var hips: Vector3 = at.call("Hips")
		var neck: Vector3 = at.call("Neck")
		var length: float = c[2]
		if length > 0.0:
			var tip := grip + blade * length
			var torso_gap := _gap(grip + blade * 0.12, tip, hips, neck)
			assert_true(torso_gap >= 0.12, "%s's blade passes %.1f cm from the spine, inside the torso" % [id, torso_gap * 100.0])
			assert_true(blade.dot(up) < -0.5, "%s's point is not down (%.2f)" % [id, blade.dot(up)])
		if sheath == "HipL":
			assert_true(grip.y > hips.y - 0.05, "the sword's grip hangs below the hip")
			assert_true((grip - hips).dot(fwd) > (_tip_of(xf, 0.86) - hips).dot(fwd), "the sword's point is ahead of its grip")
			var knee: Vector3 = at.call("LowerLeg.L")
			var thigh_gap := _gap(grip + blade * 0.12, _tip_of(xf, 0.86), at.call("UpperLeg.L"), knee)
			assert_true(thigh_gap >= 0.07, "the sword passes %.1f cm from the left thigh bone, inside the leg" % (thigh_gap * 100.0))
		else:
			assert_true(grip.y > hips.y + 0.25, "%s does not ride up the back" % id)
			assert_true((grip - neck).dot(fwd) < 0.0, "%s is in front of the neck, not on the back" % id)
	player.equip_weapon("")


static func _tip_of(xf: Transform3D, length: float) -> Vector3:
	return xf.origin + xf.basis.y.normalized() * length


static func _gap(p0: Vector3, p1: Vector3, q0: Vector3, q1: Vector3) -> float:
	var pts := Geometry3D.get_closest_points_between_segments(p0, p1, q0, q1)
	return (pts[0] as Vector3).distance_to(pts[1] as Vector3)


func test_a_humanoid_foe_holds_what_it_fights_with() -> void:
	if not _rig_built():
		return
	var e := Enemy.new()
	e.configure("core:enemy/roadside_bandit")
	_tree().root.add_child(e)
	for i in 3:
		await _tree().process_frame
	var body: Node = e.anim.model if e.anim != null else null
	var held := HeldItems.held_by(body)
	e.queue_free()
	assert_eq(held.get("WeaponR", ""), "class:sword", "the bandit's sword is not in its hand: %s" % str(held))
