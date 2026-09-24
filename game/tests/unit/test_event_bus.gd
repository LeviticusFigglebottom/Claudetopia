extends TestCase
## The bus's signals are emitted by other scripts, which is what a bus is for, and GDScript warns
## of every one its own class never uses: seventy entries in the debugger on each run, which buried
## the warnings worth reading. core/event_bus.gd turns that one warning off around its signal
## declarations and nowhere else.

const BUS := "res://core/event_bus.gd"


func test_the_unused_signal_warning_is_off_around_the_declarations_and_nowhere_else() -> void:
	var lines := FileAccess.get_file_as_string(BUS).split("\n")
	var start := -1
	var restore := -1
	for i in lines.size():
		var l := lines[i].strip_edges()
		if l == "@warning_ignore_start(\"unused_signal\")":
			assert_eq(start, -1, "the warning is turned off once")
			start = i
		elif l == "@warning_ignore_restore(\"unused_signal\")":
			assert_eq(restore, -1, "and restored once")
			restore = i
	assert_true(start >= 0 and restore > start, "the declarations sit between the start and the restore")
	var signals := 0
	for i in lines.size():
		var l := lines[i].strip_edges()
		if l.begins_with("signal "):
			signals += 1
			assert_true(i > start and i < restore, "%s is declared outside the quiet region, and warns" % l)
		elif i > start and i < restore:
			assert_true(l == "" or l.begins_with("#"), "only declarations are quiet, not: %s" % l)
	assert_gt(signals, 60, "the bus has its signals")


func test_the_bus_still_carries_what_is_emitted_on_it() -> void:
	var heard: Array = []
	var hear := func(text: String, kind: String) -> void: heard.append([text, kind])
	EventBus.notify.connect(hear)
	EventBus.emit_notify("a test", "info")
	EventBus.game_saved.connect(func(slot: String) -> void: heard.append(["saved", slot]), CONNECT_ONE_SHOT)
	EventBus.game_saved.emit("slot_a")
	EventBus.notify.disconnect(hear)
	assert_eq(heard, [["a test", "info"], ["saved", "slot_a"]], "the bus's signals are heard, the quiet ones too")
