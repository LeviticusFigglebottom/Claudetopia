extends TestCase
## What a humanoid foe wears, carries and grows (actors/enemy/enemy_dress.gd). Every humanoid foe
## stood in the world as the forge's bare mannequin, and the Hart of Thorns -- "antlered plate, a
## spear the length of a boat" -- in the middle of the Standing Moot as one.

var host: Node3D


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	host = Node3D.new()
	host.name = "EnemyDressTestHost"
	_tree().root.add_child(host)


func after_each() -> void:
	_tree().root.remove_child(host)
	host.free()


func _spawn(id: String) -> Enemy:
	var spawner := EnemySpawner.new()
	spawner.spawn_on_ready = false
	spawner.drop_to_ground = false
	host.add_child(spawner)
	return spawner.spawn_one(id, Vector3(0.0, 0.0, 0.0), 0.0)


func test_every_humanoid_foe_is_dressed() -> void:
	var bare: Array[String] = []
	for type in ["enemy", "boss"]:
		for def in ContentDB.all(type):
			if str(def.get("rig", "humanoid")) != "humanoid":
				continue
			var look := EnemyDress.look_for(def)
			var parts: Dictionary = look.get("parts", {})
			if parts.get("torso", "") == "":
				bare.append(str(def["id"]))
			# a cuirass has no sleeves: plate is worn over something that has
			if (parts.values() as Array).has("plate_torso"):
				assert_true(str(parts.get("torso", "")) in ["gambeson", "shirt", "tunic", "brigandine", "coat"],
						"%s wears plate over bare arms" % def["id"])
	assert_empty(bare, "these humanoid foes would stand in the world as the bare rig")


func test_a_foes_own_appearance_is_worn_before_its_tags_outfit() -> void:
	var own := {"id": "core:enemy/test", "tags": ["bandit"], "appearance": {"parts": {"torso": "robe"}}}
	assert_eq(EnemyDress.look_for(own)["parts"]["torso"], "robe")
	var tagged := {"id": "core:enemy/test", "tags": ["bandit", "humanoid"]}
	var bandit := EnemyDress.look_for(tagged)
	# (or, when the dice made her a woman, her long belted cut of it: triage 22)
	assert_eq(bandit["parts"]["torso"], "fitted_tunic" if float(bandit["feminine"]) >= 0.5 else "tunic",
			"a bandit in the road's own jerkin")
	var knight := {"id": "core:enemy/test", "tags": ["undead", "knight"]}
	assert_true((EnemyDress.look_for(knight)["parts"] as Dictionary).values().has("plate_torso"), "a knight is in plate before he is dead")
	assert_eq(EnemyDress.look_for({"id": "x", "tags": ["beast"]}), {}, "a beast is not dressed")


func test_the_clanless_are_in_heavy_plate() -> void:
	for id in ["core:enemy/clanless_raider", "core:enemy/clanless_hewer", "core:enemy/clanless_outrider"]:
		var parts: Dictionary = EnemyDress.look_for(ContentDB.get_or_empty(id)).get("parts", {})
		assert_true(parts.values().has("plate_torso"), "%s is an elite raider in heavy plate" % id)


func test_the_hart_wears_antlered_plate_and_carries_his_spear() -> void:
	var hart := _spawn("core:boss/hart_of_thorns")
	assert_true(hart != null)
	if hart == null:
		return
	var model: Node3D = hart.anim.model
	assert_true(model != null and model.has_method("socket"), "the Hart is the rig")
	if model == null:
		return
	var look: CharacterAppearance = model.get("appearance")
	assert_true(look.parts.values().has("plate_torso"), "plate")
	assert_eq(look.part("torso"), "gambeson", "over a padded coat with sleeves, not bare arms")
	assert_eq(look.part("headgear"), "helm", "a helm")
	var hand: Node3D = model.call("socket", "WeaponR")
	var spear := hand.get_node_or_null("Held") as Node3D
	assert_true(spear != null, "a spear in his hand")
	if spear != null:
		assert_true(spear.transform.basis.get_scale().y > 2.0, "the length of a boat, not of a hedge-stake")
	var head: Node3D = model.call("socket", "Head")
	var antlers := head.get_node_or_null("Antlers") as MeshInstance3D
	assert_true(antlers != null and antlers.mesh != null, "antlers")
	if antlers == null or antlers.mesh == null:
		return
	# at rest the antlers stand over the crown and reach out past the shoulders
	var skeleton: Skeleton3D = model.get("skeleton")
	var pose := skeleton.get_bone_global_pose(skeleton.find_bone("Socket.Head"))
	var box: AABB = pose * antlers.transform * antlers.mesh.get_aabb()
	var crown := pose.origin
	assert_true(box.position.y >= crown.y - 0.05, "they grow up from the crown (%.2f against %.2f)" % [box.position.y, crown.y])
	assert_true(box.end.y > crown.y + 0.4, "and stand well over it")
	assert_true(box.size.x > 0.8, "a spread of antler, not a pair of horns (%.2f m)" % box.size.x)


func test_a_bandit_is_not_the_bare_rig() -> void:
	var bandit := _spawn("core:enemy/roadside_bandit")
	assert_true(bandit != null and bandit.anim.model != null)
	if bandit == null or bandit.anim.model == null:
		return
	var look: CharacterAppearance = bandit.anim.model.get("appearance")
	assert_eq(look.part("torso"), "tunic")
	assert_eq(look.part("legs"), "trousers")
