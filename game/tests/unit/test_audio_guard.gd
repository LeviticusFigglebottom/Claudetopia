extends TestCase
## The audio guard (systems/audio/audio_guard.gd): in a run whose frames are not paced, the engine
## must not free a sound's bus details while its mixing thread is part-way through a mix. The
## guard holds the audio driver's lock from the end of a frame's processing to the start of the
## next frame, and the mixing thread holds the same lock for a whole mix. These check that the
## lock it holds is the one that stops the mixer, that it lets go at the start of the next frame
## and on the way out, that it is off unless a run asks for it, and that the music and the
## ambience stop handing the engine new bus details every frame for a volume that has not moved.


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _frames(n: int) -> void:
	for i in maxi(n, 1):
		await _tree().process_frame


func test_the_guard_is_off_unless_a_run_asks_for_it() -> void:
	assert_true(Foley.guard != null, "Foley stands a guard up")
	assert_false(AudioGuard.unpaced(), "this run did not ask for it (the fights do)")
	assert_false(Foley.guard.active, "and it is off")
	await _frames(2)
	assert_false(Foley.guard.is_holding(), "an inactive guard never holds the lock")


func test_the_lock_it_holds_stops_the_mixer_and_it_lets_go_at_the_next_frame() -> void:
	var guard := AudioGuard.new()
	_tree().root.add_child(guard)
	guard.active = true
	# A mix of the dummy driver comes round every 93 ms. Held for 300 ms, none happens.
	await _frames(2)
	guard._process(0.0)
	assert_true(guard.is_holding(), "the end of a frame takes the lock")
	var held_from := Time.get_ticks_msec()
	OS.delay_msec(300)
	var since_held := AudioServer.get_time_since_last_mix()
	var held_for := float(Time.get_ticks_msec() - held_from) / 1000.0
	# the start of the next frame lets it go
	guard._release()
	assert_false(guard.is_holding(), "the next frame's start lets it go")
	OS.delay_msec(300)
	var since_free := AudioServer.get_time_since_last_mix()
	print("MEASURE | the mixer while the guard holds the lock | %.2f s since a mix after %.2f s held | %.2f s after letting go" % [since_held, held_for, since_free])
	assert_gt(since_held, 0.2, "no mix while the lock is held")
	assert_gt(0.2, since_free, "the mixer mixes again once it is let go")
	guard.free()


func test_it_never_leaves_the_lock_held_on_the_way_out() -> void:
	var guard := AudioGuard.new()
	_tree().root.add_child(guard)
	guard.active = true
	await _frames(1)
	guard._process(0.0)
	assert_true(guard.is_holding())
	# Freed while holding (a quit at the end of a frame): shutting the audio server down would
	# wait for a mixer waiting for the lock.
	_tree().root.remove_child(guard)
	assert_false(guard.is_holding(), "leaving the tree lets it go")
	guard.free()
	OS.delay_msec(250)
	assert_gt(0.2, AudioServer.get_time_since_last_mix(), "and the mixer runs on")


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
