class_name Graphics
extends RefCounted
## What each graphics setting means, what the running renderer can do with it, and the one place
## it reaches the engine.
##
## `Settings` owns the values: the `graphics` section of settings.cfg. This owns the four presets
## (Low, Medium, High, Painted), the controls the settings screen builds from, the line that says
## why a control is greyed out, and `apply()`, which puts every knob into the engine live -- the
## root viewport, the rendering server, and every directional light and environment in the tree,
## the world's own sun and sky among them. The streamer and the water read their own knobs off
## `Settings.changed`, because what they do with them (cell rings, LOD bands, a water sheet) is
## theirs to know.
##
## High is the game as it was tuned before these settings existed, on purpose: every number in
## it is what the atmosphere, the project settings or the streamer already used, so the default
## preset changes nothing about how the world looks. The only thing the High preset adds is what
## the streamer's level of detail saves, and that is measured in PROGRESS.md.
##
## Lights and environments are adopted as they enter the tree and remember what their author
## gave them. Turning shadows off and on again gives back the author's shadows, a shadow distance
## is a share of the distance the author chose, and a review scene that never had fog is not
## given fog by a setting that says fog is allowed.

const PRESET_ORDER := ["low", "medium", "high", "painted"]
const PRESET_LABELS := {"low": "Low", "medium": "Medium", "high": "High", "painted": "Painted", "custom": "Custom"}
const DEFAULT_PRESET := "high"

## Every fidelity knob, per preset. Painted is everything on at its best that the renderer can do;
## Low is what a machine that is struggling should be offered first.
const PRESETS := {
	"low": {
		"render_scale": 0.75, "upscaler": 1, "msaa": 0, "fxaa": true, "taa": false, "anisotropic": 1,
		"shadows": true, "shadow_atlas": 2048, "shadow_cascades": 2, "shadow_distance": 0.6,
		"shadow_filter": 1, "scatter_density": 0.5, "view_range": 0.75, "lod_bias": 0.6,
		"fog": true, "volumetric_fog": false, "ssao": false, "ao_quality": 0, "ssil": false,
		"sdfgi": false, "glow": false, "water_quality": 0, "water_reflections": false, "night_lights": 2, "view_distance": 0,
	},
	"medium": {
		"render_scale": 0.9, "upscaler": 1, "msaa": 1, "fxaa": false, "taa": false, "anisotropic": 2,
		"shadows": true, "shadow_atlas": 4096, "shadow_cascades": 4, "shadow_distance": 0.8,
		"shadow_filter": 2, "scatter_density": 0.75, "view_range": 0.9, "lod_bias": 0.8,
		"fog": true, "volumetric_fog": false, "ssao": true, "ao_quality": 1, "ssil": false,
		"sdfgi": false, "glow": true, "water_quality": 1, "water_reflections": true, "night_lights": 4, "view_distance": 1,
	},
	"high": {
		"render_scale": 1.0, "upscaler": 0, "msaa": 1, "fxaa": false, "taa": false, "anisotropic": 3,
		"shadows": true, "shadow_atlas": 4096, "shadow_cascades": 4, "shadow_distance": 1.0,
		"shadow_filter": 2, "scatter_density": 1.0, "view_range": 1.0, "lod_bias": 1.0,
		"fog": true, "volumetric_fog": false, "ssao": true, "ao_quality": 2, "ssil": false,
		"sdfgi": false, "glow": true, "water_quality": 2, "water_reflections": true, "night_lights": 8, "view_distance": 1,
	},
	"painted": {
		"render_scale": 1.0, "upscaler": 0, "msaa": 2, "fxaa": false, "taa": true, "anisotropic": 4,
		"shadows": true, "shadow_atlas": 8192, "shadow_cascades": 4, "shadow_distance": 1.5,
		"shadow_filter": 4, "scatter_density": 1.0, "view_range": 1.25, "lod_bias": 1.5,
		"fog": true, "volumetric_fog": true, "ssao": true, "ao_quality": 3, "ssil": true,
		"sdfgi": true, "glow": true, "water_quality": 3, "water_reflections": true, "night_lights": 8, "view_distance": 2,
	},
}

## About the display rather than the picture, so no preset touches them.
const DISPLAY_DEFAULTS := {"vsync": true, "fps_cap": 0}
## The look's own toggles: the region's colour grade and the frame's vignette and film grain.
## They cost next to nothing and are a matter of taste, not of what a machine can afford, so no
## preset touches them either: Painted does not switch the grain on, Low does not grade the
## world out of its colours. The atmosphere reads them (systems/atmosphere/atmosphere.gd).
const LOOK_DEFAULTS := {"color_grade": true, "vignette": true, "film_grain": false}

## The graphics section as a new settings file has it: High, plus the display and look keys.
## Spelled out rather than merged because `Settings.DEFAULTS` is a constant and names this one;
## `test_graphics_settings` pins it to High, the display keys and the look keys.
const DEFAULTS := {
	"preset": "high",
	"render_scale": 1.0, "upscaler": 0, "msaa": 1, "fxaa": false, "taa": false, "anisotropic": 3,
	"vsync": true, "fps_cap": 0,
	"shadows": true, "shadow_atlas": 4096, "shadow_cascades": 4, "shadow_distance": 1.0,
	"shadow_filter": 2, "scatter_density": 1.0, "view_range": 1.0, "lod_bias": 1.0,
	"fog": true, "volumetric_fog": false, "ssao": true, "ao_quality": 2, "ssil": false,
	"sdfgi": false, "glow": true, "water_quality": 2, "water_reflections": true, "night_lights": 8, "view_distance": 1,
	"color_grade": true, "vignette": true, "film_grain": false,
}

## View distance (Near, Far, Epic): the player camera's far plane, which the settlements are drawn
## to (Tier C of docs/HORIZON.md); the horizon layer's reach (world/horizon_layer.gd); and the
## vertices in each of Terrain3D's clipmap rings, which is what the far hills' shape is drawn from.
const CAMERA_FAR_M: Array[float] = [3000.0, 4400.0, 6500.0]
const TERRAIN_MESH_SIZE: Array[int] = [32, 48, 56]


static func camera_far(g: Dictionary) -> float:
	return CAMERA_FAR_M[clampi(int(g.get("view_distance", 1)), 0, 2)]


static func terrain_mesh_size(g: Dictionary) -> int:
	return TERRAIN_MESH_SIZE[clampi(int(g.get("view_distance", 1)), 0, 2)]


const RENDERER_FORWARD_PLUS := "forward_plus"
const RENDERER_COMPATIBILITY := "gl_compatibility"

## What the Compatibility renderer cannot do (Godot 4.7's own renderer table), keyed by setting.
## `upscaler` is per choice: bilinear works everywhere, both FSRs are Forward+ only.
const FORWARD_PLUS_ONLY := {
	"fxaa": "Forward+ only: the Compatibility renderer has no FXAA.",
	"taa": "Forward+ only: the Compatibility renderer has no temporal anti-aliasing.",
	"volumetric_fog": "Forward+ only: the Compatibility renderer has depth fog but no volumetric fog.",
	"ssil": "Forward+ only: the Compatibility renderer has no screen-space indirect light.",
	"sdfgi": "Forward+ only: the Compatibility renderer has no SDFGI.",
}
## What Compatibility has but the world does not use on it. Its SSAO is a pass over the finished
## picture that darkens sunlit ground as much as shade (Forward+'s darkens only the sky's light),
## and the atmosphere draws the world without it on that renderer (`ssao_enabled = _forward_plus`),
## so the setting there would change the look rather than add to it. Every other knob works on both.
const COMPATIBILITY_UNUSED := {
	"ssao": "Off on Compatibility: its corner shadow darkens sunlit ground as well as shade.",
	"ao_quality": "Corner shadow is off on Compatibility.",
}
const UPSCALER_CHOICES := ["Bilinear", "FSR 1.0", "FSR 2.2"]
const UPSCALER_REASON := "FSR 1.0 and 2.2 are Forward+ only; Compatibility scales bilinearly."

## The controls the settings screen builds, in the order it shows them. A row is greyed out, with
## the reason beside it, when `unsupported_reason()` has one for the running renderer.
const CONTROLS := [
	{"key": "render_scale", "label": "Render scale", "kind": "slider", "min": 0.5, "max": 1.0, "step": 0.05, "suffix": "%",
		"note": "the 3D picture drawn at this share of the window"},
	{"key": "upscaler", "label": "Upscaling", "kind": "option", "choices": UPSCALER_CHOICES},
	{"key": "msaa", "label": "Edge smoothing (MSAA)", "kind": "option", "choices": ["Off", "2×", "4×", "8×"]},
	{"key": "fxaa", "label": "FXAA", "kind": "check"},
	{"key": "taa", "label": "Temporal smoothing (TAA)", "kind": "check"},
	{"key": "anisotropic", "label": "Texture filtering", "kind": "option", "choices": ["Plain", "2×", "4×", "8×", "16×"]},
	{"key": "vsync", "label": "Wait for the frame (vsync)", "kind": "check"},
	{"key": "fps_cap", "label": "Frame rate cap", "kind": "option", "choices": ["None", "30", "60", "90", "120", "144"],
		"values": [0, 30, 60, 90, 120, 144]},
	{"key": "shadows", "label": "Sun shadows", "kind": "check"},
	{"key": "shadow_atlas", "label": "Shadow detail", "kind": "option", "choices": ["1024", "2048", "4096", "8192"],
		"values": [1024, 2048, 4096, 8192], "note": "the size of the sun's shadow map"},
	{"key": "shadow_cascades", "label": "Shadow cascades", "kind": "option", "choices": ["1", "2", "4"], "values": [1, 2, 4]},
	{"key": "shadow_distance", "label": "Shadow distance", "kind": "slider", "min": 0.5, "max": 1.5, "step": 0.05, "suffix": "%",
		"note": "of the distance the light was designed for"},
	{"key": "shadow_filter", "label": "Shadow softness", "kind": "option", "choices": ["Hard", "Very low", "Low", "Medium", "High", "Ultra"]},
	{"key": "scatter_density", "label": "Ground cover", "kind": "slider", "min": 0.25, "max": 1.0, "step": 0.05, "suffix": "%",
		"note": "grass, flowers and bushes; never the trees"},
	{"key": "view_range", "label": "Scatter view distance", "kind": "slider", "min": 0.6, "max": 1.5, "step": 0.05, "suffix": "%"},
	{"key": "lod_bias", "label": "Detail distance (LOD)", "kind": "slider", "min": 0.5, "max": 2.0, "step": 0.05, "suffix": "%",
		"note": "how far away things keep their full shape"},
	{"key": "fog", "label": "Distance haze", "kind": "check"},
	{"key": "volumetric_fog", "label": "Volumetric fog", "kind": "check"},
	{"key": "ssao", "label": "Corner shadow (SSAO)", "kind": "check"},
	{"key": "ao_quality", "label": "Corner shadow quality", "kind": "option", "choices": ["Very low", "Low", "Medium", "High"]},
	{"key": "ssil", "label": "Bounced light (SSIL)", "kind": "check"},
	{"key": "sdfgi", "label": "Global light (SDFGI)", "kind": "check"},
	{"key": "glow", "label": "Glow", "kind": "check"},
	{"key": "water_quality", "label": "Water", "kind": "option", "choices": ["Low", "Medium", "High", "Painted"],
		"note": "ripples, the falls' spray and mist, and how far the mirror looks for the far shore"},
	{"key": "water_reflections", "label": "Reflections in the water", "kind": "check",
		"note": "the lake giving back the far shore; the sky's colours stay either way"},
	{"key": "night_lights", "label": "Lamps lit at night", "kind": "slider", "min": 0.0, "max": 8.0, "step": 1.0,
		"suffix": "lamps", "note": "real lights on the ground near you; every lamp still glows"},
	{"key": "view_distance", "label": "View distance", "kind": "option", "choices": ["Near", "Far", "Epic"],
		"note": "landmarks, towers and towns on the skyline, and the far hills' shape: 2.5, 4.2 or 6 km"},
	{"key": "color_grade", "label": "Region colour grade", "kind": "check"},
	{"key": "vignette", "label": "Vignette", "kind": "check"},
	{"key": "film_grain", "label": "Film grain", "kind": "check"},
]

## Anything a test or a tool has to be able to name, because the running renderer cannot be
## changed from inside a run: the headless test runner reports the project's Forward+ whatever
## draws it, and a check for greying out needs to see both.
static var renderer_override := ""

## What went to calls the engine cannot answer about afterwards (there is no getter for the
## directional shadow atlas size, the SSAO quality or, in a headless run, vsync), so a test can
## check that the setting was applied and not only stored.
static var last_applied: Dictionary = {}
static var _server_state: Dictionary = {}


static func renderer() -> String:
	if renderer_override != "":
		return renderer_override
	return RenderingServer.get_current_rendering_method()


## Every key the graphics section holds, with the High preset's values.
static func defaults() -> Dictionary:
	return DEFAULTS.duplicate()


static func preset_keys() -> Array:
	return (PRESETS[DEFAULT_PRESET] as Dictionary).keys()


## A preset's values as this renderer can have them: a preset that asks for FSR on Compatibility
## gets bilinear scaling, which is what the engine would fall back to anyway, and the screen then
## shows what is actually happening.
static func preset_values(name: String, for_renderer := "") -> Dictionary:
	var out: Dictionary = (PRESETS.get(name, PRESETS[DEFAULT_PRESET]) as Dictionary).duplicate()
	var r := for_renderer if for_renderer != "" else renderer()
	for key in out:
		if unsupported_reason(key, out[key], r) != "":
			out[key] = _fallback(key, out[key])
	return out


## Which preset these values are, or "custom". A knob greyed out on this renderer does not
## decide it: High chosen on Forward+ is still High when the same file is read on Compatibility.
static func matching_preset(values: Dictionary, for_renderer := "") -> String:
	var r := for_renderer if for_renderer != "" else renderer()
	for name in PRESET_ORDER:
		var p := preset_values(name, r)
		var same := true
		for key in p:
			if unsupported_reason(key, null, r) != "":
				continue
			if not _same(values.get(key), p[key]):
				same = false
				break
		if same:
			return name
	return "custom"


static func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) in [TYPE_FLOAT, TYPE_INT] and typeof(b) in [TYPE_FLOAT, TYPE_INT]:
		return is_equal_approx(float(a), float(b))
	return a == b


## What a preset asks for in place of something this renderer does not do: plain scaling for
## FSR, off for a feature, and a quality level left as it is for a feature that is off anyway.
static func _fallback(key: String, value: Variant) -> Variant:
	match key:
		"upscaler":
			return 0
		"ao_quality":
			return value
		_:
			return false


## "" when the running renderer can do this, otherwise the one line the screen shows. `value` is
## only read for the upscaler, whose choices differ.
static func unsupported_reason(key: String, value: Variant = null, for_renderer := "") -> String:
	var r := for_renderer if for_renderer != "" else renderer()
	if r == RENDERER_FORWARD_PLUS:
		return ""
	if key == "upscaler":
		return UPSCALER_REASON if value != null and int(value) > 0 else ""
	if FORWARD_PLUS_ONLY.has(key):
		return str(FORWARD_PLUS_ONLY[key])
	return str(COMPATIBILITY_UNUSED.get(key, ""))


static func is_supported(key: String, value: Variant = null, for_renderer := "") -> bool:
	return unsupported_reason(key, value, for_renderer) == ""


static func control(key: String) -> Dictionary:
	for c in CONTROLS:
		if str(c["key"]) == key:
			return c
	return {}


# --- applying ---------------------------------------------------------------------------------

## Puts every knob into the engine. Called by `Settings` whenever the graphics section changes.
static func apply(g: Dictionary, tree: SceneTree) -> void:
	if tree == null:
		return
	var r := renderer()
	apply_viewport(tree.root, g, r)
	# The rendering server's own state is only touched when it changes: a slider dragged
	# across the render scale would otherwise reallocate the shadow atlas at every step.
	var atlas := int(g.get("shadow_atlas", 4096))
	if _server_state.get("shadow_atlas", -1) != atlas:
		_server_state["shadow_atlas"] = atlas
		RenderingServer.directional_shadow_atlas_set_size(atlas, true)
		ProjectSettings.set_setting("rendering/lights_and_shadows/directional_shadow/size", atlas)
	var filter := clampi(int(g.get("shadow_filter", 2)), 0, 5)
	if _server_state.get("shadow_filter", -1) != filter:
		_server_state["shadow_filter"] = filter
		RenderingServer.directional_soft_shadow_filter_set_quality(filter as RenderingServer.ShadowQuality)
		RenderingServer.positional_soft_shadow_filter_set_quality(filter as RenderingServer.ShadowQuality)
		ProjectSettings.set_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", filter)
		ProjectSettings.set_setting("rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality", filter)
	var ao := clampi(int(g.get("ao_quality", 2)), 0, 3)
	if _server_state.get("ao_quality", -1) != ao:
		_server_state["ao_quality"] = ao
		# Quality, half size, adaptive target, blur passes, fade from, fade to: the project
		# defaults at Medium, full-size buffers at High.
		RenderingServer.environment_set_ssao_quality(ao as RenderingServer.EnvironmentSSAOQuality,
				ao < 3, 0.5, 2, 50.0, 300.0)
		RenderingServer.environment_set_ssil_quality(ao as RenderingServer.EnvironmentSSILQuality,
				ao < 3, 0.5, 4, 50.0, 300.0)
		ProjectSettings.set_setting("rendering/environment/ssao/quality", ao)
		ProjectSettings.set_setting("rendering/environment/ssao/half_size", ao < 3)
	Engine.max_fps = maxi(0, int(g.get("fps_cap", 0)))
	var vsync := DisplayServer.VSYNC_ENABLED if bool(g.get("vsync", true)) else DisplayServer.VSYNC_DISABLED
	DisplayServer.window_set_vsync_mode(vsync)
	last_applied = {"renderer": r, "shadow_atlas": atlas, "shadow_filter": filter, "ao_quality": ao,
			"ao_half_size": ao < 3, "vsync_mode": vsync, "max_fps": Engine.max_fps}
	for node in tree.get_nodes_in_group(LIGHTS):
		if node is DirectionalLight3D:
			apply_light(node as DirectionalLight3D, g)
	for node in tree.get_nodes_in_group(ENVIRONMENTS):
		if node is WorldEnvironment and (node as WorldEnvironment).environment != null:
			apply_environment((node as WorldEnvironment).environment, g, _is_world_environment(node), r)


static func apply_viewport(vp: Viewport, g: Dictionary, r := "") -> void:
	if vp == null:
		return
	if r == "":
		r = renderer()
	vp.scaling_3d_scale = clampf(float(g.get("render_scale", 1.0)), 0.25, 2.0)
	var up := int(g.get("upscaler", 0))
	if not is_supported("upscaler", up, r):
		up = 0
	vp.scaling_3d_mode = [Viewport.SCALING_3D_MODE_BILINEAR, Viewport.SCALING_3D_MODE_FSR,
			Viewport.SCALING_3D_MODE_FSR2][clampi(up, 0, 2)]
	vp.msaa_3d = clampi(int(g.get("msaa", 1)), 0, 3) as Viewport.MSAA
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA \
			if bool(g.get("fxaa", false)) and is_supported("fxaa", null, r) \
			else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = bool(g.get("taa", false)) and is_supported("taa", null, r)
	vp.anisotropic_filtering_level = clampi(int(g.get("anisotropic", 3)), 0, 4) as Viewport.AnisotropicFiltering
	# The project's own threshold is the base: a bias of two halves it, so a mesh keeps its
	# detail twice as far away.
	var base_threshold := float(ProjectSettings.get_setting("rendering/mesh_lod/lod_change/threshold_pixels", 1.0))
	vp.mesh_lod_threshold = base_threshold / maxf(float(g.get("lod_bias", 1.0)), 0.1)


## Groups the adopted nodes live in, so a settings change reaches them without a tree walk.
const LIGHTS := "graphics_directional_lights"
const ENVIRONMENTS := "graphics_environments"
const AUTHORED := "graphics_authored"


## Takes a light or an environment into the settings' care, remembering what its author gave it.
static func adopt(node: Node, g: Dictionary) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	if node is DirectionalLight3D:
		var light := node as DirectionalLight3D
		if not light.has_meta(AUTHORED):
			light.set_meta(AUTHORED, {"shadow": light.shadow_enabled,
					"distance": light.directional_shadow_max_distance,
					"mode": light.directional_shadow_mode})
		light.add_to_group(LIGHTS)
		apply_light(light, g)
	elif node is WorldEnvironment:
		var we := node as WorldEnvironment
		if we.environment == null:
			return
		var env := we.environment
		if not env.has_meta(AUTHORED):
			env.set_meta(AUTHORED, {"fog": env.fog_enabled, "glow": env.glow_enabled,
					"ssao": env.ssao_enabled, "ssil": env.ssil_enabled, "sdfgi": env.sdfgi_enabled,
					"volumetric_fog": env.volumetric_fog_enabled})
		we.add_to_group(ENVIRONMENTS)
		apply_environment(env, g, _is_world_environment(we))


const CASCADE_MODES := {1: DirectionalLight3D.SHADOW_ORTHOGONAL, 2: DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
		4: DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS}
const MODE_CASCADES := {DirectionalLight3D.SHADOW_ORTHOGONAL: 1, DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS: 2,
		DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS: 4}


## A light's shadows are its author's, cut back or reached further by the settings: never turned
## on where the author left them off (the moon), never given more cascades than it was built with.
static func apply_light(light: DirectionalLight3D, g: Dictionary) -> void:
	var a: Dictionary = light.get_meta(AUTHORED, {"shadow": light.shadow_enabled,
			"distance": light.directional_shadow_max_distance, "mode": light.directional_shadow_mode})
	light.shadow_enabled = bool(a["shadow"]) and bool(g.get("shadows", true))
	light.directional_shadow_max_distance = maxf(float(a["distance"]) * float(g.get("shadow_distance", 1.0)), 1.0)
	var authored_cascades := int(MODE_CASCADES.get(int(a["mode"]), 4))
	var wanted := int(g.get("shadow_cascades", 4))
	var cascades := mini(authored_cascades, wanted)
	if not CASCADE_MODES.has(cascades):
		cascades = 2 if cascades > 1 else 1
	light.directional_shadow_mode = CASCADE_MODES[cascades]


## The world's own environment takes the settings as the authority for the features that are
## settings (SSAO, SSIL, SDFGI, volumetric fog); fog and glow are part of each environment's look
## and a setting can only take them away. Any other environment -- a review stage, the perf probe
## -- keeps what its author gave it unless a setting turns it off.
static func apply_environment(env: Environment, g: Dictionary, world := false, r := "") -> void:
	if env == null:
		return
	if r == "":
		r = renderer()
	var a: Dictionary = env.get_meta(AUTHORED, {"fog": env.fog_enabled, "glow": env.glow_enabled,
			"ssao": env.ssao_enabled, "ssil": env.ssil_enabled, "sdfgi": env.sdfgi_enabled,
			"volumetric_fog": env.volumetric_fog_enabled})
	env.fog_enabled = bool(a["fog"]) and bool(g.get("fog", true))
	env.glow_enabled = bool(a["glow"]) and bool(g.get("glow", true))
	for key in ["ssao", "ssil", "sdfgi", "volumetric_fog"]:
		var wanted := bool(g.get(key, false)) and is_supported(key, null, r)
		var on := wanted if world else (wanted and bool(a[key]))
		match key:
			"ssao":
				env.ssao_enabled = on
			"ssil":
				env.ssil_enabled = on
			"sdfgi":
				if on and not bool(a[key]):
					# Outdoors at the scale of this country: coarser first cascade, more reach.
					env.sdfgi_min_cell_size = 0.4
					env.sdfgi_use_occlusion = true
					env.sdfgi_read_sky_light = true
				env.sdfgi_enabled = on
			"volumetric_fog":
				if on and not bool(a[key]):
					# Godot's default density is 0.05, which is a wall of fog at this scale. This is
					# light in the air on top of the atmosphere's own depth fog, not more haze; the
					# world's own atmosphere then sets its region's density and god rays every frame.
					env.volumetric_fog_density = 0.004
					env.volumetric_fog_anisotropy = 0.5
					env.volumetric_fog_length = 180.0
					env.volumetric_fog_sky_affect = 0.0
				env.volumetric_fog_enabled = on


## The environment the atmosphere owns: the one the world is drawn in.
static func _is_world_environment(node: Node) -> bool:
	var p := node.get_parent()
	return p != null and p.is_in_group("atmosphere")
