extends TestCase
## The graphics settings take effect: each knob, set through `Settings` the way the screen sets
## it, is read back from the engine -- the root viewport, the project and rendering server
## settings, a directional light's shadows, the world's environment, the streamer and the water.
## A knob with nothing in the engine to read back is a knob that does nothing, and
## `test_every_knob_moves_something_in_the_engine` fails on it by name.
##
## The directional shadow atlas size, the SSAO quality and (headless) vsync have no getter; for
## those the test reads the project setting `Graphics.apply` keeps in step and the record of the
## call it made (`Graphics.last_applied`).

const GRASS := "res://assets/models/flora/hearthvale_grass_clump_a/hearthvale_grass_clump_a.glb"
const TREE := "res://assets/models/trees/hearthvale_hawthorn_a/hearthvale_hawthorn_a.glb"
const ATMOSPHERE := "res://systems/atmosphere/atmosphere.tscn"


class FakeAtmosphere extends Node3D:
	var env: Environment
	var sun: DirectionalLight3D


## The world's ground as the settings see it: anything with a Terrain3DMaterial as `material`.
class FakeTerrain extends Node3D:
	var material: Object


var _holder: Node3D
var _light: DirectionalLight3D
var _moon: DirectionalLight3D
var _world_env: Environment
var _stage_env: Environment
var _streamer: WorldStreamer
var _water: WaterSurface
var _night: NightLights
var _horizon: HorizonLayer
var _wild: Wildlife
var _terrain: FakeTerrain
## The real atmosphere, made the first time a look knob is read: the colour grade, the vignette
## and the film grain are its to draw, and a stand-in would only prove the stand-in.
var _atmos: Atmosphere = null
var _saved: Dictionary = {}


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	_saved = Settings.data.duplicate(true)
	Graphics.renderer_override = ""


func after_each() -> void:
	Graphics.renderer_override = ""
	Settings.data = _saved.duplicate(true)
	Settings.apply_all()
	if _holder != null and is_instance_valid(_holder):
		_holder.queue_free()
	_holder = null


## A light, a moon, the world's environment under a fake atmosphere, a review stage's own
## environment, a streamer with a cell of grass and hawthorns, and a water surface: everything a
## graphics knob reaches, standing in the tree.
func _stage() -> void:
	_holder = Node3D.new()
	_tree().root.add_child(_holder)
	var atmos := FakeAtmosphere.new()
	atmos.add_to_group("atmosphere")
	_holder.add_child(atmos)
	_light = DirectionalLight3D.new()
	_light.shadow_enabled = true
	_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_light.directional_shadow_max_distance = 260.0
	atmos.add_child(_light)
	atmos.sun = _light
	_moon = DirectionalLight3D.new()
	_moon.shadow_enabled = false
	atmos.add_child(_moon)
	var we := WorldEnvironment.new()
	_world_env = Environment.new()
	_world_env.fog_enabled = true
	_world_env.glow_enabled = true
	we.environment = _world_env
	atmos.add_child(we)
	atmos.env = _world_env
	var stage := WorldEnvironment.new()
	_stage_env = Environment.new()
	_stage_env.fog_enabled = false
	stage.environment = _stage_env
	_holder.add_child(stage)
	_streamer = WorldStreamer.new()
	_holder.add_child(_streamer)
	var eye := Node3D.new()
	_holder.add_child(eye)
	eye.position = Vector3(128.0, 0.0, 128.0)
	_streamer.target = eye
	_water = WaterSurface.new()
	_water.sheet = MeshInstance3D.new()
	_water.sheet.mesh = PlaneMesh.new()
	_water._sheet_material = ShaderMaterial.new()
	_water.add_child(_water.sheet)
	_holder.add_child(_water)
	if not Settings.changed.is_connected(_water._on_setting_changed):
		Settings.changed.connect(_water._on_setting_changed)
	_terrain = FakeTerrain.new()
	_terrain.material = ClassDB.instantiate("Terrain3DMaterial") if ClassDB.class_exists("Terrain3DMaterial") else null
	_holder.add_child(_terrain)
	_terrain.add_to_group(Graphics.TERRAINS)
	_night = NightLights.new()
	_holder.add_child(_night)
	_horizon = HorizonLayer.new()
	_holder.add_child(_horizon)
	_wild = Wildlife.new()
	_holder.add_child(_wild)
	_atmos = null
	_build_cell()


func _build_cell() -> void:
	var rows_grass: Array = []
	for i in 40:
		rows_grass.append([100.0 + float(i), 0.0, 120.0, 0.0, 1.0, "#ffffff"])
	var rows_tree: Array = []
	for d in [8.0, 60.0, 140.0]:
		rows_tree.append([128.0 + d, 0.0, 128.0, 0.0, 1.0, "#ffffff"])
	_streamer._build_cell(Vector2i(16, 16), 0, {"instances": {GRASS: rows_grass, TREE: rows_tree}})


func _cell() -> Node3D:
	return _streamer._loaded.get(Vector2i(16, 16), null)


func _grass() -> MultiMeshInstance3D:
	var cell := _cell()
	if cell == null:
		return null
	for c in cell.get_children():
		if c is MultiMeshInstance3D and str(c.get_meta("asset_path", "")) == GRASS:
			return c
	return null


## The real atmosphere in Cinderlea, whose look has both a vignette and a grain, settled so what
## the settings say is drawn now rather than over the next blend.
func _look_atmosphere() -> Atmosphere:
	if _atmos == null or not is_instance_valid(_atmos):
		_atmos = (load(ATMOSPHERE) as PackedScene).instantiate() as Atmosphere
		_holder.add_child(_atmos)
		_atmos.set_region("core:region/cinderlea", true)
	_atmos.settle()
	return _atmos


## What the engine says for one knob, after it has been set.
func _read(key: String) -> Variant:
	var vp := _tree().root
	match key:
		"render_scale":
			return vp.scaling_3d_scale
		"upscaler":
			return vp.scaling_3d_mode
		"msaa":
			return vp.msaa_3d
		"fxaa":
			return vp.screen_space_aa
		"taa":
			return vp.use_taa
		"anisotropic":
			return vp.anisotropic_filtering_level
		"vsync":
			return Graphics.last_applied.get("vsync_mode")
		"fps_cap":
			return Engine.max_fps
		"shadows":
			return _light.shadow_enabled
		"shadow_atlas":
			return [ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size"),
					Graphics.last_applied.get("shadow_atlas")]
		"shadow_cascades":
			return _light.directional_shadow_mode
		"shadow_distance":
			return _light.directional_shadow_max_distance
		"shadow_filter":
			return ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality")
		"scatter_density":
			_streamer._unload(Vector2i(16, 16))
			_build_cell()
			var g := _grass()
			return g.multimesh.instance_count if g != null else -1
		"view_range":
			var g := _grass()
			return g.visibility_range_end if g != null else -1.0
		"lod_bias":
			var lad: ScatterLod.Ladder = ScatterLod._ladders.get(TREE)
			return [vp.mesh_lod_threshold, lad.near if lad != null else -1.0]
		"fog":
			return _world_env.fog_enabled
		"volumetric_fog":
			return _world_env.volumetric_fog_enabled
		"ssao":
			return _world_env.ssao_enabled
		"ao_quality":
			return [ProjectSettings.get_setting("rendering/environment/ssao/quality"),
					Graphics.last_applied.get("ao_quality")]
		"ssil":
			return _world_env.ssil_enabled
		"sdfgi":
			return _world_env.sdfgi_enabled
		"glow":
			return _world_env.glow_enabled
		"water_quality":
			return [(_water.sheet.mesh as PlaneMesh).subdivide_width,
					_water._sheet_material.get_shader_parameter("detail")]
		"water_reflections":
			# the mirrored shader names the screen texture; the other never does, so the frame
			# copy is saved as well as the mirror
			return _water._sheet_material.shader == WaterSurface.SHADER
		"night_lights":
			return _night.pool_size
		"wildlife":
			return _wild.density
		"view_distance":
			return [_horizon.reach("A"), _horizon.reach("B"), Graphics.camera_far(Settings.data.get("graphics", {})),
					Graphics.terrain_mesh_size(Settings.data.get("graphics", {}))]
		"color_grade":
			return _look_atmosphere().env.adjustment_color_correction != null
		"vignette":
			return float(_look_atmosphere()._vignette_mat.get_shader_parameter("amount"))
		"film_grain":
			return _look_atmosphere()._grain_rect.visible
		"title_vista":
			# read where the title reads it; a title already showing the country stops on it too
			return TitleVista.switched_on()
		"title_live":
			# live or filmed: a title showing the live country gives it up for the film when it goes off
			return TitleVista.live_switched_on()
		"occlusion":
			return vp.use_occlusion_culling
		"distant_ground":
			# Terrain3D's dual scaling on the ground's material, live
			return _terrain.material.get("dual_scaling") if _terrain != null and _terrain.material != null else null
		"full_terrain":
			# safe mode: the coarse ground, one threaded read at a time, and the title's country off
			return [SafeMode.active, WorldStatus.force_fallback, ThreadedLoads.limit(), TitleVista.switched_on()]
		"ground_textures":
			# the texture list the next world reads (World._start_reading_terrain)
			return World.assets_resource()
		"grass_instancer":
			# what the next world's terrain is asked to do (World._ready, GrassInstancer)
			return GrassInstancer.mode()
	return null


## A value for the knob that differs from `current`, inside its range and its choices.
static func _other(key: String, current: Variant) -> Variant:
	var c := Graphics.control(key)
	if key == "ground_textures":
		current = Graphics.ground_texture_quality({key: current})   # unchosen is this GPU's choice
	match str(c["kind"]):
		"check":
			return not bool(current)
		"slider":
			return float(c["min"]) if not is_equal_approx(float(current), float(c["min"])) else float(c["max"])
		_:
			var values: Array = c.get("values", [])
			if values.is_empty():
				return 1 if int(current) != 1 else 2
			return values[0] if not is_equal_approx(float(values[0]), float(current)) else values[values.size() - 1]


func test_defaults_are_high_and_the_display_keys() -> void:
	var expected: Dictionary = (Graphics.PRESETS["high"] as Dictionary).duplicate()
	expected.merge(Graphics.DISPLAY_DEFAULTS)
	expected.merge(Graphics.LOOK_DEFAULTS)
	expected.merge(Graphics.SAFETY_DEFAULTS)
	expected.merge(Graphics.MACHINE_DEFAULTS)
	expected.merge(Graphics.PROTOTYPE_DEFAULTS)
	expected["preset"] = "high"
	assert_eq(Graphics.DEFAULTS, expected, "Graphics.DEFAULTS is High plus the display, look and safety keys")
	for key in Graphics.LOOK_DEFAULTS.keys() + Graphics.SAFETY_DEFAULTS.keys() + Graphics.MACHINE_DEFAULTS.keys() + Graphics.PROTOTYPE_DEFAULTS.keys():
		assert_false((Graphics.PRESETS["painted"] as Dictionary).has(key), "no preset touches %s" % key)
	assert_eq(Settings.DEFAULTS["graphics"], Graphics.DEFAULTS, "and Settings.DEFAULTS names it")


func test_every_preset_sets_every_fidelity_knob_and_every_knob_has_a_control() -> void:
	var keys: Array = (Graphics.PRESETS["high"] as Dictionary).keys()
	keys.sort()
	for p in Graphics.PRESET_ORDER:
		var mine: Array = (Graphics.PRESETS[p] as Dictionary).keys()
		mine.sort()
		assert_eq(mine, keys, "%s sets a different set of knobs" % p)
	for key in Graphics.DEFAULTS:
		if key == "preset":
			continue
		assert_false(Graphics.control(key).is_empty(), "%s has no control on the screen" % key)
	for c in Graphics.CONTROLS:
		assert_has(Graphics.DEFAULTS, c["key"], "control %s is not a setting" % c["key"])


## Low is cheaper than Medium, Medium than High, High than Painted, knob by knob.
func test_presets_climb_in_cost() -> void:
	for key in ["render_scale", "shadow_atlas", "shadow_distance", "scatter_density", "view_range",
			"lod_bias", "water_quality", "anisotropic", "night_lights", "water_reflections", "view_distance", "wildlife"]:
		var prev := -INF
		for p in Graphics.PRESET_ORDER:
			var v := float(Graphics.PRESETS[p][key])
			assert_true(v >= prev, "%s: %s is below the preset before it" % [key, p])
			prev = v


func test_the_preset_is_named_until_a_knob_departs_from_it() -> void:
	Settings.apply_graphics_preset("low")
	assert_eq(Settings.get_value("graphics", "preset"), "low")
	Settings.set_value("graphics", "msaa", 3)
	assert_eq(Settings.get_value("graphics", "preset"), "custom")
	Settings.set_value("graphics", "msaa", Graphics.preset_values("low")["msaa"])
	assert_eq(Settings.get_value("graphics", "preset"), "low", "back on the preset's own value")


func test_compatibility_greys_out_what_it_cannot_do_and_says_why() -> void:
	var r := Graphics.RENDERER_COMPATIBILITY
	for key in ["fxaa", "taa", "volumetric_fog", "ssil", "sdfgi"]:
		assert_true(Graphics.unsupported_reason(key, null, r).contains("Forward+"), key)
	for key in ["msaa", "glow", "fog", "render_scale", "shadows", "lod_bias"]:
		assert_eq(Graphics.unsupported_reason(key, null, r), "", "%s works on Compatibility" % key)
	# Compatibility has an SSAO, but the world is lit without it there (see COMPATIBILITY_UNUSED)
	for key in ["ssao", "ao_quality"]:
		assert_ne(Graphics.unsupported_reason(key, null, r), "", "%s is greyed on Compatibility" % key)
		assert_eq(Graphics.unsupported_reason(key, null, Graphics.RENDERER_FORWARD_PLUS), "")
	assert_false(bool(Graphics.preset_values("high", r)["ssao"]), "High there asks for none")
	assert_eq(Graphics.preset_values("high", r)["ao_quality"], Graphics.PRESETS["high"]["ao_quality"],
			"and leaves the quality it would have had alone")
	assert_eq(Graphics.matching_preset(Graphics.DEFAULTS, r), "high",
			"a file that says High on Forward+ is still High on Compatibility")
	assert_eq(Graphics.unsupported_reason("upscaler", 0, r), "", "bilinear scaling works everywhere")
	assert_ne(Graphics.unsupported_reason("upscaler", 1, r), "", "FSR 1.0 does not on Compatibility")
	assert_ne(Graphics.unsupported_reason("upscaler", 2, r), "", "nor FSR 2.2")
	for key in Graphics.FORWARD_PLUS_ONLY:
		assert_eq(Graphics.unsupported_reason(key, null, Graphics.RENDERER_FORWARD_PLUS), "")
	# a preset asks only for what the renderer can do
	var low := Graphics.preset_values("low", r)
	assert_eq(low["upscaler"], 0, "Low on Compatibility scales bilinearly")
	assert_false(bool(low["fxaa"]), "and has no FXAA to ask for")


func test_a_forward_plus_only_knob_does_nothing_on_compatibility() -> void:
	await _stage_ready()
	Graphics.renderer_override = Graphics.RENDERER_COMPATIBILITY
	Settings.set_value("graphics", "taa", true)
	Settings.set_value("graphics", "sdfgi", true)
	Settings.set_value("graphics", "fxaa", true)
	assert_false(_tree().root.use_taa, "no TAA asked of a renderer without it")
	assert_eq(_tree().root.screen_space_aa, Viewport.SCREEN_SPACE_AA_DISABLED)
	assert_false(_world_env.sdfgi_enabled, "no SDFGI on Compatibility")
	Settings.set_value("graphics", "ssao", true)
	assert_false(_world_env.ssao_enabled, "the world keeps the look it was lit with on Compatibility")


func _stage_ready() -> void:
	_stage()
	# lights and environments are adopted at the end of the frame they arrive in
	await _tree().process_frame
	await _tree().process_frame


func test_every_knob_moves_something_in_the_engine() -> void:
	await _stage_ready()
	Settings.apply_graphics_preset("high")
	var dead: Array[String] = []
	for c in Graphics.CONTROLS:
		var key := str(c["key"])
		var before: Variant = _read(key)
		if before == null:
			dead.append("%s (nothing to read)" % key)
			continue
		Settings.set_value("graphics", key, _other(key, Settings.get_value("graphics", key)))
		var after: Variant = _read(key)
		if str(after) == str(before):
			dead.append("%s (%s before and after)" % [key, str(before)])
		Settings.set_value("graphics", key, Graphics.DEFAULTS[key])
	assert_empty(dead, "knobs the engine did not see move: %s" % ", ".join(dead))


func test_render_scale_msaa_and_lod_bias_reach_the_viewport() -> void:
	var vp := _tree().root
	Settings.set_value("graphics", "render_scale", 0.6)
	assert_near(vp.scaling_3d_scale, 0.6, 0.001)
	Settings.set_value("graphics", "msaa", 3)
	assert_eq(vp.msaa_3d, Viewport.MSAA_8X)
	var base := float(ProjectSettings.get_setting("rendering/mesh_lod/lod_change/threshold_pixels"))
	Settings.set_value("graphics", "lod_bias", 2.0)
	assert_near(vp.mesh_lod_threshold, base / 2.0, 0.001, "twice the bias, half the threshold")
	Settings.set_value("graphics", "fps_cap", 60)
	assert_eq(Engine.max_fps, 60)


func test_shadows_are_the_authors_cut_back_and_never_given_to_the_moon() -> void:
	await _stage_ready()
	Settings.set_value("graphics", "shadow_distance", 0.5)
	assert_near(_light.directional_shadow_max_distance, 130.0, 0.01, "half of the authored 260 m")
	Settings.set_value("graphics", "shadow_cascades", 2)
	assert_eq(_light.directional_shadow_mode, DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS)
	Settings.set_value("graphics", "shadows", false)
	assert_false(_light.shadow_enabled, "shadows off")
	Settings.set_value("graphics", "shadows", true)
	assert_true(_light.shadow_enabled, "and the author's shadows back")
	assert_false(_moon.shadow_enabled, "a light built without shadows is not given them")
	Settings.set_value("graphics", "shadow_atlas", 2048)
	assert_eq(int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size")), 2048)
	assert_eq(int(Graphics.last_applied["shadow_atlas"]), 2048)


func test_the_world_takes_settings_features_and_a_stage_keeps_its_own_look() -> void:
	await _stage_ready()
	Settings.set_value("graphics", "ssao", true)
	assert_true(_world_env.ssao_enabled, "the world's environment takes SSAO from the setting")
	Settings.set_value("graphics", "fog", false)
	assert_false(_world_env.fog_enabled)
	Settings.set_value("graphics", "fog", true)
	assert_true(_world_env.fog_enabled, "fog back where the world had it")
	assert_false(_stage_env.fog_enabled, "a stage that never had fog is not given it")
	Settings.set_value("graphics", "glow", false)
	assert_false(_world_env.glow_enabled)


func test_the_streamer_reads_view_range_density_and_bias() -> void:
	await _stage_ready()
	var grass := _grass()
	assert_true(grass != null, "the grass stood up as its own MultiMesh")
	if grass == null:
		return
	var base := float(grass.get_meta("range_base"))
	Settings.set_value("graphics", "view_range", 0.6)
	assert_near(grass.visibility_range_end, base * 0.6, 0.01, "view range reaches a built cell")
	Settings.set_value("graphics", "scatter_density", 0.5)
	assert_true(_streamer._rebuild_queued, "a density change rebuilds the cells")
	_streamer._unload(Vector2i(16, 16))
	_build_cell()
	assert_eq(_grass().multimesh.instance_count, 20, "half the ground cover of forty")
	var lad: ScatterLod.Ladder = ScatterLod._ladders.get(TREE)
	assert_true(lad != null, "the hawthorn is drawn down a ladder")
	if lad != null:
		var near := lad.near
		Settings.set_value("graphics", "lod_bias", 2.0)
		assert_near(lad.near, near * 2.0, 0.01, "twice the bias, twice as far at full detail")


func test_water_quality_recuts_the_sheet_live() -> void:
	await _stage_ready()
	Settings.set_value("graphics", "water_quality", 0)
	assert_eq((_water.sheet.mesh as PlaneMesh).subdivide_width, WaterSurface.QUALITY_SUBDIVISIONS[0])
	assert_near(float(_water._sheet_material.get_shader_parameter("detail")), 0.0, 0.001)
	Settings.set_value("graphics", "water_quality", 3)
	assert_eq((_water.sheet.mesh as PlaneMesh).subdivide_width, WaterSurface.QUALITY_SUBDIVISIONS[3])


## The real atmosphere: its sun is adopted with the shadows it was built with, and it draws with
## the player's brightness, which had been a slider that moved nothing.
func test_the_real_atmosphere_takes_the_settings() -> void:
	var atmos: Node = (load(ATMOSPHERE) as PackedScene).instantiate()
	_holder = Node3D.new()
	_tree().root.add_child(_holder)
	_holder.add_child(atmos)
	await _tree().process_frame
	await _tree().process_frame
	var sun: DirectionalLight3D = atmos.get("sun")
	var authored := float((sun.get_meta(Graphics.AUTHORED, {}) as Dictionary).get("distance", 0.0))
	assert_gt(authored, 0.0, "the sun was adopted with its authored reach")
	Settings.set_value("graphics", "shadow_distance", 1.5)
	assert_near(sun.directional_shadow_max_distance, authored * 1.5, 0.01)
	Settings.set_value("video", "brightness", 1.3)
	await _tree().process_frame
	var env: Environment = atmos.get("env")
	assert_near(env.adjustment_brightness, 1.3, 0.001, "brightness reaches the picture")


func test_settings_are_written_and_a_file_from_before_is_carried_across() -> void:
	var test_path := "user://test_graphics_settings.cfg"
	var old := ConfigFile.new()
	old.set_value("video", "render_scale", 0.7)
	old.set_value("video", "msaa", 0)
	old.set_value("video", "shadows", 0)
	old.set_value("video", "fov", 90.0)
	# and a file from the painted look, whose own keys were under video too
	old.set_value("video", "night_lights", 3)
	old.set_value("video", "water_reflections", false)
	old.set_value("video", "film_grain", true)
	old.save(test_path)
	var was_persist := Settings.persist
	var bindings := Settings.bindings.duplicate(true)
	Settings.path = test_path
	Settings.load_settings()
	assert_near(float(Settings.get_value("graphics", "render_scale")), 0.7, 0.001, "render scale moved over")
	assert_eq(int(Settings.get_value("graphics", "msaa")), 0)
	assert_false(bool(Settings.get_value("graphics", "shadows")), "shadows 0 meant off")
	assert_false((Settings.data["video"] as Dictionary).has("render_scale"), "and left video")
	assert_near(float(Settings.get_value("video", "fov")), 90.0, 0.001, "what stays in video stays")
	assert_eq(int(Settings.get_value("graphics", "night_lights")), 3, "the lamps moved over")
	assert_false(bool(Settings.get_value("graphics", "water_reflections")), "and the water's reflections")
	assert_true(bool(Settings.get_value("graphics", "film_grain")), "and the grain")
	for key in ["night_lights", "water_reflections", "film_grain"]:
		assert_false((Settings.data["video"] as Dictionary).has(key), "%s left video" % key)
	assert_eq(Settings.get_value("graphics", "preset"), "custom")
	Settings.persist = true
	Settings.set_value("graphics", "lod_bias", 1.75)
	Settings.save_settings()
	var back := ConfigFile.new()
	assert_eq(back.load(test_path), OK)
	assert_near(float(back.get_value("graphics", "lod_bias", 0.0)), 1.75, 0.001, "written to the file")
	Settings.persist = was_persist
	Settings.path = Settings.PATH
	Settings.bindings = bindings
	DirAccess.remove_absolute(test_path)


## Ground texture quality: a choice is kept as it is; unchosen (-1), a discrete GPU gets High and
## anything else (this machine's software renderer among them) Standard. The world reads the list
## the setting names, and Standard's when the High list is not there.
func test_ground_texture_quality_follows_the_choice_then_the_gpu() -> void:
	assert_eq(Graphics.ground_texture_quality({"ground_textures": 0}), 0, "Standard chosen")
	assert_eq(Graphics.ground_texture_quality({"ground_textures": 1}), 1, "High chosen")
	var discrete := RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU
	var by_gpu := 1 if discrete and Graphics.roomy_gpu(Graphics.video_memory_gb(), RenderingServer.get_video_adapter_name()) else 0
	assert_eq(Graphics.ground_texture_quality({}), by_gpu, "unchosen, by the GPU")
	# a discrete card: by its memory when it can be read, else by its name
	assert_true(Graphics.roomy_gpu(16.0, "AMD Radeon RX 9070 XT"), "16 GB is room")
	assert_false(Graphics.roomy_gpu(4.0, "AMD Radeon RX 9070 XT"), "4 GB is not, whatever the name")
	assert_true(Graphics.roomy_gpu(0.0, "AMD Radeon RX 9070 XT"), "unread, a large card by name")
	assert_false(Graphics.roomy_gpu(0.0, "NVIDIA GeForce GTX 1650"), "unread, a 4 GB card by name")
	assert_false(Graphics.roomy_gpu(0.0, "NVIDIA GeForce MX450"), "unread, a laptop's small discrete card")
	assert_eq(int(Graphics.DEFAULTS["ground_textures"]), -1, "shipped unchosen")
	assert_true(ResourceLoader.exists(World.ASSETS_RESOURCE_HIGH), "the High list ships")
	var was: Variant = Settings.get_value("graphics", "ground_textures", -1)
	Settings.data["graphics"]["ground_textures"] = 1
	assert_eq(World.assets_resource(), World.ASSETS_RESOURCE_HIGH, "High reads the High list")
	Settings.data["graphics"]["ground_textures"] = 0
	assert_eq(World.assets_resource(), World.ASSETS_RESOURCE, "Standard reads the Standard list")
	Settings.data["graphics"]["ground_textures"] = was
	assert_eq(int(Graphics.DEFAULTS["grass_instancer"]), 0, "the instancer trial is off unless chosen")
	GrassInstancer.active = false
	assert_false(GrassInstancer.takes(GrassInstancer.REGION, "res://assets/models/flora/x/x.glb"),
			"off, the streamer keeps every row")
	GrassInstancer.active = true
	assert_true(GrassInstancer.takes(GrassInstancer.REGION, "res://assets/models/flora/hearthvale_grass_clump_a/hearthvale_grass_clump_a.glb"),
			"on, the region's grass is the instancer's")
	assert_false(GrassInstancer.takes(GrassInstancer.REGION, "res://assets/models/trees/hearthvale_oak_a/hearthvale_oak_a.glb"),
			"and never a tree")
	assert_false(GrassInstancer.takes("core:region/skerrow", "res://assets/models/flora/skerrow_grass_clump_a/skerrow_grass_clump_a.glb"),
			"nor another region's grass")
	GrassInstancer.active = false


## A film's picture (Graphics.FILM): High and Painted are lifted, never lowered and never given a
## render scale of their own; Low and Medium, and a Custom drawn below the window, are left as they
## are, because they are what a small GPU can afford.
func test_a_film_lifts_high_and_painted_and_leaves_low_and_medium_alone() -> void:
	for preset: String in ["low", "medium"]:
		var g := Graphics.preset_values(preset)
		g["preset"] = preset
		assert_eq(Graphics.film_tier(g), "", "%s has no film tier" % preset)
		assert_eq(Graphics.film_values(g), g, "%s: a film keeps the settings" % preset)
	for preset: String in ["high", "painted"]:
		var g := Graphics.preset_values(preset)
		g["preset"] = preset
		var f := Graphics.film_values(g)
		assert_eq(f["render_scale"], g["render_scale"], "%s: the render scale is the preset's own" % preset)
		assert_eq(int(f["msaa"]), 2, "%s: 4x edges in a film" % preset)
		assert_false(bool(f["fxaa"]), "%s: no FXAA blur over MSAA" % preset)
		for key: String in g:
			if typeof(g[key]) in [TYPE_INT, TYPE_FLOAT] and key != "msaa":
				assert_true(float(f[key]) >= float(g[key]), "%s: %s is never lowered for a film" % [preset, key])
		assert_true(float(f["lod_bias"]) >= 2.0 and float(f["shadow_distance"]) >= 2.7, "%s: detail and shadows reach the subject" % preset)
	var custom := Graphics.preset_values("high")
	custom["preset"] = "custom"
	assert_eq(Graphics.film_tier(custom), "high", "a Custom at the window's size is lifted as High")
	custom["render_scale"] = 0.8
	assert_eq(Graphics.film_tier(custom), "", "a Custom drawn below the window is left alone")
