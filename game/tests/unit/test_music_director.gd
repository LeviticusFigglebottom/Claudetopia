extends TestCase
## MusicDirector: the state machine that decides what the score is doing.
## Runs headless with the Dummy audio driver, so nothing is heard; what is checked is which
## stems the director wants, at what level, and how it answers the events other systems emit.

const FakePlayer := preload("res://tests/fakes/fake_player.gd")

var player: Node3D


func before_each() -> void:
	Music.stop_all()
	Music.enabled = true
	Music.combat_intensity = 0.0
	GameState.current_interior_id = ""
	Music._open_menus.clear()
	Music._boss_id = ""
	Music._refresh_mode(true)


func after_each() -> void:
	if is_instance_valid(player):
		player.get_parent().remove_child(player)
		player.free()
		player = null
	Music.stop_all()
	GameState.current_interior_id = ""


func _spawn_player() -> Node3D:
	player = FakePlayer.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(player)
	return player


# --- content ------------------------------------------------------------------------------

func test_every_region_has_music_with_all_five_stems() -> void:
	for region in ContentDB.all("region"):
		var found := false
		for def in ContentDB.all("music"):
			if str(def.get("region", "")) != str(region["id"]):
				continue
			found = true
			var stems: Dictionary = def.get("stems", {})
			for stem in Music.STEMS:
				assert_has(stems, stem, "%s lacks the %s stem" % [def["id"], stem])
				assert_true(ResourceLoader.exists(str(stems[stem])),
					"%s -> %s does not exist" % [def["id"], stems[stem]])
		assert_true(found, "no music defined for %s" % region["id"])


func test_music_defs_declare_the_mode_their_region_asks_for() -> void:
	for def in ContentDB.all("music"):
		if not def.has("region"):
			continue
		var region := ContentDB.get_def(str(def["region"]))
		assert_eq(str(def.get("mode", "")), str(region["identity"]["music_mode"]),
			"%s mode does not match its region" % def["id"])


func test_stingers_exist_for_every_cue_the_director_plays() -> void:
	var def := ContentDB.get_def("core:music/stingers")
	var stingers: Dictionary = def.get("stingers", {})
	for kind in ["victory", "death", "level_up", "quest_update", "rest", "echo"]:
		assert_has(stingers, kind, "no %s stinger" % kind)
		assert_true(ResourceLoader.exists(str(stingers[kind])), "%s file missing" % kind)


func test_boss_tracks_exist_at_both_intensities() -> void:
	for id in ["core:music/boss_1", "core:music/boss_2", "core:music/main_theme", "core:music/naming"]:
		assert_true(ContentDB.has(id), "missing %s" % id)
		var stems: Dictionary = ContentDB.get_def(id).get("stems", {})
		assert_true(ResourceLoader.exists(str(stems.get("main", ""))), "%s has no main file" % id)


# --- region playback -----------------------------------------------------------------------

func test_play_region_starts_every_stem() -> void:
	assert_true(Music.play_region("core:region/hearthvale", true))
	assert_eq(Music.current_region_id, "core:region/hearthvale")
	for stem in Music.STEMS:
		assert_gt(Music.stem_volume_db(stem), -61.0, "%s never started" % stem)


func test_entering_the_same_region_twice_does_nothing() -> void:
	assert_true(Music.play_region("core:region/hearthvale", true))
	assert_false(Music.play_region("core:region/hearthvale", true))


func test_unknown_region_is_refused_without_changing_anything() -> void:
	Music.play_region("core:region/hearthvale", true)
	assert_false(Music.play_region("core:region/nowhere", true))
	assert_eq(Music.current_region_id, "core:region/hearthvale")


func test_region_entered_event_switches_the_music() -> void:
	Music.play_region("core:region/hearthvale", true)
	EventBus.region_entered.emit("core:region/sedgemire", "core:region/hearthvale")
	assert_eq(Music.current_region_id, "core:region/sedgemire")
	assert_eq(Music.current_music_id, "core:music/sedgemire")


# --- modes ---------------------------------------------------------------------------------

func test_exploring_plays_pad_melody_and_texture_only() -> void:
	Music.play_region("core:region/hearthvale", true)
	assert_eq(Music.mode, "explore")
	var stems := Music.playing_stems()
	assert_true(stems.has("pad") and stems.has("melody") and stems.has("texture"))
	assert_false(stems.has("combat"), "combat should be silent while exploring")
	assert_false(stems.has("deep"), "deep should be silent while exploring")


func test_damage_to_the_player_raises_the_combat_layer() -> void:
	Music.play_region("core:region/hearthvale", true)
	var p := _spawn_player()
	EventBus.damage_dealt.emit(null, p, 12.0, "physical")
	assert_gt(Music.combat_intensity, 0.0)
	assert_eq(Music.mode, "combat")
	assert_true(Music.playing_stems().has("combat"))


func test_damage_between_two_other_things_is_ignored() -> void:
	Music.play_region("core:region/hearthvale", true)
	var a := Node3D.new()
	var b := Node3D.new()
	EventBus.damage_dealt.emit(a, b, 20.0, "physical")
	assert_eq(Music.combat_intensity, 0.0)
	assert_eq(Music.mode, "explore")
	a.free()
	b.free()


func test_combat_intensity_decays_to_nothing() -> void:
	Music.play_region("core:region/hearthvale", true)
	Music.raise_combat(1.0)
	assert_eq(Music.mode, "combat")
	Music._process(Music.COMBAT_DECAY_SECONDS * 0.5)
	assert_true(Music.combat_intensity > 0.0 and Music.combat_intensity < 1.0, "should be part way down")
	Music._process(Music.COMBAT_DECAY_SECONDS)
	assert_eq(Music.combat_intensity, 0.0)
	assert_eq(Music.mode, "explore")


func test_the_combat_layer_swells_with_intensity_rather_than_switching() -> void:
	Music.play_region("core:region/hearthvale", true)
	Music.raise_combat(0.25)
	var quiet := Music._stem_db("combat")
	Music.raise_combat(0.75)
	var loud := Music._stem_db("combat")
	assert_gt(loud, quiet, "a bigger fight must be louder")


func test_interiors_drop_the_melody_for_the_deep_stem() -> void:
	Music.play_region("core:region/hearthvale", true)
	assert_false(Music.is_deep())
	GameState.current_interior_id = "core:interior/test_cell"
	EventBus.interior_entered.emit("core:interior/test_cell")
	assert_true(Music.is_deep())
	assert_eq(Music.mode, "deep")
	var stems := Music.playing_stems()
	assert_true(stems.has("deep"), "the deep stem must come in")
	assert_false(stems.has("melody"), "deep places drop the melody")


func test_a_dangerous_region_is_deep_without_an_interior() -> void:
	Music.play_region("core:region/cinderlea", true)
	assert_gt(int(ContentDB.get_def("core:region/cinderlea").get("danger", 0)), 3)
	assert_true(Music.is_deep())
	assert_eq(Music.mode, "deep")
	assert_false(Music.playing_stems().has("melody"))


func test_a_safe_region_is_not_deep() -> void:
	Music.play_region("core:region/hearthvale", true)
	assert_false(Music.is_deep())
	assert_eq(Music.mode, "explore")


func test_fighting_in_a_deep_place_keeps_both_layers() -> void:
	Music.play_region("core:region/cinderlea", true)
	Music.raise_combat(1.0)
	assert_eq(Music.mode, "deep_combat")
	var stems := Music.playing_stems()
	assert_true(stems.has("deep") and stems.has("combat"))
	assert_false(stems.has("melody"))


func test_every_mix_names_every_stem() -> void:
	for mix in [Music.MIX_EXPLORE, Music.MIX_COMBAT, Music.MIX_DEEP, Music.MIX_DEEP_COMBAT]:
		for stem in Music.STEMS:
			assert_has(mix, stem)
			assert_true(float(mix[stem]) <= 0.0, "a stem must not be pushed above unity")


# --- bosses ---------------------------------------------------------------------------------

func test_boss_started_takes_over_and_defeat_gives_it_back() -> void:
	Music.play_region("core:region/hearthvale", true)
	EventBus.boss_started.emit("core:boss/barrow_reeve")
	assert_eq(Music.overlay_kind(), "boss")
	EventBus.boss_defeated.emit("core:boss/barrow_reeve")
	assert_eq(Music.overlay_kind(), "")


func test_a_phase_change_switches_the_boss_intensity() -> void:
	EventBus.boss_started.emit("core:boss/hart_of_thorns")
	assert_eq(Music._boss_intensity, 1)
	Music.set_boss_intensity(2)
	assert_eq(Music._boss_intensity, 2)
	assert_eq(Music.overlay_kind(), "boss")
	EventBus.boss_defeated.emit("core:boss/hart_of_thorns")


func test_boss_intensity_is_ignored_when_no_boss_is_playing() -> void:
	Music.set_boss_intensity(2)
	assert_eq(Music.overlay_kind(), "")


# --- menus and stingers ------------------------------------------------------------------------

func test_a_full_screen_menu_ducks_the_music_and_closing_restores_it() -> void:
	Music.play_region("core:region/hearthvale", true)
	var before := Music._target_db("pad")
	EventBus.menu_opened.emit("inventory")
	assert_true(Music.menus_open())
	assert_gt(before, Music._target_db("pad"), "the bed must duck under a menu")
	EventBus.menu_closed.emit("inventory")
	assert_false(Music.menus_open())
	assert_eq(Music._target_db("pad"), before)


func test_a_small_popup_does_not_duck() -> void:
	Music.play_region("core:region/hearthvale", true)
	var before := Music._target_db("pad")
	EventBus.menu_opened.emit("notification")
	assert_eq(Music._target_db("pad"), before)
	EventBus.menu_closed.emit("notification")


func test_the_main_menu_brings_up_the_theme() -> void:
	EventBus.menu_opened.emit("main_menu")
	assert_eq(Music.overlay_kind(), "menu")
	EventBus.menu_closed.emit("main_menu")
	assert_eq(Music.overlay_kind(), "")


func test_stingers_play_for_their_events() -> void:
	assert_true(Music.play_stinger("victory"))
	assert_true(Music.play_stinger("death"))
	assert_false(Music.play_stinger("no_such_stinger"))


func test_death_clears_combat_and_any_overlay() -> void:
	Music.play_region("core:region/hearthvale", true)
	EventBus.boss_started.emit("core:boss/last_cantor")
	Music.raise_combat(1.0)
	EventBus.player_died.emit(Vector3.ZERO)
	assert_eq(Music.combat_intensity, 0.0)
	assert_eq(Music.overlay_kind(), "")


func test_resting_calms_the_music() -> void:
	Music.play_region("core:region/hearthvale", true)
	Music.raise_combat(1.0)
	EventBus.hearthstone_rested.emit("core:place/merrowby")
	assert_eq(Music.combat_intensity, 0.0)
	assert_eq(Music.mode, "explore")


func test_disabling_the_director_stops_it_starting_anything() -> void:
	Music.enabled = false
	assert_false(Music.play_region("core:region/briarwold", true))
	assert_false(Music.play_stinger("victory"))
	Music.enabled = true


# --- the audio buses the whole system depends on -------------------------------------------------

func test_the_project_has_the_buses_settings_expects() -> void:
	for bus_name in ["Master", "Music", "SFX", "Ambience", "UI", "Voice", "Interior"]:
		assert_gt(AudioServer.get_bus_index(bus_name), -1, "no %s bus" % bus_name)
	var interior := AudioServer.get_bus_index("Interior")
	assert_gt(AudioServer.get_bus_effect_count(interior), 0, "Interior carries no reverb")
	assert_true(AudioServer.get_bus_effect(interior, 0) is AudioEffectReverb)
	var ambience := AudioServer.get_bus_index("Ambience")
	assert_true(AudioServer.get_bus_effect(ambience, 0) is AudioEffectLowPassFilter,
		"Ambience needs a low-pass for interior muffling")
	for bus_name in ["Music", "SFX", "Ambience", "UI", "Voice"]:
		assert_eq(str(AudioServer.get_bus_send(AudioServer.get_bus_index(bus_name))), "Master")
	assert_eq(str(AudioServer.get_bus_send(AudioServer.get_bus_index("Interior"))), "SFX",
		"indoor world sounds go out through SFX, so the Sounds slider reaches them")
