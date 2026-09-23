extends TestCase
## Four places the game asked a question and nobody was ever made to answer it.
##
## `LootDrops.context_provider`, `Player.quick_slot_handler` and `Player.ammo_provider` were
## Callables that nothing assigned, and `Enchanting.enchant_blocker` was a reason nothing asked
## for. Each is wired to what owns the answer -- the world's services, the belt on the paper doll,
## the arrows in the bag, the Name-table's screen -- and each test here does the thing a player
## does and then asks the system, not the hook, whether it happened.

const POTION := "core:item/potion_restore_health"
const BOW := "core:item/hunting_bow"
const IRON_ARROW := "core:item/iron_arrow"
const BANDIT := "core:enemy/roadside_bandit"
const LOCKPICK := "core:item/lockpick"
const SWORD := "core:item/iron_sword"
const MOTE := "core:item/ember_mote"
const EMBER_BURST := "core:effect/ember_burst"
const STATION := preload("res://ui/crafting/station_screen.tscn")

var root: Node3D


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	GameState.set_flag("new_game", false)
	root = Node3D.new()
	root.name = "HookBench"
	_tree().root.add_child(root)


func after_each() -> void:
	for a in ["attack_light", "quick_1"]:
		Input.action_release(a)
	if is_instance_valid(root):
		root.free()
	root = null


func _frames(n: int) -> void:
	for i in maxi(n, 1):
		await _tree().physics_frame


func _player() -> Player:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(shape)
	root.add_child(floor_body)
	var p := (load("res://actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(p)
	p.global_position = Vector3(0.0, 0.02, 0.0)
	return p


# --- the loot context ------------------------------------------------------------------------------

## The world's services hand LootDrops a context, and what a kill can drop follows it: a bandit
## has lockpicks in its pockets from the second level on, and never had them before, because every
## kill rolled as a level-1 character.
func test_a_kill_rolls_against_the_characters_level() -> void:
	var prog := Progression.new()
	root.add_child(prog)
	assert_eq(_tree().get_nodes_in_group("progression").size(), 1, "one character sheet in the tree")
	var services := GameServices.new()
	services.installs_on_ready = false
	root.add_child(services)
	services._install_loot_drops()
	var drops := _tree().get_first_node_in_group("loot_drops") as LootDrops
	assert_true(drops != null, "the world's services put a LootDrops in the world")
	if drops == null:
		return
	assert_true(drops.context_provider.is_valid(), "and hand it something to ask about the kill")
	assert_eq(drops.context_provider.get_object(), services, "the world's services answer it")
	var bandit := ContentDB.get_or_empty(BANDIT)
	var picks := {1: 0, 5: 0}
	for lvl in [1, 5]:
		prog.leveling.level = lvl
		assert_eq(int(drops.context().get("level", -1)), lvl, "the context carries the character's level")
		drops.rng.seed = 4242
		for i in 400:
			for r in drops.drops_for(bandit, drops.context()):
				if str(r.get("item", "")) == LOCKPICK:
					picks[lvl] = int(picks[lvl]) + 1
	assert_eq(int(picks[1]), 0, "a level-1 character never finds a lockpick on a bandit")
	assert_gt(int(picks[5]), 0, "a level-5 one does")
	# And the real event: a bandit killed in the world drops through the same context.
	var got := {"results": []}
	var on_drop := func(results: Array, _pos: Vector3, _id: String) -> void: got["results"] = results
	drops.dropped.connect(on_drop)
	var victim := Node3D.new()
	root.add_child(victim)
	EventBus.entity_killed.emit(victim, null, BANDIT)
	for i in 4:
		await _tree().physics_frame
	drops.dropped.disconnect(on_drop)
	assert_false((got["results"] as Array).is_empty(), "a bandit killed in the world drops something")
	for n in _tree().current_scene.get_children():
		if n is WorldItem:
			n.queue_free()


# --- the belt --------------------------------------------------------------------------------------

## A potion on the belt is drunk by its key: the doll owns the belt and answers the key.
func test_a_quick_key_drinks_what_is_on_the_belt() -> void:
	var p := _player()
	await _frames(2)
	var bag := p.get_node("Inventory") as Inventory
	var doll := p.get_node("Equipment") as Equipment
	assert_true(p.quick_slot_handler.is_valid(), "the quick keys are wired to something")
	assert_eq(p.quick_slot_handler.get_object(), doll, "and it is the paper doll that owns the belt")
	bag.add(POTION, 2)
	assert_true(p.set_quick_slot(0, POTION))
	p.health = p.max_health * 0.3
	var hp0 := p.health
	Input.action_press("quick_1")
	await _frames(2)
	Input.action_release("quick_1")
	await _frames(2)
	assert_eq(bag.count(POTION), 1, "pressing the key used one potion")
	assert_gt(p.health, hp0, "and it did what a potion does")
	var said: Array[String] = []
	var on_notify := func(text: String, _k: String) -> void: said.append(text)
	EventBus.notify.connect(on_notify)
	bag.remove(POTION, 1)
	p.use_quick_slot(0)
	EventBus.notify.disconnect(on_notify)
	assert_true(said.has("None left."), "an empty slot says so: %s" % str(said))


# --- the quiver ------------------------------------------------------------------------------------

## A bow looses what is in the bag, one arrow a shot, and will not draw on an empty quiver.
func test_a_bow_shoots_the_arrows_in_the_bag() -> void:
	var p := _player()
	await _frames(2)
	var bag := p.get_node("Inventory") as Inventory
	assert_true(p.ammo_provider.is_valid(), "the bow is wired to something")
	assert_eq(p.ammo_provider.get_object(), bag, "and it is the bag")
	p.equip_weapon(BOW)
	bag.add(IRON_ARROW, 3)
	await _frames(2)
	Input.action_press("attack_light")
	await _frames(int(1.2 * 60.0))
	assert_eq(p.state, Player.State.BOW, "holding the attack draws the bow")
	Input.action_release("attack_light")
	await _frames(3)
	assert_eq(bag.count(IRON_ARROW), 2, "one arrow left the bag")
	bag.remove(IRON_ARROW, 2)
	await _frames(40)
	var said: Array[String] = []
	var on_notify := func(text: String, _k: String) -> void: said.append(text)
	EventBus.notify.connect(on_notify)
	Input.action_press("attack_light")
	await _frames(4)
	Input.action_release("attack_light")
	EventBus.notify.disconnect(on_notify)
	assert_ne(p.state, Player.State.BOW, "an empty quiver is not drawn")
	assert_true(said.has("No arrows."), "and says so: %s" % str(said))
	for n in _tree().current_scene.get_children():
		if n is Projectile:
			n.queue_free()


# --- the Name-table ---------------------------------------------------------------------------------

func _words(screen: Node) -> String:
	var out := ""
	for l in screen.find_children("*", "Label", true, false):
		out += (l as Label).text + "\n"
	return out


func _button(screen: Node, text: String) -> Button:
	for b in screen.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b
	return null


## The table says why it will not take a note before you press it, and takes it once it can.
func test_the_name_table_says_why_it_refuses() -> void:
	var holder := Node.new()
	root.add_child(holder)
	var bag := Inventory.new()
	var crafting := Crafting.new()
	holder.add_child(bag)
	holder.add_child(crafting)
	crafting.learn_enchantment(EMBER_BURST)
	bag.add(SWORD, 1)
	bag.add(MOTE, 1)
	var screen: Control = STATION.instantiate()
	screen.call("setup", {"station": "name_table", "crafting": crafting, "bag": bag})
	root.add_child(screen)
	await _frames(1)
	var note := _button(screen, "Ember Burst")
	assert_true(note != null, "the learned note is on the table's list")
	if note == null:
		return
	note.pressed.emit()
	await _frames(1)
	var target := _button(screen, "Iron Sword")
	assert_true(target != null, "the sword in the bag is something to write on")
	if target == null:
		return
	target.pressed.emit()
	await _frames(1)
	var write := _button(screen, "Write it in")
	assert_true(write != null and write.disabled, "one mote cannot pay for a two-mote note, and the button knows it")
	assert_true(_words(screen).contains("you carry 1"), "the table says why: %s" % _words(screen))
	bag.add(MOTE, 3)
	target.pressed.emit()              # the screen redraws on a choice, as it does in play
	await _frames(1)
	write = _button(screen, "Write it in")
	assert_false(_words(screen).contains("you carry"), "with the motes in the bag there is nothing to explain")
	assert_true(write != null and not write.disabled, "and the button can be pressed")
	if write != null:
		write.pressed.emit()
	await _frames(1)
	var sword := bag.find_first(SWORD)
	assert_true(sword != null and sword.is_enchanted(), "pressing it wrote the note into the sword")
	screen.queue_free()
