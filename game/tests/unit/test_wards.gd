extends TestCase
## Ground a kind of foe will not cross (world/pois/wards.gd): the Singing Yew's, which the
## hedge-wights from the barrow will not pass. The dressing's own ward is tested with the POIs
## (test_poi_encounters.gd); this is the rule itself, and what a foe does about it.

var holder: Node


func before_each() -> void:
	Wards.clear()
	holder = Node.new()


func after_each() -> void:
	Wards.clear()
	if is_instance_valid(holder):
		holder.free()


func test_a_ward_keeps_off_only_what_it_names_and_only_inside_it() -> void:
	Wards.add(holder, Vector3(100.0, 5.0, 100.0), 8.0, ["undead"])
	assert_false(Wards.keeping(["humanoid", "undead"], Vector3(104.0, 0.0, 100.0)).is_empty(), "a wight inside")
	assert_true(Wards.keeping(["bandit"], Vector3(104.0, 0.0, 100.0)).is_empty(), "a bandit is not kept off")
	assert_true(Wards.keeping(["undead"], Vector3(110.0, 0.0, 100.0)).is_empty(), "outside it, nothing")
	assert_true(Wards.keeping([], Vector3(100.0, 0.0, 100.0)).is_empty())


func test_a_foe_may_step_out_of_a_ward_and_not_into_it() -> void:
	Wards.add(holder, Vector3.ZERO, 8.0, ["undead"])
	var tags := ["undead"]
	assert_true(Wards.bars(tags, Vector3(9.0, 0.0, 0.0), Vector3(7.5, 0.0, 0.0)), "not across the edge")
	assert_true(Wards.bars(tags, Vector3(6.0, 0.0, 0.0), Vector3(5.0, 0.0, 0.0)), "not deeper in")
	assert_false(Wards.bars(tags, Vector3(5.0, 0.0, 0.0), Vector3(6.0, 0.0, 0.0)), "but out, yes")
	assert_false(Wards.bars(tags, Vector3(12.0, 0.0, 0.0), Vector3(11.0, 0.0, 0.0)), "and outside it, anywhere")
	assert_false(Wards.bars(["bandit"], Vector3(9.0, 0.0, 0.0), Vector3(7.5, 0.0, 0.0)))


func test_a_ward_goes_with_what_put_it_down() -> void:
	Wards.add(holder, Vector3.ZERO, 8.0, ["undead"])
	assert_eq(Wards.count(), 1)
	holder.free()
	assert_eq(Wards.count(), 0)
	assert_true(Wards.keeping(["undead"], Vector3.ZERO).is_empty())


func test_a_foe_whose_quarry_stands_on_warded_ground_turns_for_home() -> void:
	var p := {"leash": 30.0, "patience": 3.0}
	var fighting := {"detection": 1.0, "can_see": true, "alerted": true, "target_alive": true,
			"distance_to_post": 12.0, "distance_to_target": 3.0, "time_in_state": 1.0, "time_unseen": 0.0}
	assert_eq(Brain.decide(Brain.COMBAT, p, fighting), Brain.COMBAT, "unwarded, it fights")
	var warded := fighting.duplicate()
	warded["warded"] = true
	assert_eq(Brain.decide(Brain.COMBAT, p, warded), Brain.RETURN, "it turns away from the yew")
	warded["distance_to_post"] = 1.0
	assert_eq(Brain.decide(Brain.RETURN, p, warded), Brain.IDLE, "and waits at home while you stand there")
	assert_eq(Brain.decide(Brain.IDLE, p, fighting), Brain.COMBAT, "and comes again when you step off it")
