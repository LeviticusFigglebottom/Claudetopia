class_name WallTweens
extends RefCounted
## Tweens that keep the wall clock, for words that have to be read.
##
## A Tween runs on the engine's delta, and that is not the wall clock on a machine that cannot keep
## up. Below about seven frames a second Godot slows the whole game rather than step physics more
## than eight times a frame, so a five-second frame counts as an eighth of a second. A subtitle's
## third of a second of fading in then took several frames, and the frame the player looked at had
## the line still faint, or never fully in before the next one replaced it. A tween handed to
## `own()` is paused and moved on by `step()` with the time that really passed. On a quick machine
## that is the same thing.
##
## The owner calls `step()` once a frame from its own `_process`, so a paused tree still holds
## what it holds.

var _tweens: Array[Tween] = []
var _last_usec := 0


## Takes a tween over: it stops following the engine's delta and goes by the wall clock instead.
func own(tween: Tween) -> Tween:
	tween.pause()
	_tweens.append(tween)
	return tween


## Moves every tween it owns on by the wall-clock time since the last call.
func step() -> void:
	var now := Time.get_ticks_usec()
	var dt := 0.0 if _last_usec == 0 else float(now - _last_usec) / 1000000.0
	_last_usec = now
	if _tweens.is_empty():
		return
	var live: Array[Tween] = []
	for t in _tweens:
		if t != null and t.is_valid() and t.custom_step(dt):
			live.append(t)
	_tweens = live
