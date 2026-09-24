shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

// A drift of pale ash blown into a lee on the dark ground: a soft-edged, ragged patch, rippled by
// the wind and speckled, laid on the ground as a quad. Scattered round the Stair Head so the ash
// field is not one black sheet but dark soil under pale drifts.

uniform vec4 ash : source_color = vec4(0.47, 0.45, 0.42, 1.0);
uniform float seed = 0.0;
uniform float strength = 0.8;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = UV - 0.5;
	// not a disc: a blotch that breaks up into islands towards its edge and fades there, so from
	// above it reads as ash lying in the ground's hollows rather than a pale lozenge laid on it
	float r = length(p * vec2(1.0, 1.4));
	float fall = 1.0 - smoothstep(0.05, 0.5, r);
	float islands = smoothstep(0.35, 0.62, fbm(UV * 3.2 + seed * 7.3) * 0.6 + 0.55 * fall);
	float body = islands * fall;
	float ripple = 0.5 + 0.5 * sin((UV.y + 0.15 * fbm(UV * 3.0 + seed)) * 38.0);
	float speck = step(0.93, hash(floor(UV * 180.0) + seed));
	vec3 col = ash.rgb * (0.86 + 0.14 * ripple) * (1.0 - 0.35 * speck) * (0.9 + 0.2 * fbm(UV * 9.0 + 3.0));
	ALBEDO = col;
	ROUGHNESS = 0.97;
	SPECULAR = 0.1;
	ALPHA = clamp(body * strength * (0.7 + 0.3 * fbm(UV * 6.0 + 1.7)), 0.0, 1.0);
}
