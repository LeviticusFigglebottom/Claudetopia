extends TestCase


func test_builtin_commands() -> void:
	assert_true(Debug.run("time 13.5").begins_with("13:30"))
	assert_eq(Debug.run("flag dbg_x 3"), "set")
	assert_eq(Debug.run("flag dbg_x"), "3")
	assert_true(Debug.run("help").contains("weather"))
	assert_true(Debug.run("errors").begins_with("errors"))


func test_register_custom() -> void:
	Debug.register("dbg_echo", func(a: Array) -> String: return " ".join(a), "echo args")
	assert_eq(Debug.run("dbg_echo a b"), "a b")
