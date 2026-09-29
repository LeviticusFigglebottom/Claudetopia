shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

// A vent's mouth or a small ember pool in the ash (CinderCountry): a round of black crust broken
// into plates, the fire showing orange in the seams between them and breathing, hottest in the
// middle, the crust's edge ragged into the ash with a warm stain round it. Laid on the ground as a
// draped disc (UV 0-1 across it); all the pools of a cell are one mesh, each one's seed in its
// vertex colour's red and how hot it is (0-1) in its green.

uniform vec4 core : source_color = vec4(1.0, 0.46, 0.12, 1.0);
uniform vec4 crust : source_color = vec4(0.045, 0.036, 0.032, 1.0);
uniform vec4 stain : source_color = vec4(0.16, 0.10, 0.07, 1.0);
// how many plates across the disc
uniform float plates = 5.0;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// distance to the nearest seam between plates (a cellular F2 - F1)
float seams(vec2 p, float seed) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash2(i + g + seed * 13.7);
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return d2 - d1;
}

void fragment() {
	float seed = COLOR.r * 10.0;
	float heat = COLOR.g;
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float ang = atan(q.y, q.x);
	// a ragged rim, never a circle
	float rim = 0.78 + 0.1 * sin(ang * 3.0 + seed) + 0.06 * sin(ang * 7.0 + seed * 2.3);
	float inside = 1.0 - smoothstep(rim - 0.08, rim, r);
	float seam = seams(UV * plates, seed);
	float breathe = 0.72 + 0.28 * sin(TIME * (0.6 + 0.3 * fract(seed)) + seed * 5.0) * sin(TIME * 0.23 + seed);
	// the fire in the seams, wider and brighter toward the middle
	float centre = 1.0 - smoothstep(0.0, rim, r);
	float glow_w = mix(0.05, 0.22, centre * heat);
	float fire = (1.0 - smoothstep(0.0, glow_w, seam)) * inside;
	fire = max(fire, smoothstep(0.35, 0.0, r) * heat * 0.9 * inside);
	vec3 hot = core.rgb * (1.4 + 1.6 * heat) * breathe;
	vec3 col = mix(crust.rgb, hot, fire);
	// the stain on the ash round the crust
	float halo = (1.0 - smoothstep(rim, 1.0, r)) * (1.0 - inside);
	col = mix(col, stain.rgb + core.rgb * 0.25 * heat * breathe, halo);
	ALBEDO = col;
	ALPHA = clamp(max(inside, halo * 0.55), 0.0, 1.0);
}
