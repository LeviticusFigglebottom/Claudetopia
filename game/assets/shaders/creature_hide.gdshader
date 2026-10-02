shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// The hide of a foe the forge has no rig for yet (PlaceholderBody): the crag-wolf, the stone-thrall,
// the drakes and hounds. They stood as boxes in one flat colour, which under either renderer read as
// an untextured grey mannequin. This paints each part in its own space, so the pattern moves with the
// body and does not swim through it: fur in strands along the part's length with a darker back and a
// paler belly, stone in mottled beds with dark cracks and lichen, a scaled hide, or bark. Only value
// noise and arithmetic, so the Compatibility renderer draws it as Forward+ does.
//
// pattern: 0 fur  1 stone  2 scaled hide  3 bark

uniform int pattern : hint_range(0, 3) = 0;
uniform vec4 base_color : source_color = vec4(0.8, 0.8, 0.8, 1.0);
// metres a strand, a scale or a bed is (in the part's own space, before the body is scaled)
uniform float unit = 0.05;

varying vec3 obj_pos;
varying vec3 obj_normal;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
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

float fbm(vec3 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.03) * 0.3 + vnoise(p * 4.1) * 0.15;
}

void vertex() {
	obj_pos = VERTEX;
	obj_normal = NORMAL;
}

void fragment() {
	vec3 p = obj_pos / max(unit, 0.001);
	vec3 n = normalize(obj_normal);
	vec3 col = base_color.rgb;
	float rough = 0.85;
	if (pattern == 0) {
		// fur: strands drawn out along the part's length (the axis it is longest in), clumped
		vec3 stretch = abs(n.y) > 0.6 ? vec3(1.0, 1.0, 0.18) : vec3(1.0, 0.22, 1.0);
		float strands = fbm(p * stretch * vec3(1.6, 1.6, 1.6));
		float clumps = fbm(p * 0.18);
		col *= mix(0.72, 1.12, strands) * mix(0.85, 1.08, clumps);
		// a darker saddle over the back, a paler belly
		col *= mix(1.12, 0.78, smoothstep(-0.2, 0.9, n.y));
		col = mix(col, col * vec3(0.92, 0.9, 0.88), smoothstep(0.5, 0.95, clumps));
		rough = 0.95;
	} else if (pattern == 1) {
		// stone: beds of the rock, mottled, its cracks dark and the lichen in the sheltered faces
		float beds = fbm(vec3(p.x * 0.35, p.y * 1.4, p.z * 0.35));
		float mottle = fbm(p * 0.6);
		col *= mix(0.68, 1.12, mottle) * mix(0.9, 1.05, beds);
		float crack = abs(vnoise(p * 0.45) - 0.5);
		col = mix(col * 0.32, col, smoothstep(0.015, 0.06, crack));
		float lichen = smoothstep(0.62, 0.78, fbm(p * 0.9 + vec3(7.0))) * smoothstep(-0.3, 0.5, n.y);
		col = mix(col, vec3(0.62, 0.6, 0.38) * (0.7 + 0.4 * mottle), lichen * 0.65);
		rough = 0.92;
	} else if (pattern == 2) {
		// a scaled hide: rows of scales, each a little lighter at its free edge
		vec3 q = p * vec3(1.0, 1.0, 1.0);
		vec2 cell = fract(vec2(q.x + 0.5 * floor(q.z), q.z) * 0.9);
		float scale_edge = smoothstep(0.55, 0.95, max(cell.x, cell.y));
		col *= mix(0.78, 1.08, fbm(p * 0.3)) * mix(1.0, 1.18, scale_edge);
		col *= mix(1.08, 0.8, smoothstep(-0.2, 0.9, n.y));
		rough = 0.55;
	} else {
		// bark: deep furrows up the part, with moss low down
		float furrow = fbm(vec3(p.x * 2.2, p.y * 0.25, p.z * 2.2));
		col *= mix(0.45, 1.1, smoothstep(0.3, 0.7, furrow));
		float moss = smoothstep(0.55, 0.75, fbm(p * 0.7 + vec3(3.0)));
		col = mix(col, vec3(0.28, 0.34, 0.16), moss * 0.5);
		rough = 0.95;
	}
	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	ROUGHNESS = rough;
}
