extends TestCase
## The audio as the running game drives it, rather than as its own API says it can be driven.
##
## Each test starts from the thing that really happens -- an enemy turning to fight, the world
## streamer entering a region, the clock passing nine, a door into a house, a boss crossing its
## half-health line, the Atmosphere announcing rain, a foot coming down on a wooden floor, a
## sword landing on a stone thrall -- and checks what the score, the ambience and the foley do.
## Changes of level are watched a sixtieth of a second at a time, by running the director's own
## per-frame update, so "a crossfade, not a cut" is a measurement: no player may move more than
## a few dB in one step, and the outgoing and the incoming track must both be audible at once.
##
## The last few tests are inventories: every sound the code can ask for is in the table and
## loads, every audio file on disk is used by something, every bus a sound is sent to exists,
## and the Settings screen's sliders move the buses they name.

const FakePlayer := preload("res://tests/fakes/fake_player.gd")
const STEP := 1.0 / 60.0
const SWORD := "core:item/iron_sword"
const BANDIT := "core:enemy/roadside_bandit"
const WOLF := "core:enemy/down_wolf"
const REEVE := "core:boss/barrow_reeve"
## A cut is sixty dB in a step; a fade over 1.6 s is under one. Anything above this is a jump.
const MAX_DB_PER_STEP := 3.0

var root: Node3D
var _heard: Array[String] = []
var _saved_hour := 12.0
var _saved_region := ""
var _saved_amb_region := ""


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	_saved_hour = WorldClock.time_hours
	_saved_region = GameState.current_region_id
	_saved_amb_region = Ambience.region_id
	WorldClock.set_time(12.0)
	GameState.current_region_id = ""
	GameState.current_interior_id = ""
	GameState.set_flag("new_game", false)
	Music.stop_all()
	Music.enabled = true
	Music._open_menus.clear()
	Music._boss_id = ""
	Music._refresh_mode(true)
	Ambience.enabled = true
	Ambience.interior = false
	Ambience.set_weather_override({})
	Foley.enabled = true
	root = Node3D.new()
	root.name = "AudioWired"
	_tree().root.add_child(root)
	var ground := StaticBody3D.new()
	ground.name = "Floor"
	ground.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(shape)
	root.add_child(ground)
	_heard.clear()
	Foley.played.connect(_on_played)


func after_each() -> void:
	if Foley.played.is_connected(_on_played):
		Foley.played.disconnect(_on_played)
	for a in Player.ACTIONS + ["move_forward", "move_back", "move_left", "move_right"]:
		Input.action_release(a)
	if Interiors.in_interior():
		Interiors.exit()
	Interiors.unload_all()
	if is_instance_valid(root):
		root.free()
	root = null
	Music.stop_all()
	Music._boss_id = ""
	Ambience.set_weather_override({})
	Ambience.interior = false
	Ambience.stop_all()
	GameState.current_interior_id = ""
	GameState.current_region_id = _saved_region
	if not _saved_amb_region.is_empty():
		Ambience.set_region(_saved_amb_region)
	WorldClock.set_time(_saved_hour)
	Foley.stop_all()


func _on_played(id: String, _position: Vector3) -> void:
	_heard.append(id)


func _frames(n: int) -> void:
	for i in maxi(n, 1):
		await _tree().physics_frame


func _seconds(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await _tree().physics_frame


## A body the enemies can see and the interiors can move: in the "player" group, and nothing else.
func _double() -> Node3D:
	var p := FakePlayer.new()
	root.add_child(p)
	p.global_position = Vector3(0.0, 0.05, 0.0)
	return p


## An enemy placed before it enters the tree (a body added at the origin and then moved is a floor
## that jumps under whatever stands there).
func _enemy(id: String, at: Vector3, thinking := true) -> Enemy:
	var e := Enemy.new()
	e.configure(id)
	e.position = at
	e.rotation.y = PI
	root.add_child(e)
	e.spawn_position = at
	e.brain.post = at
	if not thinking:
		e.perception.enabled = false
		e.set_physics_process(false)
	return e


func _player() -> Player:
	var p := (load("res://actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(p)
	p.global_position = Vector3(0.0, 0.02, 0.0)
	p.rotation.y = 0.0
	p.camera_rig.yaw = 0.0
	return p


# --- the score, measured a step at a time ---------------------------------------------------------

## Runs the director's own per-frame update for `seconds` at 60 Hz and records every music
## player's level after each step: {player name: [dB, ...]}. A player not playing reads silence.
func _run_music(seconds: float) -> Dictionary:
	var tracks := {}
	for i in int(round(seconds / STEP)):
		Music._process(STEP)
		for child in Music.get_children():
			if child is AudioStreamPlayer:
				var p := child as AudioStreamPlayer
				if not tracks.has(p.name):
					tracks[p.name] = []
				(tracks[p.name] as Array).append(p.volume_db if p.playing else Music.SILENCE_DB)
	return tracks


static func _largest_step(tracks: Dictionary) -> float:
	var worst := 0.0
	for name in tracks:
		var t: Array = tracks[name]
		for i in range(1, t.size()):
			worst = maxf(worst, absf(float(t[i]) - float(t[i - 1])))
	return worst


## Whether `out` went down and `in_` came up, with a stretch where both could be heard at once.
static func _crossfaded(tracks: Dictionary, out: String, in_: String, audible := -40.0) -> bool:
	var a: Array = tracks.get(out, [])
	var b: Array = tracks.get(in_, [])
	if a.is_empty() or b.is_empty():
		return false
	var both := false
	for i in mini(a.size(), b.size()):
		if float(a[i]) > audible and float(b[i]) > audible:
			both = true
	return both and float(a[a.size() - 1]) < float(a[0]) and float(b[b.size() - 1]) > float(b[0])


func test_an_enemy_turning_to_fight_brings_the_fight_in_and_its_death_lets_it_go() -> void:
	Music.play_region("core:region/hearthvale", true)
	var target := _double()
	var wolf := _enemy(WOLF, Vector3(0.0, 0.05, -6.0))
	await _frames(2)
	assert_eq(Music.mode, "explore")
	# What a noise or a blow from somewhere does: the wolf knows where you are.
	wolf.perception.alert_to(target.global_position, target)
	await _frames(3)
	assert_eq(wolf.brain.state, Brain.COMBAT, "the wolf turned to fight")
	assert_eq(Music.engaged_count(), 1, "and said so")
	var coming := _run_music(2.0)
	assert_eq(Music.mode, "combat", "the fight is in the score before any blow has landed")
	assert_near(Music.combat_intensity, Music.ENGAGED_LEVEL, 0.001)
	assert_true(_largest_step(coming) < MAX_DB_PER_STEP, "the combat stem came in, it did not cut in (%.1f dB in a step)" % _largest_step(coming))
	_run_music(12.0)
	assert_eq(Music.mode, "combat", "twelve seconds of rolling and circling is still a fight")
	wolf.die(null)
	assert_eq(Music.engaged_count(), 0, "a dead wolf is not fighting")
	var going := _run_music(6.0)
	assert_eq(Music.mode, "explore", "and the score goes back to walking")
	assert_true(_largest_step(going) < MAX_DB_PER_STEP, "the combat stem went out slowly (%.1f dB in a step)" % _largest_step(going))


func test_crossing_into_another_region_crossfades_the_score() -> void:
	# What the world streamer calls when the player crosses a border.
	GameState.enter_region("core:region/hearthvale")
	assert_eq(Music.current_region_id, "core:region/hearthvale")
	_run_music(2.0)
	var old_bank := Music._bank
	GameState.enter_region("core:region/sedgemire")
	assert_eq(Music.current_region_id, "core:region/sedgemire")
	var new_bank := Music._bank
	assert_ne(old_bank, new_bank, "the new region plays on the other bank")
	var t := _run_music(5.0)
	for stem in ["pad", "texture"]:
		assert_true(_crossfaded(t, "Bank%d_%s" % [old_bank, stem], "Bank%d_%s" % [new_bank, stem]),
			"the %s stem crossfaded from the old region to the new" % stem)
	assert_true(_largest_step(t) < MAX_DB_PER_STEP, "no stem jumped (%.1f dB in a step)" % _largest_step(t))
	assert_eq(float(t["Bank%d_pad" % old_bank].back()), Music.SILENCE_DB, "and the old region is gone at the end")


func test_night_on_the_clock_brings_the_night_mix_and_morning_takes_it_away() -> void:
	Music.play_region("core:region/hearthvale", true)
	_run_music(0.5)
	assert_eq(Music.mode, "explore")
	var melody_day := Music.stem_volume_db("melody")
	WorldClock.set_time(22.0)
	assert_eq(Music.mode, "night", "the hour changing is enough")
	var dusk := _run_music(3.0)
	assert_true(Music.stem_volume_db("melody") < melody_day - 8.0, "the melody pulls back at night (%.1f -> %.1f dB)" % [melody_day, Music.stem_volume_db("melody")])
	assert_true(Music.stem_volume_db("deep") > Music.SILENCE_DB, "and a little of the deep stem comes in")
	assert_true(_largest_step(dusk) < MAX_DB_PER_STEP, "over seconds, not at once (%.1f dB in a step)" % _largest_step(dusk))
	WorldClock.set_time(7.0)
	assert_eq(Music.mode, "explore")


func test_a_door_into_a_house_brings_the_deep_mix_the_room_and_the_door() -> void:
	_double()
	Music.play_region("core:region/hearthvale", true)
	Ambience.set_region("core:region/hearthvale")
	_run_music(0.5)
	assert_true(Interiors.enter("core:interior/test_cell"))
	assert_eq(Music.mode, "deep", "indoors the melody gives way to the deep stem")
	assert_true(Ambience.interior, "the ambience knows it is indoors")
	assert_has(Ambience.active_layers(), "room_tone", "and a room tone comes in")
	assert_has(_heard, "door_wood_open", "the door is heard as it opens")
	var inside := _run_music(3.0)
	assert_true(_largest_step(inside) < MAX_DB_PER_STEP, "the change of mix is a fade (%.1f dB in a step)" % _largest_step(inside))
	assert_true(Interiors.exit())
	assert_eq(Music.mode, "explore")
	assert_false(Ambience.interior)
	assert_has(_heard, "door_wood_close")


func test_a_boss_takes_the_score_and_its_second_phase_crossfades_to_the_second_track() -> void:
	_double()
	Music.play_region("core:region/hearthvale", true)
	var reeve := _enemy(REEVE, Vector3(0.0, 0.05, -12.0))
	await _frames(2)
	reeve.start_boss()
	assert_eq(Music.overlay_kind(), "boss", "the boss track takes over")
	var opening := _run_music(2.5)
	var first := str(Music._overlays[Music._overlay_now].name)
	assert_true(float(opening[first].back()) > -1.0, "boss_1 is up (%.1f dB)" % float(opening[first].back()))
	assert_true(Music.stem_volume_db("pad") <= Music.SILENCE_DB + 0.01, "and the region bed has gone under it")
	# Its own loop sees the threshold: health under half is the second phase.
	reeve.health = reeve.max_health * 0.45
	await _frames(2)
	assert_eq(reeve.phase_index, 1, "the Reeve entered his second phase")
	assert_eq(Music._boss_intensity, 2, "and the score heard it from the boss, not from a quest")
	var second := str(Music._overlays[Music._overlay_now].name)
	assert_ne(first, second, "the second track comes in on the other player")
	var t := _run_music(2.5)
	assert_true(_crossfaded(t, first, second), "boss_1 went out while boss_2 came in")
	assert_true(_largest_step(t) < MAX_DB_PER_STEP, "no cut (%.1f dB in a step)" % _largest_step(t))
	reeve.die(null)
	assert_eq(Music.overlay_kind(), "", "the boss track gives way when he falls")


# --- the ambience, following the world -------------------------------------------------------------

func test_the_ambience_follows_the_atmospheres_weather_and_the_clock() -> void:
	var previous_world: Variant = SaveSystem.participants.get("world")
	var atm := (load("res://systems/atmosphere/atmosphere.tscn") as PackedScene).instantiate()
	root.add_child(atm)
	GameState.enter_region("core:region/sedgemire")
	assert_eq(Ambience.region_id, "core:region/sedgemire")
	assert_has(Ambience.active_layers(), "frogs", "the marsh's own layers")
	atm.call("force_weather", "core:weather/rain", true)
	var raining := false
	for i in 150:
		await _tree().physics_frame
		for key in Ambience.active_layers():
			if str(key).begins_with("rain_"):
				raining = true
		if raining:
			break
	assert_true(raining, "rain the Atmosphere announced is heard: %s" % str(Ambience.active_layers()))
	atm.call("force_weather", "core:weather/clear", true)
	var dry := false
	for i in 150:
		await _tree().physics_frame
		dry = Ambience.active_layers().filter(func(k: Variant) -> bool: return str(k).begins_with("rain_")).is_empty()
		if dry:
			break
	assert_true(dry, "and stops when it clears: %s" % str(Ambience.active_layers()))
	WorldClock.set_time(23.0)
	assert_has(Ambience.active_layers(), "night_insects_marsh", "the marsh at night")
	WorldClock.set_time(12.0)
	assert_false(Ambience.active_layers().has("night_insects_marsh"), "and not by day")
	root.remove_child(atm)
	atm.free()
	if previous_world != null and is_instance_valid(previous_world):
		SaveSystem.register("world", previous_world)
	else:
		SaveSystem.unregister("world")


# --- foley in the running game --------------------------------------------------------------------

func _walk(p: Player, seconds: float) -> void:
	Input.action_press("move_forward")
	await _seconds(seconds)
	Input.action_release("move_forward")
	await _frames(6)
	p.velocity = Vector3.ZERO


func test_footsteps_fall_on_the_floor_underfoot_and_stealth_hears_which() -> void:
	var floor_body := root.get_node("Floor") as StaticBody3D
	floor_body.set_meta("surface", "wood")
	var p := _player()
	await _frames(4)
	_heard.clear()
	await _walk(p, 1.5)
	var steps := _heard.filter(func(id: String) -> bool: return id.begins_with("footstep_"))
	assert_gt(steps.size(), 1, "walking a second and a half is more than one step: %s" % str(_heard))
	assert_true(steps.all(func(id: String) -> bool: return id == "footstep_wood"), "every step on wood: %s" % str(steps))
	assert_eq(p.surface, "wood", "the player knows what it is standing on")
	assert_eq(Stealth.surface_of(p), "wood", "and stealth hears it")
	# Ground that says nothing about itself is the region's ground.
	floor_body.remove_meta("surface")
	GameState.current_region_id = "core:region/sedgemire"
	_heard.clear()
	p.global_position = Vector3(0.0, 0.02, 0.0)
	await _walk(p, 1.5)
	steps = _heard.filter(func(id: String) -> bool: return id.begins_with("footstep_"))
	assert_gt(steps.size(), 1)
	assert_true(steps.all(func(id: String) -> bool: return id == "footstep_mud"), "the marsh is mud underfoot: %s" % str(steps))


func test_steps_come_at_the_pace_of_the_walk_not_a_clock() -> void:
	# Footfalls count ground covered: a walk and a run over the same second are different counts,
	# and a stride grows with the pace, so the cadence follows whatever speeds the gait has.
	assert_gt(Footfalls.stride_for(6.5), Footfalls.stride_for(4.2))
	assert_gt(Footfalls.stride_for(4.2), Footfalls.stride_for(2.0))
	var slow := Footfalls.new()
	var fast := Footfalls.new()
	var body := Node3D.new()
	root.add_child(body)
	var n_slow := 0
	var n_fast := 0
	for i in 120:
		if not slow.advance(body, STEP, 2.0, true).is_empty():
			n_slow += 1
		if not fast.advance(body, STEP, 6.5, true).is_empty():
			n_fast += 1
	assert_gt(n_fast, n_slow, "two seconds of running is more steps than two seconds of strolling (%d, %d)" % [n_fast, n_slow])
	var still := Footfalls.new()
	for i in 120:
		assert_true(still.advance(body, STEP, 0.2, true).is_empty(), "standing is silent")
	assert_true(Footfalls.new().advance(body, 0.5, 4.2, false).is_empty(), "and so is falling")


func test_a_blow_sounds_what_it_lands_on() -> void:
	for pair in [[BANDIT, "impact_flesh"], ["core:enemy/stone_thrall", "impact_stone"],
			["core:enemy/warden", "impact_wood"], ["core:enemy/tolling_knight", "impact_metal"]]:
		var foe := _enemy(str(pair[0]), Vector3(0.0, 0.05, -3.0), false)
		await _frames(1)
		_heard.clear()
		var hit := HitData.new()
		hit.amount = 1.0
		hit.poise_damage = 0.0
		hit.origin = Vector3.ZERO
		foe.take_hit(hit)
		assert_has(_heard, str(pair[1]), "%s struck sounds as %s: %s" % [pair[0], pair[1], str(_heard)])
		foe.free()


func test_a_swing_whooshes_as_it_goes_live_and_a_guard_rings() -> void:
	var p := _player()
	p.equip_weapon(SWORD)
	var foe := _enemy(BANDIT, Vector3(0.0, 0.05, -1.3), false)
	await _frames(4)
	_heard.clear()
	var hp := foe.health
	Input.action_press("attack_light")
	await _frames(2)
	Input.action_release("attack_light")
	for i in 90:
		if foe.health < hp:
			break
		await _tree().physics_frame
	assert_true(foe.health < hp, "the swing landed")
	var whoosh := _heard.find("sword_swing_light")
	var thud := _heard.find("impact_flesh")
	assert_true(whoosh >= 0 and thud >= 0 and whoosh < thud, "a whoosh, then flesh: %s" % str(_heard))
	# A raised guard, and a parry pressed in time: the real resolution of a blow on the player.
	var blow := foe.build_hit({"name": "test", "damage": 10.0, "poise_damage": 0.0})
	blow.origin = foe.global_position
	_heard.clear()
	p.is_blocking = true
	p.block_stability = 0.6
	assert_eq(p.take_hit(blow), "blocked")
	assert_has(_heard, "block_clang")
	p.is_blocking = false
	p.can_parry = true
	p.parry_pressed_at = Actor.now()
	_heard.clear()
	assert_eq(p.take_hit(blow.copy()), "parried")
	assert_has(_heard, "parry_clang")
	_heard.clear()
	foe.stagger(0.4)
	assert_has(_heard, "stagger_thud")


func test_what_the_world_does_is_heard() -> void:
	var ui: Node = _tree().root.get_node_or_null("UI")
	assert_true(ui != null)
	_heard.clear()
	ui.call("open", "journal")
	assert_has(_heard, "ui_book_open", "the journal opens like a book")
	close_screen("journal")
	assert_has(_heard, "ui_book_close")
	var b := UiKit.button("Take")
	_heard.clear()
	b.pressed.emit()
	b.mouse_entered.emit()
	assert_has(_heard, "ui_brass_click", "a button clicks")
	assert_has(_heard, "ui_hover_tick", "and ticks under the pointer")
	b.free()
	_heard.clear()
	EventBus.marks_changed.emit(12, 5)
	EventBus.marks_changed.emit(112, 100)
	assert_has(_heard, "coins_few")
	assert_has(_heard, "coins_many")
	EventBus.item_used.emit("core:item/bread", [])
	EventBus.item_used.emit("core:item/potion_restore_health", [])
	assert_has(_heard, "eat", "a loaf is eaten")
	assert_has(_heard, "potion_drink", "a potion is drunk")
	EventBus.notify.emit("No arrows.", "warning")
	assert_has(_heard, "ui_error_thunk", "a refusal thunks")
	var armour_heavy := ""
	var armour_light := ""
	for def in ContentDB.all("item"):
		var a: Dictionary = def.get("armour", {})
		if a.is_empty() or not str(a.get("slot", "")) in ["head", "body", "hands", "feet"]:
			continue
		if str(a.get("weight_class", "light")) == "light" and armour_light.is_empty():
			armour_light = str(def["id"])
		elif str(a.get("weight_class", "light")) == "heavy" and armour_heavy.is_empty():
			armour_heavy = str(def["id"])
	_heard.clear()
	EventBus.item_equipped.emit("body", armour_light)
	EventBus.item_equipped.emit("body", armour_heavy)
	EventBus.item_equipped.emit("main_hand", SWORD)
	assert_eq(",".join(_heard), "armour_light,armour_heavy", "armour is heard going on, a sword is not")


func test_a_pick_clicks_and_snaps() -> void:
	var door := StaticBody3D.new()
	var lock := DoorLock.new()
	lock.lock_level = 1
	door.add_child(lock)
	root.add_child(door)
	var actor := Node.new()
	var script := GDScript.new()
	script.source_code = "extends Node\nvar bag := {}\nfunc add(id: String, n: int) -> void:\n\tbag[id] = bag.get(id, 0) + n\nfunc remove(id: String, n: int) -> int:\n\tvar have: int = bag.get(id, 0)\n\tvar take: int = mini(have, n)\n\tbag[id] = have - take\n\treturn take\nfunc count(id: String) -> int:\n\treturn bag.get(id, 0)\n"
	script.reload()
	actor.set_script(script)
	root.add_child(actor)
	actor.call("add", lock.lockpick_item_id(), 2)
	_heard.clear()
	assert_true(bool(lock.attempt(actor, 0.95)["broke"]))
	assert_has(_heard, "lockpick_break")
	assert_true(bool(lock.attempt(actor, 0.05)["success"]))
	assert_has(_heard, "lockpick_click")


# --- inventories ----------------------------------------------------------------------------------

## Every .gd file the game runs (not its tests or tools), as text.
static func _game_sources() -> Dictionary:
	var out := {}
	var stack: Array[String] = ["res://"]
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		for sub in d.get_directories():
			if sub in ["tests", "tools_gd", "addons", ".godot"]:
				continue
			stack.append(dir_path.path_join(sub))
		for f in d.get_files():
			if f.ends_with(".gd"):
				var path := dir_path.path_join(f)
				out[path] = FileAccess.get_file_as_string(path)
	return out


## Every sfx id the game can ask Foley for: the literal ones in the code, and the families the
## code builds from data (a material, a school, a surface, a door, a weapon class).
static func _ids_the_game_asks_for() -> Dictionary:
	var ids := {}
	var sources := _game_sources()
	# A literal id, not the head of one being built ("impact_" + material is a family, below);
	# and the other half of `play("a" if ... else "b")`, and an id a projectile carries to its end.
	var literal := RegEx.create_from_string("(?:Foley\\.)?(?:play|play_ui)\\(\"([a-z0-9_]+)\"(?!\\s*\\+)()")
	var otherwise := RegEx.create_from_string("(?:Foley\\.)?(?:play|play_ui)\\(\"[a-z0-9_]+\" if .* else \"([a-z0-9_]+)\"\\s*[,)]()")
	var carried := RegEx.create_from_string("impact_sound = \"([a-z0-9_]+)\"(?!\\s*\\+)()")
	var step := RegEx.create_from_string("footstep\\(\"([a-z_]+)\"")
	for path in sources:
		var text: String = sources[path]
		var own: bool = str(path).ends_with("foley.gd") or str(path).ends_with("footfalls.gd")
		for re in [literal, otherwise, carried]:
			for m in (re as RegEx).search_all(text):
				if re != carried and not own and not m.get_string(0).begins_with("Foley."):
					continue
				ids[m.get_string(1)] = path
		for m in step.search_all(text):
			ids["footstep_" + m.get_string(1)] = path
	for material in ["flesh", "metal", "stone", "wood"]:
		ids["impact_" + material] = "Actor.take_hit"
	for def in ContentDB.all("spell"):
		var school := SpellRuntime.school_of(def)
		ids["spell_cast_" + school] = "SpellCaster"
		ids["spell_impact_" + school] = "SpellCaster"
	var classes := {}
	for def in ContentDB.all("item"):
		if def.has("weapon"):
			classes[str((def["weapon"] as Dictionary).get("class", "unarmed"))] = true
	for type in ["enemy", "boss"]:
		for def in ContentDB.all(type):
			for a in def.get("attacks", []):
				classes[str(a.get("weapon_class", "claw"))] = true
	for c in classes:
		for heavy in [false, true]:
			var s := Foley.swing_for(str(c), heavy)
			if not s.is_empty():
				ids[s] = "swing:" + str(c)
	for def in ContentDB.all("interior"):
		ids[Foley.door_for(str(def["id"]), true)] = "door"
		ids[Foley.door_for(str(def["id"]), false)] = "door"
	for def in ContentDB.all("region"):
		ids["footstep_" + str(def.get("identity", {}).get("ground", Foley.DEFAULT_SURFACE))] = "region ground"
	for s in ["stone", "wood", "water", Foley.DEFAULT_SURFACE]:
		ids["footstep_" + s] = "surface"
	return ids


func test_every_sound_the_game_asks_for_is_in_the_table_and_loads() -> void:
	var ids := _ids_the_game_asks_for()
	assert_gt(ids.size(), 50, "the scan found the calls: %d" % ids.size())
	for id: String in ids:
		assert_true(Foley.has(id), "%s asks for '%s' and the sfx table has no such row" % [ids[id], id])
		for f in (Foley.rows.get(id, {}) as Dictionary).get("files", []):
			assert_true(ResourceLoader.exists(str(f)), "%s -> %s is missing" % [id, f])
			assert_true(load(str(f)) is AudioStream, "%s -> %s does not import as audio" % [id, f])
	var unused: Array = []
	for id: String in Foley.ids():
		if not ids.has(id):
			unused.append(id)
	# Rows nothing in the game plays are not an error -- they may be waiting on a system that does
	# not exist yet -- but they are printed, so the list is seen.
	print("MEASURE | sfx ids nothing in the game plays | %d | %s" % [unused.size(), ", ".join(unused)])


func test_every_music_file_the_content_names_loads() -> void:
	for def in ContentDB.all("music"):
		for key in (def.get("stems", {}) as Dictionary):
			var path := str(def["stems"][key])
			assert_true(ResourceLoader.exists(path) and load(path) is AudioStream, "%s stem %s -> %s" % [def["id"], key, path])
		for key in (def.get("stingers", {}) as Dictionary):
			var path := str(def["stingers"][key])
			assert_true(ResourceLoader.exists(path) and load(path) is AudioStream, "stinger %s -> %s" % [key, path])


func test_every_audio_file_on_disk_is_used_by_something() -> void:
	var used := {}
	for id in Foley.rows:
		for f in (Foley.rows[id] as Dictionary).get("files", []):
			used[str(f)] = true
	for def in ContentDB.all("music"):
		for key in (def.get("stems", {}) as Dictionary):
			used[str(def["stems"][key])] = true
		for key in (def.get("stingers", {}) as Dictionary):
			used[str(def["stingers"][key])] = true
	for key in Ambience._manifest:
		for f in (Ambience._manifest[key] as Dictionary).get("files", []):
			used[str(f)] = true
	var files: Array[String] = []
	var stack: Array[String] = ["res://assets/audio"]
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		for sub in d.get_directories():
			stack.append(dir_path.path_join(sub))
		for f in d.get_files():
			if f.ends_with(".ogg") or f.ends_with(".wav"):
				files.append(dir_path.path_join(f))
	assert_gt(files.size(), 300, "the audio is on disk: %d files" % files.size())
	for f in files:
		assert_true(used.has(f), "%s is on disk and nothing plays it" % f)


func test_every_bus_a_sound_is_sent_to_exists() -> void:
	var buses := {"Interior": "Foley indoors"}
	var assign := RegEx.create_from_string("\\.bus = \"([A-Za-z]+)\"")
	var sources := _game_sources()
	for path in sources:
		for m in assign.search_all(str(sources[path])):
			buses[m.get_string(1)] = path
	for id in Foley.rows:
		buses[str((Foley.rows[id] as Dictionary).get("bus", "SFX"))] = "sfx:" + str(id)
	assert_gt(buses.size(), 3)
	for name: String in buses:
		assert_gt(AudioServer.get_bus_index(name), -1, "%s sends to a bus called %s, which does not exist" % [buses[name], name])


func test_the_sliders_on_the_settings_screen_move_the_buses() -> void:
	var saved: Dictionary = (Settings.data.get("audio", {}) as Dictionary).duplicate()
	var ui: Node = _tree().root.get_node_or_null("UI")
	var menu: Node = ui.call("open", "settings", {"tab": 1})
	assert_true(menu != null, "the settings screen opens on its Audio tab")
	var by_label := {}
	for s in menu.find_children("*", "HSlider", true, false):
		var row: Node = (s as Node).get_parent().get_parent()
		for c in row.get_children():
			if c is Label:
				by_label[(c as Label).text] = s
				break
	var wanted := {"Everything": "Master", "Music": "Music", "Sounds": "SFX", "The world": "Ambience",
		"Paper and brass": "UI", "Voices": "Voice"}
	for label: String in wanted:
		assert_has(by_label, label, "a slider for %s" % label)
		if not by_label.has(label):
			continue
		var slider := by_label[label] as HSlider
		slider.value = 0.25
		var bus := AudioServer.get_bus_index(str(wanted[label]))
		assert_near(AudioServer.get_bus_volume_db(bus), linear_to_db(0.25), 0.05,
			"%s at a quarter puts the %s bus at %.1f dB" % [label, wanted[label], linear_to_db(0.25)])
		slider.value = 1.0
		assert_near(AudioServer.get_bus_volume_db(bus), 0.0, 0.05)
	# The Sounds slider reaches world sounds indoors too: the Interior bus goes out through SFX.
	assert_eq(str(AudioServer.get_bus_send(AudioServer.get_bus_index("Interior"))), "SFX")
	close_screen("settings")
	for key in saved:
		Settings.set_value("audio", str(key), saved[key])
