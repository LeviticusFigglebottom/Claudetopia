extends SceneTree
## Build the bus layout once, from code, and save it as a .tres. Run headless.
func _init() -> void:
	# Master(0), Music(1), SFX(2), Ambience(3), UI(4), Voice(5), Interior(6)
	AudioServer.set_bus_count(7)
	var names := ["Master", "Music", "SFX", "Ambience", "UI", "Voice", "Interior"]
	for i in names.size():
		AudioServer.set_bus_name(i, names[i])
		if i > 0:
			AudioServer.set_bus_send(i, "Master")
		# The project's existing layout is loaded before this runs, so effects are cleared
		# first: otherwise every run adds another copy of the reverb and the filter.
		while AudioServer.get_bus_effect_count(i) > 0:
			AudioServer.remove_bus_effect(i, 0)
		AudioServer.set_bus_volume_db(i, 0.0)
		AudioServer.set_bus_mute(i, false)
	var interior := 6
	# Interior is a bus a player is routed to while indoors, not a pure aux send: a Godot bus
	# has one output, so it has to carry the dry signal as well as the reverb.
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.58
	rev.damping = 0.6
	rev.spread = 0.85
	rev.wet = 0.38
	rev.dry = 0.72
	rev.predelay_msec = 14.0
	rev.predelay_feedback = 0.25
	AudioServer.add_bus_effect(interior, rev, 0)
	AudioServer.set_bus_volume_db(interior, -1.0)
	AudioServer.set_bus_bypass_effects(interior, false)
	# Ambience carries a low-pass for interior muffling, bypassed until indoors.
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 20000.0
	lp.resonance = 0.4
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Ambience"), lp, 0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambience"), 0.0)
	var layout := AudioServer.generate_bus_layout()
	var err := ResourceSaver.save(layout, "res://default_bus_layout.tres")
	print("saved: ", err, " buses=", AudioServer.bus_count)
	for i in AudioServer.bus_count:
		print("  ", i, " ", AudioServer.get_bus_name(i), " -> ", AudioServer.get_bus_send(i), " effects=", AudioServer.get_bus_effect_count(i))
	quit()
