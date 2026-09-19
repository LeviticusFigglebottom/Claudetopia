extends TestCase
## Actor: the base every fighting body shares — components, equipment sockets, hit resolution,
## faction rules, death and save data. These need a scene tree, so actors are parented to the
## test runner's root and freed afterwards.

var actor: Actor


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	actor = Actor.new()
	actor.display_name = "Test Dummy"
	actor.faction = "hostile"
	actor.max_health = 100.0
	actor.poise_max = 30.0
	_tree().root.add_child(actor)


func after_each() -> void:
	actor.free()


# --- construction ------------------------------------------------------------------------------

func test_components_are_built() -> void:
	assert_true(actor.stamina_comp != null, "stamina component")
	assert_true(actor.poise_comp != null, "poise component")
	assert_true(actor.status != null, "status effects")
	assert_true(actor.anim != null, "animation driver")
	assert_true(actor.caster != null, "spell caster")
	assert_true(actor.hurtbox != null, "hurtbox")
	assert_true(actor.model != null, "Model pivot")
	assert_near(actor.health, 100.0)
	assert_near(actor.max_stamina, DamageModel.stamina_max(actor.endurance))
	assert_near(actor.max_poise, 30.0)
	assert_near(actor.max_mana, DamageModel.mana_max(actor.will))


func test_model_pivot_faces_gameplay_forward() -> void:
	# CONTRACTS §1: models face +Z after export, so the Model node is turned 180 degrees.
	assert_near(absf(actor.model.rotation.y), PI, 0.01)
	assert_near(actor.forward().z, -1.0, 0.01, "gameplay forward is -Z")


func test_placeholder_body_stands_in_for_the_missing_rig() -> void:
	# The forge's humanoid_model.tscn does not exist yet; the driver must still animate something.
	assert_false(actor.anim.has_real_model(), "no real model is expected in this pass")
	assert_true(actor.anim.placeholder != null, "a placeholder body is built instead")


func test_equipment_sockets_use_the_contract_names() -> void:
	for socket_name in Actor.SOCKET_NAMES:
		var socket := actor.get_socket(socket_name)
		assert_true(socket != null, "missing socket %s" % socket_name)
		# Node names cannot contain '.', so the contract name is sanitised for the node only.
		assert_eq(socket.name, Actor.socket_node_name(socket_name))
		assert_true(socket is Marker3D, "%s should be a Marker3D placeholder until the rig exists" % socket_name)
	# Looked up twice, the same node comes back (no duplicates piling up under Model).
	assert_eq(actor.get_socket("Socket.WeaponR"), actor.get_socket("Socket.WeaponR"))


func test_contract_socket_list_is_complete() -> void:
	for required in ["Socket.WeaponR", "Socket.WeaponL", "Socket.ShieldL", "Socket.Back", "Socket.HipL", "Socket.Head", "Socket.Lantern"]:
		assert_true(Actor.SOCKET_NAMES.has(required), "CONTRACTS §2 socket %s is missing" % required)


# --- hit resolution ----------------------------------------------------------------------------

func _hit(amount: float, poise: float = 0.0) -> HitData:
	var h := HitData.new()
	h.amount = amount
	h.poise_damage = poise
	h.kind = "slash"
	h.origin = actor.global_position + Vector3(0, 0, -3)   # in front of the actor
	return h


func test_plain_hit_applies_damage() -> void:
	var outcome := actor.take_hit(_hit(25.0))
	assert_eq(outcome, "hit")
	assert_near(actor.health, 75.0)


func test_armour_and_resist_reduce_damage() -> void:
	actor.armour_flat = 5.0
	actor.resists = {"slash": 0.5}
	actor.take_hit(_hit(25.0))
	assert_near(actor.health, 90.0, 0.01, "(25 - 5) * 0.5")


func test_i_frames_deny_a_hit() -> void:
	var t := Actor.now()
	actor.set_invulnerable_window(t - 0.1, t + 1.0)
	assert_eq(actor.take_hit(_hit(25.0)), "dodged")
	assert_near(actor.health, 100.0)
	actor.clear_invulnerability()
	assert_eq(actor.take_hit(_hit(25.0)), "hit")


func test_blocking_scales_damage_and_costs_stamina() -> void:
	actor.is_blocking = true
	actor.block_stability = 0.8
	var stamina_before := actor.stamina
	assert_eq(actor.take_hit(_hit(50.0)), "blocked")
	assert_near(actor.health, 90.0, 0.01, "50 * (1 - 0.8)")
	assert_near(stamina_before - actor.stamina, 6.0, 0.01, "50 * 0.6 * (1 - 0.8)")


func test_a_hit_from_behind_is_not_blocked() -> void:
	actor.is_blocking = true
	actor.block_stability = 0.8
	var h := _hit(50.0)
	h.origin = actor.global_position + Vector3(0, 0, 3)   # behind
	assert_eq(actor.take_hit(h), "hit")
	assert_near(actor.health, 50.0)


func test_parry_opens_the_attacker_for_a_riposte() -> void:
	var attacker := Actor.new()
	_tree().root.add_child(attacker)
	actor.can_parry = true
	actor.parry_pressed_at = Actor.now()
	var h := _hit(30.0)
	h.attacker = attacker
	assert_eq(actor.take_hit(h), "parried")
	assert_near(actor.health, 100.0, 0.001, "a parry takes no damage")
	assert_true(attacker.is_riposte_open(), "the attacker is open for 2 s")
	attacker.free()


func test_unparryable_hits_ignore_the_window() -> void:
	actor.can_parry = true
	actor.parry_pressed_at = Actor.now()
	var h := _hit(30.0)
	h.parryable = false
	assert_eq(actor.take_hit(h), "hit")


func test_poise_break_staggers() -> void:
	var flags := {"staggered": false}
	actor.staggered.connect(func() -> void: flags["staggered"] = true)
	actor.take_hit(_hit(1.0, 40.0))
	assert_true(bool(flags["staggered"]))
	assert_true(actor.is_stunned())
	assert_false(actor.can_act(), "a staggered actor cannot start an action")


func test_knockdown_hit_knocks_down() -> void:
	var flags := {"down": false}
	actor.knocked_down.connect(func() -> void: flags["down"] = true)
	var h := _hit(10.0)
	h.knockdown = true
	actor.take_hit(h)
	assert_true(bool(flags["down"]))
	assert_true(actor.status.has("knockdown"))


func test_hit_statuses_are_applied() -> void:
	var h := _hit(10.0)
	h.statuses = [{"id": "bleeding", "duration": 6.0, "magnitude": 2.0}]
	actor.take_hit(h)
	assert_true(actor.status.has("bleeding"))


func test_shield_absorbs_before_health() -> void:
	actor.add_shield(30.0, 10.0)
	actor.take_hit(_hit(20.0))
	assert_near(actor.health, 100.0, 0.001, "the ward took it")
	assert_near(actor.shield_hp, 10.0)
	actor.take_hit(_hit(20.0))
	assert_near(actor.health, 90.0, 0.001, "10 absorbed, 10 through")


# --- factions ----------------------------------------------------------------------------------

func test_faction_hostility() -> void:
	var other := Actor.new()
	other.faction = "hostile"
	_tree().root.add_child(other)
	assert_false(actor.is_hostile_to(other), "same faction")
	other.faction = "player"
	assert_true(actor.is_hostile_to(other), "everything hostile fights the player")
	other.faction = "beasts"
	assert_false(actor.is_hostile_to(other), "unrelated factions ignore each other")
	actor.hostile_to = ["beasts"]
	assert_true(actor.is_hostile_to(other), "unless the def says otherwise")
	assert_false(actor.is_hostile_to(actor), "never itself")
	other.free()


# --- death and restore --------------------------------------------------------------------------

func test_death_emits_entity_killed_once() -> void:
	var seen := {"count": 0}
	var on_killed := func(_v: Node, _k: Node, _id: String) -> void: seen["count"] = int(seen["count"]) + 1
	EventBus.entity_killed.connect(on_killed)
	actor.take_hit(_hit(500.0))
	actor.take_hit(_hit(500.0))
	EventBus.entity_killed.disconnect(on_killed)
	assert_true(actor.is_dead())
	assert_false(actor.is_alive())
	assert_eq(int(seen["count"]), 1, "death fires once, not per corpse hit")
	assert_near(actor.health, 0.0)


func test_dead_actors_stop_taking_hits() -> void:
	actor.die(null)
	assert_eq(actor.take_hit(_hit(10.0)), "dead")


func test_full_restore_and_revive() -> void:
	actor.take_hit(_hit(60.0))
	actor.stamina_comp.spend(50.0)
	actor.status.apply("burning")
	actor.die(null)
	actor.revive()
	assert_false(actor.is_dead())
	assert_near(actor.health, 100.0)
	assert_near(actor.stamina, actor.max_stamina)
	assert_false(actor.status.has("burning"), "statuses are cleared")


# --- save ---------------------------------------------------------------------------------------

func test_save_round_trip_keeps_hp_position_and_status() -> void:
	actor.global_position = Vector3(3.0, 1.0, -7.0)
	actor.rotation.y = 1.25
	actor.take_hit(_hit(30.0))
	actor.status.apply("poisoned", 8.0)
	var data := actor.to_save()
	var other := Actor.new()
	_tree().root.add_child(other)
	other.from_save(data)
	assert_near(other.health, 70.0)
	assert_eq(other.global_position, Vector3(3.0, 1.0, -7.0))
	assert_near(other.rotation.y, 1.25, 0.001)
	assert_true(other.status.has("poisoned"))
	assert_near(other.status.remaining("poisoned"), 8.0, 0.1)
	other.free()


func test_save_round_trip_keeps_death() -> void:
	actor.die(null)
	var data := actor.to_save()
	var other := Actor.new()
	_tree().root.add_child(other)
	other.from_save(data)
	assert_true(other.is_dead())
	other.free()
