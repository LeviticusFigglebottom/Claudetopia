shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// One material for built surfaces: plaster, floorboards, stone blocks, timber framing,
// thatch and beaten earth, chosen by `pattern`. Triplanar, so no UVs are needed on
// generated geometry, and painterly: broad tonal variation, edge wear, no photo grain.
//
// pattern: 0 plaster  1 planks  2 stone blocks  3 timber  4 thatch  5 beaten earth

uniform int pattern : hint_range(0, 5) = 0;
uniform vec4 base_color : source_color = vec4(0.78, 0.74, 0.66, 1.0);
uniform vec4 accent_color : source_color = vec4(0.58, 0.52, 0.44, 1.0);
uniform vec4 grout_color : source_color = vec4(0.44, 0.41, 0.36, 1.0);
uniform float unit_size = 1.0;             // plank width / block height, metres
uniform float roughness_base : hint_range(0.0, 1.0) = 0.85;
uniform float wear : hint_range(0.0, 1.0) = 0.3;     // traffic polish and grime
uniform float bump_strength : hint_range(0.0, 2.0) = 0.6;
uniform float soot_height = -1000.0;       // world Y above which soot gathers (near a hearth)
uniform float variation : hint_range(0.0, 1.0) = 0.5;

varying vec3 world_pos;
varying vec3 world_normal;

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

// Returns rgb tint in .xyz and surface height in .w
vec4 surface(vec3 p, vec3 n) {
	vec3 an = abs(n);
	vec3 col = base_color.rgb;
	float h = 0.0;

	if (pattern == 0) {          // plaster: fine trowel mottle and hairline cracks
		float m = fbm3(p * 2.6, 3);
		float fine = fbm3(p * 11.0, 2);
		col = mix(base_color.rgb, accent_color.rgb, clamp((m - 0.45) * variation * 0.9 + 0.12, 0.0, 1.0));
		col *= 0.97 + fine * 0.06;
		// Cracks are lines, not patches: a narrow band around a noise contour.
		float c = fbm3(p * vec3(2.2, 2.2, 2.2), 3);
		float crack = smoothstep(0.015, 0.0, abs(c - 0.5)) * smoothstep(0.35, 0.6, fbm3(p * 0.7, 2));
		col = mix(col, grout_color.rgb, crack * 0.45);
		// Lime bloom gathers low on a cob wall where the damp rises.
		float rise = clamp(1.0 - (p.y - floor(p.y / 2.75) * 2.75) / 0.9, 0.0, 1.0);
		col = mix(col, col * vec3(0.94, 0.93, 0.9) + vec3(0.03), rise * 0.35 * fine);
		h = (m - 0.5) * 0.18 + (fine - 0.5) * 0.12 - crack * 0.9;
	} else if (pattern == 1) {   // floorboards: long boards, joints, per-board tone
		vec2 uv = (an.y > 0.5) ? p.xz : ((an.x > an.z) ? p.zy : p.xy);
		float board = floor(uv.y / unit_size);
		float within = fract(uv.y / unit_size);
		float joint = smoothstep(0.0, 0.06, within) * smoothstep(1.0, 0.94, within);
		float tone = hash12(vec2(board, 3.7));
		col = mix(base_color.rgb, accent_color.rgb, tone * variation);
		float grain = fbm3(vec3(uv.x * 9.0, board * 12.3, uv.y * 1.5), 2);
		col *= 0.9 + grain * 0.22;
		col = mix(grout_color.rgb * 0.7, col, joint);
		h = (grain - 0.5) * 0.25 + (joint - 1.0) * 0.8;
	} else if (pattern == 2) {   // stone blocks: courses, staggered joints, per-block tone
		vec2 uv = (an.y > 0.5) ? p.xz : ((an.x > an.z) ? p.zy : p.xy);
		float course = floor(uv.y / unit_size);
		float offset = fract(course * 0.5) * unit_size;
		float bx = floor((uv.x + offset) / (unit_size * 2.0));
		vec2 within = vec2(fract((uv.x + offset) / (unit_size * 2.0)), fract(uv.y / unit_size));
		float joint = min(smoothstep(0.0, 0.035, within.x) * smoothstep(1.0, 0.965, within.x),
		                  smoothstep(0.0, 0.07, within.y) * smoothstep(1.0, 0.93, within.y));
		float tone = hash12(vec2(bx, course));
		col = mix(base_color.rgb, accent_color.rgb, tone * variation);
		col *= 0.92 + fbm3(p * 5.0, 2) * 0.2;
		col = mix(grout_color.rgb, col, joint);
		h = (joint - 1.0) * 1.0 + (fbm3(p * 7.0, 2) - 0.5) * 0.2;
	} else if (pattern == 3) {   // timber: heavy grain along the longest axis, adze marks
		vec3 g = (an.y > max(an.x, an.z)) ? p.xzy : ((an.x > an.z) ? p.yzx : p.xyz);
		float rings = sin(g.y * 26.0 + fbm3(g * 2.0, 2) * 9.0);
		float adze = sin(g.y * 3.1 + fbm3(g * 0.8, 1) * 4.0);
		col = mix(base_color.rgb, accent_color.rgb, clamp(rings * 0.5 + 0.5, 0.0, 1.0) * variation);
		col *= 0.93 + adze * 0.07;
		h = rings * 0.18 + adze * 0.25;
	} else if (pattern == 4) {   // thatch: dense straw strokes, darker in the depths
		vec3 g = p * vec3(1.0, 4.0, 1.0);
		float straw = fbm3(g * 12.0, 2);
		float bundle = fbm3(p * 2.2, 2);
		col = mix(accent_color.rgb, base_color.rgb, straw);
		col *= 0.75 + bundle * 0.45;
		h = (straw - 0.5) * 1.2;
	} else {                      // beaten earth: swept, uneven, darker where feet fall
		float m = fbm3(p * 2.0, 3);
		float swept = fbm3(p * vec3(8.0, 1.0, 1.4), 2);
		col = mix(base_color.rgb, accent_color.rgb, m * variation);
		col *= 0.88 + swept * 0.2;
		h = (m - 0.5) * 0.5;
	}
	return vec4(col, h);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 s = surface(world_pos, world_normal);
	vec3 col = s.rgb;

	float e = 0.03;
	float hx = surface(world_pos + vec3(e, 0, 0), world_normal).w - s.w;
	float hy = surface(world_pos + vec3(0, e, 0), world_normal).w - s.w;
	float hz = surface(world_pos + vec3(0, 0, e), world_normal).w - s.w;
	vec3 grad = vec3(hx, hy, hz) / e;
	grad -= world_normal * dot(grad, world_normal);
	vec3 nrm = normalize(world_normal - grad * bump_strength * 0.02);
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);

	// Traffic: the middle of a floor is polished and darker, the edges keep their dust.
	float traffic = wear * (1.0 - clamp(abs(s.w) * 1.5, 0.0, 1.0));
	col *= 1.0 - traffic * 0.22;

	// Soot: everything above a hearth collects it, which is half of what makes a room
	// look lived in rather than built.
	float soot = clamp((world_pos.y - soot_height) * 0.35, 0.0, 1.0);
	col = mix(col, col * vec3(0.55, 0.52, 0.5), soot * 0.5);

	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(roughness_base - traffic * 0.35 + s.w * 0.1, 0.12, 1.0);
	SPECULAR = mix(0.35, 0.55, traffic);
}
