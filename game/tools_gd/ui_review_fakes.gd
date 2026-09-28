extends Node
## Believable state for the UI review harness: the real Inventory, Equipment, Progression
## Crafting and QuestLog nodes loaded with real content, plus stand-ins for the streams that are
## still being written (player, dialogue runner, merchant).

const START_PLACES := [
	"core:place/merrowby", "core:place/tamwick", "core:place/cracked_toll", "core:place/wardens_rest",
	"core:place/hollin_barrow", "core:place/chalk_hound", "core:place/tollmere", "core:place/gullhithe",
	"core:place/the_lamp", "core:place/sayers_spire", "core:place/isseva", "core:place/pilgrims_ash",
	"core:poi/larkbourne_ford", "core:poi/hedge_shrine_of_ansel", "core:poi/singing_yew",
	"core:poi/tumbled_watchtower", "core:poi/whitecut_falls", "core:poi/bell_meadow_stones",
]

## A character mid-story: the opening quest finished, the main thread two stages in, a side
## errand and a faction errand open. [quest id, stages to advance past the first].
const REVIEW_QUESTS := [
	["core:quest/the_naming", 5],
	["core:quest/the_toll_hums", 2],
	["core:quest/seventeen_bells", 1],
	["core:quest/the_unsaid_ledger", 2],
]

## A working Sayer's repertoire: two schools well in hand, one saying from a third and
## nothing at all from Calling, so the screen shows a character and not the whole pack.
const REVIEW_SAYINGS := [
	"core:spell/kindle_bolt", "core:spell/ember_fan", "core:spell/hearth_brand",
	"core:spell/hush_frost", "core:spell/ward", "core:spell/quiet_the_blood", "core:spell/mend",
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
	# two stones out in the country keep the name, so the chart has a road to draw
	for id in ["core:poi/hedge_shrine_of_ansel", "core:poi/the_wellspring", "core:poi/larkbourne_ford"]:
		if Hearth.stone_places().has(id) and not Hearth.lit.has(id):
			Hearth.lit.append(id)


func _player() -> void:
	player = FakePlayer.new()
	player.name = "FakePlayer"
	add_child(player)
	# standing on the Merrowby road, looking north-east, so the compass and the chart
	# have something to show: 80 m east and 70 m north of the town, wherever the map puts it
	var road := PlaceRef.point_xz({"place": "core:place/merrowby", "offset": [80.0, -70.0]})
	player.global_position = Vector3(road.x, 42.0, road.y)
	player.rotation.y = deg_to_rad(-38.0)


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

	_teach_sayings()

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


## The real quest log, with real quests started in it. A stand-in was pointless here and worse
## than pointless: `Social` owns a real QuestLog in the same "quest_log" group, and the journal
## takes the *first* node in that group, so the review's three invented quests were never the
## ones drawn — the Quests tab in every capture read "Nothing is asked of you yet." while the
## fake sat beside it. Starting real quests renders the tab from the pack, which is the point
## of the harness.
func _quests() -> void:
	quest_log = get_tree().get_first_node_in_group("quest_log")
	if quest_log == null:
		quest_log = preload("res://systems/quests/quest_log.gd").new()
		quest_log.name = "QuestLog"
		add_child(quest_log)
	for quest in REVIEW_QUESTS:
		if not ContentDB.has(str(quest[0])):
			continue
		quest_log.call("start", str(quest[0]))
		for i in int(quest[1]):
			quest_log.call("advance", str(quest[0]))


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


func _teach_sayings() -> void:
	for saying in REVIEW_SAYINGS:
		progression.learn_spell(saying)
	if player and player.has_method("equip_spell"):
		player.equip_spell("core:spell/ember_fan")


func set_state(state: String) -> void:
	if state == "no_sayings":
		# the page a character who has never been taught anything actually sees
		progression.known_spells.clear()
		progression.sayings_changed.emit()
		if player:
			player.equip_spell("")
	elif progression.known_spells.is_empty():
		_teach_sayings()
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
	signal spell_readied(spell_id: String)

	var health := 92.0
	var max_health := 140.0
	var stamina := 78.0
	var max_stamina := 116.0
	var mana := 54.0
	var max_mana := 96.0
	var equipped_spell := ""
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

	## The sayings screen readies through this, exactly as it does on the real player.
	func equip_spell(spell_id: String) -> bool:
		equipped_spell = spell_id
		spell_readied.emit(spell_id)
		return true

	class FakeInteractor:
		extends Node
		signal prompt_changed(text: String)


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
