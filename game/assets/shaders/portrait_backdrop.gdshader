shader_type sky;

// The Naming's backdrop: the top of the Hushline Stair at the end of the day, painted rather
// than a void. It is the preview's sky, so the same colours light the figure (ambient) and
// shine back off steel (reflections) -- which is what lets iron read as iron on that screen.
//
// Painted, not photographed: three or four stops of colour, large soft patches of value
// smeared sideways like brushwork, a warm glow where the low sun is, and a vignette on the
// camera pass only (the reflection cubemap must not be darkened at its "edges").

uniform vec3 zenith : source_color = vec3(0.22, 0.25, 0.34);
uniform vec3 upper : source_color = vec3(0.47, 0.44, 0.47);
uniform vec3 horizon : source_color = vec3(0.88, 0.67, 0.46);
uniform vec3 ground : source_color = vec3(0.29, 0.24, 0.20);
uniform vec3 glow : source_color = vec3(1.0, 0.80, 0.56);
uniform vec3 glow_dir = vec3(0.45, 0.14, -0.88);
uniform float glow_strength = 0.55;
uniform float vignette = 0.55;
uniform float brush = 1.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1.0, 0.0, 0.0)), f.x),
				   mix(hash(i + vec3(0.0, 1.0, 0.0)), hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0.0, 0.0, 1.0)), hash(i + vec3(1.0, 0.0, 1.0)), f.x),
				   mix(hash(i + vec3(0.0, 1.0, 1.0)), hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float y = d.y;
	// broad patches of value, and strokes smeared along the horizon
	float blocks = fbm(vec3(d.x * 2.4, d.y * 5.0, d.z * 2.4) + vec3(3.1, 0.0, 1.7));
	float strokes = fbm(vec3(d.x * 1.3, d.y * 16.0, d.z * 1.3) + vec3(0.0, 2.0, 5.0));
	vec3 col = mix(horizon, upper, smoothstep(0.02, 0.30, y + 0.06 * (blocks - 0.5) * brush));
	col = mix(col, zenith, smoothstep(0.28, 0.90, y));
	col = mix(col, ground, smoothstep(0.03, -0.16, y + 0.05 * (strokes - 0.5) * brush));
	col *= 0.90 + 0.20 * blocks * brush;
	col *= 0.95 + 0.10 * strokes * brush;
	float g = pow(max(dot(d, normalize(glow_dir)), 0.0), 5.0);
	col += glow * g * glow_strength * (0.8 + 0.4 * blocks);
	if (!AT_CUBEMAP_PASS) {
		vec2 v = (SCREEN_UV - vec2(0.5, 0.46)) * vec2(1.25, 0.9);
		col *= 1.0 - vignette * smoothstep(0.30, 0.80, length(v));
	}
	COLOR = col;
}
