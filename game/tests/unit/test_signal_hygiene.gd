extends TestCase
## A node that listens to an autoload is not unhooked by being freed unless it connected a
## *method*. Godot drops the connections whose target object is destroyed; a closure's target
## is the closure, and the node it captured is only a capture, so the bus goes on calling it
## for the rest of the process. That is what "Lambda capture at index 0 was freed" on stderr
## means, and the suite printed it 139 times before these tests existed.
##
## These press it the way the game does: build the node, put it in the tree, free it, then
## emit the very signal it listened for and ask the *bus* whether anything is still hanging
## off it. The census over every autoload signal catches the next one too, in whatever file
## somebody writes it.

const BUSES := ["EventBus", "UI", "Settings", "WorldClock", "GameState", "Social", "Hearth"]


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## Every listener on an autoload signal whose object is gone. A method connection cannot be
## in here -- Godot drops those when the target is destroyed -- so everything this finds is a
## closure the bus is still holding on behalf of something that no longer exists. `get_object`
## on a Callable returns the object it was made from, and `null` once that object is freed.
func _dangling() -> Array[String]:
	var out: Array[String] = []
	for bus_name: String in BUSES:
		var bus: Node = _tree().root.get_node_or_null("/root/" + bus_name)
		if bus == null:
			continue
		for s: Dictionary in bus.get_signal_list():
			var sig := str(s["name"])
			for c: Dictionary in bus.get_signal_connection_list(sig):
				var cb: Callable = c["callable"]
				if cb.get_object() == null:
					out.append("%s.%s" % [bus_name, sig])
	return out


## The bus entries a node left behind after being freed, as readable strings. Only the ones
## this node added count: the listeners that were already stale when it was built are somebody
## else's finding, and this test names its own.
func _left_behind(node: Node) -> Array[String]:
	var before := _dangling()
	_tree().root.add_child(node)
	node.free()
	var out: Array[String] = []
	for entry: String in _dangling():
		if before.has(entry):
			before.erase(entry)
			continue
		out.append(entry + ": a listener with no object left behind")
	return out


func test_a_freed_hud_is_off_every_bus() -> void:
	var scene: PackedScene = load("res://ui/hud/hud.tscn")
	assert_true(scene != null, "the HUD scene loads")
	assert_empty(_left_behind(scene.instantiate()), "a freed HUD")


func test_a_freed_npc_streamer_is_off_every_bus() -> void:
	var streamer := NpcStreamer.new()
	streamer.enabled = false
	assert_empty(_left_behind(streamer), "a freed NPC streamer")


func test_a_freed_stat_bar_is_off_every_bus() -> void:
	var bar := StatBar.new()
	bar.kind = "health"
	assert_empty(_left_behind(bar), "a freed stat bar")


func test_a_freed_hearthstone_is_off_every_bus() -> void:
	var stone := Hearthstone.new()
	stone.hearthstone_id = "test_stone"
	assert_empty(_left_behind(stone), "a freed Hearthstone")


func test_a_freed_actor_leaves_nothing_on_its_own_components() -> void:
	var actor := Actor.new()
	_tree().root.add_child(actor)
	var errors_before := Log.error_count
	actor.free()
	assert_eq(Log.error_count, errors_before, "freeing an actor logs nothing")


## The button, pressed: the HUD listened for `item_equipped`, so equip something after it has
## gone and ask the bus, not the screen, whether anybody is still listening.
func test_equipping_something_after_the_hud_has_gone_reaches_nobody() -> void:
	var before := EventBus.item_equipped.get_connections().size()
	var hud: Node = load("res://ui/hud/hud.tscn").instantiate()
	_tree().root.add_child(hud)
	assert_gt(EventBus.item_equipped.get_connections().size(), before,
			"the HUD listens while it lives")
	hud.free()
	assert_eq(EventBus.item_equipped.get_connections().size(), before,
			"nothing of the HUD is left on item_equipped")
	var errors_before := Log.error_count
	EventBus.item_equipped.emit("main_hand", "core:item/ash_spear")
	assert_eq(Log.error_count, errors_before, "the emission reaches nobody and says nothing")


## The same for the streamer, which listens to the clock: an hour passing in a world that has
## been torn down used to refresh the people of a scene that is no longer there.
func test_an_hour_passing_after_the_streamer_has_gone_reaches_nobody() -> void:
	var before := EventBus.hour_changed.get_connections().size()
	var streamer := NpcStreamer.new()
	streamer.enabled = false
	_tree().root.add_child(streamer)
	assert_gt(EventBus.hour_changed.get_connections().size(), before,
			"the streamer listens while it lives")
	streamer.free()
	assert_eq(EventBus.hour_changed.get_connections().size(), before,
			"nothing of the streamer is left on hour_changed")
	var errors_before := Log.error_count
	EventBus.hour_changed.emit(11)
	assert_eq(Log.error_count, errors_before, "the hour reaches nobody and says nothing")


## The one that was actually firing, 139 times a run. A toast is thrown away the moment a sixth
## one arrives, five and a half seconds before its own fade-out ends; the fade was started on UI,
## which never goes, and its last step was a closure holding the panel. So the closure woke up
## with a freed capture -- and the toast it was meant to free had already been freed by somebody
## else, which is why the fault was invisible. Press it: say nine things, and ask the SceneTree
## how many of those fades are still running over toasts that are gone.
func test_a_toast_thrown_away_early_takes_its_fade_with_it() -> void:
	var tree := _tree()
	var before := 0
	for t: Tween in tree.get_processed_tweens():
		if t.is_valid() and t.is_running():
			before += 1
	for i in 9:
		EventBus.notify.emit("toast %d" % i, "item")
	# queue_free lands at the end of the frame, and a tween bound to the node goes with it.
	for i in 3:
		await tree.process_frame
	var live := 0
	for t: Tween in tree.get_processed_tweens():
		if t.is_valid() and t.is_running():
			live += 1
	# Five toasts stand at most, so at most five fades may still be running.
	assert_true(live - before <= 5,
			"%d fades still running for 9 toasts of which at most 5 survive" % (live - before))
