extends TestCase
## Reads on the loader's threads go through ThreadedLoads (core/threaded_loads.gd), a few at a time:
## a first launch froze for good when every worker thread read a mesh whose shader was still
## compiling and none was left to compile it (docs/FIRST_LAUNCH.md). No more than `limit()` are
## handed to the loader at once; the rest wait, read as in progress, and are handed over as reads end.

const PATHS := ["res://assets/shaders/ash_drift.gdshader", "res://assets/shaders/ember_crack.gdshader",
		"res://assets/shaders/banner_cloth.gdshader", "res://assets/shaders/cave_rock.gdshader",
		"res://assets/shaders/body_marks.gdshader", "res://assets/shaders/ember_pool.gdshader"]


func after_each() -> void:
	ThreadedLoads.limit_override = 0


func test_the_limit_leaves_the_pool_threads_to_compile_with() -> void:
	var pool := OS.get_processor_count()
	assert_true(ThreadedLoads.limit() >= 1, "at least one read at a time")
	assert_true(ThreadedLoads.limit() <= maxi(pool - 2, 1), "and two of the pool's %d threads always free (%d)" % [pool, ThreadedLoads.limit()])


func test_no_more_than_the_limit_are_read_at_once_and_every_one_arrives() -> void:
	ThreadedLoads.limit_override = 2
	for p in PATHS:
		assert_eq(ThreadedLoads.request(p), OK, "%s asked for" % p)
	var c := ThreadedLoads.counts()
	assert_true(c.x <= 2, "at most two handed to the loader (%d)" % c.x)
	assert_eq(c.x + c.y, PATHS.size(), "the rest wait (%s)" % str(c))
	for p in PATHS:
		assert_true(ThreadedLoads.status(p) in [ResourceLoader.THREAD_LOAD_IN_PROGRESS, ResourceLoader.THREAD_LOAD_LOADED],
				"%s reads as in progress or read" % p)
	var until := Time.get_ticks_msec() + 20000
	var most := 0
	while Time.get_ticks_msec() < until:
		var any := false
		for p in PATHS:
			if ThreadedLoads.status(p) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				any = true
		most = maxi(most, ThreadedLoads.counts().x)
		if not any:
			break
		await (Engine.get_main_loop() as SceneTree).process_frame
	assert_true(most <= 2, "never more than two at once (%d)" % most)
	for p in PATHS:
		assert_true(ThreadedLoads.take(p) is Shader, "%s arrives" % p)
	assert_eq(ThreadedLoads.counts(), Vector2i.ZERO, "and nothing is left")


func test_one_still_waiting_is_read_by_whoever_takes_it() -> void:
	ThreadedLoads.limit_override = 1
	for p in PATHS:
		ThreadedLoads.request(p)
	var last: String = PATHS[PATHS.size() - 1]
	assert_true(ThreadedLoads.take(last) is Shader, "the last one asked, taken at once, is read then")
	for p in PATHS.slice(0, PATHS.size() - 1):
		ThreadedLoads.forget(p)
	assert_eq(ThreadedLoads.counts().y, 0, "forgotten requests leave the queue")
