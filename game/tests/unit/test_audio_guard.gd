extends TestCase
## The audio guard (systems/audio/audio_guard.gd). Godot 4.7.2 frees a sound's old bus details two
## AudioServer.update()s after swapping them out, whatever its mixing thread is doing, and a mixer
## descheduled between loading a sound's details and copying them reads freed memory: the crash
## the fights, a headless unit run and a world load met. The guard takes the audio driver's lock
## at the end of every frame's processing and lets it go at once; the mixer holds that lock for a
## whole mix, so a mix under way ends before anything swapped out this frame or earlier can be
## freed. These check that it stands between every frame, that its barrier waits for whoever
## holds the lock and holds nothing itself, that it is on unless a run says otherwise, and that
## the music and ambience stop swapping bus details every frame for a volume that has not moved.
##
## The crash itself is reproduced outside the suite, where a crash cannot take the suite with it:
## tools/debug/audio_race_check.sh holds the mixing thread at that instruction under gdb, and
## fails unless the reproduction crashes without the guard and survives with it.


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _frames(n: int) -> void:
	for i in maxi(n, 1):
		await _tree().process_frame


func test_the_guard_stands_between_every_frame_unless_a_run_says_not() -> void:
	assert_true(Foley.guard != null, "Foley stands a guard up")
	assert_false(OS.get_cmdline_user_args().has("--no-audio-guard"), "this run did not turn it off")
	assert_true(Foley.guard.active, "and it is on")
	assert_eq(Foley.guard.process_priority, 1 << 30, "processed after everything else in a frame")
	var before := Foley.guard.barriers
	await _frames(10)
	assert_true(Foley.guard.barriers - before >= 9, "a barrier every frame (%d in 10)" % (Foley.guard.barriers - before))


func test_the_barrier_waits_for_whoever_holds_the_lock_and_holds_nothing() -> void:
	# Another thread holds the audio driver's lock for 250 ms, as the mixer does for a mix.
	var held := Semaphore.new()
	var worker := Thread.new()
	worker.start(func() -> void:
		AudioServer.lock()
		held.post()
		OS.delay_msec(250)
		AudioServer.unlock())
	held.wait()
	var from := Time.get_ticks_msec()
	Foley.guard.barrier()
	var waited := Time.get_ticks_msec() - from
	worker.wait_to_finish()
	print("MEASURE | a barrier behind a 250 ms hold | waited %d ms" % waited)
	assert_gt(waited, 150, "the barrier waited for the mix under way")
	# and it holds nothing: the mixer goes on mixing across frames. A mix is waited for rather than
	# sampled once after a fixed 200 ms: on a machine at load 12-18 the mixer thread can be kept off
	# a core for a quarter of a second without anything holding it (main's full suite, "0.25 s since
	# a mix"). A barrier that held the lock would stop every mix, and none would come in the window,
	# which is ten frames' time here and never under two seconds.
	await _frames(20)
	var t0 := Time.get_ticks_msec()
	await _frames(1)
	var frame_ms := maxf(float(Time.get_ticks_msec() - t0), 16.0)
	var window_ms := maxf(2000.0, frame_ms * 10.0)
	var until := Time.get_ticks_msec() + int(window_ms)
	var mixed := false
	while Time.get_ticks_msec() < until:
		if AudioServer.get_time_since_last_mix() < 0.1:
			mixed = true
			break
		OS.delay_msec(5)
	print("MEASURE | a mix after the barrier | %s within %.0f ms (a frame %.0f ms)" % [
		"came" if mixed else "none", window_ms, frame_ms])
	assert_true(mixed, "the mixer mixes on: a mix within %.0f ms of the barrier letting go (%.2f s since the last)"
			% [window_ms, AudioServer.get_time_since_last_mix()])


func test_a_volume_is_written_only_when_it_moves() -> void:
	var p := AudioStreamPlayer.new()
	_tree().root.add_child(p)
	p.volume_db = -12.0
	assert_true(AudioGuard.ease_volume(p, -6.0, 2.0), "a stem fading up is written")
	assert_near(p.volume_db, -10.0, 0.0001, "a step toward its level")
	assert_true(AudioGuard.ease_volume(p, -6.0, 10.0))
	assert_near(p.volume_db, -6.0, 0.0001, "and no further than it")
	assert_false(AudioGuard.ease_volume(p, -6.0, 2.0), "a stem at its level is not written again")
	assert_near(p.volume_db, -6.0, 0.0001)
	p.queue_free()
