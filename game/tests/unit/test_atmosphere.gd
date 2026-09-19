extends TestCase


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
