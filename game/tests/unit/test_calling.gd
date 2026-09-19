extends TestCase
## Calling (DESIGN §5.3): the fifth school, whose spells put a body in the room on your side.
## Until this pass it was a skill with no spells and a cast type the runtime refused, so these
## tests check the whole way through: content, cast, allegiance, and letting go.

const HOUND := "core:spell/call_the_hound"

var spawner: EnemySpawner
var sayer: Enemy


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	spawner = EnemySpawner.new()
	spawner.spawn_on_ready = false
	spawner.respawn_on_rest = false
	spawner.drop_to_ground = false
	_tree().root.add_child(spawner)
	sayer = spawner.spawn_one("core:enemy/roadside_bandit", Vector3.ZERO, 0.0)


func after_each() -> void:
	spawner.clear_all()
	_tree().root.remove_child(spawner)
	spawner.free()


# --- content ------------------------------------------------------------------------------------

func test_the_calling_spells_name_creatures_that_exist() -> void:
	var called := 0
	for s in ContentDB.all("spell"):
		if str(s["school"]) != "calling":
			continue
		called += 1
		assert_eq(str(s["cast_type"]), "summon")
		for e in s.get("effects", []):
			assert_eq(str(e["type"]), "summon")
			assert_true(ContentDB.has(str(e["enemy"])), "%s calls %s" % [s["id"], e.get("enemy")])
			assert_gt(float(e.get("duration", 0.0)), 0.0, "a calling runs down")
	assert_eq(called, 3)


# --- casting ------------------------------------------------------------------------------------

func test_casting_a_calling_puts_a_body_in_the_room() -> void:
	sayer.caster.cast(HOUND)
	assert_true(sayer.caster.casting)
	sayer.caster.advance(3.0)
	assert_false(sayer.caster.casting, "the cast completes")
	var hound: Enemy = null
	for e in spawner.alive():
		if e.enemy_id == "core:enemy/down_wolf":
			hound = e
	assert_true(hound != null, "the hound answers")
	assert_eq(hound.faction, "player", "what you call fights for you")
	assert_true(hound.is_in_group(Perception.ALLY_GROUP))
	assert_gt(hound.life_left, 0.0, "and it is not here forever")
	assert_eq(int(hound.marks_range[1]), 0, "a called thing is not a purse")


func test_a_called_thing_lets_go_when_its_time_runs_out() -> void:
	sayer.caster.cast(HOUND)
	sayer.caster.advance(3.0)
	var hound: Enemy = spawner.alive()[spawner.alive().size() - 1]
	var dismissed: Array = []
	var handler := func(id: String, _n: Node) -> void: dismissed.append(id)
	EventBus.summon_dismissed.connect(handler)
	hound.life_left = 0.2
	hound._tick_timers(0.3)
	EventBus.summon_dismissed.disconnect(handler)
	assert_eq(dismissed.size(), 1, "it lets go rather than dying")
	assert_true(hound.dead)


func test_calling_costs_mana_and_gives_the_school_its_xp() -> void:
	var def := ContentDB.get_or_empty(HOUND)
	assert_eq(SpellRuntime.skill_for(def), "calling")
	sayer.caster.mana_max = 120.0
	sayer.caster.mana = 100.0
	var skill := sayer.caster.skill_for(def)
	assert_true(sayer.caster.cast(HOUND))
	assert_near(sayer.caster.mana, 100.0 - SpellRuntime.cost_of(def, skill), 0.01)
	var taught: Array = []
	var handler := func(skill_id: String, xp: float) -> void: taught.append([skill_id, xp])
	EventBus.skill_used.connect(handler)
	sayer.caster.advance(3.0)
	EventBus.skill_used.disconnect(handler)
	assert_eq(taught.size(), 1, "a completed calling teaches the school")
	assert_eq(str(taught[0][0]), "calling")
	assert_near(float(taught[0][1]), SpellRuntime.xp_for(def), 0.01)


func test_an_ally_hunts_what_hunts_you_and_not_you() -> void:
	var ally := spawner.spawn_one("core:enemy/remembered_warden", Vector3(3, 0, 0), 0.0)
	ally.become_ally(30.0)
	var wolf := spawner.spawn_one("core:enemy/down_wolf", Vector3(6, 0, 0), 0.0)
	assert_true(ally.is_hostile_to(wolf), "the called takes your enemies as its own")
	assert_true(wolf.is_hostile_to(ally), "and they take it as theirs")
	var player := Node3D.new()
	player.add_to_group("player")
	_tree().root.add_child(player)
	assert_false(ally.is_hostile_to(player), "it does not turn on the one who called it")
	_tree().root.remove_child(player)
	player.free()
