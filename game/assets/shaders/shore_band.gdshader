shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;
// The water's edge on the land (world/shore_band.gd): a thin skin laid on the ground where it
// stands within a metre or so of its still water. Three things are drawn on it, by how high the
// ground here stands over the still water (`rise`):
//   the swash: a film of water that runs up the slope and draws back, a wave at a time on the sea
//     and a slow breath on a lake, with a broken line of foam at its leading edge;
//   the wet band: the ground the swash has reached, darker and glossy, drying toward its top;
//   nothing above that, and below the still line the lake sheet takes over (the band fades in
//     over its last few centimetres so the two meet with no seam).
// How the water breaks is by the shore's class: a long swash on sand and shingle, a short one
// with spray on rock, a creep with no foam on mud and in the reeds.

uniform sampler2D level_tex : filter_linear, repeat_disable, hint_default_black;
uniform sampler2D shore_tex : filter_nearest, repeat_disable, hint_default_black;
uniform bool has_shore = false;
uniform vec2 world_origin = vec2(-4096.0, -4096.0);
uniform float world_size = 8192.0;
uniform float sea_level = 0.0;
uniform vec4 water_colour : source_color = vec4(0.30, 0.52, 0.55, 1.0);
uniform vec4 foam_colour : source_color = vec4(0.93, 0.95, 0.95, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 1.0;

global uniform vec3 wm_sky_horizon;
global uniform vec3 wm_sky_zenith;
global uniform float wm_wind_strength;

varying vec3 v_world;

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

// The level map by hand: a float texture may be sampled nearest whatever the hint says, and the
// band would then step with the map's eight-metre texels.
float level_at(vec2 xz) {
	vec2 uv = (xz - world_origin) / world_size;
	vec2 n = vec2(textureSize(level_tex, 0));
	vec2 f = uv * n - 0.5;
	ivec2 i = ivec2(floor(f));
	vec2 t = f - floor(f);
	ivec2 hi = ivec2(n) - 1;
	float a = texelFetch(level_tex, clamp(i, ivec2(0), hi), 0).r;
	float b = texelFetch(level_tex, clamp(i + ivec2(1, 0), ivec2(0), hi), 0).r;
	float c = texelFetch(level_tex, clamp(i + ivec2(0, 1), ivec2(0), hi), 0).r;
	float d = texelFetch(level_tex, clamp(i + ivec2(1, 1), ivec2(0), hi), 0).r;
	return mix(mix(a, b, t.x), mix(c, d, t.x), t.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float level = level_at(v_world.xz);
	float rise = v_world.y - 0.04 - level;
	float sea = 1.0 - smoothstep(0.3, 0.8, abs(level - sea_level));
	// how the water breaks here
	float reach = 1.0;     // how far up the swash runs
	float froth = 1.0;     // how much foam at its edge
	if (has_shore) {
		vec2 uv = (v_world.xz - world_origin) / world_size;
		int cls = int(texture(shore_tex, uv).r * 255.0 + 0.5);
		reach = cls == 1 ? 1.3 : cls == 2 ? 1.0 : cls == 3 ? 0.55 : cls == 4 ? 0.4 : cls == 5 ? 0.45 : cls == 6 ? 0.3 : 0.8;
		froth = cls == 3 ? 1.4 : cls == 4 ? 1.2 : cls == 5 ? 0.15 : cls == 6 ? 0.05 : 1.0;
	}
	// The swash: a wave's run up the slope and its drawing back. On the sea each wave comes in
	// quickly and draws back slowly, and neighbouring stretches of beach are out of step; on a lake
	// it is a breath of a few centimetres.
	float amp = mix(0.07 + 0.05 * wm_wind_strength, 0.32 + 0.25 * wm_wind_strength, sea) * reach;
	float period = mix(6.5, 7.5, sea);
	float phase = TIME / period + vnoise(v_world.xz * 0.05) * 1.7 + vnoise(v_world.xz * 0.013) * 3.0;
	float cyc = fract(phase);
	float run = cyc < 0.3 ? smoothstep(0.0, 0.3, cyc) : 1.0 - smoothstep(0.3, 1.0, cyc);
	float wave_size = 0.65 + 0.35 * vnoise(vec2(floor(phase) * 3.7, v_world.x * 0.02 + v_world.z * 0.02));
	float swash = amp * run * wave_size;
	// the leading edge wanders along the beach rather than lying level
	float edge_h = swash + (vnoise(v_world.xz * 0.9 + vec2(floor(phase) * 5.1)) - 0.5) * 0.06 * reach;
	float film = 1.0 - smoothstep(edge_h - 0.02, edge_h + 0.01, rise);
	// foam: a broken line at the leading edge, thickest as the wave turns, and a lace left behind as
	// it draws back
	float line = exp(-pow((rise - edge_h) / (0.02 + 0.03 * reach), 2.0));
	float turning = 1.0 - abs(cyc - 0.3) * 1.6;
	float lace_n = vnoise(v_world.xz * vec2(2.3, 2.9) + TIME * 0.05) * 0.6 + vnoise(v_world.xz * 6.0) * 0.4;
	float foam = line * (0.5 + 0.5 * clamp(turning, 0.0, 1.0)) * smoothstep(0.35, 0.65, lace_n);
	foam += film * smoothstep(0.62, 0.8, lace_n) * 0.5 * run;
	foam = clamp(foam * froth, 0.0, 1.0);
	// the wet band: everything the swash reaches, up to its highest, drying toward the top
	// damp well above where the water reaches, the sand drawing it up: darkest at the line, drying
	// to nothing at the top, and on the sea as high as its biggest wave ran
	float wet_top = amp * 1.2 + mix(0.22, 0.45, sea) * max(reach, 0.5);
	float wet = 1.0 - smoothstep(0.0, wet_top, rise);
	wet = wet * wet * (3.0 - 2.0 * wet);
	// in with the lake sheet at the still line
	float fade_in = smoothstep(-0.12, 0.0, rise);
	vec3 sky = mix(wm_sky_horizon, wm_sky_zenith, 0.4);
	vec3 film_col = mix(water_colour.rgb, sky, 0.35);
	vec3 col = mix(vec3(0.05, 0.045, 0.04), film_col, film * 0.8);
	col = mix(col, foam_colour.rgb, foam);
	float a = max(wet * 0.55, film * 0.55);
	a = max(a, foam * 0.9);
	ALBEDO = col;
	ROUGHNESS = mix(0.55, 0.12, max(film, wet * 0.6));
	SPECULAR = 0.5;
	ALPHA = clamp(a * fade_in * strength, 0.0, 1.0);
	if (ALPHA < 0.004) {
		discard;
	}
}
