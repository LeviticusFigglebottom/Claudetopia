extends TestCase
## Potions, food and poison: what drinking a thing does to the body. The bag announced a use
## and nothing listened, so every potion in the game was coloured water — and the alchemy
## system's whole output was decorative.

const HEALTH_POTION := "core:item/potion_restore_health"
const LOAF := "core:item/hearth_loaf"


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


# --- the rules ------------------------------------------------------------------------------------

func test_an_instant_effect_becomes_a_stat_to_move() -> void:
	var plan := Consumables.plan([{"effect": "core:effect/restore_health", "magnitude": 20, "duration": 0}])
	assert_eq(plan.size(), 1)
	assert_eq(str(plan[0]["kind"]), "stat")
	assert_eq(str(plan[0]["stat"]), "health")
	assert_near(float(plan[0]["amount"]), 20.0)


func test_a_buff_becomes_a_modifier_with_a_clock() -> void:
	var plan := Consumables.plan([{"effect": "core:effect/fortify_vigour", "magnitude": 5, "duration": 60}])
	assert_eq(str(plan[0]["kind"]), "modifier")
	assert_near(float(plan[0]["duration"]), 60.0)
	assert_eq(str(plan[0]["mods"][0]["stat"]), "vigour")
	assert_near(float(plan[0]["mods"][0]["add"]), 5.0)


func test_harm_becomes_a_status() -> void:
	var plan := Consumables.plan([{"effect": "core:effect/damage_health", "magnitude": 5, "duration": 8}])
	assert_eq(str(plan[0]["kind"]), "status")
	assert_eq(str(plan[0]["id"]), "poisoned")


func test_a_cure_clears_what_it_names() -> void:
	var plan := Consumables.plan([{"effect": "core:effect/cure_poison", "magnitude": 1, "duration": 0}])
	assert_eq(str(plan[0]["kind"]), "cure")
	assert_true((plan[0]["ids"] as Array).has("poisoned"))


func test_an_effect_that_does_not_exist_is_skipped_quietly() -> void:
	assert_eq(Consumables.plan([{"effect": "core:effect/nothing_of_the_sort"}]).size(), 0)


# --- the body -------------------------------------------------------------------------------------

func test_drinking_a_potion_heals() -> void:
	var a := Actor.new()
	a.max_health = 100.0
	_tree().root.add_child(a)
	a.health = 40.0
	a.take_effects(ContentDB.get_or_empty(HEALTH_POTION).get("effects", []))
	assert_gt(a.health, 40.0, "the draught does something")
	_tree().root.remove_child(a)
	a.free()


func test_a_cure_potion_ends_the_poison() -> void:
	var a := Actor.new()
	_tree().root.add_child(a)
	a.status.apply("poisoned", 10.0, 5.0)
	assert_true(a.status.active.has("poisoned"))
	a.take_effects([{"effect": "core:effect/cure_poison", "magnitude": 1, "duration": 0}])
	assert_false(a.status.active.has("poisoned"), "cured")
	_tree().root.remove_child(a)
	a.free()


func test_the_bag_and_the_body_are_joined_up() -> void:
	# The whole point: use it in the menu, feel it in the world.
	var p := Player.new()
	var bag := Inventory.new()
	bag.name = "Inventory"
	p.add_child(bag)
	_tree().root.add_child(p)
	p.max_health = 100.0
	p.health = 30.0
	bag.is_player = true
	bag.add(HEALTH_POTION, 1)
	assert_true(bag.use(HEALTH_POTION))
	await _tree().process_frame
	assert_gt(p.health, 30.0, "drinking it in the menu heals the body in the world")
	assert_eq(bag.count(HEALTH_POTION), 0, "and the bottle is empty")
	_tree().root.remove_child(p)
	p.free()


func test_food_written_in_the_right_shape_feeds_you() -> void:
	var a := Actor.new()
	a.max_health = 100.0
	_tree().root.add_child(a)
	a.health = 50.0
	a.take_effects(ContentDB.get_or_empty(LOAF).get("effects", []))
	assert_near(a.health, 65.0, 0.01, "the Hearth Loaf is worth fifteen")
	_tree().root.remove_child(a)
	a.free()
