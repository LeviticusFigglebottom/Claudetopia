class_name Atmosphere
extends Node3D
## Sky, sun, moon, fog, post-processing, region look and weather in one node.
## See README.md in this folder.

const SKY_SHADER := preload("res://assets/shaders/painted_sky.gdshader")
const LOOK_BLEND_SECONDS := 6.0
const WEATHER_BLEND_GAME_MINUTES := 3.0

## Day cycle keyframes: hour -> [top, horizon, sun_color, sun_energy, ambient_energy, stars]
const DAY_KEYS := [
	[0.0,  Color(0.04, 0.06, 0.13), Color(0.10, 0.12, 0.20), Color(0.6, 0.7, 1.0), 0.0,  0.30, 1.0],
	[4.5,  Color(0.05, 0.07, 0.15), Color(0.14, 0.14, 0.22), Color(0.7, 0.7, 0.9), 0.0,  0.32, 0.9],
	[6.0,  Color(0.26, 0.38, 0.64), Color(0.98, 0.62, 0.38), Color(1.0, 0.66, 0.36), 0.8,  0.5,  0.2],
	[7.5,  Color(0.30, 0.52, 0.86), Color(0.93, 0.82, 0.66), Color(1.0, 0.86, 0.66), 1.05, 0.78, 0.0],
	[12.0, Color(0.20, 0.44, 0.88), Color(0.70, 0.80, 0.92), Color(1.0, 0.97, 0.90), 1.3,  1.0,  0.0],
	[16.5, Color(0.26, 0.50, 0.86), Color(0.90, 0.82, 0.66), Color(1.0, 0.90, 0.72), 1.15, 0.9,  0.0],
	[18.5, Color(0.32, 0.38, 0.66), Color(1.00, 0.56, 0.32), Color(1.0, 0.58, 0.30), 0.9,  0.55, 0.05],
	[20.0, Color(0.14, 0.16, 0.34), Color(0.52, 0.32, 0.40), Color(0.9, 0.55, 0.45), 0.15, 0.36, 0.5],
	[21.5, Color(0.05, 0.07, 0.16), Color(0.12, 0.13, 0.22), Color(0.6, 0.7, 1.0), 0.0,  0.30, 0.95],
	[24.0, Color(0.04, 0.06, 0.13), Color(0.10, 0.12, 0.20), Color(0.6, 0.7, 1.0), 0.0,  0.30, 1.0],
]

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var world_env: WorldEnvironment
var env: Environment
var sky_mat: ShaderMaterial
var precipitation: CPUParticles3D

var region_id := ""
var _look_from: Dictionary = {}
var _look_to: Dictionary = {}
var _look_t := 1.0
var _look: Dictionary = {}

var weather_by_region: Dictionary = {}     # region_id -> weather id
var _weather_from: Dictionary = {}
var _weather_to: Dictionary = {}
var _weather_t := 1.0
var _weather_params: Dictionary = {}
var _weather_timer_hours := 0.0
var _rng := RandomNumberGenerator.new()
var _forward_plus := false

const DEFAULT_LOOK := {
	"sun_color": Color(1, 0.94, 0.85), "sun_elevation_bias": 0.0, "sun_elevation_scale": 1.0,
	"fog_color": Color(0.8, 0.8, 0.78), "fog_density": 0.0012, "ambient_tint": Color(1, 1, 1),
	"saturation": 1.0, "contrast": 1.0, "bloom": 0.25, "grain": 0.0, "god_rays": false, "tint": Color(1, 1, 1),
}


func _ready() -> void:
	add_to_group("atmosphere")
	_forward_plus = RenderingServer.get_current_rendering_method() == "forward_plus"
	_rng.seed = 1043
	_build_nodes()
	_look = DEFAULT_LOOK.duplicate()
	_look_from = _look.duplicate()
	_look_to = _look.duplicate()
	_weather_params = _params_of("core:weather/clear")
	_weather_from = _weather_params.duplicate()
	_weather_to = _weather_params.duplicate()
	EventBus.region_entered.connect(_on_region_entered)
	SaveSystem.register("world", self)
	if not GameState.current_region_id.is_empty():
		set_region(GameState.current_region_id, true)
	_apply(0.0)


func _build_nodes() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 260.0
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.5
	sun.light_angular_distance = 0.8
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.shadow_enabled = false
	moon.light_color = Color(0.62, 0.70, 0.95)
	moon.light_energy = 0.0
	add_child(moon)
	world_env = WorldEnvironment.new()
	world_env.name = "Environment"
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.8
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.45
	env.fog_sun_scatter = 0.15
	env.fog_height = 0.0
	env.fog_height_density = 0.0
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	env.glow_intensity = 0.5
	env.adjustment_enabled = true
	env.ssao_enabled = _forward_plus
	env.ssao_radius = 1.5
	env.ssao_intensity = 1.5
	env.ssil_enabled = false
	world_env.environment = env
	add_child(world_env)
	precipitation = CPUParticles3D.new()
	precipitation.name = "Precipitation"
	precipitation.emitting = false
	precipitation.amount = 1200
	precipitation.lifetime = 2.0
	precipitation.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	precipitation.emission_box_extents = Vector3(14, 1, 14)
	precipitation.direction = Vector3(0, -1, 0)
	precipitation.spread = 4.0
	precipitation.gravity = Vector3.ZERO
	var qm := QuadMesh.new()
	qm.size = Vector2(0.03, 0.3)
	precipitation.mesh = qm
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pm.albedo_color = Color(0.8, 0.85, 0.95, 0.35)
	pm.vertex_color_use_as_albedo = true
	precipitation.material_override = pm
	add_child(precipitation)


# --- region look -------------------------------------------------------------------------

func _on_region_entered(new_region: String, _prev: String) -> void:
	set_region(new_region, false)


func set_region(id: String, instant := false) -> void:
	if not ContentDB.has(id):
		return
	region_id = id
	var look := _look_from_region(ContentDB.get_def(id))
	_look_from = _look.duplicate()
	_look_to = look
	_look_t = 1.0 if instant else 0.0
	if not weather_by_region.has(id):
		weather_by_region[id] = _pick_weather(id)
		_weather_timer_hours = _rng.randf_range(0.5, 1.5)
	_start_weather(weather_by_region[id], instant)


static func _look_from_region(def: Dictionary) -> Dictionary:
	var out := DEFAULT_LOOK.duplicate()
	var ident: Dictionary = def.get("identity", {})
	var light: Dictionary = ident.get("light", {})
	for key in ["sun_color", "fog_color", "ambient_tint"]:
		if light.has(key):
			out[key] = Color.html(str(light[key]))
	for key in ["sun_elevation_bias", "sun_elevation_scale", "fog_density", "saturation", "contrast", "bloom", "grain"]:
		if light.has(key):
			out[key] = float(light[key])
	out["god_rays"] = bool(light.get("god_rays", false))
	if light.has("sky_tint"):
		out["tint"] = Color.html(str(light["sky_tint"]))
	else:
		var pal: Array = ident.get("palette", [])
		if pal.size() >= 3:
			out["tint"] = Color.html(str(pal[2])).lerp(Color.WHITE, 0.8)
	return out


# --- weather -----------------------------------------------------------------------------

func _pick_weather(id: String) -> String:
	var def := ContentDB.get_def(id)
	var weights: Dictionary = def.get("identity", {}).get("weather", {"clear": 1})
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var r := _rng.randf() * total
	for k in weights:
		r -= float(weights[k])
		if r <= 0.0:
			return "core:weather/%s" % k
	return "core:weather/clear"


func _params_of(weather_id: String) -> Dictionary:
	var def := ContentDB.get_or_empty(weather_id)
	var out := {}
	for key in ["cloud_coverage", "cloud_softness", "fog_mult", "sun_mult", "precip_intensity", "wind", "wetness", "saturation_mult", "ambient_mult"]:
		out[key] = float(def.get(key, 0.0 if key in ["precip_intensity", "wind", "wetness"] else 1.0))
	if not def.has("cloud_coverage"):
		out["cloud_coverage"] = 0.3
		out["cloud_softness"] = 0.3
	out["precipitation"] = str(def.get("precipitation", "none"))
	out["thunder"] = bool(def.get("thunder", false))
	out["id"] = weather_id
	return out


func _start_weather(weather_id: String, instant := false) -> void:
	_weather_from = _weather_params.duplicate()
	_weather_to = _params_of(weather_id)
	_weather_t = 1.0 if instant else 0.0
	weather_by_region[region_id] = weather_id
	EventBus.weather_changed.emit(region_id, weather_id)


func force_weather(weather_id: String, instant := true) -> void:
	if ContentDB.has(weather_id):
		_start_weather(weather_id, instant)


func current_weather_id() -> String:
	return str(_weather_to.get("id", ""))


func weather_params() -> Dictionary:
	return _weather_params


# --- per frame ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _look_t < 1.0:
		_look_t = minf(1.0, _look_t + delta / LOOK_BLEND_SECONDS)
	if _weather_t < 1.0:
		var day_len: float = float(Settings.get_value("gameplay", "day_length_minutes", 48.0)) * 60.0
		var game_minutes_per_second := 1440.0 / maxf(day_len, 1.0)
		_weather_t = minf(1.0, _weather_t + delta * game_minutes_per_second / WEATHER_BLEND_GAME_MINUTES)
	_weather_timer_hours -= delta * 24.0 / (float(Settings.get_value("gameplay", "day_length_minutes", 48.0)) * 60.0)
	if _weather_timer_hours <= 0.0 and not region_id.is_empty():
		_weather_timer_hours = _rng.randf_range(0.6, 2.0)
		var next := _pick_weather(region_id)
		if next != current_weather_id():
			_start_weather(next)
	_apply(delta)


func _lerp_look(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for k in b:
		var va: Variant = a.get(k, b[k])
		var vb: Variant = b[k]
		match typeof(vb):
			TYPE_COLOR:
				out[k] = (va as Color).lerp(vb, t)
			TYPE_FLOAT, TYPE_INT:
				out[k] = lerpf(float(va), float(vb), t)
			_:
				out[k] = vb if t > 0.5 else va
	return out


static func _day_sample(hour: float) -> Array:
	var i := 0
	while i < DAY_KEYS.size() - 2 and hour > float(DAY_KEYS[i + 1][0]):
		i += 1
	var a: Array = DAY_KEYS[i]
	var b: Array = DAY_KEYS[i + 1]
	var span := float(b[0]) - float(a[0])
	var t := clampf((hour - float(a[0])) / maxf(span, 0.001), 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	return [
		(a[1] as Color).lerp(b[1], t), (a[2] as Color).lerp(b[2], t), (a[3] as Color).lerp(b[3], t),
		lerpf(float(a[4]), float(b[4]), t), lerpf(float(a[5]), float(b[5]), t), lerpf(float(a[6]), float(b[6]), t),
	]


func sun_direction() -> Vector3:
	return sun.global_transform.basis.z


func light_level_at(pos: Vector3) -> float:
	var day := clampf(sun.light_energy / 1.3, 0.0, 1.0)
	var moonlit := clampf(moon.light_energy / 0.25, 0.0, 1.0) * 0.15
	var base := maxf(day, moonlit)
	var space := get_world_3d().direct_space_state
	if space and day > 0.02:
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.5, pos + sun_direction() * 200.0)
		q.collision_mask = 1 | (1 << 10)
		if not space.intersect_ray(q).is_empty():
			base = maxf(base * 0.35, moonlit)
	return clampf(base * float(_weather_params.get("sun_mult", 1.0)) + 0.05, 0.0, 1.0)


func _apply(_delta: float) -> void:
	_look = _lerp_look(_look_from, _look_to, _look_t)
	_weather_params = _lerp_look(_weather_from, _weather_to, _weather_t)
	var hour := WorldClock.time_hours
	var s := _day_sample(hour)
	var top: Color = s[0]
	var horizon: Color = s[1]
	var sun_col: Color = s[2]
	var sun_energy: float = s[3]
	var ambient_energy: float = s[4]
	var stars: float = s[5]
	var w := _weather_params

	# sun position
	var elev := WorldClock.sun_elevation_deg() * float(_look["sun_elevation_scale"]) + float(_look["sun_elevation_bias"])
	var theta := PI * (hour - 6.0) / 12.0
	var e := deg_to_rad(elev)
	var sun_dir := Vector3(cos(theta) * cos(e), sin(e), 0.35 * cos(e)).normalized()
	sun.global_transform = Transform3D(Basis.looking_at(-sun_dir, Vector3.UP), Vector3.ZERO)
	var low := clampf((elev + 3.0) / 12.0, 0.0, 1.0)
	sun.light_energy = sun_energy * float(w["sun_mult"]) * low
	sun.light_color = sun_col.lerp(_look["sun_color"], 0.5)
	sun.visible = sun.light_energy > 0.01
	var moon_dir := Vector3(-sun_dir.x, absf(sun_dir.y) * 0.8 + 0.2, -sun_dir.z * 0.6).normalized()
	moon.global_transform = Transform3D(Basis.looking_at(-moon_dir, Vector3.UP), Vector3.ZERO)
	moon.light_energy = 0.38 * stars * (0.4 + 0.6 * float(w["sun_mult"]))
	moon.visible = moon.light_energy > 0.005

	# sky
	var tint: Color = _look["tint"]
	var fogc: Color = _look["fog_color"]
	var cloudy := float(w["cloud_coverage"])
	var top_c := top * tint
	var hor_c := horizon.lerp(fogc, 0.35) * tint
	top_c = top_c.lerp(hor_c.lerp(Color(0.5, 0.52, 0.55), 0.3), clampf((cloudy - 0.3) / 0.7, 0.0, 1.0) * 0.6)
	sky_mat.set_shader_parameter("horizon_sharpness", 3.2)
	sky_mat.set_shader_parameter("top_color", top_c)
	sky_mat.set_shader_parameter("horizon_color", hor_c)
	sky_mat.set_shader_parameter("ground_horizon_color", hor_c.darkened(0.25))
	sky_mat.set_shader_parameter("ground_color", hor_c.darkened(0.65))
	sky_mat.set_shader_parameter("sun_disc_color", sun_col.lightened(0.3))
	sky_mat.set_shader_parameter("sun_glow_color", sun_col)
	sky_mat.set_shader_parameter("sun_glow", 0.35 + 0.9 * (1.0 - low) + 0.3 * cloudy)
	sky_mat.set_shader_parameter("haze", 0.15 + 0.6 * clampf((float(w["fog_mult"]) - 1.0) / 2.0, 0.0, 1.0))
	sky_mat.set_shader_parameter("cloud_coverage", cloudy)
	sky_mat.set_shader_parameter("cloud_softness", float(w["cloud_softness"]))
	sky_mat.set_shader_parameter("cloud_speed", 0.004 + 0.03 * float(w["wind"]))
	sky_mat.set_shader_parameter("cloud_lit_color", Color(1.08, 1.04, 0.98).lerp(sun_col * 1.1, 0.6 * (1.0 - low)))
	sky_mat.set_shader_parameter("cloud_shade_color", hor_c.lerp(Color(0.36, 0.40, 0.50), 0.7) * (0.35 + 0.65 * ambient_energy))
	sky_mat.set_shader_parameter("cloud_opacity", 0.9)
	sky_mat.set_shader_parameter("stars", stars * (1.0 - cloudy * 0.8))
	sky_mat.set_shader_parameter("moon_dir", moon_dir)
	sky_mat.set_shader_parameter("moon_strength", stars)

	# environment
	env.ambient_light_energy = ambient_energy * float(w["ambient_mult"])
	env.ambient_light_color = (_look["ambient_tint"] as Color)
	env.fog_light_color = hor_c.lerp(fogc, 0.5).lerp(top_c, 0.15 * (1.0 - cloudy))
	env.fog_light_energy = lerpf(0.35, 1.0, ambient_energy)
	env.fog_density = float(_look["fog_density"]) * float(w["fog_mult"]) * lerpf(1.4, 1.0, ambient_energy)
	env.fog_sun_scatter = 0.1 + 0.4 * (1.0 - low) * low
	env.adjustment_saturation = float(_look["saturation"]) * float(w["saturation_mult"])
	env.adjustment_contrast = float(_look["contrast"])
	env.adjustment_brightness = 1.0
	env.glow_intensity = 0.35 + float(_look["bloom"])
	env.glow_bloom = 0.02 + 0.08 * float(_look["bloom"])

	# precipitation
	var kind: String = str(_weather_to.get("precipitation", "none")) if _weather_t > 0.5 else str(_weather_from.get("precipitation", "none"))
	var intensity := float(w["precip_intensity"])
	precipitation.emitting = kind != "none" and intensity > 0.02
	if precipitation.emitting:
		var cam := get_viewport().get_camera_3d()
		if cam:
			precipitation.global_position = cam.global_position + Vector3(0, 10, 0) + (-cam.global_transform.basis.z) * 4.0
		precipitation.amount = int(200 + 1400 * intensity)
		var mat := precipitation.material_override as StandardMaterial3D
		match kind:
			"rain":
				precipitation.initial_velocity_min = 14.0
				precipitation.initial_velocity_max = 18.0
				precipitation.lifetime = 1.4
				(precipitation.mesh as QuadMesh).size = Vector2(0.02, 0.45)
				mat.albedo_color = Color(0.75, 0.82, 0.95, 0.30)
			"snow":
				precipitation.initial_velocity_min = 1.2
				precipitation.initial_velocity_max = 2.2
				precipitation.lifetime = 7.0
				(precipitation.mesh as QuadMesh).size = Vector2(0.09, 0.09)
				mat.albedo_color = Color(1, 1, 1, 0.9)
			"ash":
				precipitation.initial_velocity_min = 0.6
				precipitation.initial_velocity_max = 1.4
				precipitation.lifetime = 9.0
				(precipitation.mesh as QuadMesh).size = Vector2(0.07, 0.05)
				mat.albedo_color = Color(0.55, 0.53, 0.5, 0.85)
		precipitation.direction = Vector3(float(w["wind"]) * 0.6, -1.0, 0.2 * float(w["wind"])).normalized()

	# global shader params for foliage / water / wetness
	RenderingServer.global_shader_parameter_set("wm_wind_strength", float(w["wind"]))
	RenderingServer.global_shader_parameter_set("wm_wind_dir", Vector3(0.8, 0.0, 0.6).normalized())
	RenderingServer.global_shader_parameter_set("wm_wetness", float(w["wetness"]))
	RenderingServer.global_shader_parameter_set("wm_time_of_day", hour)
	RenderingServer.global_shader_parameter_set("wm_region_tint", tint)


# --- save ---------------------------------------------------------------------------------

func to_save() -> Dictionary:
	return {"weather": weather_by_region.duplicate(), "weather_timer": _weather_timer_hours}


func from_save(d: Dictionary) -> void:
	weather_by_region = d.get("weather", {}).duplicate()
	_weather_timer_hours = float(d.get("weather_timer", 1.0))
	if weather_by_region.has(region_id):
		_start_weather(weather_by_region[region_id], true)
