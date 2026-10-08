class_name ThreadedLoads
extends RefCounted
## Every resource the game reads on the loader's threads goes through here, so no more than `limit()`
## are read at once and the worker pool always has threads free.
##
## Why (docs/FIRST_LAUNCH.md): the title froze for good on a first launch. A mesh read on a worker
## thread whose material's shader was not compiled yet makes that worker take the shader's lock and
## wait for the shader's compile, and the compile is itself a group of tasks on the same worker pool
## (ShaderRD::_compile_version_end, which waits without running other tasks). The streamer used to
## ask for a hundred assets at once, so every worker took one, one held the lock waiting for the
## compile and the others waited for the lock, and nobody was left to compile. The main thread,
## drawing, waited for the same shader. With a warm shader cache (the second launch) nothing
## compiles and nothing waited, which is why it was only ever the first launch.
##
## The API follows ResourceLoader's: `request`, `status`, `take`, and `forget` for a request nobody
## will take. A request waits in a queue until a read ends, and reads as in progress while it
## waits. `take` on one still queued reads it on the calling thread. Any thread may call any of
## these.
##
## Nothing here makes the main thread wait for a read that is still going when nobody wants what it
## reads: `forget` leaves it to finish and collects it on a later frame, and `after_task` does the
## same for a worker task whose owner is going (a world torn down behind the title). A main thread
## waiting on a worker is how a player's click on the title froze the game for good: a texture read
## on a worker thread can itself wait for the main thread (the rendering device's uploads are
## handed over at the end of a frame), and a main thread waiting for that read never ends its frame.

static var _mutex := Mutex.new()
## Paths asked for and not yet handed to the loader, oldest first.
static var _queue: PackedStringArray = PackedStringArray()
static var _queued: Dictionary = {}
## Paths handed to the loader and not yet seen finished.
static var _reading: Dictionary = {}
## Reads nobody will take, left to finish and collected by `pump` (`forget`).
static var _orphans: Dictionary = {}
## Worker tasks whose owners are gone: [task id, is a group, what the task needs kept alive,
## a Callable to call when it is done], waited for by `pump` once they have finished.
static var _left_tasks: Array = []
static var _ticking := false
## For a test: 0 is the machine's own limit.
static var limit_override := 0
## How long a quit waits for reads still going before it leaves them (`drain`).
const DRAIN_WAIT_MS := 1500
## Safe mode's limit (SafeMode): one read at a time. 0 when not in safe mode.
static var safe_limit := 0
## Worker threads another reader holds for a while (the terrain's region files, World), taken off
## the limit so the two together still leave a compile its threads.
static var reserved := 0


## The worker pool's threads: the project's setting, or the engine's default of one per core.
static func pool_size() -> int:
	var pool := int(ProjectSettings.get_setting("threading/worker_pool/max_threads", -1))
	return pool if pool > 0 else OS.get_processor_count()


## How many reads at once: fewer than the worker pool's threads by two, so a compile always has a
## thread (1 on a two-thread machine, at most 4), less any threads `reserved` by another reader.
static func limit() -> int:
	if limit_override > 0:
		return limit_override
	if safe_limit > 0:
		return safe_limit
	return clampi(pool_size() - 2 - reserved, 1, 4)


## Asks for `path` to be read on the loader's threads, now or when a read ends. OK, or the loader's
## refusal when it was handed over at once. `first`: ahead of every read still waiting (something is
## waiting for this one now, such as the scene a menu is going to).
static func request(path: String, first := false) -> Error:
	_mutex.lock()
	var err := OK
	if _orphans.has(path):
		# asked for again while a read nobody wanted is still going: it is wanted after all
		_orphans.erase(path)
		_reading[path] = true
	elif _queued.has(path) and first:
		_queue.remove_at(_queue.find(path))
		_queue.insert(0, path)
	elif not _queued.has(path) and not _reading.has(path):
		if _reading.size() + _orphans.size() < limit():
			err = ResourceLoader.load_threaded_request(path)
			if err == OK:
				_reading[path] = true
		elif first:
			_queue.insert(0, path)
			_queued[path] = true
		else:
			_queue.append(path)
			_queued[path] = true
	var counts_now := Vector2i(_reading.size(), _queue.size())
	_mutex.unlock()
	if StartupTrace.detailed:
		StartupTrace.detail("load asked: %s (reading %d, queued %d, limit %d)" % [path, counts_now.x, counts_now.y, limit()])
	_ensure_ticking()
	return err


## ResourceLoader.load_threaded_get_status, with a queued request reading as in progress.
static func status(path: String) -> ResourceLoader.ThreadLoadStatus:
	_mutex.lock()
	var queued := _queued.has(path)
	_mutex.unlock()
	if queued:
		pump()
		return ResourceLoader.THREAD_LOAD_IN_PROGRESS
	return ResourceLoader.load_threaded_get_status(path)


## The resource: from the loader when it was handed over (waiting for it, as load_threaded_get
## does), or read here and now when it was still queued.
static func take(path: String) -> Resource:
	_mutex.lock()
	var queued := _queued.has(path)
	if queued:
		_unqueue(path)
	var handed := _reading.has(path) or _orphans.has(path)
	_reading.erase(path)
	_orphans.erase(path)
	_mutex.unlock()
	pump()
	if StartupTrace.active and handed and OS.get_thread_caller_id() == OS.get_main_thread_id() \
			and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		# the main thread waits here until it is read: the line a hang would end on
		StartupTrace.step("load taken while still reading, the main thread waits: %s" % path)
	if StartupTrace.detailed:
		StartupTrace.detail("load taken: %s (%s)" % [path, "read here, it was queued" if queued else "from the loader"])
	if queued:
		return ResourceLoader.load(path)
	return ResourceLoader.load_threaded_get(path)


## A request nobody will take: dropped if still queued; taken off the loader if it was handed over
## and is done, and otherwise left to finish and taken off by `pump` then. Never waits.
static func forget(path: String) -> void:
	_mutex.lock()
	var queued := _queued.has(path)
	if queued:
		_unqueue(path)
	var handed := _reading.has(path)
	_reading.erase(path)
	var st := ResourceLoader.load_threaded_get_status(path) if handed else ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
	if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		_orphans[path] = true
	_mutex.unlock()
	if StartupTrace.detailed and (queued or handed):
		StartupTrace.detail("load forgotten: %s (%s)" % [path, "queued, dropped" if queued
			else "still reading, collected when done" if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS else "read, let go"])
	if handed and st != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE and st != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		ResourceLoader.load_threaded_get(path)
	_ensure_ticking()
	pump()


## Every request still queued is dropped, and every read still going is left to finish and let go
## (the title's world is gone, and nobody will take what it asked for). The paths, for their asker.
static func forget_all(paths: Array) -> void:
	for p in paths:
		forget(str(p))


## A worker task whose owner is going: `keep` (anything the task's Callable needs alive, such as the
## object whose method it runs) is held until the task has finished, then the task is waited for,
## which is then at once, and `done` is called on the main thread. Never waits.
static func after_task(task_id: int, group: bool, keep: Variant = null, done := Callable()) -> void:
	if task_id < 0:
		return
	_mutex.lock()
	_left_tasks.append([task_id, group, keep, done])
	_mutex.unlock()
	_ensure_ticking()


## How many reads and tasks are left to finish with nobody waiting (for a test or a report).
static func left_over() -> int:
	_mutex.lock()
	var n := _orphans.size() + _left_tasks.size()
	_mutex.unlock()
	return n


## How many reads are handed to the loader, and how many wait (for a test or a report).
static func counts() -> Vector2i:
	_mutex.lock()
	var out := Vector2i(_reading.size(), _queue.size())
	_mutex.unlock()
	return out


## Hands queued requests to the loader while fewer than `limit()` are being read. Called every frame
## while anything waits, and by `request`, `status` and `take`.
static func pump() -> void:
	_mutex.lock()
	for p: String in _reading.keys():
		if ResourceLoader.load_threaded_get_status(p) != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_reading.erase(p)
			if StartupTrace.detailed:
				StartupTrace.detail("load done: %s" % p)
	var collect: Array[String] = []
	for p: String in _orphans.keys():
		if ResourceLoader.load_threaded_get_status(p) != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_orphans.erase(p)
			collect.append(p)
	var finished: Array = []
	for i in range(_left_tasks.size() - 1, -1, -1):
		var t: Array = _left_tasks[i]
		var id := int(t[0])
		if WorkerThreadPool.is_group_task_completed(id) if bool(t[1]) else WorkerThreadPool.is_task_completed(id):
			finished.append(t)
			_left_tasks.remove_at(i)
	while not _queue.is_empty() and _reading.size() + _orphans.size() < limit():
		var p := _queue[0]
		_unqueue(p)
		if ResourceLoader.load_threaded_request(p) == OK:
			_reading[p] = true
	_mutex.unlock()
	# outside the lock: finished, so none of these waits
	for p in collect:
		if ResourceLoader.load_threaded_get_status(p) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_get(p)
	for t: Array in finished:
		if bool(t[1]):
			WorkerThreadPool.wait_for_group_task_completion(int(t[0]))
		else:
			WorkerThreadPool.wait_for_task_completion(int(t[0]))
		var done: Callable = t[3]
		if done.is_valid():
			done.call()


static func _unqueue(path: String) -> void:
	_queued.erase(path)
	var i := _queue.find(path)
	if i >= 0:
		_queue.remove_at(i)


## The queue is pumped once a frame from the main thread, whoever asked.
static func _ensure_ticking() -> void:
	if _ticking:
		return
	_ticking = true
	_start_ticking.call_deferred()


static func _start_ticking() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		_ticking = false
		return
	if not tree.process_frame.is_connected(pump):
		tree.process_frame.connect(pump)
	if not tree.root.tree_exiting.is_connected(drain):
		tree.root.tree_exiting.connect(drain)


## At quit: the queue is dropped, and every read handed to the loader that has finished is taken
## while the worker pool still runs, so nothing of ours is left in the loader for the engine's
## cleanup. One still going is waited for a little (DRAIN_WAIT_MS in all), and then left: a quit
## that waits for ever on a read that waits for a frame is a window whose X does nothing.
## (On lavapipe here the game still hung in that cleanup with the pool idle, before and after this;
## docs/FIRST_LAUNCH.md.)
static func drain() -> void:
	_mutex.lock()
	_queue.clear()
	_queued.clear()
	var handed: Array = _reading.keys() + _orphans.keys()
	_reading.clear()
	_orphans.clear()
	var tasks := _left_tasks.duplicate()
	_left_tasks.clear()
	_mutex.unlock()
	var until := Time.get_ticks_msec() + DRAIN_WAIT_MS
	var left: Array[String] = []
	for p: String in handed:
		while ResourceLoader.load_threaded_get_status(p) == ResourceLoader.THREAD_LOAD_IN_PROGRESS and Time.get_ticks_msec() < until:
			OS.delay_msec(5)
		var st := ResourceLoader.load_threaded_get_status(p)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			left.append(p)
		elif st != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_get(p)
	for t: Array in tasks:
		var id := int(t[0])
		var group := bool(t[1])
		while not (WorkerThreadPool.is_group_task_completed(id) if group else WorkerThreadPool.is_task_completed(id)) \
				and Time.get_ticks_msec() < until:
			OS.delay_msec(5)
		if WorkerThreadPool.is_group_task_completed(id) if group else WorkerThreadPool.is_task_completed(id):
			if group:
				WorkerThreadPool.wait_for_group_task_completion(id)
			else:
				WorkerThreadPool.wait_for_task_completion(id)
		else:
			left.append("task %d" % id)
	if not left.is_empty():
		StartupTrace.note("quit: %d reads still going were left to the engine: %s" % [left.size(), ", ".join(left.slice(0, 6))])
