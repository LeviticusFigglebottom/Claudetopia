extends TestCase

const ATMOSPHERE_SCENE := "res://systems/atmosphere/atmosphere.tscn"
const REGIONS := ["core:region/hearthvale", "core:region/brightwater", "core:region/sedgemire",
	"core:region/briarwold", "core:region/skerrow", "core:region/cinderlea"]


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func test_day_sample_shape() -> void:
	var noon: Array = Atmosphere._day_sample(12.0)
	var night: Array = Atmosphere._day_sample(1.0)
	var dawn: Array = Atmosphere._day_sample(6.5)
	assert_gt(float(noon[3]), 1.0, "noon sun energy")
	assert_near(float(night[3]), 0.0, 0.01, "night sun energy")
	assert_gt(float(night[5]), 0.9, "stars at night")
	assert_gt(float(dawn[3]), 0.1, "dawn has some sun")
	assert_gt(float(noon[4]), float(night[4]), "ambient brighter at noon")


func test_look_from_region() -> void:
	var def := ContentDB.get_def("core:region/cinderlea")
	var look := Atmosphere._look_from_region(def)
	assert_near(float(look["saturation"]), 0.55, 0.001)
	assert_near(float(look["sun_elevation_scale"]), 0.5, 0.001)
	assert_true(look["fog_color"] is Color)
	var hv := Atmosphere._look_from_region(ContentDB.get_def("core:region/hearthvale"))
	assert_gt(float(hv["saturation"]), float(look["saturation"]))


func test_weather_defs_complete() -> void:
	var needed := {}
	for r in ContentDB.all("region"):
		for k in r["identity"]["weather"]:
			needed["core:weather/%s" % k] = true
	for id in needed:
		assert_true(ContentDB.has(id), "missing weather def %s" % id)
	for w in ContentDB.all("weather"):
		for key in ["cloud_coverage", "fog_mult", "sun_mult", "precipitation", "wind", "wetness"]:
			assert_has(w, key, "%s lacks %s" % [w["id"], key])


# --- the day follows the sun, not the clock ---------------------------------------------------

## Keyed by the hour, a region whose sun is written low got a mid-afternoon sky over a sunset
## sun: Cinderlea's is nine degrees up at half past four. Keyed by the sun's own height, the sky
## and the light agree wherever the region puts its sun.
func test_the_sky_follows_the_sun_height() -> void:
	var night: Array = Atmosphere.sky_sample(-30.0)
	var low: Array = Atmosphere.sky_sample(1.0)
	var high: Array = Atmosphere.sky_sample(45.0)
	assert_near(float(night[3]), 0.0, 0.001, "a sun thirty degrees down lights nothing")
	assert_gt(float(night[5]), 0.9, "and the stars are out")
	assert_gt(float(high[3]), 1.2, "a high sun is the brightest light of the day")
	assert_gt(float(low[6]), 0.9, "a sun on the horizon sets the horizon burning")
	assert_near(float(high[6]), 0.0, 0.001, "and a high one does not")
	assert_gt((low[1] as Color).r, (high[1] as Color).r, "the horizon is redder at sunset than at noon")
	var prev := -1000.0
	for row in Atmosphere.SUN_KEYS:
		assert_gt(float(row[0]), prev, "SUN_KEYS must run from low to high")
		prev = float(row[0])


func test_night_is_zero_by_day_and_one_after_dark() -> void:
	assert_near(Atmosphere.night_of(30.0), 0.0, 0.001, "day")
	assert_near(Atmosphere.night_of(-20.0), 1.0, 0.001, "night")
	var dusk := Atmosphere.night_of(-2.0)
	assert_true(dusk > 0.2 and dusk < 0.9, "dusk is between, got %.2f" % dusk)


# --- six regions, six lights --------------------------------------------------------------------

## Each region's light is a named, deliberate palette (README.md in systems/atmosphere), and the
## names are what somebody tuning one of them reaches for.
func test_every_region_names_its_light() -> void:
	var names := {}
	for id in REGIONS:
		var look := Atmosphere._look_from_region(ContentDB.get_def(id))
		var n := str(look["name"])
		assert_false(n.is_empty(), "%s has no named light" % id)
		assert_false(names.has(n), "%s and %s share the light %s" % [id, names.get(n, ""), n])
		names[n] = id


## Regions used to differ by the colour of their ground more than by their light. This is the
## floor under that: every pair of regions differs in its sun, its shadows, its fog and its
## haze by more than a blend's worth, measured on the recipe itself.
func test_no_two_regions_are_lit_alike() -> void:
	var looks := {}
	for id in REGIONS:
		looks[id] = Atmosphere._look_from_region(ContentDB.get_def(id))
	for i in REGIONS.size():
		for j in range(i + 1, REGIONS.size()):
			var a: Dictionary = looks[REGIONS[i]]
			var b: Dictionary = looks[REGIONS[j]]
			var d := _colour_gap(a["sun_color"], b["sun_color"]) + _colour_gap(a["ambient_tint"], b["ambient_tint"]) \
				+ _colour_gap(a["fog_color"], b["fog_color"]) + _colour_gap(a["shadow_lift"], b["shadow_lift"]) \
				+ absf(float(a["saturation"]) - float(b["saturation"])) + absf(float(a["contrast"]) - float(b["contrast"])) \
				+ absf(float(a["haze_density"]) - float(b["haze_density"])) * 10.0
			assert_gt(d, 0.35, "%s and %s are lit almost alike (%.2f)" % [REGIONS[i], REGIONS[j], d])


func _colour_gap(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


## The marsh is where the fog is thickest and lowest; the high moor has the thinnest air.
func test_the_fog_is_where_the_bible_puts_it() -> void:
	var sedge := Atmosphere._look_from_region(ContentDB.get_def("core:region/sedgemire"))
	var sker := Atmosphere._look_from_region(ContentDB.get_def("core:region/skerrow"))
	for id in REGIONS:
		var look := Atmosphere._look_from_region(ContentDB.get_def(id))
		assert_true(float(sedge["haze_density"]) >= float(look["haze_density"]), "%s has more haze than the marsh" % id)
		assert_true(float(sker["fog_density"]) <= float(look["fog_density"]), "%s has thinner air than the moor" % id)


# --- the grade ---------------------------------------------------------------------------------

func test_the_grade_lifts_shadows_toward_the_region_and_keeps_white() -> void:
	var lift := Color(0.2, 0.1, 0.3)
	var black := Atmosphere.grade_colour(Color(0, 0, 0), lift, Color(1, 1, 1), Color(1, 1, 1))
	assert_near(black.b, 0.3, 0.001, "black is lifted to the lift colour")
	assert_gt(black.b, black.g, "and leans the way the lift does")
	var white := Atmosphere.grade_colour(Color(1, 1, 1), lift, Color(1, 0.9, 0.8), Color(1, 1, 1))
	assert_near(white.r, 1.0, 0.001, "white goes to the gain")
	assert_near(white.b, 0.8, 0.001)
	var mid := Atmosphere.grade_colour(Color(0.5, 0.5, 0.5), Color(0, 0, 0), Color(1, 1, 1), Color(1.0, 1.0, 0.8))
	assert_gt(mid.r, mid.b, "a midtone tint shows in the midtones")


func test_a_region_grade_is_a_full_lut() -> void:
	var look := Atmosphere._look_from_region(ContentDB.get_def("core:region/hearthvale"))
	var lut := Atmosphere.grade_lut(look)
	assert_eq(lut.get_width(), Atmosphere.GRADE_LUT_SIZE)
	assert_eq(lut.get_depth(), Atmosphere.GRADE_LUT_SIZE)


# --- a live atmosphere -------------------------------------------------------------------------

func _live(cam_y: float) -> Array:
	var holder := Node3D.new()
	_tree().root.add_child(holder)
	var cam := Camera3D.new()
	holder.add_child(cam)
	cam.position = Vector3(0.0, cam_y, 0.0)
	cam.current = true
	var atmos := (load(ATMOSPHERE_SCENE) as PackedScene).instantiate() as Atmosphere
	holder.add_child(atmos)
	return [holder, cam, atmos]


func _drop(holder: Node) -> void:
	_tree().root.remove_child(holder)
	holder.queue_free()


## The haze lies in whatever is below you. Godot's height fog is a function of a fragment's
## height alone, so a haze top fixed in the world veiled the grass at your feet as thickly as
## the valley a kilometre off; its top is held under the eye instead, and never above the
## region's ceiling.
func test_the_haze_stays_below_the_eye() -> void:
	var live := _live(200.0)
	var cam: Camera3D = live[1]
	var atmos: Atmosphere = live[2]
	atmos.set_region("core:region/hearthvale", true)
	atmos.settle()
	var look := atmos.look()
	assert_near(atmos.env.fog_height, float(look["haze_ceiling"]), 0.01, "from a hilltop the haze stops at its ceiling")
	cam.position.y = 30.0
	atmos.settle()
	assert_near(atmos.env.fog_height, 30.0 - float(look["haze_below_eye"]), 0.01, "in the vale it stays under the eye")
	assert_gt(atmos.env.fog_height_density, 0.0, "Hearthvale has a haze")
	atmos.set_interior(true)
	atmos.settle()
	assert_near(atmos.env.fog_height_density, 0.0, 0.0001, "and no haze indoors")
	_drop(live[0])


func test_settle_finishes_a_blend_at_once() -> void:
	var live := _live(50.0)
	var atmos: Atmosphere = live[2]
	atmos.set_region("core:region/hearthvale", true)
	atmos.set_region("core:region/cinderlea", false)
	atmos.settle()
	assert_near(float(atmos.look()["saturation"]), 0.55, 0.001, "a settled look is the region's own, not half of the last")
	_drop(live[0])


func test_night_puts_the_moon_up_and_the_exposure_with_it() -> void:
	var live := _live(50.0)
	var atmos: Atmosphere = live[2]
	atmos.set_region("core:region/hearthvale", true)
	var was := WorldClock.time_hours
	WorldClock.set_time(1.0)
	atmos.settle()
	assert_near(Atmosphere.night_factor, 1.0, 0.01, "one in the morning is night")
	assert_false(atmos.sun.visible, "no sun at one in the morning")
	assert_gt(atmos.moon.light_energy, 0.15, "the moon lights the ground a little")
	assert_true(atmos.moon.shadow_enabled, "and takes the shadows over from the sun")
	assert_gt(atmos.env.tonemap_exposure, 1.3, "and the eye opens up")
	WorldClock.set_time(10.0)
	atmos.settle()
	assert_near(Atmosphere.night_factor, 0.0, 0.01, "ten in the morning is day")
	assert_false(atmos.moon.shadow_enabled, "one set of cascades at a time")
	WorldClock.set_time(was)
	_drop(live[0])


## Volumetric fog and SDFGI are Forward+ features behind a settings flag each, and off unless
## asked for; nothing in the look may depend on them.
func test_the_forward_plus_extras_are_off_unless_asked_for() -> void:
	var live := _live(50.0)
	var atmos: Atmosphere = live[2]
	var extras := atmos.extras_active()
	assert_false(bool(extras["volumetric_fog"]), "volumetric fog is off by default")
	assert_false(bool(extras["sdfgi"]), "SDFGI is off by default")
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		assert_false(bool(extras["ssao"]), "SSAO is never on outside Forward+")
	_drop(live[0])
