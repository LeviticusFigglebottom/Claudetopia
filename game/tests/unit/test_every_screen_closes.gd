extends TestCase
## Pressing Escape on every screen in `UI.MENUS`.
##
## Fourteen screens are registered, each drawn by its own script, and the only thing that
## closes one on the pause key is `UI._unhandled_input`. A screen that swallows the event, or
## that never reaches the menu stack because its `setup()` threw on the args the game hands
## it, is a screen a player cannot get out of without the mouse — and nothing had ever pressed
## that key on any of them. This opens each one the way the game does and presses Escape.

const PAUSE_KEY := KEY_ESCAPE

## The args the game passes each screen (see the UI autoload's own signal handlers).
const ARGS := {
	"book": {"book_id": "core:book/the_falling_of_the_toll"},
	"crafting": {"station": "forge"},
	"trade": {"merchant_id": "core:npc/hesta_hollins"},
	"deed": {"property_id": "core:property/merrowby_cottage", "name": "The Cottage by the Toll",
		"place": "Merrowby", "price": 980},
	"save_load": {"mode": "save"},
	"settings": {"from_menu": true},
	"journal": {"tab": 0},
}

var _chest: WorldContainer = null


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	# a full-screen menu pauses the tree and frees the mouse; both want undoing after
	UI.gameplay_override = true


func after_each() -> void:
	UI.close_all()
	UI.gameplay_override = false
	_tree().paused = false
	if _chest != null and is_instance_valid(_chest):
		_chest.queue_free()
		_chest = null


func _press_pause() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = PAUSE_KEY
		event.physical_keycode = PAUSE_KEY
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _tree().process_frame
	await _tree().process_frame


## The container and the job board are handed a live node rather than an id.
func _args_for(menu_id: String) -> Dictionary:
	if menu_id == "container":
		_chest = WorldContainer.new()
		_chest.container_id = "test:container/kist"
		_tree().root.add_child(_chest)
		_chest.inventory.add("core:item/bread", 2)
		return {"container": _chest}
	if menu_id == "job_board":
		return {}
	return ARGS.get(menu_id, {}).duplicate()


func test_every_registered_screen_opens_with_the_args_the_game_gives_it() -> void:
	for menu_id: String in UI.MENUS:
		var node := UI.open(menu_id, _args_for(menu_id))
		assert_true(node != null, "%s did not open" % menu_id)
		assert_true(UI.is_menu_open(menu_id), "%s opened but never reached the menu stack" % menu_id)
		UI.close_all()
		await _tree().process_frame
		after_each()
		UI.gameplay_override = true


func test_the_pause_key_closes_every_screen() -> void:
	var stuck: Array[String] = []
	for menu_id: String in UI.MENUS:
		var node := UI.open(menu_id, _args_for(menu_id))
		if node == null:
			continue
		await _press_pause()
		if UI.is_menu_open(menu_id):
			stuck.append(menu_id)
		UI.close_all()
		await _tree().process_frame
		after_each()
		UI.gameplay_override = true
	assert_empty(stuck, "screens the pause key cannot close: %s" % ", ".join(stuck))


## Closing the last screen has to give the tree back, or the world stays frozen behind it.
func test_closing_the_last_screen_unpauses_the_tree() -> void:
	UI.open("journal", {"tab": 0})
	await _tree().process_frame
	assert_true(_tree().paused, "a full-screen menu should pause the tree")
	await _press_pause()
	assert_false(UI.is_menu_open(), "the journal did not close")
	assert_false(_tree().paused, "the tree stayed paused after the last screen closed")


## Escape on a nested screen walks back one, not all the way out.
func test_the_pause_key_walks_back_out_of_a_nested_screen() -> void:
	UI.open("pause")
	UI.open("settings", {"from_menu": false})
	await _tree().process_frame
	assert_eq(UI.top_menu(), "settings")
	await _press_pause()
	assert_eq(UI.top_menu(), "pause", "Escape in the settings should go back to the pause menu")
	await _press_pause()
	assert_false(UI.is_menu_open(), "and then out")
