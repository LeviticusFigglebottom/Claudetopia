extends TestCase

const MERROWBY := "core:place/merrowby"

var _nodes: Array[Node] = []


func before_each() -> void:
	Peers.overrides.clear()
	# Most of this file is about the board's own delivery machinery — the parcel, where it is
	# addressed, what it pays — so the radiant generator is kept out of the way. A real board
	# in the game asks the social façade first and lists bounties and hunts; the two tests at
	# the end of the board section are the ones that check that.
	Peers.overrides["social"] = null
	GameState.reset_for_new_game(1)
	WorldClock.set_time(9.0, 6)


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	_nodes.clear()
	Peers.overrides.clear()


func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


func _worker(marks := 0) -> Node:
	var s := GDScript.new()
	s.source_code = "extends Node\nvar marks := 0\nvar bag := {}\nfunc add_marks(n: int) -> void:\n\tmarks += n\nfunc remove_marks(n: int) -> int:\n\tvar t: int = mini(n, marks)\n\tmarks -= t\n\treturn t\nfunc add(id: String, n: int) -> void:\n\tbag[id] = bag.get(id, 0) + n\nfunc remove(id: String, n: int) -> int:\n\tvar have: int = bag.get(id, 0)\n\tvar t: int = mini(have, n)\n\tbag[id] = have - t\n\treturn t\nfunc count(id: String) -> int:\n\treturn bag.get(id, 0)\n"
	s.reload()
	var n := Node.new()
	n.set_script(s)
	n.set("marks", marks)
	_root().add_child(n)
	_nodes.append(n)
	return n


# --- station work ----------------------------------------------------------------------------

func test_station_table_is_complete() -> void:
	assert_eq(Jobs.station_kinds(), ["brew", "chop", "dig", "fish", "smith"])
	for kind in Jobs.station_kinds():
		assert_gt(Jobs.station_seconds(kind), 0.0)
		assert_gt(Jobs.station_xp(kind), 0.0)
		assert_false(Jobs.station_skill(kind).is_empty())
		assert_true(Jobs.station_clip(kind).begins_with("Work_"), "%s uses a Work clip" % kind)
		var item := str(Jobs.STATIONS[kind].get("yield", ""))
		assert_true(item.is_empty() or ContentDB.has(item), "%s yields a real item" % kind)


func test_station_pay_scales_with_skill() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var unskilled := Jobs.station_pay("chop", 0, rng)
	rng.seed = 7
	var skilled := Jobs.station_pay("chop", 100, rng)
	assert_gt(skilled, unskilled, "a practised hand earns half again")
	assert_eq(skilled, roundi(float(unskilled) * 1.5))
	rng.seed = 7
	assert_eq(Jobs.station_pay("bad_kind", 0, rng), 0)
	for i in 30:
		var p := Jobs.station_pay("chop", 0, rng)
		assert_true(p >= 4 and p <= 8, "chopping pays 4-8: got %d" % p)


func test_station_shift_pays_marks_xp_and_yield() -> void:
	var station := JobStation.new()
	station.kind = "chop"
	_root().add_child(station)
	_nodes.append(station)
	var worker := _worker()
	assert_true(station.is_ready())
	assert_eq(station.prompt_text(), "Chop wood")
	var starts: Array = []
	station.started.connect(func(k: String, s: float, c: String) -> void: starts.append([k, s, c]))
	var xp: Array = []
	var xcb := func(s: String, x: float) -> void: xp.append([s, x])
	EventBus.skill_used.connect(xcb)
	var jobs_done: Array = []
	var jcb := func(id: String, pay: int) -> void: jobs_done.append([id, pay])
	EventBus.job_completed.connect(jcb)
	assert_true(station.interact(worker))
	assert_true(station.working)
	assert_eq(starts.size(), 1)
	assert_eq(starts[0][0], "chop")
	assert_eq(starts[0][2], "Work_Chop")
	assert_false(station.interact(worker), "one pair of hands at a time")
	var pay := station.finish(worker)
	assert_gt(pay, 0)
	assert_eq(int(worker.get("marks")), pay)
	assert_eq(worker.call("count", "core:item/oak_plank"), 1, "and a plank of what you cut")
	assert_eq(xp.size(), 1)
	assert_eq(xp[0][0], "athletics")
	assert_eq(jobs_done.size(), 1)
	assert_eq(jobs_done[0][0], "station:chop")
	assert_eq(GameState.count("jobs_done"), 1)
	assert_eq(GameState.count("station_shifts_chop"), 1)
	assert_eq(station.finish(worker), 0, "paid once")
	EventBus.skill_used.disconnect(xcb)
	EventBus.job_completed.disconnect(jcb)


func test_station_cooldown_and_ownership() -> void:
	var station := JobStation.new()
	station.kind = "smith"
	_root().add_child(station)
	_nodes.append(station)
	var worker := _worker()
	station.interact(worker)
	station.finish(worker)
	assert_false(station.is_ready(), "the day's wood is cut")
	assert_eq(station.prompt_text(), "Work the bellows (rest first)")
	assert_false(station.interact(worker))
	assert_near(station.hours_remaining(), 4.0, 0.01)
	WorldClock.set_time(14.0, 6)
	assert_true(station.is_ready(), "five hours later there is more to do")
	var theirs := JobStation.new()
	theirs.kind = "brew"
	theirs.owner_npc = "core:npc/someone_else"
	_root().add_child(theirs)
	_nodes.append(theirs)
	assert_true(Ownership.is_owned_by_other(theirs))
	assert_false(theirs.interact(worker), "you do not brew another's mash")


# --- board work --------------------------------------------------------------------------------

func test_delivery_offers_are_local_and_deterministic() -> void:
	var a := Jobs.delivery_offers(MERROWBY, 3, 6)
	var b := Jobs.delivery_offers(MERROWBY, 3, 6)
	assert_eq(a.size(), 2, "Hearthvale has two other settlements to walk to")
	assert_eq(str(a[0]["id"]), str(b[0]["id"]), "the board says the same thing all day")
	var next_day := Jobs.delivery_offers(MERROWBY, 3, 7)
	assert_ne(str(a[0]["id"]), str(next_day[0]["id"]), "and something else tomorrow")
	var destinations := {}
	for job in a:
		assert_eq(str(job["from"]), MERROWBY)
		assert_ne(str(job["to"]), MERROWBY)
		assert_eq(WorldProbe.region_of_place(str(job["to"])), "core:region/hearthvale", "deliveries stay in the region")
		assert_false(destinations.has(job["to"]), "no two notices for the same town")
		destinations[job["to"]] = true
		assert_gt(int(job["pay"]), 0)
		assert_eq(str(job["item"]), Jobs.DELIVERY_PARCEL)
		assert_eq(str(job["kind"]), "delivery")
	assert_empty(Jobs.delivery_offers("core:place/nowhere", 3, 1))


func test_delivery_pay_follows_distance() -> void:
	assert_eq(Jobs.delivery_pay(0.0), Jobs.DELIVERY_MIN_PAY, "a short walk still pays something")
	assert_eq(Jobs.delivery_pay(3000.0), 42)
	assert_gt(Jobs.delivery_pay(5000.0), Jobs.delivery_pay(2000.0))


func test_board_prefers_the_quest_system_when_present() -> void:
	var s := GDScript.new()
	s.source_code = "extends Node\nvar asked := []\nfunc generate(region: String, count: int) -> Array:\n\tasked.append([region, count])\n\tvar out: Array = []\n\tfor i in count:\n\t\tout.append({\"id\": \"core:quest/radiant_%d\" % i, \"title\": \"Hunt %d\" % i, \"pay\": 50 + i})\n\treturn out\n"
	s.reload()
	var quests := Node.new()
	quests.set_script(s)
	_nodes.append(quests)
	Peers.overrides["quests"] = quests
	var offers := Jobs.board_offers(MERROWBY, 3, 6)
	assert_eq(offers.size(), 3)
	assert_eq(str(offers[0]["title"]), "Hunt 0")
	assert_eq(int(offers[0]["pay"]), 50)
	assert_eq(str(offers[0]["kind"]), "quest")
	assert_eq(quests.get("asked")[0][0], "core:region/hearthvale", "the board asks for its own region")
	Peers.overrides.erase("quests")
	var fallback := Jobs.board_offers(MERROWBY, 3, 6)
	assert_eq(str(fallback[0]["kind"]), "delivery", "no quest system: the board still has work")


## The path a board in the game actually takes. `QuestLog` has no `generate()` — it holds the
## RadiantGenerator, and `Social.board_jobs()` drives it — so before this was wired every
## board in Wickmere fell through to the delivery fallback and DESIGN §5.10's radiant layer
## never reached a notice post.
func test_the_board_asks_the_social_facade_for_its_radiant_work() -> void:
	Peers.overrides.erase("social")
	var offers := Jobs.board_offers(MERROWBY, 3)
	assert_gt(offers.size(), 0, "the façade offered the board nothing")
	var kinds: Array[String] = []
	for job in offers:
		kinds.append(str(job["kind"]))
		assert_false(str(job["id"]).is_empty(), "a notice with no quest behind it")
		assert_gt(int(job["pay"]), 0,
			"%s is posted at nought marks: its pay is in rewards.marks" % str(job["id"]))
	assert_false(kinds.has("delivery"),
		"the board fell back to its own deliveries with a generator right there: %s" % str(kinds))


## `QuestLog` still has no `generate()`, which is the whole reason the façade is asked. If it
## grows one, the duck-typed hook in `board_offers` picks it up and this can go.
func test_the_quest_log_is_not_the_thing_that_generates() -> void:
	assert_false(Social.quests.has_method("generate"),
		"QuestLog has a generate() now: board_offers can ask the participant directly")
	assert_true(Social.has_method("board_jobs") and Social.has_method("take_quest"),
		"the façade's board pair is what the economy stream calls")


func test_board_take_and_deliver() -> void:
	var board: JobBoard = load("res://systems/economy/job_board.tscn").instantiate()
	board.place_id = MERROWBY
	_root().add_child(board)
	_nodes.append(board)
	var carrier := _worker()
	var listed: Array = []
	board.jobs_listed.connect(func(j: Array) -> void: listed.append(j))
	var offers := board.interact(carrier)
	assert_gt(offers.size(), 0)
	assert_eq(listed.size(), 1)
	assert_true(board.prompt_text().contains("notices"))
	var job := board.take(0, carrier)
	assert_false(job.is_empty())
	assert_eq(carrier.call("count", Jobs.DELIVERY_PARCEL), 1, "the parcel is in your pack")
	assert_eq(board.taken.size(), 1)
	assert_true(board.take(99, carrier).is_empty())
	assert_eq(board.deliver(job, carrier, MERROWBY), 0, "you have not gone anywhere")
	var completed: Array = []
	var cb := func(id: String, pay: int) -> void: completed.append([id, pay])
	EventBus.job_completed.connect(cb)
	var paid := board.deliver(job, carrier, str(job["to"]))
	assert_eq(paid, int(job["pay"]))
	assert_eq(int(carrier.get("marks")), paid)
	assert_eq(carrier.call("count", Jobs.DELIVERY_PARCEL), 0, "handed over")
	assert_empty(board.taken)
	assert_eq(completed.size(), 1)
	assert_eq(GameState.count("jobs_done"), 1)
	EventBus.job_completed.disconnect(cb)
	close_screen("job_board", "reading the board opens its screen")


func test_a_parcel_must_actually_be_carried_somewhere() -> void:
	var board: JobBoard = load("res://systems/economy/job_board.tscn").instantiate()
	board.place_id = MERROWBY
	_root().add_child(board)
	_nodes.append(board)
	var carrier := CharacterBody3D.new()
	var s := GDScript.new()
	s.source_code = "extends CharacterBody3D\nvar marks := 0\nvar bag := {}\nfunc add_marks(n: int) -> void:\n\tmarks += n\nfunc add(id: String, n: int) -> void:\n\tbag[id] = bag.get(id, 0) + n\nfunc remove(id: String, n: int) -> int:\n\tvar have: int = bag.get(id, 0)\n\tvar t: int = mini(have, n)\n\tbag[id] = have - t\n\treturn t\nfunc count(id: String) -> int:\n\treturn bag.get(id, 0)\n"
	s.reload()
	carrier.set_script(s)
	_root().add_child(carrier)
	_nodes.append(carrier)
	carrier.global_position = WorldProbe.place_position(MERROWBY)
	var job := board.take(0, carrier)
	assert_false(job.is_empty())
	assert_eq(board.deliver(job, carrier), 0, "handing it back across the same counter pays nothing")
	assert_eq(int(carrier.get("marks")), 0)
	assert_eq(carrier.call("count", Jobs.DELIVERY_PARCEL), 1, "and you still have it")
	assert_true(board.take(0, carrier).is_empty(), "nor can you take the same notice twice")
	carrier.global_position = WorldProbe.place_position(str(job["to"]))
	var paid := board.deliver(job, carrier)
	assert_eq(paid, int(job["pay"]), "walk it there and you are paid")
	assert_eq(int(carrier.get("marks")), paid)
	assert_eq(carrier.call("count", Jobs.DELIVERY_PARCEL), 0)


func test_board_offers_are_cached_per_day() -> void:
	var board: JobBoard = load("res://systems/economy/job_board.tscn").instantiate()
	board.place_id = MERROWBY
	_root().add_child(board)
	_nodes.append(board)
	var first := board.offers()
	assert_eq(board.offers(), first, "the same notices all day")
	WorldClock.set_time(9.0, 7)
	var tomorrow := board.offers()
	assert_ne(str(tomorrow[0]["id"]), str(first[0]["id"]), "a new day, new notices")
