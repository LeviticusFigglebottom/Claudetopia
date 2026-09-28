extends TestCase
## AmbienceMixer: which layers should be sounding, and at what level.
## The decision is pure -- region keys, the hour, the weather, whether we are indoors -- so it
## is checked directly rather than by listening to the bus.

var _saved_hour: float
var _saved_region: String


func before_each() -> void:
	_saved_hour = WorldClock.time_hours
	_saved_region = Ambience.region_id
	Ambience.enabled = true
	Ambience.interior = false
	Ambience.set_weather_override({})
	WorldClock.set_time(12.0)
	Ambience.set_region("core:region/hearthvale")


func after_each() -> void:
	Ambience.set_weather_override({})
	Ambience.interior = false
	Ambience.stop_all()
	WorldClock.set_time(_saved_hour)
	if not _saved_region.is_empty():
		Ambience.set_region(_saved_region)


func _layers(weather: Dictionary = {}) -> Dictionary:
	Ambience.set_weather_override(weather)
	return Ambience.desired_layers()


# --- the manifest ----------------------------------------------------------------------------

func test_the_manifest_loaded_and_every_file_exists() -> void:
	assert_gt(Ambience._manifest.size(), 20, "run tools/audio/gen_ambience.py")
	for key: String in Ambience._manifest:
		var entry: Dictionary = Ambience._manifest[key]
		assert_has(entry, "kind")
		assert_true(entry["kind"] in ["bed", "pool"], "%s has kind %s" % [key, entry["kind"]])
		var files: Array = entry.get("files", [])
		assert_gt(files.size(), 0, "%s has no files" % key)
		for f in files:
			assert_true(ResourceLoader.exists(str(f)), "%s -> %s missing" % [key, f])


func test_every_region_ambience_key_has_something_to_play() -> void:
	for region in ContentDB.all("region"):
		for key: String in region["identity"].get("ambience", []):
			assert_has(Ambience._manifest, key,
				"%s asks for '%s' and nothing renders it" % [region["id"], key])


func test_sparse_things_are_pools_and_continuous_things_are_beds() -> void:
	for key in ["skylark", "owl", "woodpecker", "bittern", "buoy_bell", "creak", "bell_rare",
			"hammer_distant", "thunder_near", "thunder_far"]:
		assert_eq(str(Ambience._manifest.get(key, {}).get("kind", "")), "pool",
			"%s should be a pool of one-shots" % key)
	for key in ["wind_soft", "wind_high", "water_lap", "frogs", "silence_bed", "sustained_note",
			"ash_hiss", "rain_light", "rain_heavy", "room_tone"]:
		assert_eq(str(Ambience._manifest.get(key, {}).get("kind", "")), "bed",
			"%s should be a continuous bed" % key)


func test_every_pool_has_a_gap_or_falls_back_to_the_default() -> void:
	for key: String in Ambience._manifest:
		if str(Ambience._manifest[key].get("kind", "")) != "pool":
			continue
		var gap: Vector2 = Ambience.POOL_GAPS.get(key, Ambience.DEFAULT_GAP)
		assert_gt(gap.x, 0.0, "%s has a zero minimum gap" % key)
		assert_gt(gap.y, gap.x, "%s gap is not a range" % key)


# --- region layers ---------------------------------------------------------------------------

func test_a_region_asks_for_its_own_ambience_keys() -> void:
	var want := _layers()
	for key: String in ContentDB.get_def("core:region/hearthvale")["identity"]["ambience"]:
		if Ambience._in_time_window(key):
			assert_has(want, key, "hearthvale should be playing %s at noon" % key)


func test_regions_sound_different_from_each_other() -> void:
	Ambience.set_region("core:region/hearthvale")
	var vale := _layers().keys()
	Ambience.set_region("core:region/cinderlea")
	var ash := _layers().keys()
	assert_ne(vale, ash)
	assert_true(ash.has("silence_bed") and ash.has("sustained_note"),
		"Cinderlea is its silence and its held note, got %s" % str(ash))
	assert_false(ash.has("skylark"), "nothing sings in Cinderlea")


# --- time of day -------------------------------------------------------------------------------

func test_hour_windows_wrap_around_midnight() -> void:
	assert_true(Ambience._hour_in(23.0, Vector2(20.0, 5.0)))
	assert_true(Ambience._hour_in(2.0, Vector2(20.0, 5.0)))
	assert_false(Ambience._hour_in(12.0, Vector2(20.0, 5.0)))
	assert_true(Ambience._hour_in(12.0, Vector2(7.0, 19.0)))
	assert_false(Ambience._hour_in(23.0, Vector2(7.0, 19.0)))


func test_night_brings_insects_and_takes_the_skylarks_away() -> void:
	Ambience.set_region("core:region/hearthvale")
	WorldClock.set_time(13.0)
	var day := _layers()
	WorldClock.set_time(23.0)
	var night := _layers()
	assert_true(day.has("skylark"), "skylarks sing by day")
	assert_false(night.has("skylark"), "skylarks do not sing at midnight")
	assert_true(night.has("night_insects"), "the night should have insects")
	assert_true(day.has("bees") and not night.has("bees"))


func test_the_marsh_gets_its_own_night_layer() -> void:
	Ambience.set_region("core:region/sedgemire")
	WorldClock.set_time(23.0)
	var night := _layers()
	assert_true(night.has("marsh_night"), str(night.keys()))
	assert_true(night.has("owl"), "and an owl over the water: %s" % str(night.keys()))
	assert_false(night.has("night_insects") or night.has("night_insects_marsh"), "no insects' whine (triage 53)")


func test_cinderlea_stays_empty_at_night() -> void:
	Ambience.set_region("core:region/cinderlea")
	WorldClock.set_time(23.0)
	var night := _layers()
	assert_false(night.has("night_insects"), "the ash heath has no insects left")
	assert_false(night.has("dawn_chorus"))


# --- weather ------------------------------------------------------------------------------------

func test_rain_follows_the_precipitation_intensity() -> void:
	Ambience.set_region("core:region/hearthvale")
	var dry := _layers({"precipitation": "none", "precip_intensity": 0.0, "wind": 0.0})
	assert_false(dry.has("rain_light") or dry.has("rain_heavy"))
	var drizzle := _layers({"precipitation": "rain", "precip_intensity": 0.3, "wind": 0.2})
	assert_true(drizzle.has("rain_light"), str(drizzle.keys()))
	var pour := _layers({"precipitation": "rain", "precip_intensity": 1.0, "wind": 0.4})
	assert_true(pour.has("rain_light"), str(pour.keys()))
	assert_gt(float(pour["rain_light"]), float(drizzle["rain_light"]),
		"heavier rain must be louder")


func test_rain_lands_on_the_surface_the_region_has() -> void:
	var wet := {"precipitation": "rain", "precip_intensity": 0.9, "wind": 0.2}
	Ambience.set_region("core:region/brightwater")
	assert_true(_layers(wet).has("rain_stone"), "Tollmere is a city of stone and slate")
	Ambience.set_region("core:region/sedgemire")
	assert_true(_layers(wet).has("rain_water"), "the marsh is rain falling on water")
	Ambience.set_region("core:region/cinderlea")
	assert_true(_layers(wet).has("rain_canvas"), "the pilgrims live under canvas")


func test_snow_and_ashfall_have_their_own_layers() -> void:
	Ambience.set_region("core:region/skerrow")
	assert_true(_layers({"precipitation": "snow", "precip_intensity": 0.7, "wind": 0.3})
		.has("snow_hush"))
	Ambience.set_region("core:region/cinderlea")
	assert_true(_layers({"precipitation": "ash", "precip_intensity": 0.8, "wind": 0.15})
		.has("ash_hiss"))


func test_wind_gust_layers_follow_the_wind() -> void:
	Ambience.set_region("core:region/skerrow")
	var calm := _layers({"precipitation": "none", "precip_intensity": 0.0, "wind": 0.05})
	assert_false(calm.has("wind_gust_light") or calm.has("wind_gust_strong"))
	var breeze := _layers({"precipitation": "none", "precip_intensity": 0.0, "wind": 0.35})
	assert_true(breeze.has("wind_gust_light"))
	var gale := _layers({"precipitation": "none", "precip_intensity": 0.0, "wind": 0.95})
	assert_true(gale.has("wind_gust_strong"))
	assert_gt(float(gale["wind_gust_strong"]), float(breeze["wind_gust_light"]))


func test_thunder_only_rolls_in_a_storm() -> void:
	Ambience.set_region("core:region/briarwold")
	var rain := _layers({"precipitation": "rain", "precip_intensity": 0.5, "wind": 0.3,
			"thunder": false})
	assert_false(rain.has("thunder_far") or rain.has("thunder_near"))
	var storm := _layers({"precipitation": "rain", "precip_intensity": 1.0, "wind": 1.0,
			"thunder": true})
	assert_true(storm.has("thunder_far"), "a storm rumbles")
	assert_true(storm.has("thunder_near"), "a heavy storm strikes close")


func test_thunder_is_spaced_between_twenty_and_ninety_seconds() -> void:
	for i in 40:
		var gap := Ambience._next_gap("thunder_near")
		assert_true(gap >= 20.0 and gap <= 90.0, "thunder gap %f is outside the range" % gap)


func test_every_weather_state_in_the_pack_produces_something_playable() -> void:
	for region in ContentDB.all("region"):
		Ambience.set_region(str(region["id"]))
		for key: String in region["identity"].get("weather", {}):
			var weather := ContentDB.get_def("core:weather/%s" % key)
			var want := _layers({
				"precipitation": weather.get("precipitation", "none"),
				"precip_intensity": weather.get("precip_intensity", 0.0),
				"wind": weather.get("wind", 0.0),
				"thunder": weather.get("thunder", false),
			})
			for layer: String in want:
				assert_has(Ambience._manifest, layer,
					"%s in %s wants '%s' and nothing renders it" % [key, region["id"], layer])


# --- interiors -------------------------------------------------------------------------------------

func test_stepping_inside_muffles_the_outside_and_adds_a_room() -> void:
	Ambience.set_region("core:region/hearthvale")
	var outside := _layers()
	EventBus.interior_entered.emit("core:interior/test_cell")
	var inside := Ambience.desired_layers()
	assert_true(Ambience.interior)
	assert_true(inside.has("room_tone"), "inside needs a room to be in")
	for key: String in outside:
		if inside.has(key):
			assert_gt(float(outside[key]), float(inside[key]),
				"%s should be quieter indoors" % key)
	EventBus.interior_exited.emit("core:interior/test_cell")
	assert_false(Ambience.interior)


func test_the_low_pass_closes_indoors_and_opens_outside() -> void:
	Ambience.interior = true
	for i in 60:
		Ambience._process(0.1)
	assert_true(Ambience.cutoff_hz() < 2000.0, "got %f Hz" % Ambience.cutoff_hz())
	Ambience.interior = false
	for i in 60:
		Ambience._process(0.1)
	assert_gt(Ambience.cutoff_hz(), 15000.0)


# --- switching off ------------------------------------------------------------------------------------

func test_disabling_the_mixer_asks_for_nothing() -> void:
	Ambience.enabled = false
	assert_empty(Ambience.desired_layers())
	Ambience.enabled = true


func test_an_unknown_region_asks_for_nothing_rather_than_erroring() -> void:
	Ambience.set_region("core:region/nowhere")
	assert_empty(_layers().keys())
