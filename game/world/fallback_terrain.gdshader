// The ground when Terrain3D cannot draw it (world/fallback_terrain.gd).
//
// One flat grid mesh, shared by every chunk, lifted in the vertex shader from the runtime height
// map, so building the ground costs a texture upload rather than a million vertices in GDScript.
// Every vertex lands exactly on a height texel at every LOD, so it is read with texelFetch and
// needs no filtering; the skirt ring (UV.x = 1) drops below the edge to hide the cracks between
// neighbouring chunks at different LODs.
//
// The surface follows what the full terrain is painted from, simplified: each region has a flat
// material, a steep one, a patch that comes through in noise inside a height band and one for the
// water's edge (tools/world/worldgen/surface.py), tinted by the region's palette the way the
// builder's colour map is (surface.colour_map), with snow above the line and the lake bed under
// the water. Materials blend by the height in their albedo alpha, as Terrain3D's own shader does,
// and the normal and roughness maps are packed the same way, so the same textures read the same.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	#define fma(a, b, c) ((a) * (b) + (c))
#endif

// --- the shape of the ground ---
uniform highp sampler2D heights : filter_nearest, repeat_disable;
uniform highp sampler2D normals : filter_linear, repeat_disable;
uniform highp sampler2D regions : filter_nearest, repeat_disable;
uniform highp sampler2D water : filter_linear_mipmap, repeat_disable;
// how much of each road texel is carriageway (0..1), at road_texel metres to a texel
uniform highp sampler2D roads : filter_linear_mipmap, repeat_disable;
uniform vec2 height_origin = vec2(-4093.0);
uniform vec2 mask_origin = vec2(-4096.0);
uniform float spacing = 8.0;
uniform int grid = 1024;
uniform float road_extent = 8192.0;
uniform float skirt_depth = 48.0;

// --- the surface ---
uniform highp sampler2DArray albedo_array : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform highp sampler2DArray normal_array : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float layer_scale[24];
uniform float layer_value[24];
uniform float layer_rough[24];
// per region, four layers: flat, steep, patch, shore
uniform int region_layers[32];
// per region: patch band low and high (m), patch share (0..1), unused
uniform vec4 region_band[8];
uniform vec3 region_c0[8];
uniform vec3 region_c1[8];
uniform vec3 region_c2[8];
uniform float region_accent[8];
uniform int region_count = 6;
uniform int water_region = 6;
uniform int snow_layer = 0;
uniform int bed_layer = 0;
uniform int road_layer = 0;
uniform float snow_line = 520.0;
uniform float blend_sharpness = 0.34;
uniform vec3 macro_variation1 : source_color = vec3(0.95, 0.97, 0.91);
uniform vec3 macro_variation2 : source_color = vec3(0.92, 0.90, 0.87);

varying vec3 v_world;
varying vec3 v_normal;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// two octaves, 0..1, with a feature size of about `wl` metres
float fbm(vec2 xz, float wl, float salt) {
	vec2 p = xz / wl + vec2(salt * 17.13, salt * 5.71);
	return vnoise(p) * 0.65 + vnoise(p * 2.03 + vec2(3.1, 9.7)) * 0.35;
}

vec3 map_normal(vec2 xz) {
	// bump_map_to_normal_map's forward difference at texel k describes k + 0.5, so the texel
	// that describes a point p (in texels) is p - 0.5, which is exactly uv = p / grid
	vec2 uv = (xz - height_origin) / spacing / float(grid);
	vec3 nt = textureLod(normals, uv, 0.0).rgb * 2.0 - 1.0;
	return normalize(vec3(nt.x, nt.z, -nt.y));
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	ivec2 t = clamp(ivec2(round((w.xz - height_origin) / spacing)), ivec2(0), ivec2(grid - 1));
	float h = texelFetch(heights, t, 0).r;
	if (UV.x > 0.5) {
		h -= skirt_depth;
	}
	VERTEX.y = h - MODEL_MATRIX[3].y;
	v_world = vec3(w.x, h, w.z);
	v_normal = map_normal(w.xz);
	NORMAL = v_normal;
	TANGENT = normalize(cross(v_normal, vec3(0.0, 0.0, 1.0)));
	BINORMAL = normalize(cross(v_normal, TANGENT));
}

int region_at(vec2 q) {
	ivec2 t = clamp(ivec2(round(q)), ivec2(0), ivec2(grid - 1));
	int r = int(texelFetch(regions, t, 0).r * 255.0 + 0.5);
	return r >= region_count ? water_region : r;
}

// one layer of the texture arrays at this point: albedo (a = height) and normal-roughness
void layer(int id, vec2 xz, out vec4 alb, out vec4 nrm) {
	vec3 uvw = vec3(xz * layer_scale[id], float(id));
	alb = texture(albedo_array, uvw);
	alb.rgb *= layer_value[id];
	nrm = texture(normal_array, uvw);
	nrm.a = clamp(nrm.a + layer_rough[id], 0.0, 1.0);
	nrm.xyz = fma(nrm.xzy, vec3(2.0), vec3(-1.0));
}

// Terrain3D's height blend: a material with more height in its alpha shows through first
void blend_in(inout vec4 alb, inout vec4 nrm, int id, float t, vec2 xz, float sharp) {
	if (t <= 0.002) {
		return;
	}
	vec4 a2;
	vec4 n2;
	layer(id, xz, a2, n2);
	float wa = exp2(sharp * log2(max(1.0 - t + alb.a * 0.5, 1e-4)));
	float wb = exp2(sharp * log2(max(t + a2.a * 0.5, 1e-4)));
	float k = wb / (wa + wb);
	alb = mix(alb, a2, k);
	nrm = mix(nrm, n2, k);
}

// the builder's colour map for one region (surface.colour_map): the palette's ground colour led by
// its second voice and touched by its accent, normalised to a tint that shifts hue, not value
vec3 region_tint(int r, vec2 xz) {
	float a = fbm(xz, 520.0, 600.0 + float(r));
	float b = fbm(xz, 190.0, 620.0 + float(r));
	vec3 c = mix(region_c0[r], region_c1[r], a * 0.55);
	c = mix(c, region_c2[r], region_accent[r] * b * 0.5);
	float m = max((c.r + c.g + c.b) / 3.0, 0.04);
	vec3 chroma = clamp(1.0 + (c / m - 1.0) * 2.0, vec3(0.40), vec3(1.95));
	return mix(vec3(1.0), chroma, 0.84);
}

void ground(int r, vec2 xz, float h, float slope, float shore, out vec4 alb, out vec4 nrm) {
	int base = r * 4;
	float sharp = fma(56.0, blend_sharpness, 8.0);
	layer(region_layers[base], xz, alb, nrm);
	vec4 band = region_band[r];
	float pn = fbm(xz, 60.0, 407.0 + float(r));
	float patch_t = smoothstep(1.0 - band.z, 1.0 - band.z + 0.14, pn)
			* smoothstep(band.x - 12.0, band.x + 12.0, h) * (1.0 - smoothstep(band.y - 12.0, band.y + 12.0, h));
	float steep_t = smoothstep(0.32, 0.78, slope + (fbm(xz, 24.0, 3.0) - 0.5) * 0.3);
	blend_in(alb, nrm, region_layers[base + 2], patch_t * (1.0 - steep_t), xz, sharp);
	blend_in(alb, nrm, region_layers[base + 3], shore * (1.0 - steep_t), xz, sharp);
	blend_in(alb, nrm, region_layers[base + 1], steep_t, xz, sharp);
}

vec3 to_linear(vec3 c) {
	return pow(clamp(c, vec3(0.0), vec3(1.0)), vec3(2.2));
}

void fragment() {
	vec2 xz = v_world.xz;
	float h = v_world.y;
	vec3 n = map_normal(xz);
	float slope = sqrt(max(1.0 - n.y * n.y, 0.0)) / max(n.y, 0.05);

	// which region, with a border that wanders over tens of metres rather than following the
	// 8 m texels of the map: four taps round a warped point, and the minority's share blends in
	vec2 q = (xz - mask_origin) / spacing;
	vec2 warp = (vec2(fbm(xz, 37.0, 11.0), fbm(xz, 37.0, 12.0)) - 0.5) * 2.4
			+ (vec2(vnoise(xz / 9.0), vnoise(xz / 9.0 + vec2(7.3, 2.9))) - 0.5) * 0.9;
	vec2 p = q + warp;
	int r0 = region_at(p);
	int r1 = region_at(p + vec2(1.1, 0.4));
	int r2 = region_at(p + vec2(-0.5, 1.0));
	int r3 = region_at(p + vec2(-0.6, -1.1));
	int rs = r1 != r0 ? r1 : (r2 != r0 ? r2 : r3);
	float ws = rs == r0 ? 0.0 : (float(r1 == rs) + float(r2 == rs) + float(r3 == rs)) * 0.25;

	// water: under it is the bed, near it is the region's shore
	vec2 muv = (xz - mask_origin) / spacing / float(grid) + vec2(0.5 / float(grid));
	float under = smoothstep(0.35, 0.65, textureLod(water, muv, 0.0).r);
	float near_water = textureLod(water, muv, 2.6).r;
	float shore = smoothstep(0.02, 0.22, near_water) * (1.0 - under);

	vec4 alb;
	vec4 nrm;
	ground(r0, xz, h, slope, shore, alb, nrm);
	vec3 tint = region_tint(r0, xz);
	if (ws > 0.0) {
		vec4 alb2;
		vec4 nrm2;
		ground(rs, xz, h, slope, shore, alb2, nrm2);
		alb = mix(alb, alb2, ws);
		nrm = mix(nrm, nrm2, ws);
		tint = mix(tint, region_tint(rs, xz), ws);
	}
	float sharp = fma(56.0, blend_sharpness, 8.0);

	// the roads: the carriageway's edge wanders, as a road worn by carts does, and the trodden
	// verge either side of it is lighter than the field
	vec2 ruv = (xz - mask_origin) / road_extent;
	float cover = texture(roads, ruv).r;
	float verge = smoothstep(0.02, 0.2, textureLod(roads, ruv, 2.0).r) * (1.0 - smoothstep(0.3, 0.6, cover));
	float carriage = smoothstep(0.30, 0.62, cover + (fbm(xz, 14.0, 417.0) - 0.5) * 0.35);
	blend_in(alb, nrm, road_layer, carriage, xz, sharp);

	// snow lies where snow can lie: not on anything steep, lower on the side away from the sun
	float shaded = clamp(-n.z / max(length(n.xz), 1e-3), 0.0, 1.0) * clamp(length(n.xz) * 4.0, 0.0, 1.0);
	float line = snow_line - 90.0 * shaded;
	float holds = 1.0 - smoothstep(0.55, 1.05, slope);
	float snow_t = clamp(smoothstep(0.0, 130.0, h - line) * holds * 1.6, 0.0, 1.0);
	blend_in(alb, nrm, snow_layer, snow_t, xz, sharp);
	blend_in(alb, nrm, bed_layer, under, xz, sharp);

	// the colour map: tint, shading by height and slope, the fine grain that stops turf reading
	// as a billiard table, snow's cold, the crown of the road, clipped as an RGBA8 map is
	float shade = 1.0 + 0.10 * tanh((h - 60.0) / 260.0) - 0.10 * smoothstep(0.35, 1.1, slope);
	vec3 cmap = tint * shade;
	float fine = fbm(xz, 5.5, 422.0);
	float coarse = fbm(xz, 24.0, 423.0);
	cmap *= (0.93 + 0.14 * fine) * (0.95 + 0.10 * coarse);
	float warm = (fine - 0.5) * 0.09;
	cmap.r *= 1.0 + warm;
	cmap.b *= 1.0 - warm;
	cmap = mix(cmap, vec3(0.90, 0.95, 1.06), smoothstep(snow_line - 60.0, snow_line + 80.0, h) * 0.72);
	float crown = carriage * smoothstep(0.7, 1.0, cover);
	cmap = mix(cmap, vec3(1.0), clamp(0.70 * crown + 0.30 * carriage + 0.2 * verge, 0.0, 0.8));
	cmap *= 1.0 + 0.16 * crown + 0.06 * verge;
	cmap = mix(cmap, vec3(1.0), under);

	// Terrain3D's macro variation, on noise instead of its noise texture
	vec3 macrov = mix(macro_variation1, vec3(1.0), fbm(xz, 500.0, 31.0));
	macrov *= mix(macro_variation2, vec3(1.0), fbm(xz, 260.0, 32.0));
	macrov = mix(vec3(1.0), macrov, clamp(n.y + 0.4, 0.0, 1.0));

	float wet = clamp(0.9 * near_water + 0.6 * under, 0.0, 1.0);
	float roughness = clamp(fma((0.5 - 0.38 * wet) - 0.5, 2.0, nrm.a), 0.0, 1.0);

	ALBEDO = alb.rgb * to_linear(cmap) * macrov;
	ROUGHNESS = roughness;
	SPECULAR = 1.0 - nrm.a;
	// the ground's own normal, per fragment from the full map, whatever the LOD of the mesh
	vec3 wt = normalize(cross(n, vec3(0.0, 0.0, 1.0)));
	vec3 wb = normalize(cross(n, wt));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	TANGENT = normalize((VIEW_MATRIX * vec4(wt, 0.0)).xyz);
	BINORMAL = normalize((VIEW_MATRIX * vec4(wb, 0.0)).xyz);
	NORMAL_MAP = fma(normalize(nrm.xzy), vec3(0.5), vec3(0.5));
	NORMAL_MAP_DEPTH = 0.55;
	AO = clamp(0.55 + 0.45 * alb.a + 0.3 * n.y, 0.0, 1.0);
	AO_LIGHT_AFFECT = 0.3;
}
