extends TestCase
## Aud Fennick's life follows what happens to her.
##
## She walks into the grey at the end of the vigil, leaving her bell on a stone for Cadwen, and the
## roster put her back in her tent at Pilgrim's Ash the next hour, mending other people's grey. Her
## def now says when she is gone (`gone_when`): the registry stands her up nowhere and keeps her off
## the clock, and Seventeen Bells, which sends you south to ask her about Hesta's silent bell, has
## Cadwen to ask when she has already gone on: where she went, what to tell Hesta, and what the Order
## does with a Fennick bell that reached Pilgrim's Ash after its Fennick had left.

const AUD := "core:npc/aud_fennick"
const BELLS := "core:quest/seventeen_bells"
const GONE := "aud_left_her_bell"

var log_node: Node
var inventory: SocialFakes.FakeInventory
var player: SocialFakes.FakePlayer
var registry: NpcRegistry


func before_each() -> void:
	log_node = Social.quests
	GameState.reset_for_new_game(1)
	log_node.reset_for_new_game()
	Social.factions.reset_for_new_game()
	inventory = SocialFakes.FakeInventory.new()
	player = SocialFakes.FakePlayer.new()
	Social.bind("inventory", inventory)
	Social.bind("player", player)
	registry = NpcRegistry.ensure()
	registry.despawn_all()
	registry.loaded_cells.clear()
	WorldClock.set_time(12.0, 2)


func after_each() -> void:
	if Social.dialogue.is_running():
		Social.dialogue.stop()
	GameState.clear_flag(GONE)
	log_node.reset_for_new_game()
	Social.factions.reset_for_new_game()
	Social.bind("inventory", null)
	Social.bind("player", null)
	Social.refresh_providers()
	registry.despawn_all()
	registry.loaded_cells.clear()
	registry.simulate_all("clear")
	WorldClock.set_time(9.0, 2)


func _talk(npc_id: String) -> Node:
	var runner := Social.talk(npc_id)
	for i in 8:
		if not runner.is_running() or not runner.current_choices.is_empty():
			break
		runner.advance()
	return runner


func _press(runner: Node, prefix: String) -> bool:
	var offered: Array[String] = []
	for i in (runner.current_choices as Array).size():
		var text := str((runner.current_choices[i] as Dictionary).get("text", ""))
		offered.append(text)
		if text.begins_with(prefix):
			runner.choose(i)
			return true
	fail("no choice starting '%s' was offered; got %s" % [prefix, str(offered)])
	return false


# --- the roster ------------------------------------------------------------------------------------

func test_she_is_at_pilgrims_ash_until_she_walks_into_the_grey() -> void:
	registry.simulate_all("clear")
	assert_eq(registry.place_of(AUD), "core:place/pilgrims_ash", "before the vigil, at the Ash")
	assert_true(registry.npcs_at("core:place/pilgrims_ash").has(AUD))
	GameState.set_flag(GONE)
	registry.simulate_all("clear")
	assert_eq(registry.place_of(AUD), "", "gone into the grey, and put back in her tent the next hour")
	assert_false(registry.npcs_at("core:place/pilgrims_ash").has(AUD), "counted among the Ash's people")
	assert_true(registry.is_alive(AUD), "gone on is not dead: nobody killed her")
	registry.loaded_cells[WorldProbe.cell_of_place("core:place/pilgrims_ash")] = true
	assert_true(registry.spawn(AUD) == null, "stood up at Pilgrim's Ash after she left")


# --- Seventeen Bells, after the vigil ----------------------------------------------------------------

## Sent south to ask her, after she has already gone on: Cadwen answers, and the choice is put.
func test_cadwen_answers_for_her_and_the_bell_is_decided() -> void:
	GameState.set_flag(GONE)
	assert_true(log_node.start(BELLS))
	log_node.set_stage(BELLS, "find_a_fennick")
	EventBus.place_discovered.emit("core:place/pilgrims_ash")
	var runner := _talk("core:npc/cadwen_ash")
	_press(runner, "I'm looking for Aud Fennick")
	assert_eq(log_node.stage_id_of(BELLS), "what_now", "the Order's answer is the answer")
	if runner.is_running():
		runner.stop()
	runner = _talk("core:npc/cadwen_ash")
	_press(runner, "Hesta Hollins wants to know")
	_press(runner, "Tell Hesta the Fennicks are gone")
	assert_eq(log_node.stage_id_of(BELLS), "tell_hesta", "decided at the Ash, with nobody to carry it to")
	assert_true(GameState.has_flag("fennick_bell_buried"))


## She left while the bell was on its way to her: the Order hangs it beside hers.
func test_a_bell_that_arrives_after_its_fennick_is_hung_with_hers() -> void:
	assert_true(log_node.start(BELLS))
	log_node.set_stage(BELLS, "carry_the_bell")
	inventory.add("core:item/fennick_bell", 1)
	GameState.set_flag(GONE)
	var runner := _talk("core:npc/cadwen_ash")
	_press(runner, "Aud was gone before the Fennick bell")
	assert_eq(inventory.count("core:item/fennick_bell"), 0, "the Order took the bell")
	assert_eq(log_node.stage_id_of(BELLS), "tell_hesta")


## While she is still here, nothing about her changes: the bell goes to her own hands.
func test_while_she_is_here_the_bell_goes_to_her() -> void:
	assert_true(log_node.start(BELLS))
	log_node.set_stage(BELLS, "carry_the_bell")
	inventory.add("core:item/fennick_bell", 1)
	var runner := _talk("core:npc/cadwen_ash")
	for c in runner.current_choices:
		assert_false(str((c as Dictionary).get("text", "")).begins_with("Aud was gone"), "Cadwen took the bell off a living Aud's road")
	if runner.is_running():
		runner.stop()
	runner = _talk(AUD)
	if runner.is_running():
		runner.stop()
	assert_eq(inventory.count("core:item/fennick_bell"), 0, "handed to Aud when you finished speaking to her")
	assert_eq(log_node.stage_id_of(BELLS), "tell_hesta")
