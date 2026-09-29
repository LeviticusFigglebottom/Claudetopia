extends TestCase
## Triage 2026-09-27 #53: "the rogue starter area has a very weird ambient noise of buzzing and
## glitching noises". Two ways a place can buzz: a stream started again and again (a play() in a
## per-frame path restarts the same sound dozens of times a second, which is heard as a buzz),
## and a bed that is itself harsh. This file guards the first everywhere and the Moreva night in
## particular; tools/audio/tests guards the second (the marsh beds' own measurements).
##
## A start is counted when a player goes from silent to playing, is handed another stream, or
## its playback position jumps back. A player held at the very start of its stream frame after
## frame is counted too (a play() every frame never gets past the first few milliseconds).

const TICK := 1.0 / 60.0
## What any one stream may do in 30 s: a pool's variant comes round a few times at most, a bed
## starts once.
const MOST_STARTS := 6

var _world: World = null
## node path -> {"playing", "stream", "pos", "stuck"}
var _seen: Dictionary = {}
## stream path (or node path for an unnamed stream) -> starts
var starts: Dictionary = {}
var stuck: Dictionary = {}
var foley: Dictionary = {}


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _built() -> bool:
	return FileAccess.file_exists("res://world/generated/world_manifest.json")


func before_each() -> void:
	_seen.clear()
	starts.clear()
	stuck.clear()
	foley.clear()


func after_each() -> void:
	if Foley.played.is_connected(_on_foley):
		Foley.played.disconnect(_on_foley)
	if _world != null and is_instance_valid(_world):
		_tree().root.remove_child(_world)
		_world.queue_free()
	_world = null
	Ambience.set_weather_override({})
	Social.quests.call("reset_for_new_game")
	GameState.reset_for_new_game(53)


func _on_foley(id: String, _at: Variant = null) -> void:
	foley[id] = int(foley.get(id, 0)) + 1


static func _players(n: Node, out: Array) -> void:
	if n is AudioStreamPlayer or n is AudioStreamPlayer2D or n is AudioStreamPlayer3D:
		out.append(n)
	for c in n.get_children():
		_players(c, out)


## One look at every player in the tree; counts what started since the last look.
func _look() -> void:
	var all: Array = []
	_players(_tree().root, all)
	for p: Node in all:
		var path := str(p.get_path())
		var playing := bool(p.get("playing"))
		var stream: AudioStream = p.get("stream")
		var pos: float = float(p.call("get_playback_position")) if playing else 0.0
		var was: Dictionary = _seen.get(path, {"playing": false, "stream": null, "pos": 0.0, "stuck": 0})
		var key := stream.resource_path if stream != null and not stream.resource_path.is_empty() else path
		var started: bool = playing and (not bool(was["playing"]) or was["stream"] != stream or pos + 0.05 < float(was["pos"]))
		if started:
			starts[key] = int(starts.get(key, 0)) + 1
		var held: int = int(was["stuck"]) + 1 if playing and not started and pos < 0.02 and stream != null and stream.get_length() > 0.2 else 0
		if held == 30:
			stuck[key] = true
		_seen[path] = {"playing": playing, "stream": stream, "pos": pos, "stuck": held}


func _listen(seconds: float) -> void:
	for i in int(seconds / TICK):
		_look()
		await _tree().physics_frame


func _report() -> String:
	var keys := starts.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(starts[a]) > int(starts[b]))
	var lines: Array[String] = []
	for k in keys:
		lines.append("%4d  %s" % [int(starts[k]), str(k)])
	for k in foley.keys():
		lines.append("foley %4d  %s" % [int(foley[k]), str(k)])
	return "\n".join(lines)


func _assert_calm(where: String) -> void:
	print("[restarts] %s, 30 s:\n%s" % [where, _report()])
	for k in starts.keys():
		assert_true(int(starts[k]) <= MOST_STARTS, "%s: %s started %d times in 30 s" % [where, str(k), int(starts[k])])
	for k in stuck.keys():
		fail("%s: %s is held at its first moments, started again every frame" % [where, str(k)])
	for k in foley.keys():
		assert_true(int(foley[k]) <= 20, "%s: the foley %s played %d times in 30 s" % [where, str(k), int(foley[k])])


## The marsh at 05:00 in mist, the mixer alone: every bed starts once and stays started, the pools
## come round at their gaps.
func test_the_marsh_before_dawn_starts_each_sound_once_or_a_few_times() -> void:
	WorldClock.set_time(5.0)
	Ambience.set_weather_override({"id": "core:weather/mist", "precipitation": "none", "precip_intensity": 0.0, "wind": 0.1})
	Ambience.set_region("core:region/sedgemire")
	await _listen(30.0)
	assert_true(Ambience.active_layers().size() >= 3, "the marsh has its layers: %s" % str(Ambience.active_layers()))
	_assert_calm("Sedgemire, the mixer")


## What is sounding, and how loud each bus is, while the music rests: every player that is
## playing, with its bus, level and stream, and every bus with its level, peak and effects.
func _heard() -> String:
	var all: Array = []
	_players(_tree().root, all)
	var lines: Array[String] = []
	for p: Node in all:
		if not bool(p.get("playing")):
			continue
		var stream: AudioStream = p.get("stream")
		lines.append("  %-9s %6.1f dB  %s  (%s)" % [str(p.get("bus")), float(p.get("volume_db")),
			stream.resource_path.get_file() if stream != null else "-", str(p.name)])
	for i in AudioServer.bus_count:
		var fx: Array[String] = []
		for e in AudioServer.get_bus_effect_count(i):
			if AudioServer.is_bus_effect_enabled(i, e):
				fx.append(AudioServer.get_bus_effect(i, e).get_class())
		lines.append("  bus %-9s %6.1f dB%s  peak %6.1f dB  %s" % [AudioServer.get_bus_name(i),
			AudioServer.get_bus_volume_db(i), " MUTED" if AudioServer.is_bus_mute(i) else "",
			AudioServer.get_bus_peak_volume_left_db(i, 0), str(fx)])
	return "\n".join(lines)


## A class's start as it is played, on the built world, into a rest in the music: the story
## begun, the body on its ground, the score's piece ended and the rotation's silence begun.
func _start(style: String, calling: String, hour: float, quest: String) -> bool:
	if not _built():
		skip("no built world")
		return false
	GameState.reset_for_new_game(53)
	Social.quests.call("reset_for_new_game")
	GameState.set_flag(StyleDef.FLAG, style)
	GameState.set_flag(Openings.STYLE_START, true)
	GameState.set_flag("player_name", "Hesk")
	GameState.set_flag("player_calling", calling)
	GameState.set_flag(Openings.STYLE_DUE, true)
	WorldClock.set_time(hour)
	_world = (load("res://world/world.tscn") as PackedScene).instantiate() as World
	_tree().root.add_child(_world)
	await _world.world_ready
	for i in 600:
		if bool(Social.quests.call("is_active", quest)):
			break
		await _tree().physics_frame
	# the score has taken up the region the body stands in (the handover can come a moment later)
	for i in 600:
		if not Music.current_region_id.is_empty() and Music.current_region_id == GameState.current_region_id:
			break
		await _tree().physics_frame
	await _listen(2.0)
	# the piece ends and the music rests, as it does 70 % of the time after two minutes
	Music.next_piece(90.0)
	print("[restarts] music: region %s, piece '%s', resting %s, mode %s, cue %s" % [Music.current_region_id,
		Music.current_piece(), str(Music.in_gap()), Music.mode, Music.overlay_kind()])
	await _listen(4.0)
	Foley.played.connect(_on_foley)
	_look()
	starts.clear()
	return true


## Nothing in the music's rest but the place: every music player silent, and nothing the place
## plays started over and over.
func _assert_the_rest_is_the_place(where: String) -> void:
	print("[restarts] %s, in the music's rest:\n%s" % [where, _heard()])
	assert_true(Music.in_gap(), "the music is resting")
	var all: Array = []
	_players(Music, all)
	for p: Node in all:
		if bool(p.get("playing")):
			assert_true(float(p.get("volume_db")) <= Music.SILENCE_DB,
				"%s: the music's %s still sounds at %.1f dB in the rest" % [where, str(p.name), float(p.get("volume_db"))])
	_assert_calm(where)


## The Rogue's start: Moreva before dawn, the quest's mist, crouched on the boards with Sauve,
## Tella's watch and the props about.
func test_nothing_at_moreva_restarts_over_and_over() -> void:
	if not await _start("core:style/rogue", "core:calling/lantern_clerk", 5.4, "core:quest/first_rogue"):
		return
	var player := _world.get_node("PlayerSpawn").get("player") as Player
	if player != null:
		player.is_sneaking = true
	await _listen(30.0)
	_assert_the_rest_is_the_place("Moreva at 05:24")


## The Warrior's start (triage 53, the second report: "the same buzzing and droning in the
## warrior start when the track stopped"): Wardens' Rest in the morning.
func test_nothing_at_wardens_rest_restarts_over_and_over() -> void:
	if not await _start("core:style/warrior", "core:calling/hearthkeeper", 9.0, "core:quest/first_warrior"):
		return
	await _listen(30.0)
	_assert_the_rest_is_the_place("Wardens' Rest at 09:00")
