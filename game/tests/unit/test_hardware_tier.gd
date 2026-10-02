extends TestCase
## The first launch's graphics preset (HardwareTier, Settings.recommend_graphics): what each kind of
## adapter is offered, read from fake adapters as the renderer would report them, and a settings
## file with a graphics section of its own is never touched.

const INTEGRATED := RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU
const DISCRETE := RenderingDevice.DEVICE_TYPE_DISCRETE_GPU
const OTHER := RenderingDevice.DEVICE_TYPE_OTHER
const CPU := RenderingDevice.DEVICE_TYPE_CPU

var _saved: Dictionary = {}


func before_each() -> void:
	_saved = Settings.data.duplicate(true)


func after_each() -> void:
	HardwareTier.fake_adapter = {}
	HardwareTier.decision = {}
	Settings.data = _saved.duplicate(true)
	Settings.path = Settings.PATH
	Settings.apply_all()


static func _a(type: int, name: String, vendor := "", ram_gb := 16.0) -> Dictionary:
	return {"type": type, "name": name, "vendor": vendor, "renderer": "forward_plus", "ram_gb": ram_gb, "vram_mb": -1}


func _preset(a: Dictionary) -> String:
	return str(HardwareTier.recommend(a)["preset"])


func test_amd_radeon_apus_get_medium_whatever_the_driver_calls_them() -> void:
	# the owner's HP G11 (a Ryzen 5 PRO): a 660M or a 740M, as Vulkan and as Compatibility name them
	for a in [_a(INTEGRATED, "AMD Radeon(TM) 740M", "AMD"), _a(INTEGRATED, "AMD Radeon(TM) 660M", "AMD"),
			_a(INTEGRATED, "AMD Radeon(TM) Graphics", "AMD"), _a(OTHER, "AMD Radeon(TM) 780M Graphics", "ATI Technologies Inc."),
			_a(OTHER, "AMD Radeon(TM) Graphics", "ATI Technologies Inc."),
			# a driver that calls the APU discrete is not believed: its memory is the machine's
			_a(DISCRETE, "AMD Radeon(TM) 760M", "AMD"), _a(DISCRETE, "AMD Radeon(TM) Graphics", "AMD")]:
		assert_eq(HardwareTier.kind_of(a), "integrated", str(a["name"]))
		assert_eq(_preset(a), "medium", str(a["name"]))
	assert_eq(_preset(_a(INTEGRATED, "AMD Radeon(TM) Vega 8 Graphics", "AMD")), "low", "an old Vega APU")
	assert_eq(_preset(_a(INTEGRATED, "AMD Radeon(TM) 610M", "AMD")), "low", "two compute units")


func test_intel_iris_xe_and_arc_igpus_get_medium_and_old_uhd_low() -> void:
	for a in [_a(INTEGRATED, "Intel(R) Iris(R) Xe Graphics", "Intel"), _a(INTEGRATED, "Intel(R) Arc(TM) Graphics", "Intel"),
			_a(INTEGRATED, "Intel(R) Arc(TM) 140V GPU (16GB)", "Intel"), _a(INTEGRATED, "Intel(R) Graphics", "Intel"),
			_a(OTHER, "Mesa Intel(R) Xe Graphics (TGL GT2)", "Intel")]:
		assert_eq(HardwareTier.kind_of(a), "integrated", str(a["name"]))
		assert_eq(_preset(a), "medium", str(a["name"]))
	for a in [_a(INTEGRATED, "Intel(R) UHD Graphics 620", "Intel"), _a(OTHER, "Intel(R) HD Graphics 520", "Intel")]:
		assert_eq(_preset(a), "low", str(a["name"]))


func test_discrete_cards_keep_high() -> void:
	for a in [_a(DISCRETE, "AMD Radeon RX 9070 XT", "AMD"), _a(DISCRETE, "NVIDIA GeForce RTX 4060 Laptop GPU", "NVIDIA"),
			_a(DISCRETE, "Intel(R) Arc(TM) A770 Graphics", "Intel"),
			# the Compatibility renderer names them but calls every one "other"
			_a(OTHER, "AMD Radeon RX 9070 XT", "ATI Technologies Inc."), _a(OTHER, "NVIDIA GeForce GTX 1060 6GB/PCIe/SSE2", "NVIDIA Corporation"),
			_a(OTHER, "Intel(R) Arc(TM) B580 Graphics", "Intel")]:
		assert_eq(HardwareTier.kind_of(a), "discrete", str(a["name"]))
		assert_eq(_preset(a), "high", str(a["name"]))
	assert_eq(_preset(_a(DISCRETE, "NVIDIA GeForce RTX 4070", "NVIDIA", 4.0)), "high",
			"a card's own memory is its own: the RAM floor is for iGPUs")


func test_software_low_and_an_unknown_adapter_medium() -> void:
	assert_eq(_preset(_a(CPU, "llvmpipe (LLVM 19.1.1, 256 bits)", "Mesa")), "low")
	assert_eq(_preset(_a(OTHER, "llvmpipe (LLVM 19.1.1, 256 bits)", "Mesa")), "low", "named, on Compatibility")
	assert_eq(_preset(_a(OTHER, "Microsoft Basic Render Driver", "Microsoft")), "low")
	assert_eq(HardwareTier.kind_of(_a(OTHER, "Some Future GPU 9000", "Nobody")), "unknown")
	assert_eq(_preset(_a(OTHER, "Some Future GPU 9000", "Nobody")), "medium", "an unknown adapter: the safe middle")
	assert_eq(_preset(_a(OTHER, "", "")), "medium", "and one with no name at all")


func test_an_igpu_short_of_memory_gets_low() -> void:
	assert_eq(_preset(_a(INTEGRATED, "AMD Radeon(TM) 740M", "AMD", 7.6)), "low", "under 8 GB shared")
	assert_eq(_preset(_a(INTEGRATED, "AMD Radeon(TM) 740M", "AMD", 15.7)), "medium")


func test_a_first_launch_takes_the_recommendation_and_a_saved_section_is_kept() -> void:
	var test_path := "user://test_hardware_tier.cfg"
	DirAccess.remove_absolute(test_path)
	var was_persist := Settings.persist
	var bindings := Settings.bindings.duplicate(true)
	Settings.path = test_path
	# no file: a first launch
	Settings.load_settings()
	assert_false(Settings.graphics_saved, "no graphics section yet")
	var igpu := _a(INTEGRATED, "AMD Radeon(TM) 740M", "AMD")
	var v := Settings.recommend_graphics(igpu, true)
	assert_eq(str(v["preset"]), "medium")
	assert_eq(Settings.get_value("graphics", "preset"), "medium", "the preset is Medium's")
	for key in Graphics.preset_values("medium"):
		assert_eq(str(Settings.get_value("graphics", key)), str(Graphics.preset_values("medium")[key]), key)
	assert_true(bool(HardwareTier.decision.get("first_launch", false)), "kept for the startup trace")
	assert_true(HardwareTier.describe(igpu, v).contains("740M"), "the trace's line names the adapter")
	# written, and then the player's: a later launch reads a section and asks nothing
	Settings.apply_graphics_preset("painted")
	Settings.persist = true
	Settings.save_settings()
	Settings.persist = was_persist
	Settings.load_settings()
	assert_true(Settings.graphics_saved, "the section is there now")
	assert_eq(Settings.get_value("graphics", "preset"), "painted", "the player's choice stands")
	# a file from before the graphics section, with its video keys, is the player's too
	var old := ConfigFile.new()
	old.set_value("video", "msaa", 0)
	old.save(test_path)
	Settings.load_settings()
	assert_true(Settings.graphics_saved, "video keys carried across count as a choice")
	var fov_only := ConfigFile.new()
	fov_only.set_value("video", "fov", 80.0)
	fov_only.save(test_path)
	Settings.load_settings()
	assert_false(Settings.graphics_saved, "a file with no graphics in it is still a first launch's")
	Settings.bindings = bindings
	DirAccess.remove_absolute(test_path)


func test_a_test_run_is_not_a_players_launch() -> void:
	assert_false(HardwareTier.players_launch(), "headless tests never get a first launch's verdict")


func test_the_settings_screen_detects_on_demand() -> void:
	HardwareTier.fake_adapter = _a(INTEGRATED, "Intel(R) Iris(R) Xe Graphics", "Intel")
	Settings.apply_graphics_preset("high")
	UI.gameplay_override = true
	var screen := UI.open("settings", {"tab": "Graphics"})
	await (Engine.get_main_loop() as SceneTree).process_frame
	var b := screen.find_child("DetectRecommended", true, false) as Button
	assert_true(b != null, "a Detect recommended button on the Graphics tab")
	if b != null:
		b.pressed.emit()
		assert_eq(Settings.get_value("graphics", "preset"), "medium", "pressing it sets the recommended preset")
	UI.close_all()
	UI.gameplay_override = false
