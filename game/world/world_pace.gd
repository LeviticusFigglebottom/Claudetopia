class_name WorldPace
extends RefCounted
## The main thread's time, a frame, for standing the world up a piece at a time: one budget shared by
## everything that builds it while something is drawn -- the streamer's cells (WorldStreamer), the
## towns (Settlement, WorldDoors), the skyline (HorizonLayer) -- so that together they never make a
## frame longer than the budget says, however many of them are at work (TRIAGE item 36).
##
## Two budgets. A frame someone is watching -- the title's menu, a film playing, play -- gets
## WATCHED_USEC. A frame under a curtain -- the loading fade, a film's black hold -- gets
## CURTAIN_USEC: nobody is watching the world, only a caption and a bell, and the country is wanted
## quickly. On a machine whose frames are long anyway (a software renderer, where a frame is
## seconds) a budget of a few milliseconds would take minutes to build a forest, so the budget is at
## least a share of what the last frame cost besides the building (`note_frame`).
##
## The frame is the engine's process frame: physics ticks and the process step of one main-loop
## iteration share a count (Engine.get_process_frames), so a builder in either spends from the same
## budget. Headless (the unit suite) nothing paces: `paced()` is false and everything is built at once.

const WATCHED_USEC := 4000
const CURTAIN_USEC := 12000
## On a slow machine, building may make a watched frame this much longer than it already is, and a
## curtained one this much (PROGRESS "The fade lifts as soon as it did").
const WATCHED_SHARE := 0.25
const CURTAIN_SHARE := 1.0
## However long frames are, no longer than this: a long frame lengthens the next budget, and a frame
## made long by one big piece of building (a place, a person stood up) grew the next into 25 cells
## in one frame of 0.7 s under a film's black (TRIAGE item 36).
const WATCHED_MAX_USEC := 50000
const CURTAIN_MAX_USEC := 100000

## Whether building is paced at all: not headless (nothing is drawn, and the suite builds dozens of
## worlds as fast as it can). A tool may turn it on headless (1) to measure what the game costs the
## main thread with no renderer at all: the CPU probe's --cpu-headless (tools_gd/cpu_probe.gd).
static var paced_override := -1
## Whether something besides the loading fade asks for the curtain's budget (a film's black).
static var curtain_asked := 0
## Whether the menu is up over whatever is built (the title): never the curtain's budget, however
## dark the picture behind it is, because the menu is being used.
static var menu_up := 0

static var _frame := -1
static var _used_us := 0
## What the last frames cost besides building (microseconds): the shorter of the last two, so one
## long frame among quick ones is a hitch and not the machine.
static var _frame_cost_us := 0
static var _prev_cost_us := 0
## For the accounts: what was built each frame, and the most in one.
static var worst_frame_us := 0


static func paced() -> bool:
	if paced_override >= 0:
		return paced_override == 1
	return DisplayServer.get_name() != "headless"


static func _roll() -> void:
	var f := Engine.get_process_frames()
	if f != _frame:
		# what the frame before this spent, or nothing if nothing was built in it
		_prev_used_us = _used_us if f == _frame + 1 else 0
		_frame = f
		_used_us = 0


static var _prev_used_us := 0


## What the last frame spent building (for what that frame cost besides: WorldStreamer).
static func last_frame_used_usec() -> int:
	_roll()
	return _prev_used_us


## Whether this frame is under a curtain: the loading fade, or a film's black (`curtain_asked`),
## and no menu over it.
static func curtained() -> bool:
	if menu_up > 0:
		return false
	return curtain_asked > 0 or UI.is_faded_out()


## This frame's budget, in microseconds.
static func budget_usec() -> int:
	if curtained():
		return clampi(int(float(_frame_cost_us) * CURTAIN_SHARE), CURTAIN_USEC, CURTAIN_MAX_USEC)
	return clampi(int(float(_frame_cost_us) * WATCHED_SHARE), WATCHED_USEC, WATCHED_MAX_USEC)


## What is left of this frame's budget (negative once it is overspent).
static func left_usec() -> int:
	_roll()
	return budget_usec() - _used_us


static func used_usec() -> int:
	_roll()
	return _used_us


## Something built for `us` microseconds this frame.
static func spend(us: int) -> void:
	_roll()
	_used_us += maxi(us, 0)
	worst_frame_us = maxi(worst_frame_us, _used_us)


## What a frame just cost besides the building in it (WorldStreamer measures it each frame).
static func note_frame(cost_us: int) -> void:
	_frame_cost_us = mini(cost_us, _prev_cost_us) if _prev_cost_us > 0 else cost_us
	_prev_cost_us = cost_us


## What each kind of paced piece has cost: name -> [pieces, total ms, longest ms] (the CPU probe).
static var pieces: Dictionary = {}


## This frame's paced pieces, name -> ms (the CPU probe reads it at the end of the frame).
static var frame_pieces: Dictionary = {}
static var _pieces_frame := -1
## Every paced piece built so far, of any kind: the loading caption's watch reads a load whose count
## still goes up as moving (UI.LOADING_QUIET_S).
static var built := 0


static func count(what: String, us: int) -> void:
	if what.is_empty():
		return
	built += 1
	var ms := us / 1000.0
	if _pieces_frame != Engine.get_process_frames():
		_pieces_frame = Engine.get_process_frames()
		frame_pieces = {}
	frame_pieces[what] = float(frame_pieces.get(what, 0.0)) + ms
	var st: Array = pieces.get(what, [0, 0.0, 0.0])
	pieces[what] = [int(st[0]) + 1, snappedf(float(st[1]) + ms, 0.1), snappedf(maxf(float(st[2]), ms), 0.1)]


## Awaits the next frame; a builder that has spent the frame's budget waits here.
static func next_frame() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


## A slice of work a builder times itself: `Slice.new()`, work, then `await slice.pace()` between
## pieces. The time since the last pace is spent from the frame's budget, and once it is gone the
## builder waits for the next frame. Not paced (headless), it never waits.
class Slice:
	extends RefCounted
	var t0 := 0
	var on := true

	func _init(paced_now := true) -> void:
		on = paced_now and WorldPace.paced()
		t0 = Time.get_ticks_usec()

	## True when this slice has spent the frame's budget and should wait for the next. `what` names
	## the piece just done, for the accounts (`WorldPace.pieces`).
	func due(what := "") -> bool:
		if not on:
			return false
		var now := Time.get_ticks_usec()
		WorldPace.spend(now - t0)
		WorldPace.count(what, now - t0)
		t0 = now
		return WorldPace.left_usec() <= 0

	func pace(what := "") -> void:
		if due(what):
			await WorldPace.next_frame()
			t0 = Time.get_ticks_usec()
