shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// The painted stone of every rock and boulder (world/rock_paint.gd swaps it in for the forge's
// StandardMaterial3D when a rock's scene is first loaded): the forge's own albedo, normal and
// occlusion, drawn the way a painter blocks a stone before detailing it.
//
// * Broad planes. The light falls in two tones with a soft step between (light()): a lit plane
//   that barely changes across its face and a shadow plane, not Lambert's smooth roll over every
//   bump; the normal map is held down so its detail rides on the planes rather than breaking
//   them; and each plane takes a value from where it faces -- tops the sky's, undersides less.
// * Wear. Convex edges are worn pale (the curvature, from how fast the normal turns per metre on
//   screen), weather streaks run down the steep faces, and the stone's own grain speckles it.
// * Weather. Moss and lichen lie on the tops and on the faces the region's weather comes from,
//   in the region's colours (Briarwold's deep moss, Skerrow's crusts of lichen, Cinderlea's ash
//   dust where the moss would be), read from the world's region map at the rock's own spot, so
//   a stone lent from another region's set wears the country it stands in.
// * Feet. Over the half metre or so above the ground line the stone goes to the region's soil
//   colour and darkens, broken by noise, so a rock sits in the land rather than on it. The ground
//   line is the terrain's own height under each fragment -- the runtime height map (8 m, the
//   provider's own bilinear) corrected at the rock by the exact height there, which the scatter
//   carries in its tint's alpha (RockPaint.seat_rows) -- so it holds whatever the rock's sink and
//   tilt, and runs across a rock seated into a slope as the slope does.
//
// COLOR carries the scatter's per-instance tint (world_streamer.gd), white elsewhere; its alpha,
// below 1, is the ground correction.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_texture : hint_default_white, filter_linear_mipmap;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform bool has_normal = true;
uniform float normal_strength = 0.8;
uniform float roughness_base = 0.86;

// the stone's own character (RockPaint.STONES)
uniform float edge_wear = 0.5;
uniform float streaks = 0.3;
uniform float speckle = 0.2;
uniform float sheen = 0.0;
uniform float moss_mult = 1.0;
// what the streaks down the faces are: darker stone (alpha 0), or a colour of their own (alpha 1):
// the verdigris that runs down old bell metal
uniform vec4 streak_tint : source_color = vec4(0.0, 0.0, 0.0, 0.0);
// the stone's albedo lifted to its floor (RockPaint.value_lift): Cinderlea's near-black stone;
// and how far its picture is pulled toward its own (lifted) mean colour, so the fused stone's
// flow bands, lifted with it, stay bands in glass rather than stripes on a tent
uniform float value_lift = 1.0;
uniform vec4 value_mean : source_color = vec4(0.03, 0.03, 0.03, 1.0);
uniform float value_flatten = 0.0;

// the painted light: how dark the shadow plane is against the lit one, and how soft the step
uniform float shadow_value = 0.14;
uniform float band_soft = 0.3;

// the region the rock stands in (RockPaint.bind_world): the runtime region map, one texel per
// `world_rect.z` metres from (`world_rect.x`, `world_rect.y`), `world_rect.w` texels a side;
// and the table of each region's weathering, one column a region
uniform sampler2D region_map : filter_nearest;
uniform sampler2D region_table : filter_nearest;
uniform vec4 world_rect = vec4(-4096.0, -4096.0, 8.0, 1024.0);
uniform float regions_bound = 0.0;
// the runtime height map (R32F), its texel (0, 0) at (`height_rect.x`, `height_rect.y`), one
// texel per `height_rect.z` metres, `height_rect.w` a side
uniform sampler2D height_map : filter_nearest;
uniform vec4 height_rect = vec4(-4096.0, -4096.0, 8.0, 1024.0);
uniform float heights_bound = 0.0;
uniform int own_region = 0;
uniform int region_count = 6;

varying vec3 world_pos;
// where the stone's own patterns are drawn from: metres from the rock's pivot, plus an offset of
// its own, so no two rocks wear alike and the noise keeps its precision (in world metres, three
// and a half kilometres out, the hashes fell into stripes a hand's breadth apart)
varying vec3 stone_pos;
varying float base_h;
varying flat float ground_corr;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i + vec3(0, 0, 0)), hash3(i + vec3(1, 0, 0)), f.x),
				mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
				mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm3(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise3(p);
		p = p * 2.07 + vec3(3.1, 1.7, 5.3);
		a *= 0.5;
	}
	return v / 0.875;
}

// the provider's own bilinear over the runtime height map (TerrainProvider.sample_height)
float map_height(vec2 xz) {
	float last = height_rect.w - 1.0;
	vec2 f = clamp((xz - height_rect.xy) / height_rect.z, vec2(0.0), vec2(last - 0.001));
	ivec2 i0 = ivec2(f);
	vec2 t = f - vec2(i0);
	ivec2 i1 = min(i0 + ivec2(1), ivec2(int(last)));
	float h00 = texelFetch(height_map, i0, 0).r;
	float h10 = texelFetch(height_map, ivec2(i1.x, i0.y), 0).r;
	float h01 = texelFetch(height_map, ivec2(i0.x, i1.y), 0).r;
	float h11 = texelFetch(height_map, i1, 0).r;
	return mix(mix(h00, h10, t.x), mix(h01, h11, t.x), t.y);
}

int region_here() {
	if (regions_bound < 0.5) {
		return own_region;
	}
	int grid = int(world_rect.w);
	ivec2 t = clamp(ivec2(round((world_pos.xz - world_rect.xy) / world_rect.z)), ivec2(0), ivec2(grid - 1));
	int r = int(texelFetch(region_map, t, 0).r * 255.0 + 0.5);
	return (r < region_count) ? r : own_region;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// the rock's pivot is at its foot (the forge's bounds start at y = 0)
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	base_h = world_pos.y - origin.y;
	stone_pos = world_pos - origin + fract(origin * vec3(0.0131, 0.0077, 0.0173)) * 97.0;
	ground_corr = COLOR.a < 0.999 ? (COLOR.a - 0.5) * 4.0 : 0.0;
}

void fragment() {
	vec3 col = texture(albedo_texture, UV).rgb * albedo_tint.rgb * value_lift;
	col = mix(col, value_mean.rgb, value_flatten) * COLOR.rgb;
	vec3 orm = texture(orm_texture, UV).rgb;
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);

	int reg = region_here();
	vec4 moss_c = texelFetch(region_table, ivec2(reg, 0), 0);
	vec4 lichen_c = texelFetch(region_table, ivec2(reg, 1), 0);
	vec4 soil_c = texelFetch(region_table, ivec2(reg, 2), 0);
	vec4 misc = texelFetch(region_table, ivec2(reg, 3), 0);
	vec4 stone_c = texelFetch(region_table, ivec2(reg, 4), 0);
	vec4 turf_c = texelFetch(region_table, ivec2(reg, 5), 0);
	vec3 weather_from = normalize(vec3(misc.r * 2.0 - 1.0, 0.0, misc.g * 2.0 - 1.0) + vec3(0.0, 0.001, 0.0));

	// how big a pixel is here, for fading detail that would only shimmer
	float px = length(fwidth(stone_pos));
	float fine = 1.0 - smoothstep(0.015, 0.06, px);

	// the country's stone: a lent or a pale stone leans to the hue of the rock round it, keeping
	// its own value
	float lum = dot(col, vec3(0.3333));
	float slum = max(dot(stone_c.rgb, vec3(0.3333)), 1e-3);
	col = mix(col, stone_c.rgb * (lum / slum), stone_c.a);

	// the recesses: the forge's occlusion painted into the colour, where the light cannot reach
	// (the engine's own occlusion touches only the fill), and the planes -- tops take the sky's
	// value, undersides fall away into the shade under them
	col *= mix(0.45, 1.0, orm.r);
	col *= mix(0.62, 1.07, smoothstep(-0.5, 0.85, wn.y));

	// the stone's grain: soft specks, dark and pale, gone where they would shimmer
	float g = vnoise3(stone_pos * 19.0);
	col *= 1.0 - speckle * 0.3 * smoothstep(0.72, 0.84, g) * fine;
	col *= 1.0 + speckle * 0.22 * (1.0 - smoothstep(0.16, 0.28, g)) * fine;

	// weather streaks down the steep faces: noise stretched along the fall line
	float steep = 1.0 - abs(wn.y);
	float sn = vnoise3(vec3(stone_pos.x * 2.6, stone_pos.y * 0.22, stone_pos.z * 2.6))
			* 0.7 + vnoise3(stone_pos * vec3(7.0, 0.6, 7.0)) * 0.3;
	float streak = smoothstep(0.52, 0.8, sn) * smoothstep(0.35, 0.85, steep) * streaks;
	col = mix(col * (1.0 - 0.38 * streak), streak_tint.rgb * (0.7 + 0.5 * sn), streak * 0.8 * streak_tint.a);

	// wear on the convex edges: the normal turning fast per metre is an edge
	float curv = length(fwidth(wn)) / max(px, 1e-4);
	float edge = smoothstep(1.6, 5.0, curv) * edge_wear
			* smoothstep(0.3, 0.6, vnoise3(stone_pos * 3.3 + 7.1));
	col = mix(col, min(col * 1.55 + 0.012, vec3(1.0)), edge);

	// moss (or Cinderlea's ash dust) on the tops and on the faces the weather comes from
	float facing = dot(wn, normalize(vec3(0.0, 1.0, 0.0) + weather_from * 0.5));
	float mn = fbm3(stone_pos * 0.9 + vec3(0.0, 11.0, 0.0));
	float moss_amt = clamp(moss_c.a * moss_mult, 0.0, 1.0);
	float moss = smoothstep(0.2, 0.7, facing) * smoothstep(1.0 - moss_amt, 1.0 - moss_amt + 0.18, mn);
	vec3 moss_col = moss_c.rgb * (0.82 + 0.36 * vnoise3(stone_pos * 6.0));
	col = mix(col, moss_col, clamp(moss * 1.2, 0.0, 1.0));

	// lichen: small crusty rosettes on the exposed faces, the region's colour
	float ln = vnoise3(stone_pos * 3.1) * 0.6 + vnoise3(stone_pos * 8.7 + 3.0) * 0.4;
	float lich_amt = lichen_c.a;
	float lichen = smoothstep(1.0 - lich_amt * 0.55, 1.0 - lich_amt * 0.55 + 0.06, ln)
			* smoothstep(-0.25, 0.4, facing) * (1.0 - moss);
	col = mix(col, lichen_c.rgb * (0.9 + 0.2 * g), lichen * 0.85);

	// the feet: into the region's soil, darker, broken by noise, over `foot_h` above the ground
	// line (or above the rock's pivot where there is no height map, a headless test)
	float foot_h = max(soil_c.a * 2.0, 0.05);
	float above = heights_bound > 0.5 ? world_pos.y - (map_height(world_pos.xz) + ground_corr) : base_h;
	float fn = vnoise3(stone_pos * 2.2) - 0.5;
	float foot = 1.0 - smoothstep(0.0, foot_h, above + fn * foot_h * 0.8);
	col = mix(col, soil_c.rgb, foot * 0.7);
	col *= mix(1.0, 0.72, foot);

	// turf: the slope's own grass grown up onto the ledges and shelves near the ground, broken
	// into tufts, so a crag on a green hillside is of the hillside and not laid on it
	float turf_h = turf_c.a * 4.0;
	float tn2 = vnoise3(stone_pos * 1.7 + 4.0) * 0.65 + vnoise3(stone_pos * 5.3) * 0.35;
	float turf = smoothstep(0.45, 0.75, wn.y) * (1.0 - smoothstep(turf_h * 0.4, turf_h, above))
			* smoothstep(0.38, 0.55, tn2) * step(0.01, turf_h);
	col = mix(col, turf_c.rgb * (0.8 + 0.4 * tn2), turf * 0.85);

	// The forge's normal map is not handed to the light: its strata, stepped by the two-tone light
	// below, came out as stripes a hand apart across every boulder. Its relief is painted into the
	// colour instead -- the grooves darker, the faces toward a fixed painter's light a little
	// paler -- so it rides on the planes, and the light falls on the stone's own broad shape.
	if (has_normal) {
		vec3 tn = texture(normal_texture, UV).rgb * 2.0 - 1.0;
		float cavity = smoothstep(0.55, 0.98, tn.z);
		float emboss = dot(normalize(tn), normalize(vec3(-0.35, 0.45, 0.82)));
		float relief = normal_strength * mix(0.5, 1.0, fine) * (1.0 - 0.6 * moss);
		col *= mix(1.0, (0.72 + 0.28 * cavity) * (0.9 + 0.2 * clamp(emboss, 0.0, 1.0)), relief);
	}
	ALBEDO = col;
	ROUGHNESS = clamp(mix(roughness_base * (0.85 + 0.3 * orm.g), 0.97, max(max(moss, foot), turf)), 0.3, 1.0)
			- sheen * 0.35 * (1.0 - moss);
	SPECULAR = 0.35 + sheen * 0.4;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.35;
}

void light() {
	// Two tones with a soft step: the lit plane changes little across its face, the shadow plane
	// is a flat darker value, and the terminator between them is a band a painter would lay in.
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(-band_soft * 0.35, band_soft, ndl);
	float tone = mix(shadow_value, 0.42 + 0.58 * clamp(ndl, 0.0, 1.0), lit);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * tone / PI;
	// a broad, soft highlight on the lit planes; fused stone and basalt glint more
	vec3 h = normalize(LIGHT + VIEW);
	float spec = pow(clamp(dot(NORMAL, h), 0.0, 1.0), mix(12.0, 48.0, sheen)) * (0.03 + 0.35 * sheen);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * spec * lit * (1.0 - ROUGHNESS * 0.6) / PI;
}
