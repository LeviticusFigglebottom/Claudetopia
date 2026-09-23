shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;
// Stylised water for the Mere, the Grey Sea and the rivers.
//
// Everything it needs comes from the world builder's runtime maps, so one mesh can carry the
// lake, the sea and the marsh pools at their own levels:
//   level_tex   R32F  water surface height (filled: every texel has the nearest water level)
//   mask_tex    R8    1 where there is water surface
//   height_tex  R32F  terrain height, for depth colour and shore foam
//
// It draws no depth texture and no screen texture, so it behaves the same on the Compatibility
// renderer as on Forward+ (ARCHITECTURE.md §10). What makes it read as water is done here rather
// than left to the engine's reflection: the sky's own colours (the atmosphere publishes its
// zenith and horizon every frame) mirrored by a Fresnel term, so the water is dark where you look
// down into it and sky-coloured toward the far shore; a path of glints under the sun, and under
// the moon at night; moving ripples; and foam that follows the waterline and breaks up.
//
// The normal is written to NORMAL in view space. The first version wrote a world-space normal
// with its up component in the normal map's green channel; Godot rebuilds a normal map's z from
// its x and y, so every water surface in the game was lit as if tilted some seventy-five degrees,
// and took its reflection from the wrong part of the sky.

uniform sampler2D level_tex : filter_linear, repeat_disable, hint_default_black;
uniform sampler2D mask_tex : filter_linear, repeat_disable, hint_default_black;
uniform sampler2D height_tex : filter_linear, repeat_disable, hint_default_black;
uniform vec2 world_origin = vec2(-4096.0, -4096.0);
uniform float world_size = 8192.0;

uniform bool follow_level = true;      // sheet: take y from the level map; rivers: keep mesh y
uniform bool use_mask = true;          // sheet: discard away from water; rivers: never
uniform vec4 deep_colour : source_color = vec4(0.06, 0.20, 0.32, 1.0);
uniform vec4 shallow_colour : source_color = vec4(0.30, 0.56, 0.60, 1.0);
uniform vec4 region_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 foam_colour : source_color = vec4(0.92, 0.95, 0.96, 1.0);
uniform float depth_fade_m = 5.0;      // metres of water before the colour reads as deep
uniform float foam_width_m = 1.6;
uniform float wave_scale = 0.07;
uniform float wave_speed = 0.5;
uniform float wave_strength = 0.42;
uniform float ripple_scale = 0.8;
uniform float opacity_shallow = 0.66;
uniform float opacity_deep = 0.97;
uniform float roughness_water = 0.10;
uniform float specular_boost = 0.32;
uniform float distance_calm_m = 260.0;   // ripples flatten with distance instead of aliasing
uniform float rim_strength = 0.5;      // kept for callers; the reflection below replaces the rim
uniform bool flow_along_uv = false;    // rivers: run the waves down the ribbon's own UV
uniform float flow_speed = 0.35;       // metres of wave travel per second, downstream
uniform float reflect_strength : hint_range(0.0, 1.0) = 0.9;
uniform float glint_strength = 3.0;
uniform float glint_sharpness = 700.0;

// published by systems/atmosphere every frame, all linear
global uniform vec3 wm_sun_dir;
global uniform vec3 wm_sun_color;
global uniform vec3 wm_moon_dir;
global uniform vec3 wm_moon_color;
global uniform vec3 wm_sky_zenith;
global uniform vec3 wm_sky_horizon;
global uniform float wm_wind_strength;

varying vec3 v_world;
varying float v_depth;
varying vec2 v_uv;

vec2 world_uv(vec2 xz) {
	return (xz - world_origin) / world_size;
}

float hash12(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
	           mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Two crossing wave trains plus a finer ripple: cheap, stylised, and stable on GLES3. Returns
// the slope (d/dx, d/dz) of the surface, which is what the normal is made from.
vec2 wave_slope(vec2 p, float t) {
	vec2 a = p * wave_scale;
	vec2 b = p * wave_scale * 1.87 + vec2(13.1, 7.7);
	vec2 c = p * wave_scale * ripple_scale * 6.3 + vec2(3.3, 9.2);
	float sx = cos(a.x * 1.3 + t) * 0.55
		+ cos(b.x * 0.9 - b.y * 0.7 + t * 1.27) * 0.35
		+ cos(c.x + c.y * 0.6 + t * 2.1) * 0.10;
	float sz = -sin(a.y * 1.1 - t * 0.85) * 0.55
		+ -sin(b.x * 0.6 + b.y * 1.1 + t * 1.05) * 0.35
		+ -sin(c.y - c.x * 0.4 + t * 1.9) * 0.10;
	return vec2(sx, sz);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_uv = UV;
	if (follow_level) {
		float lvl = texture(level_tex, world_uv(v_world.xz)).r;
		v_world.y = lvl;
		VERTEX.y = lvl - NODE_POSITION_WORLD.y;
	}
	float ground = texture(height_tex, world_uv(v_world.xz)).r;
	v_depth = max(v_world.y - ground, 0.0);
	// a slow swell so the sheet is never perfectly flat
	VERTEX.y += sin(v_world.x * 0.02 + TIME * 0.35) * 0.06 + cos(v_world.z * 0.017 - TIME * 0.28) * 0.06;
}

void fragment() {
	vec2 uv = world_uv(v_world.xz);
	if (use_mask && texture(mask_tex, uv).r < 0.5) {
		discard;
	}
	float t = TIME * wave_speed * (0.7 + wm_wind_strength * 0.8);
	// a river's waves run with the current: its ribbon UV is x across, y along the channel
	vec2 wave_pos = flow_along_uv
		? vec2(v_uv.x * 6.0, v_uv.y * 2.0 - TIME * flow_speed * 4.0)
		: v_world.xz;
	vec2 slope = wave_slope(wave_pos, t) * wave_strength;
	// far water should read as one calm sheet, not as a field of shimmering pixels
	float dist = length(CAMERA_POSITION_WORLD - v_world);
	float far = clamp(dist / distance_calm_m, 0.0, 1.0);
	slope *= mix(1.0, 0.18, far);
	vec3 n_world = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	float depth_t = clamp(v_depth / depth_fade_m, 0.0, 1.0);
	vec3 body = mix(shallow_colour.rgb, deep_colour.rgb, depth_t) * region_tint.rgb;

	// shore foam: a band that follows the waterline, wobbles with the waves and breaks into
	// patches rather than lying along the shore like a painted line
	float wobble = sin(v_world.x * 0.7 + t * 1.6) * 0.25 + cos(v_world.z * 0.63 - t * 1.3) * 0.25;
	// (GLSL leaves smoothstep undefined with its edges reversed; Mesa forgives it, a GPU need not)
	float foam = 1.0 - smoothstep(0.0, foam_width_m * (1.0 + wobble * 0.35), v_depth);
	foam *= 0.35 + 0.65 * smoothstep(0.35, 0.7, vnoise(v_world.xz * 0.9 + vec2(t * 0.4, -t * 0.3)));
	foam *= 0.7;

	// the sky, mirrored: dark where you look down into the water, the sky's own colours toward
	// the grazing angle, capped so a lake seen from a hill is still a lake and not a sheet of sky
	vec3 V = normalize(CAMERA_POSITION_WORLD - v_world);
	vec3 R = reflect(-V, n_world);
	float cos_v = clamp(dot(n_world, V), 0.0, 1.0);
	float fresnel = 0.02 + 0.98 * pow(1.0 - cos_v, 5.0);
	fresnel = min(fresnel, 0.65) * reflect_strength;
	vec3 sky = mix(wm_sky_horizon, wm_sky_zenith, pow(clamp(R.y, 0.0, 1.0), 0.35));
	// a path of glints under the sun, broken into points by a fine sparkle
	float sparkle = step(0.55, hash12(floor(v_world.xz * 2.5 + vec2(TIME * 1.3, TIME * 0.9))));
	float sun_g = pow(max(dot(R, normalize(wm_sun_dir)), 0.0), glint_sharpness);
	float sun_wide = pow(max(dot(R, normalize(wm_sun_dir)), 0.0), glint_sharpness * 0.08) * 0.08;
	float moon_g = pow(max(dot(R, normalize(wm_moon_dir)), 0.0), glint_sharpness * 0.6);
	vec3 glints = wm_sun_color * (sun_g * mix(0.4, 1.6, sparkle) + sun_wide) * glint_strength
		+ wm_moon_color * moon_g * mix(0.3, 1.4, sparkle) * glint_strength * 0.6;

	ALBEDO = mix(body * (1.0 - fresnel), foam_colour.rgb, foam);
	EMISSION = (sky * fresnel + glints * (1.0 - far * 0.6)) * (1.0 - foam);
	ROUGHNESS = clamp(roughness_water + 0.25 + foam * 0.4 + far * 0.1, 0.02, 1.0);
	SPECULAR = 0.12 * (1.0 - foam);
	METALLIC = 0.0;
	// the water thins to nothing at the waterline, so the land does not end in a hard edge
	float edge = smoothstep(0.0, 0.35, v_depth);
	ALPHA = clamp(mix(opacity_shallow, opacity_deep, depth_t) * mix(0.35, 1.0, edge) + fresnel * 0.4 + foam * 0.5, 0.0, 1.0);
}
