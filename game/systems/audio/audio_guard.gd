class_name AudioGuard
extends Node
## Keeps the engine from freeing a sound's bus details while its mixing thread is still reading
## them: the crash that killed the fights, a headless unit run and a Forward+ world load, and that
## can kill the game.
##
## Whenever a playing sound's volume or panning changes, Godot 4.7.2's AudioServer swaps in new
## "bus details" for it and puts the old ones in a graveyard that AudioServer.update() (once per
## main-loop frame, after processing) frees two updates later, whatever the mixing thread is doing.
## Every AudioStreamPlayer3D that is playing makes such a swap every physics frame (it compares a
## mix count it never records). The mixing thread loads a sound's details and then copies them;
## descheduled between the two while the main loop runs a frame or two, it copies freed memory and
## dies in StringName's copy constructor (AudioServer::_mix_step, from _driver_process). The crash
## handler, running on that thread, then reports "/root: The caller thread can't call the function
## `propagate_notification()`". `tools_gd/audio_race.gd` with `tools/debug/stall_mixer.py`
## reproduces it in seconds by holding the mixing thread at that instruction; unguarded it
## crashes with frames unpaced (`--fixed-fps`) and paced at 60 a second alike.
##
## The guard stands between frames: at the end of each frame's processing it takes the audio
## driver's lock and lets it go at once. The mixing thread holds that lock for the whole of a mix,
## so this waits out a mix that is under way and holds nothing. Everything a later update() frees
## was swapped out before this barrier, so any mix that loaded it started before the barrier and
## has ended by it; a mix that starts after the barrier loads only the details that are current.
## The cost is a frame that waits for a mix already under way (a millisecond or two, or as long as
## the mixer is descheduled: a hitch where the engine would have crashed).

## Whether the guard stands between frames. On unless a run says `-- --no-audio-guard` (which the
## reproduction uses to show the crash it prevents).
var active := true
## How many frames it has stood between.
var barriers := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Last of everything processed in a frame: the swaps a frame makes are all behind it, and only
	# the deferred calls, navigation, the render sync and AudioServer.update() come after it.
	process_priority = 1 << 30
	active = not OS.get_cmdline_user_args().has("--no-audio-guard")


func _process(_delta: float) -> void:
	if active:
		barrier()


## Waits out a mix that is under way, and holds nothing.
func barrier() -> void:
	AudioServer.lock()
	AudioServer.unlock()
	barriers += 1


## Moves a player's volume `step` dB toward `target`, and writes it only when it moves; true when
## it wrote. Every write to a playing player's volume hands the AudioServer new bus details and
## leaves the old in the graveyard above; music stems and ambience beds sit at their level most of
## the time, and were rewritten every frame regardless.
static func ease_volume(p: AudioStreamPlayer, target: float, step: float) -> bool:
	var v := move_toward(p.volume_db, target, step)
	if v == p.volume_db:
		return false
	p.volume_db = v
	return true
