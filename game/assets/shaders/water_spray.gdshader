shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;
// The white water and the mist a fall throws up (world/river_falls.gd): each particle a soft
// round puff facing the camera, its edge worked from the quad's own UV, so nothing about it
// depends on a texture's alpha surviving the renderer. The particle's colour (COLOR, from the
// process material's ramp) carries its fade in and out; the puff is lit by the sky's own
// colours, so mist in a gorge's shade is grey, not a pasted white.

uniform float softness : hint_range(0.1, 1.0) = 0.8;

global uniform vec3 wm_sky_horizon;
global uniform vec3 wm_sky_zenith;
global uniform vec3 wm_sun_color;

varying float v_seed;

void vertex() {
	v_seed = INSTANCE_CUSTOM.x;
	// a billboard at the particle, keeping its scale and turning with its spin
	mat4 at = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	at = at * mat4(vec4(cos(INSTANCE_CUSTOM.x), -sin(INSTANCE_CUSTOM.x), 0.0, 0.0),
			vec4(sin(INSTANCE_CUSTOM.x), cos(INSTANCE_CUSTOM.x), 0.0, 0.0),
			vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * at;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
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

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	// a puff is not a perfect disc: its edge is broken by a little noise of its own
	float seed = v_seed * 7.0;
	float r = length(d) * (0.85 + 0.3 * vnoise(d * 2.5 + seed));
	float a = 1.0 - smoothstep(1.0 - softness, 1.0, r);
	a *= a;
	// lit mostly by the sky and only a little by the sun, and nearly grey: taken at the sun's warm
	// colour, the mist over a fall in a shaded gorge came out tan, and read as dust
	vec3 light = mix(wm_sky_horizon, wm_sky_zenith, 0.3) * 0.65 + wm_sun_color * 0.2;
	light = mix(vec3(dot(light, vec3(0.333))), light, 0.25);
	ALBEDO = COLOR.rgb * clamp(light, vec3(0.35), vec3(1.1));
	ALPHA = clamp(COLOR.a * a, 0.0, 1.0);
}
