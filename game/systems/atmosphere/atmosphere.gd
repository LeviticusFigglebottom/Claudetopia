class_name Atmosphere
extends Node3D
## Sky, sun, moon, fog, grade, region look and weather in one node.
## See README.md in this folder, which also carries the six regions' light and what each is for.

const SKY_SHADER := preload("res://assets/shaders/painted_sky.gdshader")
const OVERLAY_SHADER := preload("res://assets/shaders/grade_overlay.gdshader")
const LOOK_BLEND_SECONDS := 6.0
const WEATHER_BLEND_GAME_MINUTES := 3.0
## The colour grade is a 3D lookup table this many texels on a side, rebuilt from the region's
## lift, gain and midtone tint; while one region's look blends into the next it is rebuilt at
## most this often, because a rebuild is five thousand texels of GDScript.
const GRADE_LUT_SIZE := 17
const GRADE_REFRESH_SECONDS := 0.4
## How much of a region's `shadow_lift` colour reaches the blacks. The colour is written as the
## hue the shadows lean toward; at full strength a lift of #1a1430 would grey every shadow. It was
## 0.45, which raised Cinderlea's blacks to an eighth grey and every region's to a matte: with the
## fog, the bloom and the vignette over it, the first frame of the game read as washed out.
const GRADE_LIFT := 0.2
## The canvas layer the vignette and grain sit on: over the world, under the HUD (UI.LAYER_HUD).
const OVERLAY_LAYER := 1

## The day is keyed by the sun's height, not by the hour. Keyed by the hour, a region whose sun
## is written low -- Cinderlea stands at nine degrees at half past four -- got a mid-afternoon sky
## over a sunset sun. Columns: elevation (degrees), zenith, horizon, sun colour, sun energy,
## ambient energy, stars, dusk (how hard the horizon under the sun burns).
## The stars come out as the sky darkens, as they do: none until the sun is six degrees down (the
## end of civil twilight), most of them by twelve and all of them by eighteen. They used to be at
## half strength by six degrees down, over a dusk the night exposure had already brightened to
## rose, and the opening's evening at the Toll had stars in a sky still full of light.
const SUN_KEYS := [
	[-90.0, Color("#0b1226"), Color("#1a2238"), Color("#ff6a3a"), 0.0, 0.26, 1.0, 0.0],
	[-18.0, Color("#0c1429"), Color("#1f2640"), Color("#ff6a3a"), 0.0, 0.26, 1.0, 0.0],
	[-12.0, Color("#0e1630"), Color("#262c48"), Color("#ff6a3a"), 0.0, 0.27, 0.7, 0.05],
	[-6.0, Color("#1d2a52"), Color("#6b4a5e"), Color("#ff6a3a"), 0.0, 0.31, 0.12, 0.55],
	[-2.0, Color("#2f4478"), Color("#c46a4e"), Color("#ff6a3a"), 0.08, 0.40, 0.0, 1.0],
	[2.0, Color("#4a64a0"), Color("#f0955a"), Color("#ff8c4a"), 0.55, 0.55, 0.0, 1.0],
	[7.0, Color("#5a80c0"), Color("#f4c28c"), Color("#ffb070"), 0.95, 0.70, 0.0, 0.55],
	[15.0, Color("#4a7cc8"), Color("#d8dcd4"), Color("#ffd8a8"), 1.15, 0.85, 0.0, 0.15],
	[30.0, Color("#3a6fc8"), Color("#bcd2e6"), Color("#fff2e0"), 1.28, 0.95, 0.0, 0.0],
	[90.0, Color("#3468c6"), Color("#b4cce4"), Color("#fff8f0"), 1.32, 1.0, 0.0, 0.0],
]

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var world_env: WorldEnvironment
var env: Environment
var sky_mat: ShaderMaterial
var precipitation: CPUParticles3D
var overlay: CanvasLayer
var _vignette_mat: ShaderMaterial
var _grain_rect: ColorRect
var _grain_mat: ShaderMaterial

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
var interior := false
var _grade_age := 999.0
var _grade_dirty := true
## The grade's table: made once and rewritten in place, never replaced. The first cut handed the
## Environment a new texture for every refresh of a blend -- fifteen in a six-second blend --
## swapping a resource the renderer was drawing with.
var _grade_tex: ImageTexture3D = null
## What the precipitation was last set up as. Its mesh, material and particle count are resources
## and a reallocation: set every frame, as they were, a weather blend rebuilt the quad and
## restarted the particles sixty times a second.
var _precip_kind := ""
var _precip_amount := -1
## The last frame's state, for tests, the debug console and anything that wants to know how dark
## it is without asking the renderer: night (0 day .. 1 night), dusk, sun elevation in degrees.
var state: Dictionary = {}
## Values laid over the region's look while a tool tries a change without editing the pack: the
## capture runner's per-shot "look" and the debug console's `look <key> <value>`. The keys are a
## region light's (regions.json identity.light; `sky_tint` is `tint`), colours as "#rrggbb".
## Empty in play.
var look_override: Dictionary = {}

## 0 by day, 1 at night, in between at dusk. Lamps, windows and the night-light pool read it.
static var night_factor := 0.0
## What the grade LUT costs to rebuild: count, total and worst in microseconds. It is rebuilt on
## the main thread, at most every GRADE_REFRESH_SECONDS while one region's look blends into the
## next, so its worst case is a hitch at a region border. The capture runner writes it out.
## `textures` is how many table textures were ever made and `assigned` how many times one was
## handed to the Environment: one each, however many blends there are.
static var lut_stats := {"builds": 0, "us_total": 0, "us_max": 0, "textures": 0, "assigned": 0}

## `sun_elevation_scale` flattens the day's arc, and it is the difference between a country
## with shadows in it and one without. `WorldClock.sun_elevation_deg()` is a bare
## `-cos(hour)` curve that reaches 90 degrees at noon -- the sun directly overhead, which is
## a latitude Wickmere is not at. A sun that high casts a shadow 0.2 of the caster's height,
## straight down and hidden underneath it, so a village street at nine in the morning had no
## shadow anywhere in the frame and read as flat as a cardboard model. The scale is therefore
## not a mood dial but the region's latitude: 0.53 puts Hearthvale's noon sun at the 40-odd
## degrees WORLD_BIBLE section 6.1 asks for, and its nine o'clock sun at 30, where a cottage
## throws ten metres of shadow across the green.
##
## Every key a region's `identity.light` may carry, and what it is when the region is silent.
## README.md in this folder says what each one does and why each region's are what they are.
const DEFAULT_LOOK := {
	"name": "",
	# the sun
	"sun_color": Color(1, 0.94, 0.85), "sun_color_low": Color(1.0, 0.66, 0.40),
	"sun_elevation_bias": 0.0, "sun_elevation_scale": 0.55, "sun_energy": 1.0,
	# the fill: shadows take this colour, at this strength, with this much of the sky in it, and
	# `low_sun_fill` times the strength while the sun is up but low (`fill_lift`)
	"ambient_tint": Color(1, 1, 1), "ambient_energy": 1.0, "sky_contribution": 0.8, "low_sun_fill": 1.0,
	# the far fog, which is aerial perspective
	"fog_color": Color(0.8, 0.8, 0.78), "fog_density": 0.0012, "aerial_perspective": 0.35,
	"fog_sun_scatter": 0.15, "fog_sky_affect": 0.15,
	# the low haze, which lies in whatever is below you
	"haze_density": 0.0, "haze_ceiling": 60.0, "haze_below_eye": 20.0, "haze_morning": 0.0,
	# the grade
	"saturation": 1.0, "contrast": 1.0, "brightness": 1.0, "exposure": 1.0, "tonemap_white": 6.0,
	"shadow_lift": Color(0, 0, 0), "highlight_gain": Color(1, 1, 1), "midtone_tint": Color(1, 1, 1),
	"bloom": 0.25, "grain": 0.0, "vignette": 0.2, "vignette_tint": Color(0.08, 0.06, 0.05),
	# the sky
	"tint": Color(1, 1, 1), "horizon_tint": Color(1, 1, 1), "dusk_tint": Color(1.0, 0.55, 0.30),
	# the colour the far fog goes at dusk (unset, alpha 0: the burning horizon's own), and how
	# much more of the sky the distance takes then
	"dusk_fog_color": Color(0, 0, 0, 0), "dusk_aerial": 0.0,
	"cloud_bias": 0.0, "cloud_scale": 1.0, "cloud_height": 0.15, "cloud_band": 0.25, "cirrus": 0.3,
	"painterly": 0.45,
	# the night
	"night_tint": Color(0.62, 0.70, 0.95), "night_exposure": 1.3, "moon_energy": 1.0,
	"god_rays": false,
}
const _COLOUR_KEYS := ["sun_color", "sun_color_low", "ambient_tint", "fog_color", "shadow_lift",
	"highlight_gain", "midtone_tint", "vignette_tint", "horizon_tint", "dusk_tint", "night_tint",
	"dusk_fog_color"]
const _FLOAT_KEYS := ["sun_elevation_bias", "sun_elevation_scale", "sun_energy", "ambient_energy",
	"sky_contribution", "low_sun_fill", "fog_density", "aerial_perspective", "fog_sun_scatter", "fog_sky_affect",
	"haze_density", "haze_ceiling", "haze_below_eye", "haze_morning", "saturation", "contrast",
	"brightness", "exposure", "tonemap_white", "bloom", "grain", "vignette", "cloud_bias",
	"cloud_scale", "cloud_height", "cloud_band", "cirrus", "painterly", "night_exposure", "moon_energy",
	"dusk_aerial"]


func _ready() -> void:
	add_to_group("atmosphere")
	# The sun, the moon and the rain that follows the camera are placed every frame, not moved by
	# physics: interpolating them between ticks would only make them lag and step.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
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
	Settings.changed.connect(_on_setting_changed)
	SaveSystem.register("world", self)
	if not GameState.current_region_id.is_empty():
		set_region(GameState.current_region_id, true)
	_apply_extras()
	_apply(0.0)


func _exit_tree() -> void:
	night_factor = 0.0


func _build_nodes() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	_shadow_setup(sun)
	add_child(sun)
	# The moon is a light of its own and is left out of the sky shader, which draws its own
	# disc; it takes the shadows over when the sun has set, so only one of them ever pays for
	# the cascades.
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.shadow_enabled = false
	_shadow_setup(moon)
	# Moonlight is soft and nobody reads a shadow at forty metres by it: two cascades over
	# 160 m cost half of what the sun's four do, which is what a night frame pays over a day's.
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.directional_shadow_max_distance = 160.0
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
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
	env.tonemap_white = 6.0   # outdoors; _apply() drops it indoors
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
	world_env.environment = env
	add_child(world_env)
	_build_overlay()
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


static func _shadow_setup(light: DirectionalLight3D) -> void:
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	light.directional_shadow_max_distance = 260.0
	light.directional_shadow_split_1 = 0.06
	light.directional_shadow_split_2 = 0.18
	light.directional_shadow_split_3 = 0.45
	light.directional_shadow_blend_splits = true
	light.shadow_bias = 0.03
	light.shadow_normal_bias = 1.5
	light.light_angular_distance = 0.8


## The vignette and the grain: two full-screen rects over the world and under the HUD. Neither
## reads the screen, so each is one alpha-blended canvas draw and works on every renderer.
func _build_overlay() -> void:
	overlay = CanvasLayer.new()
	overlay.name = "GradeOverlay"
	overlay.layer = OVERLAY_LAYER
	add_child(overlay)
	var vignette := ColorRect.new()
	vignette.name = "Vignette"
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_mat = ShaderMaterial.new()
	_vignette_mat.shader = OVERLAY_SHADER
	_vignette_mat.set_shader_parameter("mode", 0)
	vignette.material = _vignette_mat
	overlay.add_child(vignette)
	_grain_rect = ColorRect.new()
	_grain_rect.name = "Grain"
	_grain_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_grain_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grain_mat = ShaderMaterial.new()
	_grain_mat.shader = OVERLAY_SHADER
	_grain_mat.set_shader_parameter("mode", 1)
	_grain_rect.material = _grain_mat
	_grain_rect.visible = false
	overlay.add_child(_grain_rect)


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
	_grade_dirty = true
	if not weather_by_region.has(id):
		weather_by_region[id] = _pick_weather(id)
		_weather_timer_hours = _rng.randf_range(0.5, 1.5)
	_start_weather(weather_by_region[id], instant)


## Finishes whatever look or weather is blending, now. A capture teleports between regions and
## photographs the first settled frame; a six-second blend is right for walking and wrong for a
## photograph, which would otherwise be of half of one region's light and half of the last.
func settle() -> void:
	_look_t = 1.0
	_weather_t = 1.0
	_grade_dirty = true
	_apply(0.0)


func look() -> Dictionary:
	return _look


static func _look_from_region(def: Dictionary) -> Dictionary:
	var out := DEFAULT_LOOK.duplicate()
	var ident: Dictionary = def.get("identity", {})
	var light: Dictionary = ident.get("light", {})
	for key in _COLOUR_KEYS:
		if light.has(key):
			out[key] = Color.html(str(light[key]))
	for key in _FLOAT_KEYS:
		if light.has(key):
			out[key] = float(light[key])
	out["god_rays"] = bool(light.get("god_rays", false))
	out["name"] = str(light.get("name", ""))
	if light.has("sky_tint"):
		out["tint"] = Color.html(str(light["sky_tint"]))
	else:
		var pal: Array = ident.get("palette", [])
		if pal.size() >= 3:
			out["tint"] = Color.html(str(pal[2])).lerp(Color.WHITE, 0.8)
	if not light.has("horizon_tint"):
		out["horizon_tint"] = out["tint"]
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
		_grade_dirty = true
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
	_grade_age += delta
	_apply(delta)


## `lk` with the keys of `over` laid on it, each as the type the look holds it: a colour from
## "#rrggbb", a number from anything numeric. Keys the look does not have are ignored.
static func with_override(lk: Dictionary, over: Dictionary) -> Dictionary:
	var out := lk.duplicate()
	for k in over:
		var key := "tint" if str(k) == "sky_tint" else str(k)
		if not out.has(key):
			continue
		var v: Variant = over[k]
		match typeof(out[key]):
			TYPE_COLOR:
				out[key] = Color.html(str(v)) if v is String else v
			TYPE_FLOAT, TYPE_INT:
				out[key] = float(v)
			TYPE_BOOL:
				out[key] = str(v) in ["true", "1", "on"] if v is String else bool(v)
			_:
				out[key] = v
	return out


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


## The sky and the light for a sun at `elev_deg`. Returns zenith, horizon, sun colour, sun
## energy, ambient energy, stars and dusk, smoothly interpolated between SUN_KEYS.
static func sky_sample(elev_deg: float) -> Array:
	var i := 0
	while i < SUN_KEYS.size() - 2 and elev_deg > float(SUN_KEYS[i + 1][0]):
		i += 1
	var a: Array = SUN_KEYS[i]
	var b: Array = SUN_KEYS[i + 1]
	var span := float(b[0]) - float(a[0])
	var t := clampf((elev_deg - float(a[0])) / maxf(span, 0.001), 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	return [
		(a[1] as Color).lerp(b[1], t), (a[2] as Color).lerp(b[2], t), (a[3] as Color).lerp(b[3], t),
		lerpf(float(a[4]), float(b[4]), t), lerpf(float(a[5]), float(b[5]), t),
		lerpf(float(a[6]), float(b[6]), t), lerpf(float(a[7]), float(b[7]), t),
	]


## The day by the hour, for a region that says nothing about its sun: [zenith, horizon, sun
## colour, sun energy, ambient energy, stars]. Kept for callers that think in hours.
static func _day_sample(hour: float) -> Array:
	var elev := -cos(hour / 24.0 * TAU) * 90.0 * float(DEFAULT_LOOK["sun_elevation_scale"])
	var s := sky_sample(elev)
	return [s[0], s[1], s[2], s[3], s[4], s[5]]


## How much the region's fill is multiplied by for a sun at `elev_deg`: all of `low_sun_fill` while
## the sun is up but under four degrees, less as it climbs, none by twenty-four, and none at
## night, which has its own exposure. A sun that low lights flat ground at a graze, so what the
## ground shows is the fill; in a region whose sun never climbs, the fill is the day. Cinderlea's
## sun stands at six degrees when a new game hands over at the Stair Head, and under its fill
## alone the ash ground came out black on every renderer: dark soil in dim light lands in the
## toe of the ACES curve, which takes the darkest values to zero, and a grey ground (albedo 0.2,
## Terrain3D's debug view) came out as black as the ash did.
static func fill_lift(lk: Dictionary, elev_deg: float) -> float:
	var low := (1.0 - smoothstep(4.0, 24.0, elev_deg)) * smoothstep(-6.0, 0.0, elev_deg)
	return lerpf(1.0, float(lk.get("low_sun_fill", 1.0)), low)


## How far into the night a sun at `elev_deg` puts the world: 0 by day, 1 once it is dark.
static func night_of(elev_deg: float) -> float:
	return 1.0 - smoothstep(-8.0, 3.0, elev_deg)


func set_interior(inside: bool) -> void:
	interior = inside


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
	if not look_override.is_empty():
		_look = with_override(_look, look_override)
	_weather_params = _lerp_look(_weather_from, _weather_to, _weather_t)
	var lk := _look
	var w := _weather_params
	var hour := WorldClock.time_hours
	var rising := hour < 12.0

	# the sun's height is the region's latitude applied to the clock
	# A positive bias on a region whose noon is already at the top of the arc used to push the
	# elevation past vertical (Brightwater reached 94 degrees), which flips cos(e) negative and
	# swings the sun's bearing to the opposite side of the sky between one hour and the next.
	var elev: float = clampf(WorldClock.sun_elevation_deg() * float(lk["sun_elevation_scale"])
			+ float(lk["sun_elevation_bias"]), -90.0, 86.0)
	var s := sky_sample(elev)
	var zenith: Color = s[0]
	var horizon: Color = s[1]
	var ramp_sun: Color = s[2]
	var sun_energy: float = s[3]
	var ambient_energy: float = s[4]
	var stars: float = s[5]
	var dusk: float = s[6]
	var night := night_of(elev)
	night_factor = night
	var cloudy := clampf(float(w["cloud_coverage"]) + float(lk["cloud_bias"]), 0.0, 1.0)
	var sun_mult := float(w["sun_mult"])

	# --- sun and moon ------------------------------------------------------------------
	var theta := PI * (hour - 6.0) / 12.0
	var e := deg_to_rad(elev)
	var sun_dir := Vector3(cos(theta) * cos(e), sin(e), 0.35 * cos(e)).normalized()
	sun.global_transform = Transform3D(Basis.looking_at(-sun_dir, Vector3.UP), Vector3.ZERO)
	# the region's own sun: its low colour near the horizon, its day colour above twenty degrees
	var region_sun: Color = (lk["sun_color_low"] as Color).lerp(lk["sun_color"], smoothstep(1.0, 22.0, elev))
	var sun_col := ramp_sun.lerp(region_sun, 0.6)
	sun.light_energy = sun_energy * float(lk["sun_energy"]) * sun_mult
	sun.light_color = sun_col
	sun.visible = sun.light_energy > 0.01
	var moon_dir := Vector3(-sun_dir.x, absf(sun_dir.y) * 0.8 + 0.2, -sun_dir.z * 0.6).normalized()
	moon.global_transform = Transform3D(Basis.looking_at(-moon_dir, Vector3.UP), Vector3.ZERO)
	var night_tint: Color = lk["night_tint"]
	moon.light_color = night_tint.lerp(Color(0.85, 0.9, 1.0), 0.35)
	moon.light_energy = 0.26 * night * float(lk["moon_energy"]) * (0.35 + 0.65 * clampf(sun_mult, 0.0, 1.0))
	moon.visible = moon.light_energy > 0.005
	# one set of cascades at a time: the moon casts only once the sun has gone
	moon.shadow_enabled = moon.visible and not sun.visible and not interior

	# --- sky -----------------------------------------------------------------------------
	var tint: Color = lk["tint"]
	var fogc: Color = lk["fog_color"]
	var top_c := zenith * tint
	# The horizon takes a little of the fog's colour, so the land's far edge melts into it; at
	# three tenths every region's horizon went the grey-brown of its fog, and a level view -- which
	# sees the sky only up to twenty degrees -- saw nothing but that band.
	var hor_c := horizon.lerp(fogc, 0.15) * (lk["horizon_tint"] as Color)
	top_c = top_c.lerp(hor_c.lerp(Color(0.5, 0.52, 0.55), 0.3), clampf((cloudy - 0.3) / 0.7, 0.0, 1.0) * 0.6)
	var dusk_col: Color = lk["dusk_tint"]
	if rising:
		# dawn is cooler and pinker than dusk, which is redder
		dusk_col = dusk_col.lerp(Color(1.0, 0.62, 0.68), 0.35)
	var sky_dusk := dusk * (1.0 - cloudy * 0.55)
	var shown_sun := sun_energy * clampf(sun_mult * 1.2, 0.2, 1.0)
	# the blue comes down to within a few degrees of the horizon: at 3.2 a level view's sky was
	# more than half horizon colour up to the top of the frame
	sky_mat.set_shader_parameter("horizon_sharpness", 4.5)
	sky_mat.set_shader_parameter("top_color", top_c)
	sky_mat.set_shader_parameter("horizon_color", hor_c)
	sky_mat.set_shader_parameter("ground_horizon_color", hor_c.darkened(0.25))
	sky_mat.set_shader_parameter("ground_color", hor_c.darkened(0.65))
	sky_mat.set_shader_parameter("sun_dir", sun_dir)
	# a source_color uniform is converted from sRGB, so 3.0 here is about 10 in the shader: enough
	# to clear the glow threshold and bloom, not so much that the disc floods the frame
	sky_mat.set_shader_parameter("sun_disc_color", sun_col.lightened(0.35) * (1.0 + 1.6 * shown_sun))
	sky_mat.set_shader_parameter("sun_energy", shown_sun)
	sky_mat.set_shader_parameter("sun_glow_color", sun_col)
	sky_mat.set_shader_parameter("sun_glow", 0.45 + 0.8 * sky_dusk + 0.3 * cloudy)
	sky_mat.set_shader_parameter("dusk", sky_dusk)
	sky_mat.set_shader_parameter("dusk_color", dusk_col)
	sky_mat.set_shader_parameter("antisolar_color", dusk_col.lerp(Color(0.78, 0.60, 0.72), 0.6))
	sky_mat.set_shader_parameter("haze", 0.15 + 0.6 * clampf((float(w["fog_mult"]) - 1.0) / 2.0, 0.0, 1.0))
	var light_dir := sun_dir if elev > -4.0 else moon_dir
	sky_mat.set_shader_parameter("light_dir", light_dir)
	sky_mat.set_shader_parameter("cloud_coverage", cloudy)
	sky_mat.set_shader_parameter("cloud_softness", float(w["cloud_softness"]))
	sky_mat.set_shader_parameter("cloud_speed", 0.004 + 0.03 * float(w["wind"]))
	sky_mat.set_shader_parameter("cloud_scale", float(lk["cloud_scale"]))
	sky_mat.set_shader_parameter("cloud_height", float(lk["cloud_height"]))
	sky_mat.set_shader_parameter("cloud_band", float(lk["cloud_band"]))
	sky_mat.set_shader_parameter("cirrus", float(lk["cirrus"]) * (1.0 - cloudy * 0.6))
	sky_mat.set_shader_parameter("painterly", float(lk["painterly"]))
	var wind_dir := Vector2(0.8, 0.6).normalized()
	sky_mat.set_shader_parameter("wind", wind_dir)
	var day_lit := Color(1.06, 1.03, 0.98).lerp(sun_col * 1.15, 0.65 * dusk) * clampf(0.35 + sun_energy * 0.7, 0.3, 1.2)
	var night_lit := moon.light_color * 0.42
	sky_mat.set_shader_parameter("cloud_lit_color", day_lit.lerp(night_lit, night))
	sky_mat.set_shader_parameter("cloud_shade_color", hor_c.lerp(Color(0.36, 0.40, 0.50), 0.65) * (0.3 + 0.7 * ambient_energy))
	sky_mat.set_shader_parameter("cloud_under_color", dusk_col.lerp(sun_col, 0.3))
	sky_mat.set_shader_parameter("cloud_opacity", 0.92)
	sky_mat.set_shader_parameter("stars", stars * (1.0 - cloudy * 0.8))
	sky_mat.set_shader_parameter("moon_dir", moon_dir)
	sky_mat.set_shader_parameter("moon_color", night_tint.lerp(Color(0.92, 0.94, 1.0), 0.6))
	sky_mat.set_shader_parameter("moon_strength", stars * (1.0 - cloudy * 0.6))

	# --- the fill: coloured shadows ------------------------------------------------------
	env.ambient_light_energy = ambient_energy * float(lk["ambient_energy"]) * float(w["ambient_mult"]) \
			* (0.62 if interior else fill_lift(lk, elev))
	env.ambient_light_color = (lk["ambient_tint"] as Color).lerp(night_tint, night)
	# At dusk the sky is orange at one side and the shadows would take it; painted dusk is warm
	# light and cool shadow, so the region's own tint carries more of the fill as the sun goes.
	env.ambient_light_sky_contribution = lerpf(float(lk["sky_contribution"]) * (1.0 - 0.5 * dusk), 0.25, night)

	# --- fog: the far layer and the low haze ---------------------------------------------
	# The far fog is aerial perspective: it takes the horizon's colour, most of all at dusk,
	# when the whole distance goes the colour of the sky behind it.
	# A region can name the colour its distance goes at dusk: Hearthvale's goes lavender-rose
	# over the gold, where otherwise every dusk in the country was the same orange haze.
	var dfog: Color = lk["dusk_fog_color"]
	var fog_col := fogc.lerp(hor_c, 0.25 + 0.15 * dusk * (1.0 - dfog.a))
	fog_col = fog_col.lerp(Color(dfog.r, dfog.g, dfog.b), 0.6 * dusk * dfog.a)
	fog_col = fog_col.lerp(night_tint * 0.32, night * 0.85)
	env.fog_light_color = fog_col.lerp(top_c, 0.12 * (1.0 - cloudy))
	env.fog_light_energy = lerpf(0.35, 1.0, ambient_energy)
	env.fog_density = float(lk["fog_density"]) * float(w["fog_mult"]) * lerpf(1.0, 1.3, night) * (0.12 if interior else 1.0)
	env.fog_aerial_perspective = clampf(float(lk["aerial_perspective"]) * (1.0 - 0.7 * night)
			+ float(lk["dusk_aerial"]) * dusk, 0.0, 1.0)
	env.fog_sun_scatter = float(lk["fog_sun_scatter"]) * (0.35 + 0.65 * dusk) * (1.0 if sun.visible else 0.0)
	env.fog_sky_affect = float(lk["fog_sky_affect"])
	# The haze lies in whatever is below you. Godot's height fog is a function of a fragment's
	# height alone, not of how far away it is, so a haze top fixed in the world veils the grass
	# at your feet as thickly as the valley a kilometre off. Holding its top a region's
	# `haze_below_eye` under the camera, and never above its `haze_ceiling`, keeps the near
	# ground clear and fills the valleys you look down into -- which is what a vista is for.
	var morning := 0.0
	if rising:
		morning = smoothstep(-4.0, 2.0, elev) * (1.0 - smoothstep(4.0, 22.0, elev))
	var eye_y := _eye_height()
	env.fog_height = minf(float(lk["haze_ceiling"]), eye_y - float(lk["haze_below_eye"]))
	env.fog_height_density = 0.0 if interior else float(lk["haze_density"]) \
			* clampf(float(w["fog_mult"]), 0.5, 3.0) * (1.0 + float(lk["haze_morning"]) * morning)

	# --- grade -----------------------------------------------------------------------------
	# Indoors the brightest thing is a lamp, so the white point comes down with it or every lit
	# wall reads as a sixth of its value; and the eye does not adapt to a moonless room.
	env.tonemap_white = 2.0 if interior else float(lk["tonemap_white"])
	env.tonemap_exposure = float(lk["exposure"]) * (1.0 if interior else lerpf(1.0, float(lk["night_exposure"]), night))
	env.adjustment_saturation = float(lk["saturation"]) * float(w["saturation_mult"]) * lerpf(1.0, 0.8, night)
	env.adjustment_contrast = float(lk["contrast"])
	# the player's own brightness setting multiplies the region's; glow can be turned off
	env.adjustment_brightness = float(lk["brightness"]) * float(Settings.get_value("video", "brightness", 1.0))
	var glow_on := bool(Settings.get_value("graphics", "glow", true))
	if env.glow_enabled != glow_on:
		env.glow_enabled = glow_on
	# Glow is for what is brighter than white: the sun, a lamp at night. `glow_bloom` feeds the
	# whole frame into it, which on Forward+ laid a soft light over everything by day.
	env.glow_intensity = 0.3 + 0.4 * float(lk["bloom"])
	env.glow_bloom = 0.03 * night
	env.glow_hdr_threshold = lerpf(1.1, 0.8, night)
	if _grade_dirty and (_look_t >= 1.0 or _grade_age >= GRADE_REFRESH_SECONDS):
		_grade_dirty = false
		_grade_age = 0.0
		if bool(Settings.get_value("graphics", "color_grade", true)):
			var t0 := Time.get_ticks_usec()
			var slices := grade_slices(lk)
			if _grade_tex == null:
				_grade_tex = ImageTexture3D.new()
				_grade_tex.create(Image.FORMAT_RGBA8, GRADE_LUT_SIZE, GRADE_LUT_SIZE, GRADE_LUT_SIZE, false, slices)
				lut_stats["textures"] += 1
			else:
				_grade_tex.update(slices)
			if env.adjustment_color_correction != _grade_tex:
				env.adjustment_color_correction = _grade_tex
				lut_stats["assigned"] += 1
			var us := Time.get_ticks_usec() - t0
			lut_stats["builds"] += 1
			lut_stats["us_total"] += us
			lut_stats["us_max"] = maxi(int(lut_stats["us_max"]), us)
		elif env.adjustment_color_correction != null:
			env.adjustment_color_correction = null
	# The frame overlays are the player's to have: a region's vignette is shown (and kept faint)
	# unless `graphics/vignette` is off, and its film grain only if `graphics/film_grain` is on.
	var vignette := float(lk["vignette"]) if bool(Settings.get_value("graphics", "vignette", true)) else 0.0
	_vignette_mat.set_shader_parameter("amount", vignette)
	_vignette_mat.set_shader_parameter("tint", lk["vignette_tint"])
	var grain := float(lk["grain"]) if bool(Settings.get_value("graphics", "film_grain", false)) else 0.0
	_grain_rect.visible = grain > 0.001
	_grain_mat.set_shader_parameter("amount", grain)

	# God rays are volumetric fog on Forward+ (the sun scatters in it): a region that asks for
	# them gets it denser and scattering forward, toward the light. Compatibility draws none of
	# this, and nothing in the look above depends on it.
	if env.volumetric_fog_enabled:
		var rays := bool(lk["god_rays"])
		env.volumetric_fog_density = (0.02 if rays else 0.005) * float(w["fog_mult"]) * (0.0 if interior else 1.0)
		env.volumetric_fog_albedo = fogc.lerp(Color.WHITE, 0.5)
		env.volumetric_fog_anisotropy = 0.75 if rays else 0.4
		sun.light_volumetric_fog_energy = 2.0 if rays else 1.0

	state = {"elevation": elev, "night": night, "dusk": dusk, "rising": rising,
		"sun_energy": sun.light_energy, "moon_energy": moon.light_energy, "haze_top": env.fog_height}

	# --- precipitation ---------------------------------------------------------------------
	var kind: String = str(_weather_to.get("precipitation", "none")) if _weather_t > 0.5 else str(_weather_from.get("precipitation", "none"))
	var intensity := float(w["precip_intensity"])
	precipitation.emitting = kind != "none" and intensity > 0.02 and not interior
	if precipitation.emitting:
		var cam := get_viewport().get_camera_3d()
		if cam:
			precipitation.global_position = cam.global_position + Vector3(0, 10, 0) + (-cam.global_transform.basis.z) * 4.0
		# in steps of a hundred, so a blend in intensity does not restart the particles every frame
		var amount := int(round((200.0 + 1400.0 * intensity) / 100.0)) * 100
		if amount != _precip_amount:
			_precip_amount = amount
			precipitation.amount = amount
	if precipitation.emitting and kind != _precip_kind:
		_precip_kind = kind
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
	if precipitation.emitting:
		precipitation.direction = Vector3(float(w["wind"]) * 0.6, -1.0, 0.2 * float(w["wind"])).normalized()

	# --- global shader parameters: foliage, water, windows and lamps read these -----------
	RenderingServer.global_shader_parameter_set("wm_wind_strength", float(w["wind"]))
	RenderingServer.global_shader_parameter_set("wm_wind_dir", Vector3(0.8, 0.0, 0.6).normalized())
	RenderingServer.global_shader_parameter_set("wm_wetness", float(w["wetness"]))
	RenderingServer.global_shader_parameter_set("wm_time_of_day", hour)
	RenderingServer.global_shader_parameter_set("wm_region_tint", tint)
	RenderingServer.global_shader_parameter_set("wm_night", night)
	RenderingServer.global_shader_parameter_set("wm_sun_dir", sun_dir)
	# colours go to the shaders as linear vec3s, so no shader has to guess whether a colour global
	# was converted from sRGB for it
	RenderingServer.global_shader_parameter_set("wm_sun_color", _linear(sun_col) * (sun.light_energy if sun.visible else 0.0))
	RenderingServer.global_shader_parameter_set("wm_moon_dir", moon_dir)
	RenderingServer.global_shader_parameter_set("wm_moon_color", _linear(moon.light_color) * moon.light_energy * 3.0)
	RenderingServer.global_shader_parameter_set("wm_sky_zenith", _linear(top_c))
	RenderingServer.global_shader_parameter_set("wm_sky_horizon", _linear(hor_c))


static func _linear(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	return Vector3(l.r, l.g, l.b)


func _eye_height() -> float:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp else null
	return cam.global_position.y if cam else 0.0


# --- the grade ---------------------------------------------------------------------------

## A region's colour grade as a 3D lookup table: shadows lifted toward `shadow_lift`, highlights
## pulled toward `highlight_gain`, midtones tinted by `midtone_tint`. The table works on the
## tonemapped picture, so it is a painter's grade -- what the shadows lean toward and what the
## lights are warmed by -- and not a second exposure.
##
## It is `grade_colour` over every texel, written straight into the bytes of each slice: through
## `Image.set_pixel` and a call per texel the 4913 of them took four milliseconds on average and
## eighteen at worst, on the main thread, every refresh of a blend between two regions.
static func grade_lut(lk: Dictionary) -> ImageTexture3D:
	var n := GRADE_LUT_SIZE
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RGBA8, n, n, n, false, grade_slices(lk))
	return tex


## The table's slices, blue by blue: what `grade_lut` uploads (and what a test can read, since a
## headless renderer keeps no copy of a texture's data).
static func grade_slices(lk: Dictionary) -> Array[Image]:
	var n := GRADE_LUT_SIZE
	var lift := (lk.get("shadow_lift", Color(0, 0, 0)) as Color) * GRADE_LIFT
	var gain: Color = lk.get("highlight_gain", Color(1, 1, 1))
	var mid: Color = lk.get("midtone_tint", Color(1, 1, 1))
	var span := Vector3(gain.r - lift.r, gain.g - lift.g, gain.b - lift.b)
	var tint := Vector3(mid.r - 1.0, mid.g - 1.0, mid.b - 1.0)
	var images: Array[Image] = []
	var step := 1.0 / float(n - 1)
	var bytes := PackedByteArray()
	bytes.resize(n * n * 4)
	for bi in n:
		var cb := float(bi) * step
		var i := 0
		for gi in n:
			var cg := float(gi) * step
			for ri in n:
				var cr := float(ri) * step
				var l := cr * 0.2126 + cg * 0.7152 + cb * 0.0722
				var m := 4.0 * l * (1.0 - l)
				bytes[i] = int(clampf((lift.r + cr * span.x) * (1.0 + tint.x * m), 0.0, 1.0) * 255.0 + 0.5)
				bytes[i + 1] = int(clampf((lift.g + cg * span.y) * (1.0 + tint.y * m), 0.0, 1.0) * 255.0 + 0.5)
				bytes[i + 2] = int(clampf((lift.b + cb * span.z) * (1.0 + tint.z * m), 0.0, 1.0) * 255.0 + 0.5)
				bytes[i + 3] = 255
				i += 4
		images.append(Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, bytes))
	return images


## One colour through the grade: lift and gain, then the midtone tint weighted to the middle.
static func grade_colour(c: Color, lift: Color, gain: Color, mid: Color) -> Color:
	var l := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
	var m := 4.0 * l * (1.0 - l)
	var r := (lift.r + c.r * (gain.r - lift.r)) * lerpf(1.0, mid.r, m)
	var g := (lift.g + c.g * (gain.g - lift.g)) * lerpf(1.0, mid.g, m)
	var b := (lift.b + c.b * (gain.b - lift.b)) * lerpf(1.0, mid.b, m)
	return Color(clampf(r, 0.0, 1.0), clampf(g, 0.0, 1.0), clampf(b, 0.0, 1.0))


# --- the Forward+ extras -----------------------------------------------------------------

## SSAO, SSIL, volumetric fog and SDFGI are Forward+ features: the Compatibility renderer takes
## the values and draws nothing, and the look is written so that it never depends on them (DESIGN
## 7.0, ARCHITECTURE 10). Each is behind its own setting in the `graphics` section as well as the
## renderer, so a machine that can run Forward+ but not afford them can say no; the presets there
## (core/graphics.gd) turn them on together at Painted. SSAO keeps the default DESIGN 7.0 gives it.
func _apply_extras() -> void:
	env.ssao_enabled = _forward_plus and bool(Settings.get_value("graphics", "ssao", true))
	env.ssao_radius = 1.5
	env.ssao_intensity = 1.5
	env.ssil_enabled = _forward_plus and bool(Settings.get_value("graphics", "ssil", false))
	var vol := _forward_plus and bool(Settings.get_value("graphics", "volumetric_fog", false))
	env.volumetric_fog_enabled = vol
	if vol:
		env.volumetric_fog_density = 0.012
		env.volumetric_fog_anisotropy = 0.6
		env.volumetric_fog_length = 96.0
	env.sdfgi_enabled = _forward_plus and bool(Settings.get_value("graphics", "sdfgi", false))


func _on_setting_changed(section: String, key: String, _value: Variant) -> void:
	if section != "graphics":
		return
	if key in ["ssao", "ssil", "volumetric_fog", "sdfgi"]:
		_apply_extras()
	elif key == "color_grade":
		_grade_dirty = true


## What this node's per-frame work has cost so far (see `lut_stats`).
func costs() -> Dictionary:
	return {"grade_lut": lut_stats.duplicate()}


## Whether the Forward+ extras are drawn at all: false on the Compatibility renderer whatever the
## settings say.
func extras_active() -> Dictionary:
	return {"ssao": env.ssao_enabled, "volumetric_fog": env.volumetric_fog_enabled, "sdfgi": env.sdfgi_enabled}


# --- save ---------------------------------------------------------------------------------

func to_save() -> Dictionary:
	return {"weather": weather_by_region.duplicate(), "weather_timer": _weather_timer_hours}


func from_save(d: Dictionary) -> void:
	weather_by_region = d.get("weather", {}).duplicate()
	_weather_timer_hours = float(d.get("weather_timer", 1.0))
	if weather_by_region.has(region_id):
		_start_weather(weather_by_region[region_id], true)
