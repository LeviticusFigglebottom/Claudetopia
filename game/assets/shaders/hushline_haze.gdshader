shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// The Hushline's mist seen from afar (world/horizon_bands.gd): a curtain along the south cliff
// foot, pale and colourless, thick at the ground and gone by its top, broken up so it is a bank
// and not a wall, and thinning away as the eye comes near so walking into it is walking into
// mist. The world's fog is left on: the haze is itself in the air, and far off it melts into it.

uniform vec3 mist : source_color = vec3(0.78, 0.79, 0.80);
uniform float density : hint_range(0.0, 1.0) = 0.5;
uniform float near_fade_from = 60.0;
uniform float near_fade_to = 260.0;

varying float v_dist;
varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	float up = UV.y;
	// thick to two-thirds of the way up, so it stands over the cliff's brow, then thinning out
	float body = 1.0 - smoothstep(0.5, 1.0, up);
	// a slow drift along the bank, so its top is billows and not a ruled line
	float n = noise(vec2(v_world.x * 0.012 + TIME * 0.01, up * 3.0));
	n = n * 0.6 + noise(vec2(v_world.x * 0.04 - TIME * 0.02, up * 7.0)) * 0.4;
	float edge = smoothstep(0.0, 0.5, body * (0.55 + n * 0.9));
	float near = smoothstep(near_fade_from, near_fade_to, v_dist);
	ALBEDO = mist;
	ALPHA = clamp(edge * density * near, 0.0, 1.0);
}
