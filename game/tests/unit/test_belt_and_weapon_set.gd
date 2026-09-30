extends TestCase
## The belt and the weapon set on the HUD (playtest 09-30):
##   * the belt has eight sockets, on 1-8, and shows what is on it as a painted picture
##     (ThemeBuilder.item_art), not a drawn glyph;
##   * the weapon in the hand shows over the belt's left end with the cycle key;
##   * the cycle key goes round the weapon set on a real player, and the HUD shows the set for a
##     moment with the weapon now in hand named; the wheel does the same;
##   * the hint strip teaches the cycle key while there is another weapon to go to, and lets it go
##     once it has been used;
##   * the Controls page lists the cycle key and all eight belt keys, from the bindings.

const HUD_SCENE := "res://ui/hud/hud.tscn"
const BOW := "core:item/hunting_bow"
const KNIFE := "core:item/hunting_knife"
const POTION := "core:item/potion_restore_health"
const TORCH := "core:item/torch"

var player: Player = null
var hud: Node = null
var floor_body: StaticBody3D = null


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	GameState.reset_for_new_game(7)
	GameState.set_flag("new_game", false)
	Settings.load_settings()
	Settings._load_binding_defs()
	Settings.apply_bindings()
	Settings.data["gameplay"]["show_hints"] = true
	UI.using_gamepad = false
	floor_body = StaticBody3D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	floor_body.add_child(shape)
	_tree().root.add_child(floor_body)
	floor_body.global_position = Vector3(0.0, -0.5, 0.0)
	player = (load("res://actors/player/player.tscn") as PackedScene).instantiate() as Player
	_tree().root.add_child(player)
	player.global_position = Vector3(0.0, 0.02, 0.0)
	var bag := player.get_node("Inventory") as Inventory
	var doll := player.get_node("Equipment") as Equipment
	bag.add(BOW, 1)
	bag.add(KNIFE, 1)
	bag.add(POTION, 3)
	bag.add(TORCH, 2)
	doll.equip(BOW, "main_hand")
	doll.add_to_weapon_set(KNIFE)
	player.set_quick_slot(0, POTION)
	player.set_quick_slot(5, TORCH)


func after_each() -> void:
	Input.action_release("cycle_weapon")
	UI.close_all()
	for n in [hud, player, floor_body]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	hud = null
	player = null
	floor_body = null
	await _tree().process_frame


func _make_hud() -> Node:
	hud = (load(HUD_SCENE) as PackedScene).instantiate()
	_tree().root.add_child(hud)
	await _tree().process_frame
	hud.call("_connect_world")
	return hud


func test_the_belt_has_eight_painted_sockets() -> void:
	await _make_hud()
	var slots: Array = hud.get("_quick_slots")
	assert_eq(slots.size(), 8, "eight sockets on the belt")
	var icon := (slots[0] as Control).find_child("Icon", true, false) as TextureRect
	assert_true(icon.texture != null, "the draught on 1 is shown")
	assert_eq(icon.texture, ThemeBuilder.item_art("potion_red"), "as its painting, not the drawn glyph")
	var torch := (slots[5] as Control).find_child("Icon", true, false) as TextureRect
	assert_eq(torch.texture, ThemeBuilder.item_art("torch"), "and the torch on 6")
	var key := (slots[7] as Control).find_child("Key", true, false) as Label
	assert_eq(key.text, "8", "the eighth socket is on 8")
	for name in ["potion_red", "potion_blue", "hearth_flask", "bread", "torch", "sword", "bow", "staff", "sword_shield"]:
		assert_true(ThemeBuilder.item_art(name) != null, "painted art for %s" % name)
	var plate := hud.get("_weapon_plate") as Control
	assert_true(plate.visible, "the weapon in hand shows over the belt")
	assert_eq((hud.get("_weapon_art") as TextureRect).texture, ThemeBuilder.item_art("bow"))


func test_the_cycle_key_goes_round_the_set_and_the_hud_shows_it() -> void:
	await _make_hud()
	for i in 10:
		await _tree().physics_frame
	var doll := player.get_node("Equipment") as Equipment
	Input.action_press("cycle_weapon")
	for i in 3:
		await _tree().physics_frame
	Input.action_release("cycle_weapon")
	await _tree().process_frame
	assert_eq(doll.item_id("main_hand"), KNIFE, "the cycle key took the knife into the hand")
	var notice := hud.get("_cycle_notice") as Control
	assert_true(notice.visible, "the HUD shows the weapon set")
	assert_eq((hud.get("_cycle_name") as Label).text, "Hunting Knife", "with the weapon now in hand named")
	assert_eq((hud.get("_cycle_row") as Control).get_child_count(), 2, "and both weapons of the set")
	# the wheel goes round too, while nothing is locked on
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	player._unhandled_input(wheel)
	assert_eq(doll.item_id("main_hand"), BOW, "the wheel gave the bow back")
	await _tree().create_timer(float((hud.get_script() as Script).get_script_constant_map()["CYCLE_NOTICE_S"]) + 0.6).timeout
	assert_false(notice.visible, "the notice goes after a moment")


func test_the_hints_teach_the_cycle_key_while_there_is_another_weapon() -> void:
	await _make_hud()
	var hints := hud.find_children("*", "ControlHints", true, false)[0] as ControlHints
	for i in 3:
		await _tree().process_frame
	assert_true(hints.showing().has("weapons"), "the strip teaches the cycle key: %s" % str(hints.showing()))
	player.cycle_weapon(1)
	await _tree().process_frame
	assert_false(hints.showing().has("weapons"), "and lets it go once it has been used")


func test_the_controls_page_lists_the_cycle_and_the_belt() -> void:
	var labels: Array = []
	for def in Settings.binding_defs:
		labels.append(str((def as Dictionary).get("action", "")))
	for a in ["cycle_weapon", "quick_1", "quick_5", "quick_8"]:
		assert_true(labels.has(a), "%s is a rebindable action" % a)
		assert_true(InputMap.has_action(a), "%s is in the input map" % a)
	assert_eq(Settings.prompt_for("cycle_weapon", false), "R")
	assert_eq(Settings.prompt_for("quick_8", false), "8")
