shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// The rags the Ash-Pilgrims tie to a cairn's pole (CinderCountry): strips of grey, bone and faded
// red cloth hanging from the pole's top, stirring in the wind and torn at their hems. The strips of
// a cell are one mesh; each one's colour is its vertex colour, and UV.y runs 0 at the knot to 1
// at the hem, so the knot stays and the hem moves.

global uniform float wm_wind_strength;
global uniform vec3 wm_wind_dir;

float hash(float n) { return fract(sin(n * 91.3458) * 47453.5453); }

void vertex() {
	float hang = UV.y;
	float seed = UV.x * 7.0 + VERTEX.x * 3.1 + VERTEX.z * 1.7;
	float gust = 0.35 + 0.65 * clamp(wm_wind_strength, 0.0, 1.0);
	float wave = sin(TIME * (2.2 + hash(floor(seed)) * 1.4) + hang * 3.0 + seed) * 0.5 + 0.5;
	vec3 lean = normalize(wm_wind_dir + vec3(0.0001)) * hang * hang * (0.10 + 0.22 * wave) * gust;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(lean, 0.0)).xyz;
}

void fragment() {
	// a torn hem: the strip ends at a ragged line across its last tenth
	float tear = 0.9 + 0.08 * hash(floor(UV.x * 23.0) + floor(COLOR.r * 97.0));
	if (UV.y > tear) {
		discard;
	}
	// weathered: paler toward the hem, a darker line where it is knotted
	float fade = mix(0.85, 1.1, UV.y);
	float knot = smoothstep(0.0, 0.06, UV.y);
	ALBEDO = COLOR.rgb * fade * mix(0.55, 1.0, knot);
	ROUGHNESS = 0.95;
}
