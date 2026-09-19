extends Node
## Believable state for the UI review harness: the real Inventory, Equipment, Progression
## and Crafting nodes loaded with real content, plus stand-ins for the streams that are
## still being written (player, quest log, dialogue runner, merchant).

const START_PLACES := [
	"core:place/merrowby", "core:place/tamwick", "core:place/cracked_toll", "core:place/wardens_rest",
	"core:place/hollin_barrow", "core:place/chalk_hound", "core:place/tollmere", "core:place/gullhithe",
	"core:place/the_lamp", "core:place/sayers_spire", "core:place/isseva", "core:place/pilgrims_ash",
	"core:poi/larkbourne_ford", "core:poi/hedge_shrine_of_ansel", "core:poi/singing_yew",
	"core:poi/tumbled_watchtower", "core:poi/whitecut_falls", "core:poi/bell_meadow_stones",
]

var player: Node3D
var bag: Inventory
var doll: Equipment
var progression: Progression
var crafting: Crafting
var quest_log: Node
var runner: Node
var merchant_bag: Inventory


func build() -> void:
	_world_state()
	_player()
	_bags()
	_progression()
	_quests()
	_dialogue()
	write_slots()


func _world_state() -> void:
	GameState.reset_for_new_game(1987)
	GameState.enter_region("core:region/hearthvale")
	for p in START_PLACES:
		if ContentDB.has(p):
			GameState.discover(p)
	GameState.set_flag("player_name", "Wren of the Hushline")
	GameState.set_flag("player_calling", "core:calling/hearthkeeper")
	GameState.set_flag("surveyed:core:place/chalk_hound", true)
	GameState.set_flag("surveyed:core:place/the_lamp", true)
	for book in ["core:book/naming_day_primer", "core:book/hearthvale_cookery",
			"core:book/unreliable_bestiary", "core:book/the_falling_of_the_toll"]:
		if ContentDB.has(book):
			GameState.mark_book_read(book)
	for enemy in ContentDB.ids_of("enemy"):
		GameState.set_flag("bestiary:" + enemy, true)
		GameState.inc("killed:" + enemy, 3 + enemy.length() % 7)
	for rumour in ContentDB.ids_of("rumour"):
		GameState.set_flag("rumour:" + rumour, true)
	GameState.play_time_seconds = 4.0 * 3600.0 + 37.0 * 60.0
	WorldClock.set_time(17.6, 12)
	WorldClock.running = false


func _player() -> void:
	player = FakePlayer.new()
	player.name = "FakePlayer"
	add_child(player)


func _bags() -> void:
	bag = Inventory.new()
	bag.name = "Bag"
	bag.is_player = true
	add_child(bag)
	for entry in [
		["core:item/iron_sword", 1], ["core:item/hunting_bow", 1], ["core:item/iron_dagger", 1],
		["core:item/gambeson", 1], ["core:item/kettle_helm", 1], ["core:item/leather_boots", 1],
		["core:item/leather_gloves", 1], ["core:item/oak_round_shield", 1], ["core:item/iron_arrow", 24],
		["core:item/potion_restore_health", 4], ["core:item/potion_restore_stamina", 2],
		["core:item/bread", 3], ["core:item/apple", 5], ["core:item/eel_pie", 2],
		["core:item/watercress", 6], ["core:item/hawthorn_berry", 4], ["core:item/iron_ingot", 7],
		["core:item/leather", 5], ["core:item/ember_mote", 6], ["core:item/candle", 3],
		["core:item/amulet_ansels_ember", 1], ["core:item/ring_tallymans_band", 1],
		["core:item/foundlings_token", 1], ["core:item/merrowby_house_key", 1],
	]:
		if ContentDB.has(str(entry[0])):
			bag.add(str(entry[0]), int(entry[1]))
	for id in ContentDB.ids_of("item"):
		if bag.items().size() >= 26:
			break
		var d := ContentDB.get_or_empty(id)
		if str(d.get("category", "")) in ["ingredient", "material", "misc"] and not bag.has(id):
			bag.add(id, 2)
	bag.marks = 1246

	doll = Equipment.new()
	doll.name = "Doll"
	add_child(doll)
	doll.set_inventory(bag)
	for pair in [["core:item/iron_sword", "main_hand"], ["core:item/oak_round_shield", "off_hand"],
			["core:item/kettle_helm", "head"], ["core:item/gambeson", "body"],
			["core:item/leather_gloves", "hands"], ["core:item/leather_boots", "feet"],
			["core:item/amulet_ansels_ember", "amulet"], ["core:item/ring_tallymans_band", "ring_1"]]:
		if bag.has(str(pair[0])):
			doll.equip(str(pair[0]), str(pair[1]))
	doll.bind_quick("quick_1", "core:item/potion_restore_health")
	doll.bind_quick("quick_2", "core:item/potion_restore_stamina")
	doll.bind_quick("quick_3", "core:item/bread")

	merchant_bag = Inventory.new()
	merchant_bag.name = "MerchantBag"
	merchant_bag.add_to_group("merchant_bag")
	merchant_bag.capacity_override = 900.0
	add_child(merchant_bag)
	for entry in [["core:item/iron_axe", 2], ["core:item/iron_ingot", 12], ["core:item/leather", 9],
			["core:item/bread", 6], ["core:item/potion_restore_health", 3], ["core:item/candle", 10],
			["core:item/rope", 4], ["core:item/lantern", 1], ["core:item/wool_tunic", 2],
			["core:item/oatcake", 5], ["core:item/lockpick", 6], ["core:item/linen", 8]]:
		if ContentDB.has(str(entry[0])):
			merchant_bag.add(str(entry[0]), int(entry[1]))
	merchant_bag.marks = 780


func _progression() -> void:
	progression = Progression.new()
	progression.name = "Progression"
	add_child(progression)
	progression.apply_calling("core:calling/hearthkeeper")
	for pair in [["one_handed", 900.0], ["block", 420.0], ["archery", 260.0], ["speech", 640.0],
			["alchemy", 520.0], ["smithing", 380.0], ["sneak", 210.0], ["athletics", 300.0],
			["kindling", 180.0], ["mending", 120.0], ["armour", 260.0]]:
		progression.award(str(pair[0]), float(pair[1]))

	crafting = Crafting.new()
	crafting.name = "Crafting"
	add_child(crafting)
	crafting.inventory = bag
	for e in ["core:effect/fortify_armour", "core:effect/ember_burst", "core:effect/resist_fire"]:
		if ContentDB.has(e):
			crafting.learn_enchantment(e)
	# eating a few reveals their second effect, so the alembic shows known and unknown
	for ing in bag.query({"category": "ingredient"}).slice(0, 4):
		crafting.eat_ingredient(ing.id)


func _quests() -> void:
	quest_log = FakeQuestLog.new()
	quest_log.name = "FakeQuestLog"
	add_child(quest_log)


## Two saved names so the title menu, Continue and the save/load screen have something real.
func write_slots() -> void:
	SaveSystem.save_to_slot("slot1")
	WorldClock.set_time(6.2, 3)
	GameState.enter_region("core:region/sedgemire")
	GameState.play_time_seconds = 1.0 * 3600.0 + 12.0 * 60.0
	SaveSystem.save_to_slot("slot2")
	WorldClock.set_time(17.6, 12)
	GameState.enter_region("core:region/hearthvale")
	GameState.play_time_seconds = 4.0 * 3600.0 + 37.0 * 60.0
	SaveSystem.save_to_slot("auto")


func clear_slots() -> void:
	for slot in ["slot1", "slot2", "auto"]:
		SaveSystem.delete_slot(slot)


func _dialogue() -> void:
	runner = FakeRunner.new()
	runner.name = "FakeDialogueRunner"
	add_child(runner)


func set_state(state: String) -> void:
	if player:
		player.set_state(state)


func fire_hud_events(state: String) -> void:
	if player:
		player.fire_hud_events(state)


func drive_dialogue(dialogue_ui: Node, state: String) -> void:
	if dialogue_ui.has_method("bind_runner"):
		dialogue_ui.call("bind_runner", runner)
	runner.play()
	if state == "gestures" and dialogue_ui.has_method("open_gesture_wheel"):
		dialogue_ui.call("open_gesture_wheel", "core:npc/wren_tallow")


# --- stand-ins ---------------------------------------------------------------------------

class FakePlayer:
	extends Node3D
	signal stats_changed
	signal lock_on_changed(target: Node3D)

	var health := 92.0
	var max_health := 140.0
	var stamina := 78.0
	var max_stamina := 116.0
	var mana := 54.0
	var max_mana := 96.0
	var poise := 42.0
	var max_poise := 60.0
	var interactor: Node

	func _init() -> void:
		add_to_group("player")
		interactor = FakeInteractor.new()
		interactor.name = "interactor"
		add_child(interactor)

	func set_state(state: String) -> void:
		if state == "combat":
			health = 48.0
			stamina = 26.0
			mana = 31.0
			var target := Node3D.new()
			target.name = "Hedge-wight"
			add_child(target)
			target.global_position = Vector3(0.4, 1.2, -3.0)
			lock_on_changed.emit(target)
			EventBus.boss_started.emit("core:boss/she_who_waits")
			EventBus.status_applied.emit(self, "core:effect/damage_health")
			EventBus.status_applied.emit(self, "core:effect/cold_bite")
			EventBus.status_applied.emit(self, "core:effect/fortify_armour")
		else:
			health = 92.0
			stamina = 78.0
			mana = 54.0
			lock_on_changed.emit(null)
		stats_changed.emit()

	## Only the HUD shots want prompts and notifications on screen.
	func fire_hud_events(state: String) -> void:
		if state == "combat":
			return
		interactor.prompt_changed.emit("Read the Roll")
		EventBus.notify.emit("The Wardens will see you now.", "quest")
		EventBus.notify.emit("Iron Sword (Fine) added.", "item")

	func is_dead() -> bool:
		return false

	class FakeInteractor:
		extends Node
		signal prompt_changed(text: String)


class FakeQuestLog:
	extends Node

	func _init() -> void:
		add_to_group("quest_log")

	var _active: Array[Dictionary] = [
		{"id": "core:quest/toll_hums", "name": "The Toll Hums", "layer": "main", "stage": 2,
		 "journal": [
			"Old Pennywort says the Cracked Toll has begun to hum at night, the way it did before the Quiet Villages. He would not say that in the tavern, which is how I know he means it.",
			"Roll-Warden Cade let me read the page at the back of the Roll. Eight villages have gone quiet in living memory. Two of the names on the far page have started being answered.",
			"Whatever is humming, it is answering something. I should stand in the Toll's crater at night and listen."],
		 "objectives": [
			{"text": "Speak to Pennywort at the mill", "done": true},
			{"text": "Read the Roll at Wardens' Rest", "done": true},
			{"text": "Stand in the Toll's crater after dark", "done": false},
			{"text": "Find what answers it", "done": false}]},
		{"id": "core:quest/wheel_that_turns", "name": "The Wheel That Turns", "layer": "side", "stage": 1,
		 "journal": [
			"The mill wheel turns with no water in the race. The miller has stopped charging for flour, which the village finds more frightening than the wheel."],
		 "objectives": [
			{"text": "Look under the mill", "done": false},
			{"text": "Ask the Larkbourne Boys about the wheel they stole", "done": false}]},
		{"id": "core:quest/lantern_clerks_errand", "name": "A Lantern-Clerk's Errand", "layer": "faction", "stage": 3,
		 "journal": [
			"The Sayers' Circle wants three accounts of the Dwindling written down from people who have never met a Sayer. They pay by the account and argue with each one."],
		 "objectives": [
			{"text": "Take down an account in Merrowby", "done": true},
			{"text": "Take down an account in Gullhithe", "done": true},
			{"text": "Take down an account in Isseva", "done": false}]},
	]

	func active_quests() -> Array[Dictionary]:
		return _active

	func completed_quests() -> Array[Dictionary]:
		return [{"id": "core:quest/a_name_for_the_foundling", "name": "A Name for the Foundling",
				"layer": "main", "outcome": "named",
				"journal": ["I came up the Hushline Stair with no name and no memory. Wren Tallow gave me the first and said the second would keep."],
				"objectives": [{"text": "Climb out of the Hush", "done": true}, {"text": "Be named at the Hearthstone", "done": true}]}]

	func active_markers() -> Array[Dictionary]:
		return [
			{"place_id": "core:place/cracked_toll", "radius": 260.0},
			{"place_id": "core:place/pennywort_mill", "radius": 180.0},
			{"place_id": "core:place/gullhithe", "radius": 320.0},
		]


class FakeRunner:
	extends Node
	signal line_shown(speaker: String, text: String, choices: Array)
	signal choice_needed(choices: Array)
	signal ended

	var running := false

	func _init() -> void:
		add_to_group("dialogue_runner")

	func is_running() -> bool:
		return running

	func play() -> void:
		running = true
		var choices := [
			{"text": "What does the Roll do, exactly?"},
			{"text": "Who else has heard the Toll hum?"},
			{"text": "[Speech 25] You are frightened of something.", "conditions": [{"skill_min": ["speech", 25]}]},
			{"text": "I'll come back."},
		]
		line_shown.emit("Roll-Warden Hesper Cade",
			"Thirty-three villages in the Roll, and I read every name of them on Naming Day whether anyone answers or not. My grandmother read forty-one. You may draw your own conclusions; most people draw the comfortable one.",
			choices)
		choice_needed.emit(choices)

	func choose(_index: int) -> void:
		pass

	func advance() -> void:
		pass
