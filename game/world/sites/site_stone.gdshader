shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// The stone of a large site's outside (a fort, a ruin, a watchtower): the painted surface's coursed
// blocks (painted_surface.gdshader, pattern 2) in the region's own stone, weathered as a wall that
// has stood out on a down for two hundred years is weathered. Built for the fort that read as a toy
// of clean white blocks (the 0-C review sheet):
//   - the stone's tone wanders in broad patches (older courses, a repair, iron stain) and each
//     block keeps its own;
//   - grime rises from the ground: splash, soil and damp, darkest at the foot and ragged at its top,
//     with a green film in the lowest hand's breadth;
//   - rain streaks run down the faces from under the parapet and the walkway's lip;
//   - moss lies in the tops of things (the walkway, the merlons' tops, the plinth's ledge) and creeps
//     into the joints low down; lichen rosettes, pale and orange, dot the higher faces.
//
// Per vertex the builder (site_exterior.gd) gives UV2.x the local height of the ground under the
// vertex and UV2.y 1.0, and UV.x the local height of the top of the wall the vertex belongs to. A
// mesh laid without them (a drum's courses) uses `ground_y` and no streaks. COLOR tints the block
// (a bay laid in another stone, a patched merlon), as it does on the painted surface.

uniform vec4 base_color : source_color = vec4(0.72, 0.68, 0.6, 1.0);
uniform vec4 accent_color : source_color = vec4(0.6, 0.56, 0.48, 1.0);
uniform vec4 grout_color : source_color = vec4(0.4, 0.37, 0.32, 1.0);
uniform float unit_size = 0.42;
uniform float variation : hint_range(0.0, 1.0) = 0.7;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.9;
uniform float bump_strength : hint_range(0.0, 2.0) = 0.8;
// the stone's broad tones: a warmer (older, stained) and a cooler (fresher, rain-washed) look
uniform vec4 warm_tint : source_color = vec4(0.86, 0.76, 0.6, 1.0);
uniform vec4 cool_tint : source_color = vec4(0.7, 0.72, 0.72, 1.0);
uniform float tone_amount : hint_range(0.0, 1.0) = 0.45;
uniform vec4 grime_color : source_color = vec4(0.33, 0.3, 0.24, 1.0);
uniform float grime_height = 1.8;
uniform float grime_amount : hint_range(0.0, 1.0) = 0.7;
uniform vec4 damp_color : source_color = vec4(0.3, 0.34, 0.22, 1.0);
uniform vec4 moss_color : source_color = vec4(0.34, 0.4, 0.2, 1.0);
uniform vec4 moss_dark : source_color = vec4(0.2, 0.25, 0.13, 1.0);
uniform float moss_amount : hint_range(0.0, 1.0) = 0.6;
uniform vec4 lichen_pale : source_color = vec4(0.8, 0.8, 0.66, 1.0);
uniform vec4 lichen_gold : source_color = vec4(0.78, 0.58, 0.26, 1.0);
uniform float lichen_amount : hint_range(0.0, 1.0) = 0.5;
uniform float streak_amount : hint_range(0.0, 1.0) = 0.55;
uniform float ground_y = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;
varying float above;       // metres over the ground under this point
varying float below_top;   // metres under the top of its wall (large where unknown)

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float hash12(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
	               mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
	           mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
	               mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm3(vec3 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	float t = 0.0;
	for (int i = 0; i < oct; i++) {
		v += a * vnoise(p);
		t += a;
		p *= 2.11;
		a *= 0.5;
	}
	return v / t;
}

void vertex() {
	float g = UV2.y > 0.5 ? UV2.x : ground_y;
	above = VERTEX.y - g;
	below_top = UV2.y > 0.5 ? UV.x - VERTEX.y : 100.0;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// the coursed stone: rgb, height in w, and how much of this point is joint in the last slot of
// `joint_out`
vec4 stone(vec3 p, vec3 n, out float joint_out) {
	vec3 an = abs(n);
	vec2 uv = (an.y > 0.5) ? p.xz : ((an.x > an.z) ? p.zy : p.xy);
	float course = floor(uv.y / unit_size);
	// courses are not all one height: every so often a thinner one
	float offset = fract(course * 0.5) * unit_size + hash12(vec2(course, 7.1)) * unit_size * 0.6;
	float blen = unit_size * (1.6 + 0.9 * hash12(vec2(course, 2.3)));
	float bx = floor((uv.x + offset) / blen);
	vec2 within = vec2(fract((uv.x + offset) / blen), fract(uv.y / unit_size));
	// joints of uneven width, some arrises chipped back into the joint
	float chip = fbm3(p * 9.0, 2);
	float jx = 0.03 + 0.03 * chip;
	float jy = 0.06 + 0.05 * chip;
	float joint = min(smoothstep(0.0, jx, within.x) * smoothstep(1.0, 1.0 - jx, within.x),
	                  smoothstep(0.0, jy, within.y) * smoothstep(1.0, 1.0 - jy, within.y));
	float tone = hash12(vec2(bx, course));
	vec3 col = mix(base_color.rgb, accent_color.rgb, tone * variation);
	// the odd block of another bed, darker or warmer
	float odd = step(0.9, hash12(vec2(bx * 1.7, course + 3.0)));
	col = mix(col, col * vec3(0.86, 0.8, 0.72), odd * 0.8);
	// a stone's own face: pitted, a little darker toward its middle where the weather sits
	float face = fbm3(p * 4.5, 3);
	col *= 0.86 + face * 0.26;
	col = mix(grout_color.rgb, col, joint);
	joint_out = 1.0 - joint;
	float h = (joint - 1.0) * 1.0 + (face - 0.5) * 0.35 + (tone - 0.5) * 0.15;
	return vec4(col, h);
}

void fragment() {
	vec3 p = world_pos;
	vec3 n = world_normal;
	float jt;
	vec4 s = stone(p, n, jt);
	vec3 col = s.rgb;
	float up = smoothstep(0.55, 0.9, n.y);
	float side = 1.0 - smoothstep(0.35, 0.7, abs(n.y));

	// broad tone: patches metres across, warm and cool, and a slower wash over the whole
	float broad = fbm3(p * 0.09, 3);
	float mid = fbm3(p * 0.33 + vec3(4.1), 2);
	col = mix(col, col * warm_tint.rgb, smoothstep(0.45, 0.75, broad) * tone_amount);
	col = mix(col, col * cool_tint.rgb, smoothstep(0.55, 0.3, broad) * tone_amount * 0.7);
	col *= 0.9 + mid * 0.18;

	// rain streaks: long vertical runs from under the top of the wall, fading down the face
	vec3 an = abs(n);
	float along = (an.x > an.z) ? p.z : p.x;
	float streak = fbm3(vec3(along * 5.5, p.y * 0.35, along * 0.7), 3);
	float run_down = exp(-max(below_top, 0.0) / 3.2) + 0.25 * exp(-max(below_top, 0.0) / 9.0);
	float streaks = smoothstep(0.52, 0.72, streak) * run_down * side * streak_amount;
	col = mix(col, col * vec3(0.62, 0.6, 0.56), streaks);

	// grime from the ground: splash and soil, its top edge ragged
	float edge = grime_height * (0.55 + 0.9 * fbm3(vec3(along * 0.8, 0.0, p.y * 0.1) + p * vec3(0.3, 0.0, 0.3), 2));
	float grime = 1.0 - smoothstep(edge * 0.35, edge, above);
	col = mix(col, col * grime_color.rgb * 1.6, clamp(grime * grime_amount, 0.0, 1.0));
	float damp = 1.0 - smoothstep(0.0, 0.35 + 0.3 * streak, above);
	col = mix(col, damp_color.rgb, damp * 0.55 * side);

	// moss: in the tops of things, and in the joints low down
	float mn = fbm3(p * 1.25 + vec3(1.7), 3);
	float moss_top = smoothstep(0.42, 0.6, mn) * up;
	float moss_joint = jt * smoothstep(0.45, 0.62, mn) * (1.0 - smoothstep(0.4, 2.6, above)) * side;
	float moss_foot = smoothstep(0.5, 0.66, mn) * (1.0 - smoothstep(0.1, 0.9, above)) * side;
	float moss = clamp(max(max(moss_top, moss_joint), moss_foot) * moss_amount, 0.0, 1.0);
	vec3 moss_col = mix(moss_dark.rgb, moss_color.rgb, fbm3(p * 5.0, 2));
	col = mix(col, moss_col, moss);

	// lichen rosettes on the higher faces, where the air moves
	float ln = fbm3(p * 2.6 + vec3(9.3), 2);
	float rosette = smoothstep(0.66, 0.7, ln) * (1.0 - jt);
	float gold = step(0.55, fbm3(p * 0.7 + vec3(3.3), 2));
	float lichen = rosette * smoothstep(0.8, 2.2, above) * lichen_amount * (0.4 + 0.6 * side);
	col = mix(col, mix(lichen_pale.rgb, lichen_gold.rgb, gold) * (0.9 + 0.2 * ln), lichen);

	// the relief the stone's pattern draws
	float e = 0.03;
	float j2;
	float hx = stone(p + vec3(e, 0, 0), n, j2).w - s.w;
	float hy = stone(p + vec3(0, e, 0), n, j2).w - s.w;
	float hz = stone(p + vec3(0, 0, e), n, j2).w - s.w;
	vec3 grad = vec3(hx, hy, hz) / e;
	grad -= n * dot(grad, n);
	vec3 nrm = normalize(n - grad * bump_strength * 0.02);
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);

	ALBEDO = clamp(col * COLOR.rgb, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(roughness_base + moss * 0.08 - damp * 0.25, 0.3, 1.0);
	SPECULAR = 0.3;
}
