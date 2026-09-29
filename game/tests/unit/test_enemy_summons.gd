extends TestCase
## Summoning: a boss attack carrying a "summons" block calls up help when the blow lands.
## The Barrow Reeve rings his hammer at half health and the cists answer (WORLD_BIBLE §9), so
## the data has to reach real bodies standing in the room rather than sitting in the JSON.

const REEVE := "core:boss/barrow_reeve"
const WIGHT := "core:enemy/hedge_wight"

var spawner: EnemySpawner


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	spawner = EnemySpawner.new()
	spawner.spawn_on_ready = false
	spawner.respawn_on_rest = false
	spawner.drop_to_ground = false
	_tree().root.add_child(spawner)


func after_each() -> void:
	spawner.clear_all()
	_tree().root.remove_child(spawner)
	spawner.free()


func _reeve() -> Enemy:
	return spawner.spawn_one(REEVE, Vector3.ZERO, 0.0)


func test_the_reeve_exists_and_rings_at_half_health() -> void:
	var def := ContentDB.get_or_empty(REEVE)
	assert_false(def.is_empty(), "the Hollin Barrow encounter data calls for this boss")
	var phases: Array = def.get("phases", [])
	assert_eq(phases.size(), 2, "on watch, then the row is not finished")
	assert_near(float(phases[1].get("hp", 0.0)), 0.5, 0.001)
	var toll: Dictionary = {}
	for a in phases[1].get("attacks", []):
		if str(a.get("name", "")) == "the_toll":
			toll = a
	assert_false(toll.is_empty(), "the second phase rings the hammer")
	assert_eq(str(toll["summons"]["enemy"]), WIGHT)
	assert_eq(int(toll["summons"]["count"]), 1, "one of the cist-dead a toll: four buried the fights run's level-1 player")


func test_summoning_puts_bodies_in_the_room() -> void:
	var reeve := _reeve()
	assert_true(reeve != null, "the boss spawns")
	reeve._summon({"enemy": WIGHT, "count": 3, "radius": 5.0})
	var wights := 0
	for e in spawner.alive():
		if e.enemy_id == WIGHT:
			wights += 1
	assert_eq(wights, 3, "three wights stand up")
	assert_eq(reeve.summons_alive.size(), 3)
	for e in reeve.summons_alive:
		var d := e.global_position.distance_to(reeve.global_position)
		assert_true(d > 1.0 and d < 8.0, "help arrives around the summoner, not inside it (%.1f m)" % d)


func test_the_cap_holds_across_several_tolls() -> void:
	var reeve := _reeve()
	reeve._summon({"enemy": WIGHT, "count": 4, "radius": 5.0, "cap": 4})
	reeve._summon({"enemy": WIGHT, "count": 4, "radius": 5.0, "cap": 4})
	assert_eq(reeve.summons_alive.size(), 4, "the second toll adds nobody while four still stand")


func test_the_dead_stop_counting_against_the_cap() -> void:
	var reeve := _reeve()
	reeve._summon({"enemy": WIGHT, "count": 4, "radius": 5.0, "cap": 4})
	for e in reeve.summons_alive:
		e.dead = true
	reeve._summon({"enemy": WIGHT, "count": 2, "radius": 5.0, "cap": 4})
	var standing := 0
	for e in reeve.summons_alive:
		if not e.dead:
			standing += 1
	assert_eq(standing, 2, "the room has room again")


func test_a_summons_block_without_an_enemy_is_ignored() -> void:
	var reeve := _reeve()
	reeve._summon({"count": 3})
	assert_eq(reeve.summons_alive.size(), 0)
