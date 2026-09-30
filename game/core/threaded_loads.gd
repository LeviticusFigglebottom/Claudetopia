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

static var _mutex := Mutex.new()
## Paths asked for and not yet handed to the loader, oldest first.
static var _queue: PackedStringArray = PackedStringArray()
static var _queued: Dictionary = {}
## Paths handed to the loader and not yet seen finished.
static var _reading: Dictionary = {}
static var _ticking := false
## For a test: 0 is the machine's own limit.
static var limit_override := 0


## How many reads at once: fewer than the worker pool's threads by two, so a compile always has a
## thread (1 on a two-thread machine, at most 4).
static func limit() -> int:
	if limit_override > 0:
		return limit_override
	var pool := int(ProjectSettings.get_setting("threading/worker_pool/max_threads", -1))
	if pool <= 0:
		pool = OS.get_processor_count()
	return clampi(pool - 2, 1, 4)


## Asks for `path` to be read on the loader's threads, now or when a read ends. OK, or the loader's
## refusal when it was handed over at once.
static func request(path: String) -> Error:
	_mutex.lock()
	var err := OK
	if not _queued.has(path) and not _reading.has(path):
		if _reading.size() < limit():
			err = ResourceLoader.load_threaded_request(path)
			if err == OK:
				_reading[path] = true
		else:
			_queue.append(path)
			_queued[path] = true
	_mutex.unlock()
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
	_reading.erase(path)
	_mutex.unlock()
	pump()
	if queued:
		return ResourceLoader.load(path)
	return ResourceLoader.load_threaded_get(path)


## A request nobody will take: dropped if still queued, taken off the loader if it was handed over.
static func forget(path: String) -> void:
	_mutex.lock()
	var queued := _queued.has(path)
	if queued:
		_unqueue(path)
	var handed := _reading.has(path)
	_reading.erase(path)
	_mutex.unlock()
	if handed and ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		ResourceLoader.load_threaded_get(path)
	pump()


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
	while not _queue.is_empty() and _reading.size() < limit():
		var p := _queue[0]
		_unqueue(p)
		if ResourceLoader.load_threaded_request(p) == OK:
			_reading[p] = true
	_mutex.unlock()


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


## At quit: the queue is dropped and every read handed to the loader is waited for and taken while
## the worker pool still runs, so nothing of ours is left in the loader for the engine's cleanup.
## (On lavapipe here the game still hung in that cleanup with the pool idle, before and after this;
## docs/FIRST_LAUNCH.md.)
static func drain() -> void:
	_mutex.lock()
	_queue.clear()
	_queued.clear()
	var handed: Array = _reading.keys()
	_reading.clear()
	_mutex.unlock()
	for p: String in handed:
		if ResourceLoader.load_threaded_get_status(p) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_get(p)
