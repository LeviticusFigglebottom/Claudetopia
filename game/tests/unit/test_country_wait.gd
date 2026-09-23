extends TestCase
## The fade's wait for the cells round a body that has just stood up (UI.wait_for_country), against
## a streamer throttled by hand rather than a machine hoped to be slow.
##
## It gave up after 20 s of the clock. A machine drawing a frame every few seconds, where the
## streamer builds a fixed share of a cell each frame, got through a handful of frames in that time,
## and the fade lifted with 8 of 9 cells standing after 535 s. It counts cells now: it holds while
## they keep coming, gives up only when none has come for a stretch of frames and of seconds
## together, and has a generous cap.


## A streamer that brings in one of `wanted` cells every `every` frames, from `start`, and stops
## at `stop` (a stalled streamer) if that is short of `wanted`. Called once a frame by the wait.
class Throttled:
	extends RefCounted
	var wanted := 9
	var every := 1
	var start := 0
	var stop := 9
	var calls := 0

	func progress() -> Vector2i:
		var loaded := mini(start + floori(float(calls) / float(every)), stop)
		calls += 1
		return Vector2i(mini(loaded, wanted), wanted)


## A clock that moves `step_ms` every time it is read: a machine that slow, whatever this one is.
class SlowClock:
	extends RefCounted
	var t := 0
	var step_ms := 0

	func read() -> int:
		t += step_ms
		return t


func _throttled(wanted: int, every: int, stop := -1, start := 0) -> Throttled:
	var s := Throttled.new()
	s.wanted = wanted
	s.every = every
	s.start = start
	s.stop = wanted if stop < 0 else stop
	return s


func _clock(step_ms: int) -> SlowClock:
	var c := SlowClock.new()
	c.step_ms = step_ms
	return c


## The machine in the report: a frame every couple of seconds, a cell every eight frames. The old
## wait would have lifted after ten frames with one cell in; this one waits for all nine.
func test_a_slow_machine_is_waited_for_while_the_cells_keep_coming() -> void:
	var streamer := _throttled(9, 8)
	var clock := _clock(2000)
	var r: Dictionary = await UI.wait_for_country(streamer.progress, clock.read)
	assert_false(bool(r["timed_out"]), "it did not give up: %s" % str(r))
	assert_eq(r["cells"], Vector2i(9, 9), "every near cell was in when it ended")
	assert_true(int(r["frames"]) >= 64, "which took the frames it took (%d)" % int(r["frames"]))
	assert_true(int(r["ms"]) > 20000, "and far longer than the 20 s it used to allow (%d ms)" % int(r["ms"]))


func test_a_stalled_streamer_lifts_the_fade_after_a_stretch_of_frames_and_seconds() -> void:
	var streamer := _throttled(9, 2, 5)
	var clock := _clock(100)
	var r: Dictionary = await UI.wait_for_country(streamer.progress, clock.read, 30, 5.0, 600.0)
	assert_true(bool(r["timed_out"]), "a country that stops arriving is not waited for for ever")
	assert_eq(str(r["why"]), "stalled")
	assert_eq(r["cells"], Vector2i(5, 9), "and the count says how far it got")
	# The fifth cell came on frame 10. The stall then needs 30 quiet frames and 5 s of quiet, and at
	# 100 ms a frame the seconds are the longer half: about 50 frames more.
	var frames := int(r["frames"])
	assert_true(frames >= 10 + 45 and frames <= 10 + 60, "it waited out both halves of the stall, and no more (%d frames)" % frames)


func test_a_fast_machine_does_not_give_up_on_frames_alone() -> void:
	# 1 ms a frame: 30 quiet frames pass in 30 ms, but the stall also wants its seconds
	var streamer := _throttled(9, 45)
	var clock := _clock(1)
	var r: Dictionary = await UI.wait_for_country(streamer.progress, clock.read, 30, 0.2, 600.0)
	assert_false(bool(r["timed_out"]), "a cell every 45 frames is still a country arriving: %s" % str(r))
	assert_eq(r["cells"], Vector2i(9, 9))


func test_the_cap_ends_even_a_wait_that_is_still_moving() -> void:
	# a cell every 5 frames of 1000 wanted: moving, never done
	var streamer := _throttled(1000, 5)
	var clock := _clock(1000)
	var r: Dictionary = await UI.wait_for_country(streamer.progress, clock.read, 120, 10.0, 60.0)
	assert_true(bool(r["timed_out"]))
	assert_eq(str(r["why"]), "cap", "the cap, not a stall: cells were still coming")
	assert_true(int(r["ms"]) >= 60000 and int(r["frames"]) <= 62, "at the cap (%d ms, %d frames)" % [int(r["ms"]), int(r["frames"])])


func test_all_in_at_once_or_nothing_wanted_does_not_wait() -> void:
	# kept in locals: a Callable does not keep its RefCounted alive
	var all_in := _throttled(9, 1, -1, 9)
	var clock := _clock(10)
	var done: Dictionary = await UI.wait_for_country(all_in.progress, clock.read)
	assert_eq(int(done["frames"]), 0, "nine of nine already: no frame waited")
	assert_false(bool(done["timed_out"]))
	var none_wanted := _throttled(0, 1)
	var nothing: Dictionary = await UI.wait_for_country(none_wanted.progress, clock.read)
	assert_eq(int(nothing["frames"]), 0, "nothing wanted: nothing to wait for")
	assert_false(bool(nothing["timed_out"]))
