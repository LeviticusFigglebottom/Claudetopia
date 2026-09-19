extends TestCase
## Doing a wrong thing and the law hearing about it. The crime system could always price a
## theft and find its witnesses; what it never got told about was a chest being emptied or a
## villager being killed, because nothing in the world called `Bounty.commit()` for either.

const OWNER := "core:npc/ellard_wynstead"
const HERE := Vector3(900.0, 56.0, 2350.0)

var reports: CrimeReports
var bounty: Bounty
var player: Node3D
var seen: Array[Dictionary] = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	bounty = Bounty.ensure()
	bounty.clear_all()
	reports = CrimeReports.ensure()
	player = Node3D.new()
	player.name = "StandInPlayer"
	player.add_to_group("player")
	_tree().root.add_child(player)
	player.global_position = HERE
	seen = []
	EventBus.crime_committed.connect(_note)


func after_each() -> void:
	if EventBus.crime_committed.is_connected(_note):
		EventBus.crime_committed.disconnect(_note)
	if is_instance_valid(player):
		player.queue_free()
	if is_instance_valid(bounty):
		bounty.clear_all()


func _note(crime: Dictionary) -> void:
	seen.append(crime)


## A body with a name in the roster. `Npc` is a CharacterBody3D, and the script will not take
## on a bare Node3D, which is how the first run of this test killed somebody with no name.
func _villager(npc_id: String) -> Node3D:
	var victim := CharacterBody3D.new()
	victim.set_script(load("res://actors/npc/npc.gd"))
	victim.set("npc_id", npc_id)
	_tree().root.add_child(victim)
	victim.global_position = HERE
	return victim


func _kinds() -> Array[String]:
	var out: Array[String] = []
	for c in seen:
		out.append(str(c.get("kind", "")))
	return out


# --- theft ---------------------------------------------------------------------------------

func test_taking_somebody_elses_thing_is_reported() -> void:
	CrimeReports.theft(player, HERE, 120, OWNER, "", "core:item/test")
	assert_eq(_kinds(), ["theft"] as Array[String], "a theft went unreported")
	assert_eq(int(seen[0].get("value", 0)), 120, "the value of what was taken was lost")
	assert_eq(str(seen[0].get("victim", "")), OWNER, "nobody was robbed in particular")


func test_taking_something_nobody_owns_is_not_a_crime() -> void:
	CrimeReports.theft(player, HERE, 500, "", "", "core:item/test")
	assert_true(seen.is_empty(), "picking up an unowned thing was reported as theft")


func test_taking_your_own_thing_is_not_a_crime() -> void:
	CrimeReports.theft(player, HERE, 500, Ownership.PLAYER, "", "core:item/test")
	assert_true(seen.is_empty(), "the player was booked for taking their own property")


func test_somebody_who_is_not_the_player_is_not_reported() -> void:
	var other := Node3D.new()
	_tree().root.add_child(other)
	CrimeReports.theft(other, HERE, 500, OWNER, "", "core:item/test")
	assert_true(seen.is_empty(), "an NPC taking something raised a bounty on the player")
	other.queue_free()


func test_a_world_item_knows_whose_it_is() -> void:
	var item := WorldItem.new()
	item.item_id = "core:item/bread"
	item.count = 1
	item.owner_npc = OWNER
	_tree().root.add_child(item)
	item.global_position = HERE
	var inv := Inventory.new()
	player.add_child(inv)
	await _tree().process_frame
	item.interact(player)
	await _tree().process_frame
	assert_eq(_kinds(), ["theft"] as Array[String], "taking an owned loaf was not a theft")
	inv.queue_free()


func test_emptying_an_owned_chest_is_reported_at_what_was_in_it() -> void:
	var chest := WorldContainer.new()
	chest.container_id = "test:container/strongbox"
	chest.owner_npc = OWNER
	_tree().root.add_child(chest)
	chest.global_position = HERE
	chest.inventory.add_marks(300)
	var inv := Inventory.new()
	player.add_child(inv)
	await _tree().process_frame
	chest.take_all(player)
	await _tree().process_frame
	assert_eq(_kinds(), ["theft"] as Array[String], "a strongbox was emptied without a word")
	assert_gt(int(seen[0].get("value", 0)), 0, "the theft was priced at nothing")
	inv.queue_free()
	chest.queue_free()


func test_an_unowned_chest_in_a_cave_is_nobodys_loss() -> void:
	var chest := WorldContainer.new()
	chest.container_id = "test:container/cave_crate"
	_tree().root.add_child(chest)
	chest.global_position = HERE
	chest.inventory.add_marks(300)
	var inv := Inventory.new()
	player.add_child(inv)
	await _tree().process_frame
	chest.take_all(player)
	await _tree().process_frame
	assert_true(seen.is_empty(), "looting a cave was reported as theft")
	inv.queue_free()
	chest.queue_free()


# --- murder --------------------------------------------------------------------------------

func test_killing_a_villager_is_a_murder() -> void:
	var victim := _villager(OWNER)
	EventBus.entity_killed.emit(victim, player, OWNER)
	await _tree().process_frame
	assert_eq(_kinds(), ["murder"] as Array[String], "a villager was killed and nobody minded")
	assert_eq(str(seen[0].get("victim", "")), OWNER)
	victim.queue_free()


func test_killing_a_wolf_is_a_hunt() -> void:
	var wolf := Node3D.new()
	_tree().root.add_child(wolf)
	wolf.global_position = HERE
	EventBus.entity_killed.emit(wolf, player, "core:enemy/thornhound")
	await _tree().process_frame
	assert_true(seen.is_empty(), "killing an animal raised a murder charge")
	wolf.queue_free()


func test_a_villager_killed_by_something_else_is_not_your_crime() -> void:
	var victim := _villager(OWNER)
	var drake := Node3D.new()
	_tree().root.add_child(drake)
	EventBus.entity_killed.emit(victim, drake, OWNER)
	await _tree().process_frame
	assert_true(seen.is_empty(), "a drake's kill was booked against the player")
	victim.queue_free()
	drake.queue_free()


# --- it is installed -------------------------------------------------------------------------

func test_the_world_installs_the_reporter() -> void:
	assert_true(GameServices.ORDER.any(func(pair: Array) -> bool:
			return str(pair[0]) == "CrimeReports"),
			"nothing installs the reporter, so nothing will tell the law")
