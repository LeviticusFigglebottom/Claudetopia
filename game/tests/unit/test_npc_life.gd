extends TestCase
## A person whose hour keeps them in one place lives through it (IdleLife): the work in bouts, talk
## in turns, a look round, a few steps. Before, one clip went round from arriving until the hour
## moved them on, in step with the whole street, and whatever interrupted it (a wave to the player,
## a cower, a conversation) was the last thing they did until the clock moved (playtest 2026-09-27,
## 18). The first tests read the rhythm itself; the rest watch a body.

const BRAM := "core:npc/example_thatcher_bram"

var _nodes: Array[Node] = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	Peers.overrides.clear()
	var reg := NpcRegistry.instance
	if reg != null:
		reg.despawn_all()
		reg.abstract_only = true
	if Reactions.instance != null:
		Reactions.instance.forget_all()


func after_each() -> void:
	if Social.dialogue != null and bool(Social.dialogue.call("is_running")):
		Social.dialogue.call("stop")
	for n in _nodes:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.free()
	_nodes.clear()
	Peers.overrides.clear()


# --- the rhythm ------------------------------------------------------------------------------------

func _beats(life: IdleLife, activity: String, clip: String, n := 60) -> Array:
	var out: Array = []
	for i in n:
		out.append(life.next_beat(activity, clip))
	return out


func test_work_comes_in_bouts_with_a_breather_between() -> void:
	var beats := _beats(IdleLife.new(7), "work", "Work_Hammer")
	var at_it := 0
	var breathers := 0
	for b: Dictionary in beats:
		assert_gt(float(b["hold"]), 0.5, "every beat lasts a while")
		if str(b["clip"]) == "Work_Hammer":
			at_it += 1
			assert_true(float(b["hold"]) <= 15.0, "no bout goes on for ever (%.1f s)" % float(b["hold"]))
		else:
			breathers += 1
	assert_gt(at_it, 20, "they work")
	assert_gt(breathers, 20, "and stop now and then")


func test_talk_takes_turns_in_both_clips() -> void:
	var clips := {}
	var looks := {}
	for b: Dictionary in _beats(IdleLife.new(3), "socialise", "Talk_1"):
		clips[str(b["clip"])] = true
		looks[str(b["look"])] = true
	assert_true(clips.has("Talk_1") and clips.has("Talk_2"), "both ways of talking (%s)" % str(clips.keys()))
	assert_true(clips.has("Idle"), "and listening")
	assert_true(looks.has("person"), "turned to whoever is there")


func test_standing_about_looks_round_and_takes_a_few_steps() -> void:
	var looks := {}
	var wandered := 0.0
	for b: Dictionary in _beats(IdleLife.new(11), "idle", "Idle", 80):
		looks[str(b["look"])] = true
		wandered = maxf(wandered, float(b["wander"]))
		assert_true(float(b["wander"]) <= IdleLife.WANDER_M, "never far from their spot")
	assert_true(looks.has("around") and looks.has("person"), "a look round and a look at somebody (%s)" % str(looks.keys()))
	assert_gt(wandered, 0.9, "and a few steps now and then")


func test_no_two_people_keep_time_together() -> void:
	var a := _beats(IdleLife.new(1), "work", "Work_Dig", 6)
	var b := _beats(IdleLife.new(2), "work", "Work_Dig", 6)
	var same := 0
	for i in a.size():
		if absf(float(a[i]["hold"]) - float(b[i]["hold"])) < 0.01:
			same += 1
	assert_lt_or(same, 2, "two seeds' beats differ")
	assert_ne(IdleLife.new(1).tempo, IdleLife.new(2).tempo, "and so does their pace")


func assert_lt_or(a: int, b: int, msg: String) -> void:
	assert_true(a < b, msg)


# --- a body --------------------------------------------------------------------------------------

func _box(at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_tree().root.add_child(body)
	body.global_position = at
	_nodes.append(body)


func _worker() -> Npc:
	var o := Vector3(5300.0, 0.0, 5000.0)
	_box(o + Vector3(0, -0.5, 0), Vector3(60, 1, 60))
	var n: Npc = load("res://actors/npc/npc.tscn").instantiate()
	n.npc_id = BRAM
	_tree().root.add_child(n)
	_nodes.append(n)
	n.global_position = o
	n.apply_state({"place": "core:place/merrowby", "activity": "work", "spot": "roof_row", "alive": true, "hostile": false})
	return n


## Seconds until the model is back in `clip`, watched for at most `most` s; -1 when it never is.
func _until(n: Npc, clip: String, most: float) -> float:
	var t := 0.0
	while t < most:
		await _tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		var m := n._body_model()
		if m != null and str(m.call("current_intent")) == clip:
			return t
		if m == null and n.current_intent() == clip:
			return t
	return -1.0


func test_a_worker_waved_at_goes_back_to_work() -> void:
	var n := _worker()
	await _tree().physics_frame
	n.play_reaction("greet")
	assert_eq(n.current_intent(), "Wave")
	var back: float = await _until(n, "Work_Hammer", 14.0)
	assert_gt(back, 0.0, "back at the roof after the wave")


func test_one_who_cowered_gets_up_again() -> void:
	var n := _worker()
	await _tree().physics_frame
	n.play_reaction("hide")
	assert_eq(n.current_intent(), "Cower")
	var back: float = await _until(n, "Work_Hammer", 16.0)
	assert_gt(back, 0.0, "the cower ends and the work goes on")


func test_after_a_conversation_the_day_goes_on() -> void:
	var n := _worker()
	var talker := Node3D.new()
	_tree().root.add_child(talker)
	_nodes.append(talker)
	talker.global_position = n.global_position + Vector3(0, 0, 1.5)
	await _tree().physics_frame
	n.interact(talker)
	assert_eq(n.current_intent(), "Talk_1")
	if Social.dialogue != null and bool(Social.dialogue.call("is_running")):
		Social.dialogue.call("stop")
	else:
		EventBus.dialogue_ended.emit(BRAM)
	var back: float = await _until(n, "Work_Hammer", 12.0)
	assert_gt(back, 0.0, "back to work once the talk is over, not talking on to nobody")
