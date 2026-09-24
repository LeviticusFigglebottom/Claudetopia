shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// A hanging banner of weathered wool: a woven ground in the house colour with a border and a
// centre stripe in a second colour, sun-bleached toward the top, stained and frayed at the hem
// (the hem is ragged, not a straight cut), moving in the wind from the pole down. The Wardens'
// colours at the Stair Head were a flat grey-green board with one plain material on it.
// UV: u across (0..1), v down from the pole (0 at the top). The mesh is PoiMasonry.sheet.

uniform vec4 cloth_colour : source_color = vec4(0.23, 0.31, 0.22, 1.0);
uniform vec4 trim_colour : source_color = vec4(0.62, 0.50, 0.26, 1.0);
uniform vec4 stain_colour : source_color = vec4(0.16, 0.13, 0.10, 1.0);
uniform float trim_width = 0.08;
uniform float stripe_width = 0.12;
uniform float fray = 0.09;            // how far into the cloth the hem is torn
uniform float sway = 0.12;            // metres of wave at the hem in a still day
uniform float seed = 0.0;
global uniform float wm_wind_strength;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	// hangs from the top: nothing moves at v = 0, the hem the most
	float v = UV.y;
	float wind = 0.35 + 1.4 * clamp(wm_wind_strength, 0.0, 1.0);
	float t = TIME * (1.1 + 0.8 * wind) + seed * 6.28;
	float wave = sin(t + UV.x * 2.6 + v * 3.1) * 0.6 + sin(t * 1.7 + v * 5.3) * 0.4;
	VERTEX += NORMAL * wave * sway * wind * v * v;
	// a little sag across the width, as cloth does between its two top corners
	VERTEX.y -= 0.05 * sin(UV.x * 3.14159) * (1.0 - v);
}

void fragment() {
	vec2 uv = UV;
	// the torn hem: a noisy edge above the bottom of the sheet
	float tear = fray * (0.35 + 0.65 * vnoise(vec2(uv.x * 23.0 + seed * 7.0, 1.0)))
			+ fray * 0.5 * step(0.8, vnoise(vec2(uv.x * 6.0 + seed, 3.0)));
	if (uv.y > 1.0 - tear) {
		discard;
	}
	// weave: fine warp and weft
	float weave = 0.5 + 0.5 * sin(uv.x * 420.0) * sin(uv.y * 520.0);
	float blotch = vnoise(uv * vec2(5.0, 9.0) + seed * 3.1);
	vec3 col = cloth_colour.rgb * (0.86 + 0.22 * blotch) * (0.94 + 0.08 * weave);
	// border and centre stripe in the trim colour, worn thin in places
	float border = step(uv.x, trim_width) + step(1.0 - trim_width, uv.x) + step(uv.y, trim_width * 0.8);
	float stripe = step(abs(uv.x - 0.5), stripe_width * 0.5) * step(0.18, uv.y) * step(uv.y, 0.72);
	float worn = smoothstep(0.25, 0.6, vnoise(uv * vec2(14.0, 20.0) + 11.0 + seed));
	col = mix(col, trim_colour.rgb * (0.85 + 0.2 * blotch), clamp(border + stripe, 0.0, 1.0) * worn);
	// bleached toward the pole, stained and damp toward the hem
	col = mix(col, col * 1.18 + vec3(0.03), smoothstep(0.35, 0.0, uv.y) * 0.5);
	float grime = smoothstep(0.55, 1.0, uv.y) * (0.5 + 0.5 * vnoise(uv * vec2(9.0, 4.0) + seed * 2.0));
	col = mix(col, stain_colour.rgb, grime * 0.6);
	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
	// light through the wool on the side away from the sun
	BACKLIGHT = cloth_colour.rgb * 0.35;
}
