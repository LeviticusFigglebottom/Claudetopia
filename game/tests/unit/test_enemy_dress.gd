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


## The bosses of the large places (the identity pass): each a shape of its own, at its def's size.
const BOSSES: Array[String] = ["core:boss/gideon_spall", "core:boss/the_receiver", "core:boss/ysolde_carrow",
	"core:boss/unvowed_marshal", "core:boss/the_name_wife", "core:boss/ama_lissa_the_sounder",
	"core:boss/hethra_undertone", "core:boss/the_last_bellwright", "core:boss/captain_haddow",
	"core:boss/kadda_the_rasp", "core:boss/haldo_the_lampman", "core:boss/the_gaffer", "core:boss/digger_king",
	"core:boss/barrow_wife"]


func test_a_humanoid_foe_is_drawn_at_its_defs_scale() -> void:
	# every humanoid foe stood at a person's height whatever its def's scale: the bell-bearer, built
	# for 2.6 m of capsule, stood 1.78 m inside it
	var plain := {"id": "core:enemy/test", "tags": ["bandit", "humanoid"], "scale": 1.5}
	var look := EnemyDress.sized_look(plain)
	var own := float(EnemyDress.look_for(plain).get("height", 1.78))
	assert_near(float(look["height"]), own * 1.5, 0.001, "its look is its height times its scale")
	var wright := _spawn("core:boss/the_last_bellwright")
	assert_true(wright != null and wright.anim.model != null)
	if wright == null or wright.anim.model == null:
		return
	var app: CharacterAppearance = wright.anim.model.get("appearance")
	var def := ContentDB.get_or_empty("core:boss/the_last_bellwright")
	assert_near(app.height, float(def["appearance"]["height"]) * float(def["scale"]), 0.001)
	assert_gt(app.height, 2.8, "the Last Bellwright stands half again as tall as a man")


func test_the_bosses_stand_above_their_people_and_are_struck_where_they_stand() -> void:
	for id in BOSSES:
		var def := ContentDB.get_or_empty(id)
		var tall := float(EnemyDress.sized_look(def).get("height", 0.0))
		assert_gt(tall, 2.1, "%s stands above its people (%.2f m)" % [id, tall])
		# its capsule (what a blow and a body strike) is the body it is drawn as
		var capsule := float(def.get("height", 1.8))
		assert_true(absf(capsule - tall) < tall * 0.18, "%s: capsule %.2f m for a body %.2f m tall" % [id, capsule, tall])
		# a person's body is about 0.27 m round from its middle to its arm, at the size it is drawn
		assert_gt(float(def.get("radius", 0.35)), 0.27 * float(def.get("scale", 1.0)) * float(def.get("breadth", 1.0)),
				"%s is as broad to a blow as it is drawn" % id)


func test_no_two_bosses_wear_the_same_outfit() -> void:
	var seen := {}
	for type in ["boss"]:
		for def in ContentDB.all(type):
			if str(def.get("rig", "humanoid")) != "humanoid":
				continue
			var look := EnemyDress.look_for(def)
			var parts: Dictionary = look.get("parts", {})
			var keys := parts.keys()
			keys.sort()
			var outfit: Array = []
			for k in keys:
				outfit.append("%s=%s" % [k, parts[k]])
			var sig := ",".join(outfit)
			if BOSSES.has(str(def["id"])) or seen.has(sig) and BOSSES.has(str(seen[sig])):
				assert_false(seen.has(sig), "%s wears %s's outfit" % [def["id"], seen.get(sig, "")])
			seen[sig] = str(def["id"])


func test_each_boss_carries_what_its_lore_gives_it() -> void:
	# the hand: the overman's pick, the digger-king's spade, the founder's sledge, the lampman's lamp
	var tools := {"core:boss/the_gaffer": "pick_chalk", "core:boss/digger_king": "spade_iron",
		"core:boss/the_last_bellwright": "sledge_iron", "core:boss/haldo_the_lampman": "lamp_pole_iron",
		"core:boss/kadda_the_rasp": "rasp_iron", "core:boss/ama_lissa_the_sounder": "leister_iron",
		"core:boss/barrow_wife": "crook_thorn", "core:boss/hethra_undertone": "censer_bronze",
		"core:boss/the_receiver": "seal_staff_iron", "core:boss/gideon_spall": "drift_hook_brass"}
	for id in tools:
		var e := _spawn(id)
		assert_true(e != null and e.anim.model != null, id)
		if e == null or e.anim.model == null:
			continue
		var hand: Node3D = e.anim.model.call("socket", "WeaponR")
		var held := ""
		for c in hand.get_children():
			if c.has_meta(HeldItems.TAG):
				held = str(c.name)
		assert_true(held.ends_with(str(tools[id])), "%s holds its %s (holds %s)" % [id, tools[id], held])
	# the lamp on the pole is lit; the bell rides on the founder's back
	var haldo := _spawn("core:boss/haldo_the_lampman")
	if haldo != null and haldo.anim.model != null:
		assert_gt(haldo.anim.model.find_children("CarriedLight", "OmniLight3D", true, false).size(), 0, "Haldo's lamp is lit")
	var wright := _spawn("core:boss/the_last_bellwright")
	if wright != null and wright.anim.model != null:
		var bell := wright.anim.model.find_children("Carried_tuning_bell_bronze", "Node3D", true, false)
		assert_eq(bell.size(), 1, "the tuning-bell on the Bellwright's back")
		if bell.size() == 1:
			var at := (bell[0] as Node3D).global_position - wright.global_position
			assert_gt(at.y, 1.0, "hung high on him")
	# the crown on the digger-king, Ardo's antlers on the marshal
	var king := _spawn("core:boss/digger_king")
	if king != null and king.anim.model != null:
		assert_eq((king.anim.model.get("appearance") as CharacterAppearance).part("headgear"), "crude_crown")
	var marshal := _spawn("core:boss/unvowed_marshal")
	if marshal != null and marshal.anim.model != null:
		var head: Node3D = marshal.anim.model.call("socket", "Head")
		assert_true(head.get_node_or_null("Antlers") != null, "Ardo's antlers on the Marshal")


func test_the_uncanny_are_lit_by_their_own_light() -> void:
	for id in ["core:boss/the_name_wife", "core:boss/hethra_undertone", "core:boss/barrow_wife"]:
		var e := _spawn(id)
		assert_true(e != null and e.anim.model != null, id)
		if e == null or e.anim.model == null:
			continue
		var lit := 0
		for mi in e.anim.model.find_children("*", "MeshInstance3D", true, false):
			var over := (mi as MeshInstance3D).material_overlay
			while over != null:
				if over is ShaderMaterial and (over as ShaderMaterial).shader == EnemyDress.AURA_SHADER:
					lit += 1
					break
				over = over.next_pass
		assert_gt(lit, 3, "%s's whole body is lit at its edges" % id)
		assert_gt(e.anim.model.find_children("AuraMotes", "CPUParticles3D", true, false).size(), 0, "%s has motes about it" % id)


func test_a_carried_thing_rides_its_bone_where_the_def_puts_it() -> void:
	var e := _spawn("core:boss/the_receiver")
	assert_true(e != null and e.anim.model != null)
	if e == null or e.anim.model == null:
		return
	var book := e.anim.model.find_children("Carried_hearthvale_book_a", "Node3D", true, false)
	assert_eq(book.size(), 1, "the register at his hip")
	if book.size() != 1:
		return
	# at his left hip (+X is the body's left): the register is on his left, hip-high
	var local: Vector3 = (e.anim.model as Node3D).global_transform.affine_inverse() * (book[0] as Node3D).global_position
	var s := float(ContentDB.get_or_empty("core:boss/the_receiver")["scale"]) * 1.88 / 1.78
	assert_gt(local.x, 0.15 * s, "on his left side (%.2f)" % local.x)
	assert_true(local.y > 0.6 * s and local.y < 1.1 * s, "hip-high (%.2f)" % local.y)
