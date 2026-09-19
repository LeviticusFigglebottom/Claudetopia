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
// renderer as on Forward+ (ARCHITECTURE.md §10): the sense of depth comes from the height map,
// and the sense of a surface from an animated normal plus a view-angle (Fresnel) rim.

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
uniform float wave_scale = 0.09;
uniform float wave_speed = 0.55;
uniform float wave_strength = 0.55;
uniform float ripple_scale = 0.9;
uniform float opacity_shallow = 0.45;
uniform float opacity_deep = 0.93;
uniform float roughness_water = 0.06;
uniform float specular_boost = 0.6;
uniform vec2 flow = vec2(0.0, 0.0);    // rivers push their waves downstream

varying vec3 v_world;
varying float v_depth;

vec2 world_uv(vec2 xz) {
	return (xz - world_origin) / world_size;
}

// Two crossing wave trains plus a finer ripple: cheap, stylised, and stable on GLES3.
vec3 wave_normal(vec2 p, float t) {
	vec2 a = p * wave_scale;
	vec2 b = p * wave_scale * 1.87 + vec2(13.1, 7.7);
	vec2 c = p * wave_scale * ripple_scale * 6.3 + vec2(3.3, 9.2);
	float nx = sin(a.x * 1.3 + t) * 0.55
		+ sin(b.x * 0.9 - b.y * 0.7 + t * 1.27) * 0.35
		+ sin(c.x + c.y * 0.6 + t * 2.1) * 0.10;
	float nz = cos(a.y * 1.1 - t * 0.85) * 0.55
		+ cos(b.x * 0.6 + b.y * 1.1 + t * 1.05) * 0.35
		+ cos(c.y - c.x * 0.4 + t * 1.9) * 0.10;
	return normalize(vec3(nx * wave_strength, 2.0, nz * wave_strength));
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
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
	float t = TIME * wave_speed;
	vec3 n = wave_normal(v_world.xz + flow * TIME * 2.0, t);
	NORMAL_MAP = n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;

	float depth_t = clamp(v_depth / depth_fade_m, 0.0, 1.0);
	vec3 base = mix(shallow_colour.rgb, deep_colour.rgb, depth_t) * region_tint.rgb;

	// shore foam: a band that follows the waterline and wobbles with the waves
	float wobble = sin(v_world.x * 0.7 + t * 1.6) * 0.25 + cos(v_world.z * 0.63 - t * 1.3) * 0.25;
	float foam = smoothstep(foam_width_m * (1.0 + wobble * 0.35), 0.0, v_depth);
	foam *= 0.85;

	vec3 view = normalize(VIEW);
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), view), 0.0, 1.0), 4.0);
	vec3 sky_rim = mix(base, region_tint.rgb * vec3(0.72, 0.82, 0.92), clamp(fres, 0.0, 1.0));

	ALBEDO = mix(sky_rim, foam_colour.rgb, foam);
	ROUGHNESS = clamp(roughness_water + foam * 0.55 + (1.0 - depth_t) * 0.10, 0.02, 1.0);
	SPECULAR = clamp(0.5 + specular_boost * (1.0 - foam), 0.0, 1.0);
	METALLIC = 0.0;
	ALPHA = clamp(mix(opacity_shallow, opacity_deep, depth_t) + foam * 0.5, 0.0, 1.0);
}
