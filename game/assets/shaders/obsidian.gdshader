shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

// Black volcanic glass: what the Ash Winter left of the Glass Falls and of the Glassbed's river when
// it sang them dry. Not water and not rock (DESIGN and the WORLD_BIBLE's Cinderlea say so on purpose):
//
// - near-black, with faint depth: bands of the flow seen a little way *under* the surface (a
//   parallax step along the view), smoky and very slightly violet, and glints of sheen along them;
// - the flow lines frozen mid-pour: ridges running down the flow, meandering, each rope of the
//   liquid that set; and across them the arcs a slowing flow wrinkles into, bowed downstream;
// - conchoidal fracture where it broke: shells of concentric ripples round each strike point;
// - its cracks: the polygons a sheet of glass cools into, dusted with the region's ash;
// - glossy: a sharp, hot highlight off the sun and a broad soft one, plus the sky's reflection at a
//   grazing angle (Fresnel), all drawn here in light() off the region's own sun, so it reads the
//   same on Compatibility as on Forward+, dims at dusk and goes out at night.
//
// Meshes give UV in metres: u across the flow, v along it (down a fall, down the bed). A mesh with no
// flow of its own (a block, a shard) sets `world_uv` and the flow is drawn off world xz along
// `world_flow`.
uniform vec4 glass_color : source_color = vec4(0.030, 0.028, 0.034, 1.0);
uniform vec4 band_color : source_color = vec4(0.060, 0.052, 0.068, 1.0);
uniform vec4 depth_color : source_color = vec4(0.11, 0.085, 0.13, 1.0);
uniform vec4 sheen_color : source_color = vec4(0.62, 0.52, 0.80, 1.0);
uniform vec4 ash_color : source_color = vec4(0.34, 0.31, 0.29, 1.0);
uniform vec4 sky_tint : source_color = vec4(0.62, 0.68, 0.84, 1.0);
// how strongly the frozen ropes, the arcs across them and the shells of fracture stand
uniform float ropes = 1.0;
uniform float ripples = 0.6;
uniform float conchoidal = 0.5;
// how far the flow lines wander (1 a fall's ropes; more, a bed's lines that bend, gather and part)
uniform float meander = 1.0;
// broad glossy swells of the set flow, and how much they break the lines along their length and
// take over the bands under the surface (0 = a fall's ropes, 1 = a bed's)
uniform float swells = 0.0;
// the cooling cracks' cell (m) and how many of them there are (0 = none)
uniform float crack_cell = 2.6;
uniform float cracks = 0.6;
// how much of the cracks the ash fills (light lines); a bed's cracks drawn light read as paving
uniform float crack_ash = 1.0;
// ash in the hollows, the cracks and on the flat tops (0 = none)
uniform float ash = 0.3;
uniform float bump = 1.0;
uniform float gloss = 1.0;
uniform float sky_reflect = 1.0;
uniform float world_uv = 0.0;
uniform vec2 world_flow = vec2(0.0, 1.0);

varying vec3 world_pos;
varying vec3 world_n;
varying float sky_term;
varying float ash_mask;
varying float sheen_mask;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
	           mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

// the nearest feature point's distance, the edge distance to the next (for cracks), and its id
vec3 cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash22(i + g) * 0.8 + 0.1;
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = hash12(i + g);
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec3(d1, d2 - d1, id);
}

// the across coordinate the ropes follow: the flow meanders, so the ropes do
float across_of(vec2 uv) {
	float extra = max(meander - 1.0, 0.0);
	return uv.x + (vnoise(uv * vec2(0.18, 0.07)) - 0.5) * 2.4 * meander + (vnoise(uv * vec2(0.6, 0.2) + 7.0) - 0.5) * 0.5 * meander
			+ (vnoise(uv * vec2(0.3, 0.45) + 13.0) - 0.5) * 1.4 * extra;
}

// the frozen ropes: rounded ridges down the flow, of uneven width, fading in and out along it
float rope_height(vec2 uv) {
	float a = across_of(uv);
	float r1 = 1.0 - abs(sin(a * 2.3 + vnoise(vec2(a * 0.7, uv.y * 0.09)) * 3.0));
	float r2 = 1.0 - abs(sin(a * 5.9 + 1.7 + vnoise(vec2(a * 1.3, uv.y * 0.21)) * 4.0));
	float fade = 0.55 + 0.45 * vnoise(vec2(a * 0.9, uv.y * 0.12) + 3.0);
	// broken along their length where the flow swelled, so no line runs on like a plank's grain
	fade = mix(fade, smoothstep(0.3, 0.8, vnoise(vec2(a * 0.8, uv.y * 0.4) + 3.0)), clamp(swells, 0.0, 1.0));
	return (r1 * r1 * 0.65 + r2 * r2 * 0.35) * fade;
}

// the arcs a slowing flow wrinkles into, bowed downstream across the ropes
float ripple_height(vec2 uv) {
	float a = across_of(uv);
	float bow = sin(a * 0.35) * 1.4;
	// unevenly spaced and patchy: evenly spaced arcs read as the planks of a boardwalk
	float w = uv.y * (1.5 + 0.9 * vnoise(uv * 0.07 + 5.0)) + bow + vnoise(uv * 0.5) * 2.2;
	float patch = smoothstep(0.25, 0.8, vnoise(uv * vec2(0.3, 0.18) + 11.0));
	return (0.5 + 0.5 * sin(w * 3.14159)) * patch;
}

float height_of(vec2 uv, out float crack, out float band) {
	float h = rope_height(uv) * ropes * 0.6 + ripple_height(uv) * ripples * 0.25;
	// the broad swells: lobes of the flow a few metres across, each one a wide glossy highlight
	float sw = 0.0;
	if (swells > 0.0) {
		sw = vnoise(uv * vec2(0.26, 0.17)) * 0.65 + vnoise(uv * vec2(0.66, 0.48) + 9.0) * 0.35;
		h += sw * swells * 1.5;
	}
	// shells of fracture: concentric ripples round strike points, fading out from each
	if (conchoidal > 0.0) {
		vec3 c = cells(uv * 0.75 + 31.0);
		float shell = sin(c.x * 15.0) * exp(-c.x * 2.6) * step(0.45, c.z);
		h += shell * conchoidal * 0.18;
	}
	// the cooling cracks: a thin groove at each polygon's edge
	vec3 k = cells(uv / max(crack_cell, 0.1));
	crack = (1.0 - smoothstep(0.0, 0.035, k.y)) * cracks;
	h -= crack * 0.25;
	band = swells >= 1.0 ? 0.0 : rope_height(uv * vec2(1.7, 0.6) + 5.0);
	band = mix(band, smoothstep(0.2, 0.85, sw), clamp(swells, 0.0, 1.0));
	return h;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = UV;
	if (world_uv > 0.5) {
		vec2 f = normalize(world_flow);
		vec2 side = vec2(-f.y, f.x);
		// a face that stands steep takes its flow down the world's y instead
		float steep = 1.0 - smoothstep(0.35, 0.75, abs(world_n.y));
		vec2 flat_uv = vec2(dot(world_pos.xz, side), dot(world_pos.xz, f));
		vec2 wall_uv = vec2(dot(world_pos.xz, side) + dot(world_pos.xz, f), -world_pos.y);
		uv = mix(flat_uv, wall_uv, steep);
	}
	float crack;
	float band;
	float h = height_of(uv, crack, band);
	float c1;
	float b1;
	float hx = height_of(uv + vec2(0.03, 0.0), c1, b1);
	float hy = height_of(uv + vec2(0.0, 0.03), c1, b1);
	vec2 grad = vec2(hx - h, hy - h) / 0.03;
	vec3 nm = normalize(vec3(-grad * 0.22 * bump, 1.0));
	// bent here rather than through NORMAL_MAP, so the sky's reflection below runs in the ropes too
	vec3 geo_n = NORMAL;
	NORMAL = normalize(TANGENT * nm.x + BINORMAL * nm.y + geo_n * nm.z);

	// depth: the flow's bands a little way under the surface, seen along the view
	vec3 v = normalize(VIEW);
	float nv = max(dot(v, geo_n), 0.25);
	vec2 par = vec2(dot(v, TANGENT), dot(v, BINORMAL)) / nv * 0.22;
	float inner = rope_height(uv * vec2(1.3, 0.8) - par + 17.0);
	vec3 col = mix(glass_color.rgb, band_color.rgb, smoothstep(0.3, 0.9, band));
	col = mix(col, depth_color.rgb, smoothstep(0.55, 0.95, inner) * 0.55);

	// ash: in the cracks, in the hollows, on what faces up, never on the ridges' crests
	float up = clamp(world_n.y, 0.0, 1.0);
	float hollow = 1.0 - smoothstep(0.05, 0.35, h);
	float drift = smoothstep(0.35, 0.8, vnoise(world_pos.xz * 0.35) * 0.7 + vnoise(world_pos.xz * 1.7) * 0.3);
	float a = clamp(crack * 1.2 * crack_ash + hollow * drift * up * 0.9 + up * up * drift * 0.25, 0.0, 1.0) * ash;
	ash_mask = a;
	col = mix(col, ash_color.rgb, a);
	col *= 1.0 - crack * (1.0 - crack_ash) * 0.6;
	ALBEDO = col;
	ROUGHNESS = mix(0.06 + 0.06 * (1.0 - h), 0.92, a);
	// none of the engine's own reflection: at a low roughness its sky turned the glass pool white
	// under a grazing eye (a mirror, so water). The sky's reflection is drawn in light() instead, the
	// same on every renderer and held to a sheen.
	SPECULAR = 0.0;
	METALLIC = 0.0;
	sheen_mask = smoothstep(0.55, 0.95, band) * (1.0 - a);

	// the sky in the glass: what the reflected ray sees, the horizon's band brighter than the zenith,
	// the ground below dark; times Fresnel, so it is a sheen at a grazing angle and nearly nothing
	// straight on, which is what glass is
	vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v_world = normalize((INV_VIEW_MATRIX * vec4(v, 0.0)).xyz);
	vec3 r = reflect(-v_world, n_world);
	// a bright band at the horizon, a dim sky over it and the dark ground under it: the glass shows
	// that band only where a ridge or an arc turns to it, so it breaks into streaks of light over
	// black (a smooth gradient over the whole of it read as matte grey stone)
	float sky = 0.06 + 0.8 * exp(-abs(r.y - 0.08) * 11.0) * smoothstep(-0.1, 0.0, r.y) + 0.5 * smoothstep(0.0, 0.6, r.y);
	float fres = 0.05 + 0.55 * pow(1.0 - clamp(dot(n_world, v_world), 0.0, 1.0), 4.0);
	sky_term = sky * fres * (1.0 - a) * sky_reflect;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// the ash and the glass's faint body take the light softly; the glass itself hardly at all
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * clamp(ndl * 0.8 + 0.2, 0.0, 1.0) / PI;
	vec3 h = normalize(LIGHT + VIEW);
	float ndh = clamp(dot(NORMAL, h), 0.0, 1.0);
	float vdh = clamp(dot(VIEW, h), 0.0, 1.0);
	float fres = 0.04 + 0.96 * pow(1.0 - vdh, 5.0);
	float lit = smoothstep(-0.05, 0.1, ndl);
	float g = gloss * (1.0 - ash_mask);
	// a hot, small highlight where a face turns to the sun, and a broad soft one round it
	float sharp = pow(ndh, 700.0) * 40.0;
	float broad = pow(ndh, 40.0) * 0.35;
	float sheen = pow(ndh, 14.0) * 0.18 * sheen_mask;
	vec3 spec = LIGHT_COLOR * ATTENUATION * lit * g * ((sharp + broad) * (0.25 + fres) + 0.0);
	spec += LIGHT_COLOR * ATTENUATION * lit * sheen * sheen_color.rgb;
	if (LIGHT_IS_DIRECTIONAL) {
		// the sky, as bright as the sun makes it but the sky's own cool colour (in the sun's it was
		// brown wood at dusk), dim under the moon, and reflected in shade as well
		float lum = dot(LIGHT_COLOR, vec3(0.3, 0.59, 0.11));
		spec += sky_tint.rgb * lum * sky_term * 0.35;
	}
	SPECULAR_LIGHT += spec / PI;
}
