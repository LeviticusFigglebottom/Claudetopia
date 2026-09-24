shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// The Hushline's mist seen from afar (world/horizon_bands.gd): a curtain out over the Hush along
// the whole south coast, pale and colourless, thick from the water to well over the cliffs' brow
// and gone by its top, broken up so it is a bank and not a wall, thinning away along its length
// at either end, and thinning away as the eye comes near so walking into it is walking into mist.
// The world's fog is left on: the haze is itself in the air, and far off it melts into it.
//
// Its light is the sky's at the horizon, drained of colour: a pale bank by day, a dim one at dusk
// and a faint grey one under the moon. An unshaded sheet of a fixed colour stood white all night.

global uniform vec3 wm_sky_horizon;

uniform vec3 mist : source_color = vec3(0.78, 0.79, 0.80);
uniform float density : hint_range(0.0, 1.0) = 0.85;
// how much brighter than the horizon's sky the bank is: sunlit mist is whiter than the air
uniform float brightness = 1.15;
// metres above the sea: thick to here, gone by the top
uniform float thick_to = 170.0;
uniform float top = 260.0;
// the curtain's ends along x, and how far in from each it thins away
uniform float from_x = -3600.0;
uniform float to_x = 4080.0;
uniform float end_fade_m = 500.0;
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
	float up = v_world.y / top;
	float body = 1.0 - smoothstep(thick_to, top, v_world.y);
	// a slow drift along the bank, so its top is billows and not a ruled line
	float n = noise(vec2(v_world.x * 0.012 + TIME * 0.01, up * 3.0));
	n = n * 0.6 + noise(vec2(v_world.x * 0.04 - TIME * 0.02, up * 7.0)) * 0.4;
	float edge = smoothstep(0.0, 0.5, body * (0.55 + n * 0.9));
	// and it is not an even sheet where it is thick: it thickens and thins along its length
	float swell = 0.82 + 0.18 * n;
	float ends = smoothstep(from_x, from_x + end_fade_m, v_world.x)
			* (1.0 - smoothstep(to_x - end_fade_m, to_x, v_world.x));
	float near = smoothstep(near_fade_from, near_fade_to, v_dist);
	float lum = dot(wm_sky_horizon, vec3(0.2126, 0.7152, 0.0722));
	float tint_lum = dot(mist, vec3(0.2126, 0.7152, 0.0722));
	ALBEDO = mist / max(tint_lum, 0.001) * clamp(lum * brightness, 0.0, 1.0);
	ALPHA = clamp(edge * swell * density * ends * near, 0.0, 1.0);
}
