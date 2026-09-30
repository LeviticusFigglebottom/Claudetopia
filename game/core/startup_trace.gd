class_name StartupTrace
extends RefCounted
## One line per step of the game starting, written to disk the moment it happens, so a launch that
## hangs leaves a file whose last line says where (docs/FIRST_LAUNCH.md, "If the title freezes").
##
##   user://logs/startup_<date>_<time>.txt     the last KEEP of them are kept
##
## Every line has the seconds since the game started, the milliseconds since the line before, the
## thread that wrote it, what happened, and the memory then: the engine's own allocations (static),
## the rendering server's video memory where the main thread can ask for it cheaply, and what the
## machine still has free. The file is flushed after every line, so a game killed from the Task
## Manager still has every line it wrote.
##
## The trace is on from boot until a game's world is ready (`finish`): after that `step` returns at
## once and costs nothing. The threaded reads (hundreds of them) are written until the title's first
## shot is shown (`details_done`), and the title's clicks and what they tear down after it: the
## freeze a player met was a click on a title that looked fine. The watchdog (Startup) goes on
## writing its stall lines into the same file for as long as the game runs (`note`).
##
## Any thread may call any of these: the region files are read on worker threads and say so.

const DIR := "user://logs"
const PREFIX := "startup_"
const KEEP := 10
const MB := 1048576.0

## Whether `step` writes: from `begin` until `finish`.
static var active := false
## Whether `detail` writes (every threaded read): from `begin` until `details_done` or `finish`.
static var detailed := false
## The file this launch writes, "" before `begin` (and in a headless run, which writes none).
static var path := ""
## What the main thread's last step was, for the watchdog's stall line.
static var last_step := ""
## Whether each line is also printed (the console the tester ran it from).
static var echo := true

static var _file: FileAccess = null
static var _mutex := Mutex.new()
static var _t0_us := 0
static var _last_us := 0
static var _lines := 0


## Opens this launch's file in `dir` and drops the oldest past KEEP. The path, or "" when it could
## not be opened.
static func begin(dir := DIR) -> String:
	_mutex.lock()
	if _file != null:
		_file.close()
		_file = null
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	var file_name := "%s%s.txt" % [PREFIX, stamp]
	var n := 1
	while FileAccess.file_exists("%s/%s" % [dir, file_name]):
		n += 1
		file_name = "%s%s_%d.txt" % [PREFIX, stamp, n]
	path = "%s/%s" % [dir, file_name]
	_file = FileAccess.open(path, FileAccess.WRITE)
	active = _file != null
	detailed = active
	_t0_us = Time.get_ticks_usec()
	_last_us = _t0_us
	_lines = 0
	last_step = ""
	_mutex.unlock()
	if active:
		prune(dir, KEEP)
	else:
		path = ""
	return path


## One step: written, flushed and printed while the trace is on; nothing at all after `finish`.
static func step(what: String) -> void:
	if not active:
		return
	var main := OS.get_thread_caller_id() == OS.get_main_thread_id()
	if main:
		_mutex.lock()
		last_step = what
		_mutex.unlock()
	_write(what, memory(main), echo)


## A step written to the file and not printed: one of the hundreds of threaded reads.
static func detail(what: String) -> void:
	if not detailed:
		return
	var main := OS.get_thread_caller_id() == OS.get_main_thread_id()
	_write(what, memory(main), false)


## A line whether or not the trace is still on (the watchdog's), as long as the file is open.
static func note(what: String, mem := "") -> void:
	_write(what, mem if not mem.is_empty() else memory(false), echo)


## The trace is done: one last line, and `step` costs nothing from here on. The file stays open for
## the watchdog's lines.
static func finish(why: String) -> void:
	if not active:
		return
	step("trace ends: %s (%d lines)" % [why, _lines + 1])
	active = false
	detailed = false


## The threaded reads are no longer written; the steps go on.
static func details_done(why: String) -> void:
	if not detailed:
		return
	detailed = false
	step("threaded reads are no longer traced: %s" % why)


## Closes the file (the game is ending).
static func close() -> void:
	_mutex.lock()
	active = false
	detailed = false
	if _file != null:
		_file.close()
		_file = null
	_mutex.unlock()


## The step the trace last wrote, safely from any thread.
static func last() -> String:
	_mutex.lock()
	var s := last_step
	_mutex.unlock()
	return s


## Memory now, in words. The engine's allocations can be asked from any thread; the rendering
## server's video memory only from the main thread (`with_video`).
static func memory(with_video: bool) -> String:
	var out := "static %.0f MB" % (OS.get_static_memory_usage() / MB)
	if with_video:
		out += ", perf %.0f MB" % (Performance.get_monitor(Performance.MEMORY_STATIC) / MB)
		out += ", video %.0f MB" % (RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / MB)
	var info := OS.get_memory_info()
	if int(info.get("available", -1)) > 0:
		out += ", machine free %.0f MB" % (int(info["available"]) / MB)
	return out


## Keeps the newest `keep` startup files in `dir` (their names sort by when they were written).
static func prune(dir: String, keep: int) -> void:
	var files: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.begins_with(PREFIX) and f.ends_with(".txt"):
			files.append(f)
	files.sort()
	while files.size() > keep:
		var old: String = files.pop_front()
		DirAccess.remove_absolute("%s/%s" % [dir, old])


## "[  12.34 s] +  120 ms  main  what  | memory"
static func format(t_s: float, dt_ms: int, thread: String, what: String, mem: String) -> String:
	return "[%8.2f s] +%6d ms  %-6s %s%s" % [t_s, dt_ms, thread, what, ("  | " + mem) if not mem.is_empty() else ""]


static func _write(what: String, mem: String, printed: bool) -> void:
	var main := OS.get_thread_caller_id() == OS.get_main_thread_id()
	var thread := "main" if main else "t%d" % (OS.get_thread_caller_id() % 100000)
	_mutex.lock()
	if _file == null:
		_mutex.unlock()
		return
	var now := Time.get_ticks_usec()
	var line := format((now - _t0_us) / 1000000.0, roundi((now - _last_us) / 1000.0), thread, what, mem)
	_last_us = now
	_lines += 1
	_file.store_line(line)
	_file.flush()
	_mutex.unlock()
	if printed:
		print("I [Startup] " + line)
