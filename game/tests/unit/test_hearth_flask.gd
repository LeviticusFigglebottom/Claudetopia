extends TestCase
## The Hearth Flask (DESIGN §5.5: resting at a Hearthstone "refills flask charges"). Nothing in the
## game healed in a fight but a loaf and a saying half the Callings do not know; this is the
## flask, end to end on the real player scene: carried from the first moment, drunk from the belt
## as a committed swallow, spilled by a stagger, filled by a rest and by coming back from death,
## kept by the save, shown on the belt, and never sold.

const FLASK := Flask.ITEM
const FOE := "core:enemy/roadside_bandit"

var root: Node3D
var player: Player
var bag: Inventory
var doll: Equipment


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	root = Node3D.new()
	root.name = "FlaskBench"
	_tree().root.add_child(root)
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(shape)
	root.add_child(ground)
	# A new character: the flask comes with the Naming, whatever the Calling.
	GameState.set_flag("new_game", true)
	GameState.set_flag("player_calling", "core:calling/lantern_clerk")
	player = (load("res://actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(player)
	GameState.set_flag("new_game", false)
	player.global_position = Vector3(0.0, 0.02, 0.0)
	bag = player.get_node("Inventory") as Inventory
	doll = player.get_node("Equipment") as Equipment


func after_each() -> void:
	if is_instance_valid(root):
		root.free()
	root = null
	player = null
	GameState.set_flag("player_calling", "")


func _frames(n: int) -> void:
	for i in maxi(n, 1):
		await _tree().physics_frame


func _belt_slot() -> int:
	for i in Equipment.QUICK_SLOTS.size():
		if doll.quick_item(Equipment.QUICK_SLOTS[i]) == FLASK:
			return i
	return -1


## Drinks through the real belt key and waits the swallow out. Returns health gained.
func _drink_from_the_belt() -> float:
	var before := player.health
	var slot := _belt_slot()
	Input.action_press("quick_%d" % (slot + 1))
	await _frames(2)
	Input.action_release("quick_%d" % (slot + 1))
	for i in 90:
		await _tree().physics_frame
		if player.state != Player.State.DRINK:
			break
	return player.health - before


func test_a_new_character_carries_a_full_flask_on_the_belt() -> void:
	var flask := Flask.find(bag)
	assert_true(flask != null, "the Naming hands over a flask")
	assert_eq(Flask.charges(flask), 3, "full: three swallows")
	assert_gt(_belt_slot(), -1, "and it is on the belt")
	assert_eq(doll.quick_count(Equipment.QUICK_SLOTS[_belt_slot()]), 3, "the belt counts swallows")
	# Only one, however many times it is asked for.
	Flask.ensure(bag, doll)
	var n := 0
	for s in bag.stacks():
		if s.id == FLASK:
			n += s.count
	assert_eq(n, 1)


func test_a_swallow_from_the_belt_heals_two_fifths_and_is_committed() -> void:
	await _frames(3)
	player.health = player.max_health * 0.3
	var started := Actor.now()
	var healed := await _drink_from_the_belt()
	var took := Actor.now() - started
	print("FLASK | a swallow | healed %.1f of %.1f max | %.2f s | charges left %d" % [healed, player.max_health, took, Flask.charges(Flask.find(bag))])
	assert_near(healed, player.max_health * 0.4, 0.5, "two fifths of the greatest health")
	assert_eq(Flask.charges(Flask.find(bag)), 2, "one swallow spent")
	assert_true(took >= 0.95, "the drink holds the drinker about a second (%.2f s)" % took)
	assert_eq(player.state, Player.State.FREE, "and lets go")


func test_a_stagger_before_the_swallow_spills_it() -> void:
	await _frames(3)
	player.health = player.max_health * 0.3
	var before := player.health
	assert_true(player.drink_flask(), "a drink starts")
	assert_true(player.is_busy(), "a drink is a committed action")
	await _frames(10)
	player.stagger(0.8)
	await _frames(60)
	assert_near(player.health, before, 0.01, "staggered before the warmth landed: nothing healed")
	assert_eq(Flask.charges(Flask.find(bag)), 2, "and the swallow is gone")


func test_a_dry_flask_gives_nothing_and_says_so() -> void:
	await _frames(3)
	var flask := Flask.find(bag)
	flask.data["charges"] = 0
	var said := {"text": ""}
	var listen := func(text: String, _kind: String) -> void: said["text"] = text
	EventBus.notify.connect(listen)
	assert_false(player.drink_flask(), "no swallow in a dry flask")
	EventBus.notify.disconnect(listen)
	assert_true(str(said["text"]).contains("dry"), "the player is told why")
	assert_eq(player.state, Player.State.FREE)


func test_resting_at_a_hearthstone_and_coming_back_fill_it() -> void:
	await _frames(3)
	var flask := Flask.find(bag)
	flask.data["charges"] = 0
	Hearth.rest_at("flask_bench", player.global_position, 0.0, false)
	assert_eq(Flask.charges(flask), 3, "a rest fills the flask")
	flask.data["charges"] = 1
	player.respawn(player.global_position, 0.0)
	assert_eq(Flask.charges(flask), 3, "and so does coming back from death")


func test_the_charges_are_kept_by_the_save() -> void:
	var flask := Flask.find(bag)
	flask.data["charges"] = 1
	var bag_save := bag.to_save()
	var doll_save := doll.to_save()
	var other_root := Node.new()
	_tree().root.add_child(other_root)
	var other_bag := Inventory.new()
	other_root.add_child(other_bag)
	other_bag.from_save(JSON.parse_string(JSON.stringify(bag_save)))
	assert_eq(Flask.charges(Flask.find(other_bag)), 1, "one swallow left, after a save and a load")
	var other_doll := Equipment.new()
	other_root.add_child(other_doll)
	other_doll.set_inventory(other_bag)
	other_doll.from_save(JSON.parse_string(JSON.stringify(doll_save)))
	assert_eq(other_doll.quick_count(Equipment.QUICK_SLOTS[_belt_slot()]), 1, "and the belt still counts it")
	other_root.free()


func test_a_save_from_before_the_flask_is_given_one() -> void:
	var flask := Flask.find(bag)
	bag.remove_stack(flask, flask.count)
	assert_true(Flask.find(bag) == null, "an old character with no flask")
	EventBus.game_loaded.emit("test")
	assert_true(Flask.find(bag) != null, "is given one when its save is loaded")
	var bound := 0
	for slot in Equipment.QUICK_SLOTS:
		if doll.quick_item(slot) == FLASK:
			bound += 1
	assert_eq(bound, 1, "on the belt once")


func test_the_flask_is_not_sold_or_eaten_from_the_bag() -> void:
	var shop := Merchant.new()
	shop.npc_id = "core:npc/_flask_shop"
	shop.stock_table = "core:table/stock_general"
	shop.place_id = "core:place/merrowby"
	shop.buys = ["all"]
	shop.restock_on_clock = false
	root.add_child(shop)
	assert_false(shop.will_buy(FLASK), "a merchant does not buy a keepsake")
	assert_true(shop.will_buy("core:item/bread"), "and still buys bread")
	assert_false(bag.use(Flask.find(bag)), "using it from the bag does not eat it")
	assert_true(Flask.find(bag) != null, "the flask is still there")


func test_the_belt_shows_the_swallows_left() -> void:
	var hud := (load("res://ui/hud/hud.tscn") as PackedScene).instantiate()
	root.add_child(hud)
	await _frames(2)
	hud.call("_connect_world")
	var flask := Flask.find(bag)
	Flask.take_swallow(bag, flask)
	await _frames(1)
	var panel: Control = (hud.get("_quick_slots") as Array)[_belt_slot()]
	var count := panel.find_child("Count", true, false) as Label
	assert_eq(count.text, "2/3", "the slot reads swallows against a full flask")
	flask.data["charges"] = 0
	bag.notify_changed(flask)
	await _frames(1)
	assert_eq(count.text, "0/3")
	assert_true(panel.modulate.a < 0.5, "and dims when it is dry")
