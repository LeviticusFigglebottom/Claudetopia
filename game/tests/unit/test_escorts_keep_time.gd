extends TestCase
## The escorts look round on the wall clock (PollTimer), as the people, a stage's foes and the reach
## check already did. On a machine drawing a frame every few seconds the engine counts each frame as
## an eighth of a second, and a look every quarter second of game time came round every few seconds.


class CountingEscorts extends Escorts:
	var looks := 0

	func tick() -> void:
		looks += 1


func test_the_escorts_look_round_on_the_wall_clock() -> void:
	var escorts := CountingEscorts.new()
	# out of the tree, so only these calls move it
	escorts._process(0.001)
	var first := escorts.looks
	OS.delay_msec(int(Escorts.INTERVAL * 1000.0) + 60)
	escorts._process(0.001)
	assert_gt(escorts.looks, first, "one long frame that the engine counts as a millisecond still brings a look round")
	escorts.free()
