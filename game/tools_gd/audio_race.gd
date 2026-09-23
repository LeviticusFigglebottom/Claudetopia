extends SceneTree
## Reproduces the engine's audio crash: a playback's bus details freed under the mixing thread.
##
##   godot --headless --path game --audio-driver Dummy --fixed-fps 60 \
##       --script res://tools_gd/audio_race.gd -- [--seconds=60] [--players=24] [--silent]
##       [--realtime] [--churn] [--audio-guard]
##
## Every AudioStreamPlayer3D that is playing hands the AudioServer new bus details every physics
## frame (_update_panning -> set_playback_bus_volumes_linear; it compares a mix count it never
## records, so it does not wait for a mix), and so does every write to a playing player's volume;
## the old ones go to a graveyard that AudioServer::update() empties two main-loop frames later,
## whatever the mixing thread is doing. The mixing thread loads a playback's details and then
## copies them; descheduled between the two while the main loop runs two frames, it copies freed
## memory and dies in StringName's copy constructor (the crash `./run.sh fights` met, the same
## backtrace all four times).
##
## On its own this rarely crashes: the gap is a few instructions. With tools/debug/stall_mixer.py
## holding only the mixing thread at that instruction, it crashes at once: unpaced frames at the
## first 30 ms stall; frames paced at 60 a second (`--realtime`) at the first 20 ms stall, and
## after 57 of 10 ms. `--audio-guard` turns on the guard (systems/audio/audio_guard.gd) that
## closes the race for unpaced runs. `--churn` allocates and frees memory the size of a set of bus
## details, filled with 0xFF, as a game does between mixes (freed memory nobody reuses reads back
## intact); `--silent` plays nothing (the control).

var _players: Array[AudioStreamPlayer3D] = []
var _streams: Array[AudioStream] = []
var _seconds := 60.0
var _silent := false
var _t := 0.0
var _frames := 0
var _plays := 0
var _started := 0
var _churn := false
var _junk: Array[PackedByteArray] = []


func _initialize() -> void:
	var count := 24
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seconds="):
			_seconds = float(a.substr(10))
		elif a.begins_with("--players="):
			count = int(a.substr(10))
		elif a == "--silent":
			_silent = true
		elif a == "--churn":
			_churn = true
		elif a == "--realtime":
			Engine.max_fps = 60
	for i in 4:
		var s := load("res://assets/audio/sfx/footstep_stone/footstep_stone_0%d.ogg" % (i + 1)) as AudioStream
		if s != null:
			_streams.append(s)
	var root3d := Node3D.new()
	root.add_child(root3d)
	var cam := Camera3D.new()
	root3d.add_child(cam)
	cam.current = true
	for i in count:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 60.0
		root3d.add_child(p)
		p.position = Vector3(float(i % 6) * 2.0 - 5.0, 0.0, -2.0 - float(i / 6) * 2.0)
		_players.append(p)
	_started = Time.get_ticks_msec()
	print("AUDIO_RACE | %d players, %s, %.0f s, frames %s%s" % [count, "silent" if _silent else "playing",
			_seconds, "paced at 60/s" if Engine.max_fps > 0 else "unpaced", ", with allocation churn" if _churn else ""])


func _process(delta: float) -> bool:
	_t += delta
	_frames += 1
	for i in _players.size():
		var p := _players[i]
		# keep every one playing, and moving, so each hands over new bus details every mix
		p.position.x = sin(_t * 3.0 + float(i)) * 6.0
		if not _silent and not p.playing and not _streams.is_empty():
			p.stream = _streams[(i + _frames) % _streams.size()]
			p.play()
			_plays += 1
	# What a game does between mixes: allocate and free. A freed set of bus details is only fatal
	# once something else has written over it; churn in its size class (about 250 bytes) filled
	# with 0xFF stands for the game's own traffic.
	if _churn:
		for k in 8:
			var junk := PackedByteArray()
			junk.resize(200 + (k * 16))
			junk.fill(255)
			_junk.append(junk)
		while _junk.size() > 64:
			_junk.pop_front()
	var wall := float(Time.get_ticks_msec() - _started) / 1000.0
	if wall >= _seconds:
		print("AUDIO_RACE | survived %.0f s: %d frames, %d plays" % [wall, _frames, _plays])
		return true
	return false
