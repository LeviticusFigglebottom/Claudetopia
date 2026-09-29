shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;

// A person's own marks on a head, drawn over the skin as the head's material_overlay (triage 39):
// the brows' style, a scar, moles and the face paint of their people. Every head carries its face
// coordinates as UV2 (tools/forge/lib/face_morphs.face_coords): across the face as an arc from its
// middle, + to the head's left, and up it from the eye line, in metres, mapped into 0..1 over
// UV2_SPAN. So a mark is drawn at a place on the face, lands there on every head, and goes with the
// skin when a face slider moves it. Nothing here is baked: the skin shader and the bake are left
// alone (HumanoidModel._face_overlay sets these; the choices are CharacterAppearance's).

const float UV2_SPAN = 0.40;

#include "res://assets/shaders/tattoo_designs.gdshaderinc"

uniform int brow_style = 0;          // 0 as painted, 1 full, 2 straight, 3 arched, 4 bushy, 5 joined
uniform vec3 brow_colour : source_color = vec3(0.23, 0.16, 0.11);
uniform float brow_lift = 0.0;       // metres: a woman's brows sit a little higher (the paint's)
uniform int scar = 0;                // 0 none, 1 cheek, 2 brow, 3 lip, 4 nose, 5 jaw
uniform vec3 skin_colour : source_color = vec3(0.86, 0.68, 0.53);
uniform float moles = 0.0;           // 0..1: how many of a person's six places carry one
uniform float mole_seed = 0.0;
uniform int paint = 0;               // 0 none, 1 woad, 2 reed dots, 3 ash mark, 4 leaf lines, 5 lake tears
// tattoos on the face (triage 48), two at most: the design (tattoo_designs.gdshaderinc), its box in
// face coordinates (centre x, centre y, half-width, half-height, metres; a negative half-width mirrors
// it) and its ink (rgb, a = fade)
uniform int tattoo0 = 0;
uniform int tattoo1 = 0;
uniform vec4 tattoo0_box = vec4(0.0, 0.0, 0.01, 0.01);
uniform vec4 tattoo1_box = vec4(0.0, 0.0, 0.01, 0.01);
uniform vec4 tattoo0_ink : source_color = vec4(0.1, 0.11, 0.13, 0.0);
uniform vec4 tattoo1_ink : source_color = vec4(0.1, 0.11, 0.13, 0.0);

varying vec2 face;

void vertex() {
	// a hair's breadth off the skin, so the overlay never loses the depth test to it
	VERTEX += NORMAL * 0.00012;
	face = vec2((UV2.x - 0.5) * UV2_SPAN, (0.5 - UV2.y) * UV2_SPAN);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// distance from p to the segment a-b
float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// how much of a brow covers p (0..1), in the style asked for: a band over the brow line from the
// inner end to the outer, thick at the head and thinning to the tail, with hair-like streaks
float brow(vec2 p, int style) {
	float x = abs(p.x);
	float inner = 0.011;
	float outer = style == 4 ? 0.060 : 0.056;
	float t = clamp((x - inner) / (outer - inner), 0.0, 1.0);
	float base = 0.0215 + brow_lift;
	float arch = 0.0;
	float thick = 0.0;
	if (style == 1) { arch = 0.0022 * sin(t * 2.6); thick = mix(0.0068, 0.0032, t); }
	else if (style == 2) { arch = 0.0006 * t; thick = mix(0.0056, 0.0036, t); }
	else if (style == 3) { arch = 0.0055 * sin(t * 2.4) - 0.0015 * t; thick = mix(0.0044, 0.0022, t); }
	else if (style == 4) { arch = 0.0015 * sin(t * 2.6); thick = mix(0.0092, 0.0052, t); }
	else if (style == 5) { arch = 0.0020 * sin(t * 2.6); thick = mix(0.0066, 0.0032, t); }
	float centre = base + arch - 0.0035 * t * t;
	float d = abs(p.y - centre) - thick * 0.5;
	float along = x < inner ? (inner - x) : (x > outer ? x - outer : 0.0);
	if (style == 5 && x < inner) {
		// joined: a thinner run of hair over the bridge of the nose
		along = 0.0;
		d = abs(p.y - base) - 0.0022;
	}
	// (triage 46's review: with a 1 mm edge and the streaks only dimming it, an older face's brow
	// was a flat dark bar.) A brow is hairs: the band is feathered over a third of its thickness,
	// thin at its head and fading at its tail, and inside it the hairs are drawn as strands lying up
	// and out at the head and out along the tail, with skin between them.
	float edge = (style == 4 ? 0.55 : 0.40) * thick;
	float cover = (1.0 - smoothstep(-0.35 * edge, edge, d)) * (1.0 - smoothstep(0.0, 0.003, along));
	cover *= mix(0.55, 1.0, smoothstep(0.0, 0.25, t)) * (1.0 - 0.55 * smoothstep(0.65, 1.0, t));
	float slant = mix(1.6, 0.25, t);                        // up and out at the head, along the tail
	vec2 q = vec2(x - (p.y - centre) * slant, p.y - centre);
	float hair = noise(vec2(q.x * 1800.0, q.y * 260.0));
	float fine = noise(vec2(q.x * 3100.0 + 17.0, q.y * 420.0));
	float strands = smoothstep(0.30, 0.70, 0.6 * hair + 0.4 * fine);
	float rag = style == 4 ? mix(0.7, 1.0, noise(p * 900.0)) : 1.0;
	return cover * mix(0.18, 0.95, strands) * rag;
}

float scar_line(vec2 p, vec2 a, vec2 b, float w) {
	float d = seg(p, a, b);
	float wob = 0.5 + noise(p * 700.0);
	return 1.0 - smoothstep(w * 0.4 * wob, w * wob, d);
}

float scar_mask(vec2 p, int kind) {
	if (kind == 1) return scar_line(p, vec2(0.027, -0.018), vec2(0.047, -0.060), 0.0020);
	if (kind == 2) return scar_line(p, vec2(-0.028, 0.036), vec2(-0.035, 0.004), 0.0017);
	if (kind == 3) return scar_line(p, vec2(0.006, -0.064), vec2(0.011, -0.090), 0.0015);
	if (kind == 4) return scar_line(p, vec2(-0.011, -0.006), vec2(0.012, -0.015), 0.0016);
	if (kind == 5) return scar_line(p, vec2(-0.043, -0.092), vec2(-0.022, -0.124), 0.0021);
	return 0.0;
}

float mole_mask(vec2 p) {
	float m = 0.0;
	for (int i = 0; i < 6; i++) {
		vec2 k = vec2(float(i) * 7.13 + mole_seed, mole_seed * 0.37 + float(i) * 3.1);
		if (hash(k) > moles) continue;
		vec2 c = vec2((hash(k + 1.7) - 0.5) * 0.11, -0.12 + hash(k + 4.2) * 0.13);
		// clear of the eyes and the lips
		if (abs(c.y) < 0.012 && abs(abs(c.x) - 0.033) < 0.02) continue;
		if (abs(c.y + 0.077) < 0.010 && abs(c.x) < 0.03) continue;
		float r = 0.0009 + 0.0010 * hash(k + 9.9);
		m = max(m, 1.0 - smoothstep(r * 0.55, r, length(p - c)));
	}
	return m;
}

// the paint of a people, as (colour, cover)
vec4 paint_of(vec2 p, int kind) {
	float brush = mix(0.55, 1.0, noise(p * vec2(420.0, 160.0)));
	float x = abs(p.x);
	if (kind == 1) {
		// woad: a band across the eyes from temple to temple, ragged at its edges
		float band = abs(p.y - 0.002) - 0.010 - 0.002 * noise(p * 300.0);
		float c = (1.0 - smoothstep(0.0, 0.0025, band)) * (1.0 - smoothstep(0.070, 0.085, x));
		return vec4(0.16, 0.25, 0.50, c * brush * 0.85);
	}
	if (kind == 2) {
		// reed dots: a row under each eye, out to the temple
		float c = 0.0;
		for (int i = 0; i < 5; i++) {
			vec2 d = vec2(0.018 + float(i) * 0.0085, -0.022 - float(i) * 0.0012);
			c = max(c, 1.0 - smoothstep(0.0011, 0.0019, length(vec2(x, p.y) - d)));
		}
		return vec4(0.74, 0.52, 0.22, c * 0.9);
	}
	if (kind == 3) {
		// ash: a thumb drawn up the forehead, and a smear under the lower lip
		float c = 1.0 - smoothstep(0.0, 0.003, max(abs(p.x) - 0.0045, max(0.030 - p.y, p.y - 0.066)));
		c = max(c, 1.0 - smoothstep(0.0, 0.003, max(abs(p.x) - 0.009, abs(p.y + 0.094) - 0.0035)));
		return vec4(0.56, 0.54, 0.50, c * brush * 0.8);
	}
	if (kind == 4) {
		// leaf lines: three dark strokes down and out over each cheek
		float c = 0.0;
		for (int i = 0; i < 3; i++) {
			float o = float(i) * 0.008;
			c = max(c, 1.0 - smoothstep(0.0008, 0.0016, seg(vec2(x, p.y), vec2(0.024 + o, -0.018), vec2(0.036 + o, -0.052))));
		}
		return vec4(0.11, 0.20, 0.11, c * brush * 0.9);
	}
	if (kind == 5) {
		// lake tears: a short line down from the outer corner of each eye, a dot at its end
		float c = 1.0 - smoothstep(0.0007, 0.0014, seg(vec2(x, p.y), vec2(0.050, -0.007), vec2(0.052, -0.024)));
		c = max(c, 1.0 - smoothstep(0.0012, 0.0020, length(vec2(x, p.y) - vec2(0.0525, -0.028))));
		return vec4(0.28, 0.40, 0.52, c * 0.85);
	}
	return vec4(0.0);
}

float face_tattoo(vec2 p, int id, vec4 box, float fade) {
	vec2 q = (p - box.xy) / box.zw;
	float soft = 0.025 + 0.08 * fade;
	return tattoo(id, q, 0.08 * (1.0 + 0.35 * fade), soft) * (1.0 - 0.3 * fade);
}

void fragment() {
	vec2 p = face;
	vec3 col = vec3(0.0);
	float a = 0.0;
	if (paint > 0) {
		vec4 pc = paint_of(p, paint);
		col = pc.rgb;
		a = pc.a;
	}
	if (tattoo0 > 0) {
		float t = face_tattoo(p, tattoo0, tattoo0_box, tattoo0_ink.a);
		col = mix(col, tattoo_ink(tattoo0_ink.rgb, tattoo0_ink.a), t);
		a = max(a, t * 0.88);
	}
	if (tattoo1 > 0) {
		float t = face_tattoo(p, tattoo1, tattoo1_box, tattoo1_ink.a);
		col = mix(col, tattoo_ink(tattoo1_ink.rgb, tattoo1_ink.a), t);
		a = max(a, t * 0.88);
	}
	if (brow_style > 0) {
		float b = brow(p, brow_style);
		col = mix(col, brow_colour, b);
		a = max(a, b * 0.80);
	}
	if (moles > 0.0) {
		float m = mole_mask(p);
		col = mix(col, vec3(0.20, 0.12, 0.08), m);
		a = max(a, m * 0.85);
	}
	if (scar > 0) {
		// scar tissue: paler and pinker than the skin round it, and no hair grows through it
		float s = scar_mask(p, scar);
		vec3 tissue = mix(skin_colour * 1.18, vec3(0.86, 0.62, 0.58), 0.35);
		col = mix(col, tissue, s);
		a = max(a, s * 0.9);
	}
	ALBEDO = clamp(col, 0.0, 1.0);
	ALPHA = clamp(a, 0.0, 1.0);
	ROUGHNESS = 0.72;
	SPECULAR = 0.2;
}
