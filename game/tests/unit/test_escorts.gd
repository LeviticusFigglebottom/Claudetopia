extends TestCase
## Walking somebody somewhere, with bodies. `QuestLog` has waited for `escort_arrived` since it
## was written and nothing in the game ever said it, so the Tolling Order's first quest and every
## escort a job board posts could be taken and not finished. These stand Aud Fennick up, walk her
## to the Hushline by moving her and a stand-in player by hand and asking `Escorts` to look, and
## check the four things that can happen on the road: she arrives, she is left behind and caught
## up with, she dies, or the game is saved half way.

const VIGIL := "core:quest/vigil"
const AUD := "core:npc/aud_fennick"
const HUSHLINE := "core:place/hushline"
const HEARTHVALE := "core:region/hearthvale"
const MERROWBY := "core:place/merrowby"
const STEP_M := 25.0

var registry: NpcRegistry
var escorts: Escorts
var player: Node3D
var host: Node3D
var bag: SocialFakes.FakeInventory
var arrived: Array = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	Social.quests.reset_for_new_game()
	Social.standing.reset_for_new_game()
	Social.factions.reset_for_new_game()
	bag = SocialFakes.FakeInventory.new()
	Social.bind("inventory", bag)
	registry = NpcRegistry.ensure()
	registry.despawn_all()
	registry.states.clear()
	registry.rebuild()
	# A streamer left in the tree by another test would stand villagers up round the stand-in;
	# this stands up only who it needs.
	var streamer := _tree().get_first_node_in_group(NpcStreamer.GROUP)
	if streamer != null:
		streamer.set("enabled", false)
	host = Node3D.new()
	host.name = "EscortTestHost"
	_tree().root.add_child(host)
	escorts = Escorts.new()
	escorts.enabled = false
	host.add_child(escorts)
	player = Node3D.new()
	player.name = "StandIn"
	player.add_to_group("player")
	host.add_child(player)
	arrived = []
	EventBus.escort_arrived.connect(_on_arrived)


func after_each() -> void:
	EventBus.escort_arrived.disconnect(_on_arrived)
	registry.despawn_all()
	registry.states.clear()
	registry.rebuild()
	_tree().root.remove_child(host)
	host.free()
	for flag in ["cadwen_asked_escort", "aud_agreed_to_walk"]:
		Social.ctx.clear_flag(flag)
	Social.quests.reset_for_new_game()
	Social.bind("inventory", null)
	Social.refresh_providers()


func _on_arrived(npc_id: String, place_id: String) -> void:
	arrived.append([npc_id, place_id])


## Vigil at the escort, with Aud spoken to and willing, and her body standing beside the player.
func _set_out() -> Node3D:
	assert_true(Social.quests.start(VIGIL))
	Social.quests.set_stage(VIGIL, "the_pilgrim")
	Social.ctx.set_flag("cadwen_asked_escort")
	Social.ctx.set_flag("aud_agreed_to_walk")
	EventBus.dialogue_ended.emit(AUD)
	var body := registry.spawn(AUD) as Node3D
	assert_true(body != null, "Aud was not stood up")
	player.global_position = body.global_position + Vector3(2.0, 0.0, 0.0)
	escorts.tick()
	return body


## Walks the player and Aud together towards `to`, a step at a time, looking at each step.
func _walk_together(body: Node3D, to: Vector3, max_steps := 200) -> int:
	var steps := 0
	while steps < max_steps and arrived.is_empty():
		var at := player.global_position
		var dir := Vector3(to.x - at.x, 0.0, to.z - at.z)
		if dir.length() < 1.0:
			break
		var step := minf(STEP_M, dir.length())
		player.global_position = at + dir.normalized() * step
		body.global_position = player.global_position - dir.normalized() * 2.0
		escorts.tick()
		steps += 1
	return steps


func _journal() -> Array:
	return Social.quests.entry(VIGIL)["journal"]


func _journal_says(words: String) -> bool:
	for line in _journal():
		if str(line).contains(words):
			return true
	return false


# --- setting out ------------------------------------------------------------------------------------

func test_nothing_sets_out_until_she_has_been_asked_and_said_yes() -> void:
	assert_true(Social.quests.start(VIGIL))
	Social.quests.set_stage(VIGIL, "the_pilgrim")
	var body := registry.spawn(AUD) as Node3D
	player.global_position = body.global_position
	escorts.tick()
	assert_false(registry.is_escorted(AUD), "the stage asks you to speak to her first")
	EventBus.dialogue_ended.emit(AUD)
	escorts.tick()
	assert_false(registry.is_escorted(AUD), "spoken to, but she has not said she will walk")
	Social.ctx.set_flag("aud_agreed_to_walk")
	escorts.tick()
	assert_true(registry.is_escorted(AUD), "asked and willing, she sets out")
	assert_true(bool(body.call("is_following")), "and walks at your side")
	assert_true(_journal_says("falls in beside you"))


# --- arriving -----------------------------------------------------------------------------------------

func test_she_walks_with_you_to_the_line_and_the_objective_closes_there() -> void:
	var body := _set_out()
	assert_true(registry.is_escorted(AUD))
	var line := WorldProbe.place_position(HUSHLINE)
	var steps := _walk_together(body, line)
	assert_gt(steps, 40, "Pilgrim's Ash to the Hushline is most of two kilometres")
	assert_eq(arrived, [[AUD, HUSHLINE]], "Escorts said she had arrived, once")
	assert_eq(Social.quests.stage_id_of(VIGIL), "what_she_left", "and the quest log closed the walk")
	assert_false(registry.is_escorted(AUD))
	assert_false(bool(body.call("is_following")), "she stops at the line")
	assert_eq(registry.waiting_at(AUD), HUSHLINE, "and stands there")
	registry.simulate_all("clear")
	assert_eq(registry.place_of(AUD), HUSHLINE, "while you are there, her timetable does not take her away")
	registry.despawn(AUD)
	assert_eq(registry.waiting_at(AUD), "", "once you have gone, she goes back to her own life")


# --- left behind ------------------------------------------------------------------------------------

func test_she_waits_where_you_left_her_and_falls_in_again() -> void:
	var body := _set_out()
	var at := body.global_position
	player.global_position = at + Vector3(80.0, 0.0, 0.0)
	escorts.tick()
	assert_true(registry.escort_left(AUD), "eighty metres off, she has been left behind")
	assert_false(bool(body.call("is_following")), "and stands where she was")
	assert_true(registry.is_escorted(AUD), "the escort is paused, not over")
	assert_true(_journal_says("You left Aud Fennick behind"), "the journal says so: %s" % str(_journal()))
	assert_true(arrived.is_empty())
	player.global_position = at + Vector3(10.0, 0.0, 0.0)
	escorts.tick()
	assert_false(registry.escort_left(AUD), "come back to her and she walks on")
	assert_true(bool(body.call("is_following")))
	assert_true(_journal_says("falls in beside you again"))


# --- dying ------------------------------------------------------------------------------------------------

func test_if_she_dies_on_the_road_the_quest_is_lost_and_says_so() -> void:
	var body := _set_out()
	assert_true(body != null)
	registry.kill(AUD)
	escorts.tick()
	assert_true(Social.quests.is_failed(VIGIL), "an escort nobody can finish fails")
	assert_true(_journal_says("Aud Fennick died on the road to The Hushline"), "and the journal says who and where: %s" % str(_journal()))
	assert_false(registry.is_escorted(AUD))


# --- a save on the road --------------------------------------------------------------------------------

func test_a_save_made_on_the_road_loads_on_the_road() -> void:
	var body := _set_out()
	var line := WorldProbe.place_position(HUSHLINE)
	_walk_together(body, body.global_position + (line - body.global_position).normalized() * 300.0, 12)
	var stood := body.global_position
	var npcs := JSON.stringify(registry.to_save())
	var quests := JSON.stringify(Social.quests.to_save())
	registry.despawn_all()
	registry.states.clear()
	registry.rebuild()
	Social.quests.reset_for_new_game()
	assert_false(registry.is_escorted(AUD))
	Social.quests.from_save(JSON.parse_string(quests))
	registry.from_save(JSON.parse_string(npcs))
	assert_true(registry.is_escorted(AUD), "the roster remembers she is on the road")
	assert_true(registry.escort_position(AUD).distance_to(stood) < 0.5, "and where")
	assert_true(registry.spawn_position(AUD).distance_to(stood) < 0.5, "so she stands up there, not at home")
	var again := (registry.actor(AUD) if registry.is_spawned(AUD) else registry.spawn(AUD)) as Node3D
	player.global_position = again.global_position + Vector3(3.0, 0.0, 0.0)
	escorts.tick()
	assert_true(bool(again.call("is_following")), "and walks on with you")
	assert_eq(_count_bodies(AUD), 1, "one of her, not two")


func _count_bodies(npc_id: String) -> int:
	var n := 0
	for node in _tree().get_nodes_in_group("npc"):
		if str(node.get("npc_id")) == npc_id and not node.is_queued_for_deletion():
			n += 1
	return n


# --- the walking itself ------------------------------------------------------------------------------

func test_a_follower_keeps_a_step_behind_and_hurries_to_catch_up() -> void:
	var body := registry.spawn(AUD) as Npc
	var leader := Node3D.new()
	host.add_child(leader)
	leader.global_position = body.global_position + Vector3(10.0, 0.0, 0.0)
	body.follow(leader)
	body.update_follow()
	assert_true(body.has_target, "ten metres behind, she walks")
	assert_true(body.target_position.distance_to(leader.global_position) < Npc.FOLLOW_GAP_M, "to a step behind, not onto your heels")
	assert_eq(body.move_speed(), Npc.TRAVEL_SPEED, "and a little quicker than a stroll")
	leader.global_position = body.global_position + Vector3(20.0, 0.0, 0.0)
	body.update_follow()
	assert_eq(body.move_speed(), Npc.FLEE_SPEED, "well behind, she hurries")
	leader.global_position = body.global_position + Vector3(1.0, 0.0, 0.0)
	body.update_follow()
	assert_false(body.has_target, "at your elbow she stands")
	body.stop_following()
	assert_false(body.is_following())


# --- the job boards' escorts ------------------------------------------------------------------------

func test_a_board_escort_walks_the_same_road() -> void:
	var job: Dictionary = {}
	for seed_value in range(1, 400):
		for candidate in Social.radiant.generate(HEARTHVALE, 6, MERROWBY, seed_value):
			if str(candidate.get("kind", "")) == "escort":
				job = candidate
				break
		if not job.is_empty():
			break
	assert_false(job.is_empty(), "no board in Hearthvale ever posted an escort")
	if job.is_empty():
		return
	var quest_id := str(job["id"])
	var traveller := ""
	var destination := ""
	for stage in job["stages"]:
		for o in (stage as Dictionary).get("objectives", []):
			if str((o as Dictionary).get("type", "")) == "escort":
				traveller = str(o["target"])
				destination = str(o["place"])
	assert_true(Social.quests.start(quest_id))
	var body := registry.spawn(traveller) as Node3D
	assert_true(body != null, "%s was not stood up" % traveller)
	player.global_position = body.global_position + Vector3(2.0, 0.0, 0.0)
	escorts.tick()
	assert_false(registry.is_escorted(traveller), "not before you have told them you are ready")
	EventBus.dialogue_ended.emit(traveller)
	escorts.tick()
	assert_true(registry.is_escorted(traveller), "the board's traveller sets out")
	_walk_together(body, WorldProbe.place_position(destination), 400)
	assert_eq(arrived, [[traveller, destination]])
	assert_true(Social.quests.is_completed(quest_id), "and the job is done when they get there")
