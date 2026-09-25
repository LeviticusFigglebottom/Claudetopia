extends TestCase
## The runs that measure the game start from its shipped settings.
##
## Every worktree on the build machine is the project "Wickmere", and Godot keeps user:// by project
## name, so they all shared one settings.cfg: at 02:24 on 2026-09-25 a run wrote
## play_opening=false and every branch's flow failed "a new game plays the opening" from then on.
## run.sh now gives each checkout its own user:// (tools/godot_env.sh) and takes its settings.cfg
## away before a run; the flow checks it came in as shipped, and the test runner says so and puts
## it right. These hold the question both ask.


func test_the_shipped_settings_are_not_off_default() -> void:
	assert_empty(Settings.off_default(Settings.DEFAULTS.duplicate(true)))


func test_the_opening_turned_off_is_caught() -> void:
	var d: Dictionary = Settings.DEFAULTS.duplicate(true)
	d["gameplay"]["play_opening"] = false
	var off := Settings.off_default(d)
	assert_eq(off.size(), 1, "one setting off: %s" % str(off))
	assert_true(off[0].begins_with("gameplay.play_opening="), off[0])


func test_any_setting_moved_is_caught_and_a_number_saved_as_a_whole_is_not() -> void:
	var d: Dictionary = Settings.DEFAULTS.duplicate(true)
	d["video"]["fov"] = 90.0
	d["audio"]["music"] = 0.1
	assert_eq(Settings.off_default(d).size(), 2, str(Settings.off_default(d)))
	# a ConfigFile gives 75 back for 75.0: the same setting
	var e: Dictionary = Settings.DEFAULTS.duplicate(true)
	e["video"]["fov"] = 75
	assert_empty(Settings.off_default(e))

