extends TestCase
## Every way a conversation is left lets the camera go (triage 41: "some dialog interactions, like
## trading, seem to freeze the camera stuck focusing on that person"). The shopkeeper's trade said
## `dialogue_started` and nothing ever said it ended, so the two-shot stayed on her; nothing ended a
## talk on a blow, a load, or the person walking off. The runner owns the conversation and every
## ending goes through its stop(); the camera's shot lasts only while it runs.
##
## A real player (its CameraRig) and real people, walked up to and spoken to with the interact key.

const BRAM := "core:npc/example_thatcher_bram"     # nothing written: the bare greeting
const NELL := "core:npc/example_grocer_nell"       # a shop and nothing written: the shop itself
const MAUD := "core:npc/maud_brambling"            # a shop and her own words: talks, offers the shop
const PLAYER := preload("res://actors/player/player.tscn")
const FRAME := 1.0 / 60.0
const RUNNER := preload("res://systems/dialogue/dialogue_runner.gd")

var _nodes: Array[Node] = []


func before_each() -> void:
	Peers.overrides.clear()
	GameState.reset_for_new_game(41)
	Social.reset_for_new_game()
	var reg := NpcRegistry.instance
	if reg != null:
		reg.despawn_all()
		reg.states.clear()
		reg.abstract_only = true
		reg.rebuild()


func after_each() -> void:
	if bool(Social.dialogue.call("is_running")):
		Social.dialogue.call("stop")
	UI.close_all()
	for n in _nodes:
		if is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	_nodes.clear()
	Peers.overrides.clear()


func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


func _player() -> Player:
	var p := PLAYER.instantiate() as Player
	_root().add_child(p)
	_nodes.append(p)
	p.global_position = at_place("core:place/merrowby", 40.0) + Vector3(0, 0, 1.4)
	Peers.overrides["player"] = p
	return p


func _npc(id: String) -> Npc:
	var n: Npc = load("res://actors/npc/npc.tscn").instantiate()
	n.npc_id = id
	_root().add_child(n)
	_nodes.append(n)
	n.global_position = at_place("core:place/merrowby", 40.0)
	n.set_physics_process(false)
	n.detection = 0.0
	return n


func _run(rig: CameraRig, seconds: float) -> void:
	for i in int(seconds / FRAME):
		rig._process(FRAME)


func _talking() -> bool:
	return bool(Social.dialogue.call("is_running"))


## Spoken to with the interact key; the camera is on them.
func _talk_to(me: Player, who: Npc) -> void:
	who.interact(me)
	assert_true(_talking(), "%s is spoken to" % who.npc_id)
	_run(me.camera_rig, 0.2)
	assert_eq(me.camera_rig.speaker, who, "and the camera frames %s" % who.npc_id)


func _assert_let_go(me: Player, why: String) -> void:
	assert_false(_talking(), "%s: the conversation is over" % why)
	_run(me.camera_rig, 1.2)
	assert_true(me.camera_rig.speaker == null, "%s: the camera lets the speaker go" % why)
	assert_false(me.camera_rig.is_framing_speaker(), "%s: and is back behind the player" % why)


func _choice_index(text: String) -> int:
	var i := 0
	for c in Social.dialogue.get("current_choices"):
		if str((c as Dictionary).get("text", "")) == text:
			return i
		i += 1
	return -1


# --- the shop -----------------------------------------------------------------------------------

func test_a_shop_with_nothing_to_say_is_its_screen_and_the_camera_stays_the_player_s() -> void:
	var me := _player()
	var nell := _npc(NELL)
	var said: Array = []
	var on_start := func(id: String) -> void: said.append(id)
	EventBus.dialogue_started.connect(on_start)
	nell.interact(me)
	EventBus.dialogue_started.disconnect(on_start)
	assert_true(UI.is_menu_open("trade"), "the shop's screen opens")
	assert_true(said.is_empty(), "and no conversation is said to have begun that nothing would end")
	_run(me.camera_rig, 0.5)
	assert_true(me.camera_rig.speaker == null, "the camera is not held on her")
	UI.close("trade")
	_run(me.camera_rig, 0.5)
	assert_false(me.camera_rig.is_framing_speaker(), "after the shop, the view is the player's")


func test_a_shopkeeper_with_words_talks_and_the_shop_hands_back_to_the_talk() -> void:
	var me := _player()
	var maud := _npc(MAUD)
	_talk_to(me, maud)
	# her hub may take a line or two to reach
	for i in 6:
		if _choice_index(RUNNER.TRADE_CHOICE) >= 0 or not _talking():
			break
		if (Social.dialogue.get("current_choices") as Array).is_empty():
			Social.dialogue.call("advance")
		else:
			break
	var at := _choice_index(RUNNER.TRADE_CHOICE)
	if at < 0:
		skip("Maud's first page does not offer the shop: %s" % str(Social.dialogue.get("current_choices")))
		return
	Social.dialogue.call("choose", at)
	assert_true(UI.is_menu_open("trade"), "asking to see her stock opens the shop")
	assert_true(_talking(), "and the conversation waits under it")
	UI.close("trade")
	assert_true(_talking(), "the shop closed, she is still there to talk to")
	# Escape on the page leaves the conversation
	var page: Node = UI.show_dialogue()
	page.call("_leave")
	_assert_let_go(me, "left after the shop")


# --- the other screens ----------------------------------------------------------------------------

func test_a_crouched_hand_opens_the_pocket_and_never_the_two_shot() -> void:
	var me := _player()
	var bram := _npc(BRAM)
	me.is_sneaking = true
	bram.interact(me)
	assert_true(UI.is_menu_open("pickpocket"), "the pocket's screen opens")
	assert_false(_talking(), "nobody is talking")
	_run(me.camera_rig, 0.5)
	assert_true(me.camera_rig.speaker == null, "and the camera is not on him")
	UI.close_all()


func test_the_road_between_the_stones_ends_the_talk_that_offered_it() -> void:
	var me := _player()
	var bram := _npc(BRAM)
	# a conversation with a body, whose one answer takes the road (as the Hearthstone's does)
	Social.dialogue.call("set_next_speaker", bram)
	Social.dialogue.call("start_def", {"id": "", "start": "road", "nodes": {"road": {"speaker": "npc", "text": "The flame leans.",
			"choices": [{"text": "Go on.", "next": "end", "effects": [{"travel": "core:place/nowhere"}]}]}}}, BRAM)
	_run(me.camera_rig, 0.2)
	assert_eq(me.camera_rig.speaker, bram, "framed while the road is offered")
	Social.dialogue.call("choose", 0)
	_assert_let_go(me, "the road taken")


func test_carried_off_mid_talk_the_talk_is_over() -> void:
	var me := _player()
	var bram := _npc(BRAM)
	_talk_to(me, bram)
	me.global_position += Vector3(300.0, 0.0, 0.0)     # a fast travel, a fall, a cart
	Social.dialogue.call("check_speaker")
	_assert_let_go(me, "the player carried off")


# --- interrupted ----------------------------------------------------------------------------------

func test_a_blow_ends_the_talk() -> void:
	var me := _player()
	var bram := _npc(BRAM)
	_talk_to(me, bram)
	EventBus.damage_dealt.emit(null, me, 6.0, "blunt")
	_assert_let_go(me, "struck mid-talk")


func test_a_foe_turning_on_the_player_ends_the_talk() -> void:
	var me := _player()
	var bram := _npc(BRAM)
	_talk_to(me, bram)
	var foe := Node3D.new()
	foe.set_script(_foe_script())
	_root().add_child(foe)
	_nodes.append(foe)
	foe.global_position = me.global_position + Vector3(8.0, 0.0, 0.0)
	foe.set("target", me)
	EventBus.enemy_engaged.emit(foe, true)
	_assert_let_go(me, "a foe engaged")


func _foe_script() -> GDScript:
	var s := GDScript.new()
	s.source_code = "extends Node3D\nvar target: Node3D = null\n"
	s.reload()
	return s


func test_the_person_walking_off_ends_the_talk() -> void:
	var me := _player()
	var bram := _npc(BRAM)
	_talk_to(me, bram)
	bram.global_position += Vector3(0.0, 0.0, -20.0)
	await (Engine.get_main_loop() as SceneTree).create_timer(RUNNER.WATCH_S * 3.0).timeout
	_assert_let_go(me, "he walked off (the runner's own watch)")


func test_the_person_gone_ends_the_talk() -> void:
	var me := _player()
	var bram := _npc(BRAM)
	_talk_to(me, bram)
	_root().remove_child(bram)
	Social.dialogue.call("check_speaker")
	_assert_let_go(me, "his cell unloaded")
	_root().add_child(bram)


func test_a_load_ends_the_talk() -> void:
	var me := _player()
	var bram := _npc(BRAM)
	_talk_to(me, bram)
	EventBus.game_loaded.emit("quick")
	_assert_let_go(me, "a save loaded mid-talk")


## The old trade's shape: a conversation said to begin that nothing runs. The camera does not take
## it, and a shot a conversation asked for ends the frame the conversation is not running.
func test_a_talk_that_is_not_running_holds_nothing() -> void:
	var me := _player()
	var bram := _npc(BRAM)
	EventBus.dialogue_started.emit(BRAM)
	_run(me.camera_rig, 0.3)
	assert_true(me.camera_rig.speaker == null, "a stray dialogue_started does not frame anybody")
	_talk_to(me, bram)
	# ended behind the bus's back (no dialogue_ended heard)
	Social.dialogue.set("_running", false)
	_run(me.camera_rig, 0.1)
	assert_true(me.camera_rig.speaker == null, "the shot lasts only while the conversation runs")
	Social.dialogue.set("_running", true)
	Social.dialogue.call("stop")
