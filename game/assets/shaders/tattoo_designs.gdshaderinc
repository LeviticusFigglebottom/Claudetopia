// Tattoo designs (triage 48), shared by the face's marks (face_marks.gdshader) and the body's
// (body_marks.gdshader). Each is drawn in its own box, p in -1..1 across and up; `soft` is how far an
// edge has spread, in the same units (an old tattoo's ink has run under the skin). A design returns
// how much of p it covers, 0..1. The ids are CharacterAppearance.TATTOO_DESIGNS' indices.
//
// 1 knotwork band (the Clans)      2 three-looped knot (the Clans)
// 3 water lines (the Reedfolk)     4 reeds (the Reedfolk)
// 5 a leaf (the Woodfolk)          6 antlers (the Woodfolk)
// 7 ash rings (the Ash-Pilgrims)   8 a hearth-mark (the Vale)
// 9 tally strokes (the Lakefolk)  10 a row of dots               11 plain bands

float tat_seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// a stroke of half-width w at distance d
float tat_line(float d, float w, float soft) {
	return 1.0 - smoothstep(w - soft * 0.5, w + soft, d);
}

float tat_knot_band(vec2 p, float w, float soft) {
	// two strands weaving across the band, each passing under the other at alternate crossings,
	// between two border lines
	float k = 3.14159 * 1.5;
	float y1 = 0.48 * sin(p.x * k);
	float y2 = -y1;
	float d1 = abs(p.y - y1) * 0.8;
	float d2 = abs(p.y - y2) * 0.8;
	float s1 = tat_line(d1, w, soft);
	float s2 = tat_line(d2, w, soft);
	// the crossings are where sin = 0: x = n / 1.5; at even n strand 1 goes over, at odd strand 2
	float n = floor(p.x * 1.5 + 0.5);
	float near = 1.0 - smoothstep(0.10, 0.20, abs(p.x * 1.5 - n));
	bool one_over = mod(n, 2.0) < 0.5;
	// the strand underneath is cut back either side of the one over it
	float gap1 = one_over ? 0.0 : tat_line(d2, w * 2.4, soft) * near;
	float gap2 = one_over ? tat_line(d1, w * 2.4, soft) * near : 0.0;
	float c = max(s1 * (1.0 - gap1), s2 * (1.0 - gap2));
	float border = tat_line(abs(abs(p.y) - 0.86), w * 0.8, soft);
	return max(c, border) * (1.0 - smoothstep(0.96, 1.0, abs(p.x)));
}

float tat_triple_knot(vec2 p, float w, float soft) {
	float c = 0.0;
	for (int i = 0; i < 3; i++) {
		float a = 1.5708 + float(i) * 2.0944;
		vec2 o = vec2(cos(a), sin(a)) * 0.34;
		c = max(c, tat_line(abs(length(p - o) - 0.46), w, soft));
	}
	return c;
}

float tat_water(vec2 p, float w, float soft) {
	float c = 0.0;
	for (int i = -1; i <= 1; i++) {
		float y = float(i) * 0.55 + 0.16 * sin(p.x * 5.5 + float(i) * 1.3);
		c = max(c, tat_line(abs(p.y - y), w, soft));
	}
	return c * (1.0 - smoothstep(0.92, 1.0, abs(p.x)));
}

float tat_reeds(vec2 p, float w, float soft) {
	float c = 0.0;
	for (int i = -1; i <= 1; i++) {
		float x0 = float(i) * 0.42;
		float lean = 0.10 * float(i);
		// a stem, bending as it rises, and the seed-head at its top
		float x = x0 + lean * (p.y + 1.0) * 0.5;
		float stem = tat_line(abs(p.x - x), w * 0.8, soft) * step(-0.95, p.y) * step(p.y, 0.35);
		vec2 h = vec2(x0 + lean, 0.60);
		vec2 q = (p - h) / vec2(0.11, 0.30);
		float head = 1.0 - smoothstep(1.0 - soft * 3.0, 1.0 + soft * 3.0, length(q));
		c = max(c, max(stem, head));
	}
	return c;
}

float tat_leaf(vec2 p, float w, float soft) {
	// a pointed leaf up the box: its outline, the midrib and three veins a side
	float half_w = 0.52 * (1.0 - p.y * p.y);
	float outline = tat_line(abs(abs(p.x) - max(half_w, 0.0)), w, soft) * step(abs(p.y), 0.98);
	float rib = tat_line(abs(p.x), w * 0.8, soft) * step(-1.0, p.y) * step(p.y, 0.95);
	float veins = 0.0;
	for (int i = 0; i < 3; i++) {
		float y0 = -0.45 + float(i) * 0.4;
		veins = max(veins, tat_line(tat_seg(vec2(abs(p.x), p.y), vec2(0.0, y0), vec2(0.36 * (1.0 - y0 * y0), y0 + 0.28)), w * 0.6, soft));
	}
	// and a stalk below
	float stalk = tat_line(tat_seg(p, vec2(0.0, -1.0), vec2(0.0, -0.85)), w, soft);
	return max(max(outline, rib), max(veins * step(abs(p.x), half_w), stalk));
}

float tat_antlers(vec2 p, float w, float soft) {
	// a pair of antlers from a brow at the foot of the box, each a beam with three tines
	vec2 q = vec2(abs(p.x), p.y);
	float c = tat_line(tat_seg(q, vec2(0.10, -0.85), vec2(0.55, 0.05)), w, soft);
	c = max(c, tat_line(tat_seg(q, vec2(0.55, 0.05), vec2(0.62, 0.92)), w, soft));
	c = max(c, tat_line(tat_seg(q, vec2(0.30, -0.44), vec2(0.12, -0.05)), w * 0.8, soft));
	c = max(c, tat_line(tat_seg(q, vec2(0.52, 0.00), vec2(0.20, 0.42)), w * 0.8, soft));
	c = max(c, tat_line(tat_seg(q, vec2(0.58, 0.45), vec2(0.88, 0.70)), w * 0.8, soft));
	c = max(c, tat_line(tat_seg(q, vec2(0.0, -0.85), vec2(0.12, -0.85)), w, soft));
	return c;
}

float tat_ash_rings(vec2 p, float w, float soft) {
	// two rings, one within the other, and seven dots round them: a pilgrim counts bells
	float r = length(p);
	float c = max(tat_line(abs(r - 0.42), w, soft), tat_line(abs(r - 0.66), w * 0.7, soft));
	for (int i = 0; i < 7; i++) {
		float a = 1.5708 + float(i) * 0.8976;
		c = max(c, tat_line(length(p - vec2(cos(a), sin(a)) * 0.88), w * 1.3, soft));
	}
	return c;
}

float tat_hearth(vec2 p, float w, float soft) {
	// a small hearth-mark: the hearth-stone's line, and a flame over it
	float base = tat_line(tat_seg(p, vec2(-0.6, -0.6), vec2(0.6, -0.6)), w, soft);
	vec2 q = (p - vec2(0.0, -0.1)) / vec2(0.36, 0.55);
	// a teardrop: round below, drawn to a point above
	float drop = length(vec2(q.x / max(1.0 - max(q.y, 0.0), 0.05), min(q.y, 0.0)));
	float flame = tat_line(abs(drop - 0.8) * 0.36, w, soft) * step(q.y, 1.0);
	return max(base, flame);
}

float tat_tally(vec2 p, float w, float soft) {
	// a ledger's count: four strokes and a fifth across, twice
	float c = 0.0;
	for (int row = 0; row < 2; row++) {
		float y0 = row == 0 ? 0.45 : -0.45;
		for (int i = 0; i < 4; i++) {
			float x = -0.6 + float(i) * 0.4;
			c = max(c, tat_line(tat_seg(p, vec2(x, y0 - 0.35), vec2(x, y0 + 0.35)), w * 0.8, soft));
		}
		c = max(c, tat_line(tat_seg(p, vec2(-0.8, y0 - 0.25), vec2(0.8, y0 + 0.25)), w * 0.8, soft));
	}
	return c;
}

float tat_dots(vec2 p, float w, float soft) {
	float c = 0.0;
	for (int i = 0; i < 5; i++) {
		vec2 o = vec2(-0.8 + float(i) * 0.4, 0.0);
		c = max(c, tat_line(length(p - o), w * 1.6, soft));
	}
	return c;
}

float tat_bands(vec2 p, float w, float soft) {
	float c = tat_line(abs(p.y - 0.4), w * 2.2, soft);
	return max(c, tat_line(abs(p.y + 0.4), w * 1.4, soft));
}

// design `id` at p, strokes of half-width w, edges spread by soft
float tattoo(int id, vec2 p, float w, float soft) {
	if (abs(p.x) > 1.3 || abs(p.y) > 1.3) return 0.0;
	if (id == 1) return tat_knot_band(p, w, soft);
	if (id == 2) return tat_triple_knot(p, w, soft);
	if (id == 3) return tat_water(p, w, soft);
	if (id == 4) return tat_reeds(p, w, soft);
	if (id == 5) return tat_leaf(p, w, soft);
	if (id == 6) return tat_antlers(p, w, soft);
	if (id == 7) return tat_ash_rings(p, w, soft);
	if (id == 8) return tat_hearth(p, w, soft);
	if (id == 9) return tat_tally(p, w, soft);
	if (id == 10) return tat_dots(p, w, soft);
	if (id == 11) return tat_bands(p, w, soft);
	return 0.0;
}

// the ink as it sits in the skin after `fade` (0 fresh .. 1 old): an old tattoo is bluer, greyer and
// thinner, and its edges have run
vec3 tattoo_ink(vec3 ink, float fade) {
	vec3 old = mix(vec3(0.20, 0.27, 0.31), ink, 0.35);
	return mix(ink, old, fade * 0.8);
}
