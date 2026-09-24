extends TestCase
## The pad layout as shipped (core/default_bindings.json): one button does one thing, everything a
## player does in play is on the pad, and a player who never changed a binding is moved onto the
## layout as it is now while one who did keeps theirs.
##
## Found shared: the right stick's click locked on and switched the view at once, and the D-pad's
## up cast and used the first quick slot at once; the map sat on Guide, which Windows keeps for
## itself. Now B is Sprint (a tap rolls, as the Souls games have it), the left stick's click sneaks,
## LB casts, R3 locks on, Back is the chart, and Start is the pause page, which holds the rest.

## A's two actions are never listened for at once: in play it uses, in a menu it confirms.
const ONE_BUTTON_TWO_PLACES := {"joy_button:0": ["interact", "ui_accept_alt"]}
## What a player does in play, each with a pad input of its own.
const ON_THE_PAD: Array[String] = ["move_forward", "move_back", "move_left", "move_right",
		"look_up", "look_down", "look_left", "look_right", "jump", "sprint", "sneak",
		"attack_light", "attack_heavy", "block", "cast", "lock_on", "interact", "gesture",
		"quick_1", "quick_2", "quick_3", "quick_4", "pause", "map"]
## Reached on a pad another way: the roll is a tap of Sprint, walking a light stick, another foe a
## flick of the right stick, and these screens a page of the pause menu.
const ANOTHER_WAY: Array[String] = ["dodge", "walk", "cycle_target", "inventory", "journal", "skills",
		"sayings", "quick_save", "quick_load"]
const GUIDE := "joy_button:5"


func _defaults() -> Dictionary:
	var out := {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://core/default_bindings.json"))
	for def in (parsed as Dictionary).get("actions", []):
		out[str(def["action"])] = Array(def["events"])
	return out


func test_one_pad_button_does_one_thing() -> void:
	var owners := {}
	for action in _defaults():
		for ev: String in _defaults()[action]:
			if ev.begins_with("joy"):
				owners[ev] = owners.get(ev, []) + [action]
	for ev in owners:
		var acts: Array = (owners[ev] as Array).duplicate()
		if acts.size() < 2:
			continue
		var allowed: Array = (ONE_BUTTON_TWO_PLACES.get(ev, []) as Array).duplicate()
		acts.sort()
		allowed.sort()
		assert_eq(acts, allowed, "%s does %s at once" % [ev, " and ".join(acts)])


func test_what_a_player_does_in_play_is_on_the_pad() -> void:
	var bound := _defaults()
	for action in ON_THE_PAD:
		var on_pad := false
		for ev: String in bound.get(action, []):
			on_pad = on_pad or ev.begins_with("joy")
		assert_true(on_pad, "%s has no pad input" % action)
	for action in bound:
		assert_false((bound[action] as Array).has(GUIDE), "%s is on Guide, which Windows keeps for itself" % action)
	# the screens off the pad are on the pause page
	var pages: Array = []
	for entry in (load("res://ui/menus/pause_menu.gd") as GDScript).get_script_constant_map().get("ENTRIES", []):
		pages.append(str(entry[1]))
	for page in ["inventory", "journal", "map", "skills", "sayings"]:
		assert_true(pages.has(page), "the pause page has no way to %s" % page)
	for action in ANOTHER_WAY:
		assert_true(bound.has(action), "%s is not an action any more" % action)


## A saved binding that is still exactly the old default was never the player's choice, and takes
## the layout as it is now; one they changed is theirs.
func test_an_untouched_old_default_moves_and_a_changed_one_stays() -> void:
	assert_eq(Settings.migrated_binding("cast", ["key:F", "joy_button:11"]), Settings.default_events("cast"),
			"an untouched old default was kept")
	assert_eq(Settings.migrated_binding("map", ["key:M", "joy_button:5"]), Settings.default_events("map"))
	assert_eq(Settings.migrated_binding("lock_on", ["mouse:3", "joy_button:2"]), ["mouse:3", "joy_button:2"],
			"a binding the player chose was changed")
	assert_eq(Settings.migrated_binding("cast", ["key:R", "joy_button:11"]), ["key:R", "joy_button:11"],
			"a binding the player half changed was changed")
