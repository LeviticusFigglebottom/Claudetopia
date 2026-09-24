extends TestCase
## What a body holds is drawn in its hands (HeldItems): every weapon and shield in the pack has a
## model the forge made, a weapon goes in the right hand along the socket's +Y, a bow in the
## left, a shield on the left forearm facing out, and a humanoid foe holds what it fights with.
##
## Found by the attack audit: nothing was ever put in a hand. The player, the foes and the Wardens
## swung the attack clips' sword arcs with an empty, open hand.

const PLAYER := preload("res://actors/player/player.tscn")
## Items with no model yet, and why.
const NOT_YET := {"core:item/crossbow": "the forge has no crossbow yet"}

var player: Player = null


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	if player != null and is_instance_valid(player):
		player.queue_free()
	player = null


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
	player = PLAYER.instantiate() as Player
	_tree().root.add_child(player)
	player.teleport(Vector3(0.0, 0.02, 0.0), 0.0)
	for i in 4:
		await _tree().physics_frame


func test_the_player_holds_what_is_equipped() -> void:
	if not _rig_built():
		return
	await _stand()
	var body := player.body_model()
	assert_true(body != null, "the player has no body")
	if body == null:
		return
	player.equip_weapon("core:item/iron_sword")
	await _tree().process_frame
	assert_eq(HeldItems.held_by(body).get("WeaponR", ""), "core:item/iron_sword", "the sword is not in the right hand")
	player.equip_offhand("core:item/round_shield")
	await _tree().process_frame
	var held := HeldItems.held_by(body)
	assert_eq(held.get("ShieldL", ""), "core:item/round_shield", "the shield is not on the left arm")
	assert_eq(held.get("WeaponR", ""), "core:item/iron_sword", "the shield took the sword away")
	if body.has_method("grip"):
		assert_near(float(body.call("grip", "R")), 1.0, 0.01, "the right hand is open round the sword")
	player.equip_offhand("")
	player.equip_weapon("core:item/hunting_bow")
	await _tree().process_frame
	held = HeldItems.held_by(body)
	assert_eq(held.get("WeaponL", ""), "core:item/hunting_bow", "the bow is not in the left hand")
	assert_false(held.has("WeaponR"), "a bow left something in the right hand")
	player.equip_weapon("")
	await _tree().process_frame
	assert_true(HeldItems.held_by(body).is_empty(), "the hands still hold %s" % str(HeldItems.held_by(body)))


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
