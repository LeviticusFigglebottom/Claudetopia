extends SceneTree
## Does each DISTINCT stream that is played leave a playback behind, even after stop()?
func _init() -> void:
	var p := AudioStreamPlayer.new()
	root.add_child(p)
	var n := int(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 1
	var files := ["bell_hand", "bell_tavern", "coins_few", "eat", "pick_up"]
	for i in mini(n, files.size()):
		p.stop()
		p.stream = load("res://assets/audio/sfx/%s/%s_01.ogg" % [files[i], files[i]])
		p.play()
	p.stop()
	p.stream = null
	print("PROBE played %d distinct streams" % mini(n, files.size()))
	quit()
