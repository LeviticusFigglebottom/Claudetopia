extends TestCase
## Foley: the sfx table lookup, variant and pitch selection, pooling, and surface resolution.
## Headless with the Dummy audio driver: players are told to play, and what is checked is what
## they were handed, not what came out.


func before_each() -> void:
	Foley.enabled = true
	Foley.stop_all()
	GameState.current_interior_id = ""


func after_each() -> void:
	Foley.stop_all()
	GameState.current_interior_id = ""


# --- the table -----------------------------------------------------------------------------

func test_the_table_loaded() -> void:
	assert_true(ContentDB.has(Foley.TABLE_ID), "core:table/sfx is missing; run gen_sfx.py")
	assert_gt(Foley.rows.size(), 50, "expected a full sfx table")


func test_every_row_is_complete_and_its_files_exist() -> void:
	for id: String in Foley.rows:
		var row: Dictionary = Foley.rows[id]
		for key in ["files", "volume_db", "pitch_variance", "bus"]:
			assert_has(row, key, "%s lacks %s" % [id, key])
		var files: Array = row["files"]
		assert_gt(files.size(), 0, "%s has no files" % id)
		for f in files:
			assert_true(ResourceLoader.exists(str(f)), "%s -> %s missing" % [id, f])
		assert_gt(AudioServer.get_bus_index(str(row["bus"])), -1,
			"%s wants bus %s, which does not exist" % [id, row["bus"]])
		assert_true(float(row["pitch_variance"]) >= 0.0 and float(row["pitch_variance"]) < 0.5,
			"%s pitch variance %s is out of range" % [id, row["pitch_variance"]])
		assert_true(float(row["volume_db"]) <= 6.0, "%s is trimmed too hot" % id)


func test_the_sounds_other_systems_are_promised_are_all_there() -> void:
	var needed := [
		"sword_swing_light", "sword_swing_heavy", "axe_swing", "mace_swing",
		"impact_flesh", "impact_wood", "impact_metal", "impact_stone",
		"block_clang", "parry_clang", "stagger_thud",
		"bow_draw", "bow_release", "arrow_whoosh", "arrow_hit",
		"armour_light", "armour_heavy",
		"potion_drink", "eat", "pick_up", "coins_few", "coins_many",
		"door_wood_open", "door_wood_close", "door_iron_open", "door_iron_close",
		"chest_open", "lockpick_click", "lockpick_break",
		"hearthstone_rest", "echo_recovered", "player_death",
		"bell_hand", "bell_tavern", "bell_tower", "bell_toll",
		"thunder_near", "thunder_far", "wind_gust", "water_splash", "wood_creak", "cart_wheels",
		"ui_paper_slide", "ui_brass_click", "ui_hover_tick", "ui_error_thunk",
		"ui_page_turn", "ui_book_open", "ui_book_close", "ui_map_unroll",
	]
	for id in needed:
		assert_true(Foley.has(id), "missing sfx id '%s'" % id)


func test_every_spell_school_can_be_cast_and_can_land() -> void:
	for school in ["kindling", "hush", "binding", "mending", "calling"]:
		assert_true(Foley.has("spell_cast_%s" % school), "no cast sound for %s" % school)
		assert_true(Foley.has("spell_impact_%s" % school), "no impact sound for %s" % school)


func test_every_surface_has_four_footstep_variants() -> void:
	var surfaces := ["vale_grass", "dirt", "stone", "wood", "water", "snow", "ash", "gravel",
			"mud", "sand"]
	for s in surfaces:
		var id := "footstep_%s" % s
		assert_true(Foley.has(id), "no footsteps for %s" % s)
		assert_eq(Foley.rows[id]["files"].size(), 4, "%s should have 4 variants" % id)


func test_ui_sounds_are_on_the_ui_bus() -> void:
	for id: String in Foley.rows:
		if id.begins_with("ui_"):
			assert_eq(str(Foley.rows[id]["bus"]), "UI", "%s should be on the UI bus" % id)


# --- playing -------------------------------------------------------------------------------

func test_play_returns_a_positional_player_at_the_position() -> void:
	var p := Foley.play("impact_wood", Vector3(3, 1, -4)) as AudioStreamPlayer3D
	assert_true(p != null, "nothing played")
	assert_eq(p.global_position, Vector3(3, 1, -4))
	assert_true(p.playing)
	assert_true(p.stream != null)


func test_play_without_a_position_is_flat() -> void:
	var p := Foley.play("ui_error_thunk")
	assert_true(p is AudioStreamPlayer, "a sound with no position must not be positional")


func test_play_ui_uses_the_ui_bus() -> void:
	var p := Foley.play_ui("ui_page_turn") as AudioStreamPlayer
	assert_true(p != null)
	assert_eq(p.bus, "UI")


func test_volume_argument_offsets_the_table_level() -> void:
	var base := float(Foley.rows["impact_stone"]["volume_db"])
	var p := Foley.play("impact_stone", Vector3.ZERO, -6.0) as AudioStreamPlayer3D
	assert_near(p.volume_db, base - 6.0, 0.001)


func test_pitch_stays_inside_the_declared_variance() -> void:
	var row: Dictionary = Foley.rows["footstep_dirt"]
	var v := float(row["pitch_variance"])
	for i in 30:
		var p := Foley.play("footstep_dirt", Vector3.ZERO) as AudioStreamPlayer3D
		assert_true(p.pitch_scale >= 1.0 - v - 0.001 and p.pitch_scale <= 1.0 + v + 0.001,
			"pitch %f outside +/-%f" % [p.pitch_scale, v])
		p.stop()


func test_variants_are_used_and_never_repeat_immediately() -> void:
	var seen := {}
	var previous: AudioStream = null
	for i in 24:
		var p := Foley.play("footstep_gravel", Vector3.ZERO) as AudioStreamPlayer3D
		assert_ne(p.stream, previous, "the same variant twice running is what a pool must avoid")
		previous = p.stream
		seen[p.stream.resource_path] = true
		p.stop()
	assert_gt(seen.size(), 2, "the pool is barely being used")


func test_an_unknown_id_is_refused_quietly() -> void:
	assert_eq(Foley.play("no_such_sound", Vector3.ZERO), null)
	assert_eq(Foley.play_ui("no_such_sound"), null)


func test_disabling_foley_silences_it() -> void:
	Foley.enabled = false
	assert_eq(Foley.play("impact_wood", Vector3.ZERO), null)
	assert_eq(Foley.play_ui("ui_hover_tick"), null)
	Foley.enabled = true


func test_the_pool_never_runs_out() -> void:
	for i in Foley.POOL_3D + 8:
		var p := Foley.play("footstep_stone", Vector3(i, 0, 0))
		assert_true(p != null, "play %d returned nothing; a sound was dropped" % i)


func test_active_count_tracks_what_is_playing() -> void:
	assert_eq(Foley.active_count(), 0)
	Foley.play("bell_hand", Vector3.ZERO)
	assert_gt(Foley.active_count(), 0)
	Foley.stop_all()
	assert_eq(Foley.active_count(), 0)


# --- footsteps and surfaces -------------------------------------------------------------------

func test_footstep_picks_the_surface_it_is_given() -> void:
	var p := Foley.footstep("snow", Vector3.ZERO) as AudioStreamPlayer3D
	assert_true(p != null)
	assert_true(p.stream.resource_path.contains("footstep_snow"),
		"got %s" % p.stream.resource_path)


func test_an_unknown_surface_falls_back_rather_than_going_silent() -> void:
	var p := Foley.footstep("obsidian", Vector3.ZERO) as AudioStreamPlayer3D
	assert_true(p != null, "an unknown surface must still make a sound")
	assert_true(p.stream.resource_path.contains("footstep_%s" % Foley.DEFAULT_SURFACE))


func test_surface_of_reads_metadata_from_a_collider() -> void:
	var body := StaticBody3D.new()
	body.set_meta(Foley.SURFACE_META, "wood")
	assert_eq(Foley.surface_of(body), "wood")
	body.free()


func test_surface_of_walks_up_to_a_parent() -> void:
	var prop := Node3D.new()
	prop.set_meta(Foley.SURFACE_META, "gravel")
	var body := StaticBody3D.new()
	prop.add_child(body)
	assert_eq(Foley.surface_of(body), "gravel")
	prop.free()


func test_surface_of_falls_back_for_an_unlabelled_or_unknown_collider() -> void:
	var bare := StaticBody3D.new()
	assert_eq(Foley.surface_of(bare), Foley.DEFAULT_SURFACE)
	bare.set_meta(Foley.SURFACE_META, "lava")
	assert_eq(Foley.surface_of(bare), Foley.DEFAULT_SURFACE)
	bare.free()
	assert_eq(Foley.surface_of(null), Foley.DEFAULT_SURFACE)


func test_surface_at_returns_the_default_with_nothing_underfoot() -> void:
	assert_eq(Foley.surface_at(Vector3(0, 500, 0)), Foley.DEFAULT_SURFACE)


# --- interiors ---------------------------------------------------------------------------------

func test_world_sounds_route_through_the_interior_reverb_indoors() -> void:
	var outside := Foley.play("impact_stone", Vector3.ZERO) as AudioStreamPlayer3D
	assert_eq(outside.bus, "SFX")
	GameState.current_interior_id = "core:interior/test_cell"
	var inside := Foley.play("impact_stone", Vector3.ONE) as AudioStreamPlayer3D
	assert_eq(inside.bus, "Interior", "indoors, world sounds should carry the room")
	GameState.current_interior_id = ""


func test_ui_sounds_are_not_reverberated_indoors() -> void:
	GameState.current_interior_id = "core:interior/test_cell"
	var p := Foley.play_ui("ui_brass_click") as AudioStreamPlayer
	assert_eq(p.bus, "UI")
	GameState.current_interior_id = ""
