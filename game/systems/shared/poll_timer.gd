class_name PollTimer
extends RefCounted
## "Is it time to look again?", on whichever clock gets there first: the engine's delta or the wall.
##
## The engine's delta is not the wall clock on a machine that cannot keep up. Below about seven
## frames a second Godot slows the whole game rather than step physics more than eight times a
## frame, so a five-second frame arrives as an eighth of a second. A look every three quarters of a
## second of game time then came round once in half a minute (PROGRESS, the opening's third-shot
## stall). The delta still counts on its own, so a run at a fixed frame rate (`--fixed-fps`), which
## simulates faster than the wall, looks as often as it always did.

var seconds := 1.0
var _since := 0.0
var _last_ms := -1


func _init(every_seconds: float) -> void:
	seconds = every_seconds


## Whether a look is due now. Counts `delta`, and when a look is due starts the next wait.
func due(delta: float) -> bool:
	_since += delta
	var now := Time.get_ticks_msec()
	if _last_ms < 0:
		_last_ms = now
	if _since < seconds and float(now - _last_ms) < seconds * 1000.0:
		return false
	_since = 0.0
	_last_ms = now
	return true
