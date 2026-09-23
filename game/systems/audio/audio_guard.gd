class_name AudioGuard
extends Node
## Keeps the engine from freeing a sound's bus details under the mixing thread in a run whose
## frames are not paced.
##
## Whenever a playing sound's volume or panning changes, AudioServer swaps in new "bus details"
## for it and puts the old ones in a graveyard that AudioServer.update() (once per main-loop
## frame, after processing) frees two frames later -- whatever the mixing thread is doing. The
## mixing thread loads a sound's details and then copies them; stalled between the two for two
## frames, it copies freed memory and dies (StringName's copy constructor, in
## AudioServer::_mix_step). Every AudioStreamPlayer3D that is playing makes such a swap every
## physics frame. Two frames of a game paced at 60 fps are up to 33 ms, and the mixing thread is
## seldom descheduled for that long at that instruction; under `--fixed-fps` the frames are not
## paced at all (the main loop skips its frame delay) and two of them take a millisecond or two,
## so on a busy machine the fights crashed about once in an hour or two of fighting.
## `tools_gd/audio_race.gd` with `tools/debug/stall_mixer.py` reproduces it in seconds by holding
## the mixing thread at that instruction.
##
## In such a run this holds the audio driver's lock from the end of each frame's processing to the
## start of the next frame. The mixing thread holds the same lock for the whole of a mix, so
## AudioServer.update() then never runs while a mix is under way, and nothing it frees can be in
## a mixer's hands. A paced game does not need it and must not have it: the lock would span the
## frame's sleep and starve the mixer.

## Whether the guard holds the lock at the end of each frame. On in unpaced runs.
var active := false
var _held := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Last of everything processed in a frame, so the lock spans only what runs after processing:
	# the deferred calls, navigation, the render sync and AudioServer.update() itself.
	process_priority = 1 << 30
	active = unpaced()
	var tree := get_tree()
	tree.physics_frame.connect(_release)
	tree.process_frame.connect(_release)


## Whether this run asked for the guard (`-- --audio-guard`, which `./run.sh fights` passes). The
## engine keeps `--fixed-fps` to itself, so a run cannot see that its frames are unpaced; the run
## that makes them so says it.
static func unpaced() -> bool:
	return OS.get_cmdline_user_args().has("--audio-guard")


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


func _process(_delta: float) -> void:
	if active and not _held:
		AudioServer.lock()
		_held = true


func _release() -> void:
	if _held:
		_held = false
		AudioServer.unlock()


func is_holding() -> bool:
	return _held


func _notification(what: int) -> void:
	# Never leave the lock held on the way out: shutting the audio server down waits for the mixing
	# thread, and the mixing thread would be waiting for the lock.
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_release()
