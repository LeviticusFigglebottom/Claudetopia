shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;
// Stylised water for the Mere, the Grey Sea and the rivers.
//
// Everything it needs comes from the world builder's runtime maps, so one mesh can carry the
// lake, the sea and the marsh pools at their own levels:
//   level_tex   R32F  water surface height (filled: every texel has the nearest water level)
//   mask_tex    R8    1 where there is water surface
//   height_tex  R32F  terrain height, for depth colour and shore foam
//
// What makes it read as water is done here rather than left to the engine's reflection, so it
// works on the Compatibility renderer as it would on Forward+ (ARCHITECTURE.md §10): the world
// mirrored by a Fresnel term, so the water is dark where you look down into it and gives back
// the far shore, the hills and the sky toward the grazing angle; a path of glints under the sun,
// and under the moon at night; moving ripples; and foam that follows the waterline and breaks up.
// tools_gd/render_probe.gd measured the screen texture on Compatibility: read back and drawn
// again it comes out within a tenth of the scene with the post-process path on (glow and the
// grade, as the game has them), so it is the scene's own light and goes into EMISSION as it is;
// and SCREEN_UV's y runs up the frame in this renderer, which the mirror's sign takes care of.
//
// The mirror is the frame's own pixels, looked up where the reflected ray points: the direction
// is projected to infinity, which puts it above the horizon wherever the camera is above the
// water, so the lookup can land on a hill, a far shore or the sky but never on the lake itself.
// That is exact for anything far away and wrong in parallax for something near, which on a lake
// is the right way round. Where the ray leaves the frame the sky's own zenith and horizon (the
// atmosphere publishes them every frame) stand in. `mirror` = 0 fades the lookup out; the
// setting that turns reflections off builds this shader with WATER_NO_MIRROR defined instead
// (world/water_surface.gd), because a material that so much as names the screen texture makes
// the renderer copy the frame for it, whatever the uniform says.
//
// The normal is written to NORMAL in view space. The first version wrote a world-space normal
// with its up component in the normal map's green channel; Godot rebuilds a normal map's z from
// its x and y, so every water surface in the game was lit as if tilted some seventy-five degrees,
// and took its reflection from the wrong part of the sky.

uniform sampler2D level_tex : filter_linear, repeat_disable, hint_default_black;
uniform sampler2D mask_tex : filter_linear, repeat_disable, hint_default_black;
uniform sampler2D height_tex : filter_linear, repeat_disable, hint_default_black;
// what the shore is made of, by class (WaterSurface._shore_texture): 0 none, 1 sand, 2 shingle,
// 3 rock, 4 cliff, 5 mud, 6 reeds; `has_shore` false where the world build did not write them
uniform sampler2D shore_tex : filter_nearest, repeat_disable, hint_default_black;
uniform bool has_shore = false;
// where a river ribbon or a fall's pool draws the water instead of the sheet (WaterSurface)
uniform sampler2D claim_tex : filter_linear, repeat_disable, hint_default_black;
uniform vec2 world_origin = vec2(-4096.0, -4096.0);
uniform float world_size = 8192.0;

uniform bool follow_level = true;      // sheet: take y from the level map; rivers: keep mesh y
uniform bool use_mask = true;          // sheet: discard away from water; rivers: never
uniform vec4 deep_colour : source_color = vec4(0.06, 0.20, 0.32, 1.0);
uniform vec4 shallow_colour : source_color = vec4(0.30, 0.56, 0.60, 1.0);
uniform vec4 region_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 foam_colour : source_color = vec4(0.92, 0.95, 0.96, 1.0);
uniform float depth_fade_m = 5.0;      // metres of water before the colour reads as deep
uniform float foam_width_m = 1.6;
// how much foam the region's water raises at its edges: surf on the sea, a trace on a still marsh
uniform float foam_strength : hint_range(0.0, 1.0) = 0.7;
uniform float wave_scale = 0.07;
uniform float wave_speed = 0.5;
uniform float wave_strength = 0.42;
uniform float ripple_scale = 0.8;
uniform float opacity_shallow = 0.66;
uniform float opacity_deep = 0.97;
uniform float roughness_water = 0.10;
uniform float specular_boost = 0.32;
uniform float distance_calm_m = 260.0;   // ripples flatten with distance instead of aliasing
uniform float rim_strength = 0.5;      // kept for callers; the reflection below replaces the rim
// The graphics setting's water quality (world/water_surface.gd): how much of the finest ripple
// layer and of the foam's wobble is drawn. 1.0, the default, is the water as it was built.
uniform float detail : hint_range(0.0, 1.0) = 1.0;
uniform float reflect_strength : hint_range(0.0, 1.0) = 0.9;
uniform float glint_strength = 3.0;
uniform float glint_sharpness = 700.0;
uniform float mirror : hint_range(0.0, 1.0) = 1.0;
// how far over the water the mirror looks for the far shore, in steps that grow by 1.4 each
// (the water quality setting's reflection quality): 16 reach about 4 km, 8 about 250 m
uniform int mirror_steps = 16;
// how much of the waves bends what the mirror shows: all of it scrambles a hill into streaks of
// sky and shore; a third leaves the hill, wavering
uniform float mirror_ripple : hint_range(0.0, 1.0) = 0.3;
// the most of the light the water gives back at the grazing angle, before `reflect_strength`
uniform float fresnel_cap : hint_range(0.0, 1.0) = 0.65;
#ifndef WATER_NO_MIRROR
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
#endif
// What the frame has drawn behind the water, for its true depth at the waterline. The height map
// is eight metres a texel, and the ground the player stands on is Terrain3D's two: a sheet cut
// where the map says the water ends stood as a slab over a beach lower than it, with a hard edge,
// and thinned out where the map said shallow rather than where the water met the ground.
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
// how many metres of water the sheet takes to thin to nothing at the waterline
uniform float shore_soft_m = 0.5;
// out to here the frame's depth says how deep the water is; past it the height map does, where a
// depth buffer's precision has run out
uniform float true_depth_m = 380.0;

// published by systems/atmosphere every frame, all linear
global uniform vec3 wm_sun_dir;
global uniform vec3 wm_sun_color;
global uniform vec3 wm_moon_dir;
global uniform vec3 wm_moon_color;
global uniform vec3 wm_sky_zenith;
global uniform vec3 wm_sky_horizon;
global uniform float wm_wind_strength;
global uniform vec3 wm_wind_dir;

varying vec3 v_world;
varying vec2 v_uv;

vec2 world_uv(vec2 xz) {
	return (xz - world_origin) / world_size;
}

// The ground's height under the water, filtered here from four texels. It is a float texture,
// and a renderer may sample one of those nearest whatever the hint asks: the shallows' foam was
// cut to the height map's eight-metre squares, a staircase of white across the Mere beside the
// Long Stride.
// The same filtering for any map: the water mask came out in eight-metre steps as well, and the
// sheet's edge where it fades past the mask was a staircase.
float filtered(sampler2D tex, vec2 uv) {
	vec2 n = vec2(textureSize(tex, 0));
	vec2 f = uv * n - 0.5;
	ivec2 i = ivec2(floor(f));
	vec2 t = f - floor(f);
	ivec2 hi = ivec2(n) - 1;
	float a = texelFetch(tex, clamp(i, ivec2(0), hi), 0).r;
	float b = texelFetch(tex, clamp(i + ivec2(1, 0), ivec2(0), hi), 0).r;
	float c = texelFetch(tex, clamp(i + ivec2(0, 1), ivec2(0), hi), 0).r;
	float d = texelFetch(tex, clamp(i + ivec2(1, 1), ivec2(0), hi), 0).r;
	return mix(mix(a, b, t.x), mix(c, d, t.x), t.y);
}

float ground_at(vec2 uv) {
	vec2 n = vec2(textureSize(height_tex, 0));
	vec2 f = uv * n - 0.5;
	ivec2 i = ivec2(floor(f));
	vec2 t = f - floor(f);
	ivec2 hi = ivec2(n) - 1;
	float h00 = texelFetch(height_tex, clamp(i, ivec2(0), hi), 0).r;
	float h10 = texelFetch(height_tex, clamp(i + ivec2(1, 0), ivec2(0), hi), 0).r;
	float h01 = texelFetch(height_tex, clamp(i + ivec2(0, 1), ivec2(0), hi), 0).r;
	float h11 = texelFetch(height_tex, clamp(i + ivec2(1, 1), ivec2(0), hi), 0).r;
	return mix(mix(h00, h10, t.x), mix(h01, h11, t.x), t.y);
}

float hash12(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
	           mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Two crossing wave trains plus a finer ripple: cheap, stylised, and stable on GLES3. Returns
// the slope (d/dx, d/dz) of the surface, which is what the normal is made from.
vec2 wave_slope(vec2 p, float t) {
	vec2 a = p * wave_scale;
	vec2 b = p * wave_scale * 1.87 + vec2(13.1, 7.7);
	vec2 c = p * wave_scale * ripple_scale * 6.3 + vec2(3.3, 9.2);
	float sx = cos(a.x * 1.3 + t) * 0.55
		+ cos(b.x * 0.9 - b.y * 0.7 + t * 1.27) * 0.35
		+ cos(c.x + c.y * 0.6 + t * 2.1) * 0.10 * detail;
	float sz = -sin(a.y * 1.1 - t * 0.85) * 0.55
		+ -sin(b.x * 0.6 + b.y * 1.1 + t * 1.05) * 0.35
		+ -sin(c.y - c.x * 0.4 + t * 1.9) * 0.10 * detail;
	return vec2(sx, sz);
}

// A river's ribbon (built with WATER_RIVER defined, world/water_surface.gd) carries its own
// flow: UV is metres across the channel (0 on the centre line) and metres along it; UV2 the
// current's speed in m/s and how hard the river bends there (signed, -1..1, + turning toward +x
// across); COLOR the downstream direction in x and z (as 0..1), the half-width of its water / 20,
// and how much of the ribbon is drawn (it fades out where the river runs into a lake or the sea).
varying vec4 v_river;
varying vec4 v_flow;

// the height of a river's surface texture at `p` (across, along), for the flow-mapped normal:
// ripples stretched across the current, the way a riffle stands
float river_height(vec2 p) {
	return vnoise(p * vec2(0.55, 0.9)) * 0.55
		+ vnoise(p * vec2(1.3, 2.1) + vec2(7.1, 3.3)) * 0.3
		+ vnoise(p * vec2(3.2, 4.4) + vec2(2.7, 9.4)) * 0.15 * detail;
}

vec2 river_slope(vec2 p) {
	float e = 0.12;
	float h = river_height(p);
	return vec2(river_height(p + vec2(e, 0.0)) - h, river_height(p + vec2(0.0, e)) - h) / e;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_uv = UV;
#ifdef WATER_RIVER
	// a river sits in the channel the builder carved, at its own surface: no swell lifts it
	v_river = vec4(UV, UV2);
	v_flow = COLOR;
#else
	if (follow_level) {
		float lvl = texture(level_tex, world_uv(v_world.xz)).r;
		v_world.y = lvl;
		VERTEX.y = lvl - NODE_POSITION_WORLD.y;
	}
	// a slow swell so the sheet is never perfectly flat
	VERTEX.y += sin(v_world.x * 0.02 + TIME * 0.35) * 0.06 + cos(v_world.z * 0.017 - TIME * 0.28) * 0.06;
#endif
}

void fragment() {
	vec2 uv = world_uv(v_world.xz);
	// The sheet runs on a texel past where the map says the water ends: the map's edge is eight
	// metres coarse, and where the true ground there is lower than the water the water is over it.
	// Where the ground rises out of the water it hides the sheet, and the waterline is where they
	// meet; the thinning below makes that line soft.
	// Past the world's edge the sea skirt is open sea to the horizon. The maps are clamped out
	// there, so they repeated the edge's last row outward: north of the Skerrow wall the land's
	// row discarded the skirt in a band to the horizon, and the sky's grey underside showed in
	// it beside the sea, a hard straight seam (the w4096c Skerrow shots).
	bool outside = any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)));
	float mask_v = outside ? 1.0 : filtered(mask_tex, uv);
	if (use_mask && mask_v < 0.02) {
		discard;
	}
	// where a river's ribbon or a fall's pool draws the water, the sheet leaves it to them: its
	// level is read at vertices ninety metres apart, and on a river in the hills it stood metres
	// off the channel
	if (use_mask && !outside && texture(claim_tex, uv).r > 0.5) {
		discard;
	}
	// and where the sheet would stand clear above its own water: where two waters at different
	// levels meet within a cell, the cell between them is drawn at a level between the two
	if (use_mask && !outside && v_world.y - texture(level_tex, uv).r > 0.6) {
		discard;
	}
	// and wherever its water is not level: a lake, a marsh pool and the sea are flat, and water
	// that falls from one texel to the next is a river, which its ribbon draws. The level map is
	// filled, so down a river out of a lake it slopes, and the sheet laid on it stood as a tilted
	// pane over the beach beside the ribbon (the Lark Pool's outflow, playtest 6).
	if (use_mask && !outside) {
		ivec2 ln = textureSize(level_tex, 0);
		ivec2 li = clamp(ivec2(uv * vec2(ln)), ivec2(1), ln - 2);
		// a slope, not a step: where the marsh's water table meets the sea the map steps from one
		// flat to the other, and a step here cut a strip out of the sea down to the mud
		float l0 = texelFetch(level_tex, li, 0).r;
		float gx = min(abs(texelFetch(level_tex, li + ivec2(1, 0), 0).r - l0), abs(l0 - texelFetch(level_tex, li - ivec2(1, 0), 0).r));
		float gz = min(abs(texelFetch(level_tex, li + ivec2(0, 1), 0).r - l0), abs(l0 - texelFetch(level_tex, li - ivec2(0, 1), 0).r));
		if (max(gx, gz) > 0.06) {
			discard;
		}
	}
	float t = TIME * wave_speed * (0.7 + wm_wind_strength * 0.8);
	// how hard the wind is on the water here: the cat's paws (open water only); and the slicks,
	// lanes down the wind where it lies smooth
	float gust = 0.0;
	float slick = 0.0;
	float dist = length(CAMERA_POSITION_WORLD - v_world);
	float far = clamp(dist / distance_calm_m, 0.0, 1.0);
#ifdef WATER_RIVER
	float across = v_river.x;
	float along = v_river.y;
	float speed = max(v_river.z, 0.05);
	float bend = v_river.w;
	vec3 fdir = normalize(vec3(v_flow.x * 2.0 - 1.0, 0.0, v_flow.y * 2.0 - 1.0));
	vec3 sdir = vec3(-fdir.z, 0.0, fdir.x);
	float half_w = max(v_flow.z * 20.0, 0.5);
	float xt = clamp(abs(across) / half_w, 0.0, 1.5);
	// The flow map: the texture is carried downstream at the current's speed, drawn twice half a
	// cycle apart and crossfaded so that neither is ever dragged far enough to smear, however the
	// speed changes along the river.
	float cyc = 2.0;
	float ph0 = fract(TIME / cyc);
	float ph1 = fract(TIME / cyc + 0.5);
	float w0 = 1.0 - abs(2.0 * ph0 - 1.0);
	// the eddy: on the inside of a bend the water turns back on itself, slowly
	float inner = clamp(-sign(bend) * across / half_w, 0.0, 1.0) * abs(bend);
	float swirl = inner * 1.4 * sin(TIME * 0.35 + along * 0.2);
	mat2 turn = mat2(vec2(cos(swirl), sin(swirl)), vec2(-sin(swirl), cos(swirl)));
	vec2 rp = turn * vec2(across, along * 0.8);
	float drift = speed * (1.0 - inner * 0.8);
	vec2 q0 = rp - vec2(0.0, drift * ph0 * cyc);
	vec2 q1 = rp - vec2(0.0, drift * ph1 * cyc) + vec2(3.7, 11.3);
	vec2 rs = river_slope(q0) * w0 + river_slope(q1) * (1.0 - w0);
	// faster water is rougher; a sluggish reach lies nearly still and holds a reflection
	rs *= wave_strength * (0.25 + 0.55 * clamp(speed, 0.0, 2.5)) * (1.0 + inner);
	vec3 g = sdir * rs.x + fdir * rs.y;
	vec2 slope = vec2(g.x, g.z);
#else
	vec2 slope = wave_slope(v_world.xz, t) * wave_strength;
	// Wind on open water: gusts cross it in patches (cat's paws), roughening the fine ripples and
	// breaking up what the water mirrors, so a lake is never one flat sheet of reflected sky; and
	// a finer ripple runs downwind within them.
	vec2 wind = normalize(wm_wind_dir.xz + vec2(0.0001));
	vec2 gp = v_world.xz * 0.011 - wind * TIME * 0.035;
	gust = smoothstep(0.38, 0.78, vnoise(gp) * 0.7 + vnoise(gp * 2.7 + vec2(5.0, 1.0)) * 0.3);
	gust *= 0.55 + 0.9 * clamp(wm_wind_strength, 0.0, 1.0);
	vec2 wp = vec2(dot(v_world.xz, wind), dot(v_world.xz, vec2(-wind.y, wind.x)));
	float ph = wp.x * 1.9 - TIME * 2.4 + vnoise(wp * vec2(0.3, 0.9)) * 4.0;
	float fine = cos(ph) * (0.6 + 0.4 * vnoise(wp * vec2(0.8, 2.5) - TIME * 0.4));
	slope += wind * fine * gust * 0.22 * detail;
	slope *= 0.6 + 0.9 * gust;
	// Slicks: long smooth lanes laid down the wind between the gusts, lighter and sharper in what
	// they give back. From a hill they are what makes a lake read as water moved by the air
	// rather than a painted floor; they are drawn out far, where the ripples are calmed away.
	vec2 lane = vec2(wp.y * 0.011, wp.x * 0.0016 - TIME * 0.006);
	slick = smoothstep(0.56, 0.82, vnoise(lane) * 0.72 + vnoise(lane * 2.3 + vec2(4.0, 9.0)) * 0.28);
	slick *= 1.0 - gust;
	slope *= 1.0 - 0.7 * slick;
#endif
	// far water should read as one calm sheet, not as a field of shimmering pixels
	slope *= mix(1.0, 0.18, far);
	vec3 n_world = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

#ifdef WATER_RIVER
	// A river's depth is the channel the builder carved (worldgen/hydro.py carve_rivers): a
	// parabola under the surface, 1.1 m and a tenth of the width deep on the centre line, nothing
	// at the waterline. The height map is eight metres a texel and cannot see a five-metre channel.
	float depth = (1.1 + 0.2 * half_w) * max(1.0 - xt * xt, 0.0);
#else
	// How deep the water is here, per fragment. It was read at the vertices and interpolated, and
	// the sheet's vertices are ninety metres apart: a quad with one corner on an island or a shore
	// was "shallow" for most of its width, so open water ten metres deep was see-through near the
	// camera and a band of shore foam ran across the middle of the Mere, a white ring that looked
	// like a lens effect from every low camera.
	// past the world's edge the sea bed goes on down from the edge's own depth, a metre in 25, so
	// the open sea darkens away from the land with no line where the world ends
	vec2 cuv = clamp(uv, vec2(0.0), vec2(1.0));
	float beyond = length((uv - cuv) * world_size);
	float depth = max(v_world.y - ground_at(cuv), 0.0) + beyond * 0.04;
#endif
	// The water's true depth over what lies behind it in the frame, straight down from the surface
	// to the point of the ground (or the bed) the eye sees through it. Near, it is what the colour,
	// the foam and the thinning at the waterline go by; far off, the height map's.
	float frag_y = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
	float zb = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, zb * 2.0 - 1.0);
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, zb);
#endif
	vec4 behind_v = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	behind_v.xyz /= behind_v.w;
	float behind_y = (INV_VIEW_MATRIX * vec4(behind_v.xyz, 1.0)).y;
	float true_depth = max(frag_y - behind_y, 0.0);
	// nothing behind but the sky (a lake seen over its far edge): as deep as it can be
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	bool sky_behind = zb >= 0.99999;
#else
	bool sky_behind = zb <= 0.00001;
#endif
	true_depth = sky_behind ? 1000.0 : true_depth;
	float near_t = 1.0 - smoothstep(true_depth_m * 0.6, true_depth_m, dist);
	// only in the shallows: over open water the height map knows the depth well enough, and a
	// depth buffer seen at a grazing angle over a far sea does not (it turned the Grey Sea off
	// the Cinderlea strand into a dark band from sixty metres out)
	near_t *= 1.0 - smoothstep(2.0, 4.0, depth);
	// seen from under the surface the frame behind it is above it: nothing to thin by
	near_t *= FRONT_FACING ? 1.0 : 0.0;
#ifndef WATER_RIVER
	depth = mix(depth, true_depth, near_t);
#endif
	float depth_t = clamp(depth / depth_fade_m, 0.0, 1.0);
	vec3 body = mix(shallow_colour.rgb, deep_colour.rgb, depth_t) * region_tint.rgb;
	// a gust darkens the water it roughens: it gives back less of the sky there (below), and the
	// patches drifting across a lake are what show it is water and not a painted floor
	body *= 1.0 - 0.18 * gust;

	// shore foam: a band that follows the waterline, wobbles with the waves and breaks into
	// patches rather than lying along the shore like a painted line
	float wobble = (sin(v_world.x * 0.7 + t * 1.6) * 0.25 + cos(v_world.z * 0.63 - t * 1.3) * 0.25)
			* detail;
#ifndef WATER_RIVER
	// The sea laps: its foam line runs up the shore and draws back, and lines of surf come in
	// from deeper water and die on the beach. A lake's edge only breathes.
	// (the marsh's creeks stand at its water table, 1.25 m: still water, not the sea)
	float sea = 1.0 - smoothstep(0.5, 1.0, v_world.y);
	// how the water breaks on this shore: broken surf on rock, a swash line on sand and shingle, a
	// wash at a cliff's foot, and almost none on mud or in the reeds
	float breaks = 1.0;
	float runs_up = 1.0;
	if (has_shore) {
		int cls = int(texture(shore_tex, uv).r * 255.0 + 0.5);
		breaks = cls == 3 ? 1.5 : cls == 4 ? 1.2 : cls == 5 ? 0.12 : cls == 6 ? 0.05 : cls == 2 ? 0.85 : 1.0;
		runs_up = (cls == 1 || cls == 2) ? 1.3 : cls == 3 ? 0.6 : cls == 5 || cls == 6 ? 0.0 : 0.8;
	}
	float surge = sin(TIME * 0.8 + vnoise(v_world.xz * 0.02) * 6.0) * 0.5 + 0.5;
	wobble += sea * (surge - 0.3) * 1.6 * runs_up;
#endif
	// (GLSL leaves smoothstep undefined with its edges reversed; Mesa forgives it, a GPU need not)
	float foam = 1.0 - smoothstep(0.0, foam_width_m * (1.0 + wobble * 0.35), depth);
	// Broken into patches by two octaves of noise on a grid turned off the world's axes. One octave
	// on the world's own grid, cut hard, drew squares; while the lakes were not drawn nobody saw
	// it, and then the Sedgemire, which is shallower than the foam band everywhere, was one field
	// of white pixels.
	vec2 fp = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * v_world.xz;
	float fnoise = 0.65 * vnoise(fp * 0.9 + vec2(t * 0.4, -t * 0.3)) + 0.35 * vnoise(fp * 2.3 - vec2(t * 0.2, t * 0.5));
	foam *= 0.3 + 0.7 * smoothstep(0.42, 0.72, fnoise);
#ifndef WATER_RIVER
	// the surf lines: a band at a depth that shoals toward the beach over each wave's life
	float wave_life = fract(TIME * 0.11 + vnoise(v_world.xz * 0.015) * 0.6);
	float line_d = foam_width_m * 3.2 * (1.0 - wave_life);
	float surf = exp(-pow((depth - line_d) / (0.18 + 0.25 * foam_width_m), 2.0)) * (1.0 - wave_life) * wave_life * 4.0;
	surf *= smoothstep(0.35, 0.65, fnoise + 0.15) * sea * runs_up;
	foam = max(foam, surf * 0.8);
#endif
	foam *= foam_strength;
	// no shore past the world's edge: its last row of land is not a beach out there
	foam *= outside ? 0.0 : 1.0;
#ifndef WATER_RIVER
	foam = clamp(foam * breaks, 0.0, 1.0);
#endif
#ifdef WATER_RIVER
	// Foam where the water runs fast: streaks drawn out along the current and carried down it,
	// thickest along the banks and on the outside of a bend, and a fleck or two on a slow reach.
	vec2 f0 = vec2(across * 1.5, (along - drift * ph0 * cyc) * 0.22);
	vec2 f1 = vec2(across * 1.5 + 4.1, (along - drift * ph1 * cyc) * 0.22 + 9.0);
	float streak = vnoise(f0) * w0 + vnoise(f1) * (1.0 - w0);
	float fleck = vnoise(f0 * vec2(2.6, 5.0)) * w0 + vnoise(f1 * vec2(2.6, 5.0)) * (1.0 - w0);
	float fast = smoothstep(0.7, 2.2, speed);
	float outer = clamp(sign(bend) * across / half_w, 0.0, 1.0) * abs(bend);
	float bank = smoothstep(0.55, 0.95, xt);
	float lines = smoothstep(0.6 - 0.2 * fast, 0.85, streak * 0.7 + fleck * 0.3) * (0.15 + 0.85 * fast);
	float river_foam = lines * (0.35 + 0.65 * max(bank, outer)) + smoothstep(0.78, 0.92, fleck) * 0.15;
	// white water where it is fastest, whatever the bank
	river_foam += fast * fast * smoothstep(0.5, 0.8, streak) * 0.5;
	// a slow reach's flecks fade with distance; a steep one's white water holds, so rapids read
	// from the hill above as well as from the bank
	foam = clamp(max(foam * 0.5, river_foam * (1.0 - far * 0.7 * (1.0 - fast))), 0.0, 1.0);
	// Strokes down the current: long bands of lighter and darker water carried with it, which
	// hold at a distance where the ripples are calmed away, so a river seen from the hill above
	// it is painted water running, not one flat strip of colour.
	float band = vnoise(f0 * vec2(0.45, 0.3)) * w0 + vnoise(f1 * vec2(0.45, 0.3)) * (1.0 - w0);
	body *= 0.86 + 0.26 * band;
#endif

	// the sky, mirrored: dark where you look down into the water, the sky's own colours toward
	// the grazing angle, capped so a lake seen from a hill is still a lake and not a sheet of sky
	vec3 V = normalize(CAMERA_POSITION_WORLD - v_world);
	vec3 R = reflect(-V, n_world);
	float cos_v = clamp(dot(n_world, V), 0.0, 1.0);
	float fresnel = 0.02 + 0.98 * pow(1.0 - cos_v, 5.0);
	fresnel = min(fresnel, fresnel_cap) * reflect_strength
			* (1.0 - 0.35 * gust * (1.0 - 0.6 * far)) * (1.0 + 0.2 * slick);
#ifdef WATER_RIVER
	// the strokes show in what the river gives back as well, or at a grazing angle it is all sky
	fresnel *= 0.88 + 0.24 * band;
#endif
	// Seen from under the surface the water is its own colour and gives back nothing: the mirror
	// works out where a ray from above would land, and from below it smeared the lake bed across
	// the ceiling (the Mere's look camera stood under its surface until the lakes were drawn).
	bool from_below = !FRONT_FACING;
	if (from_below) {
		fresnel = 0.0;
	}
	// what the mirror shows is bent by a share of the waves only (`mirror_ripple`)
	vec3 n_mirror = normalize(vec3(-slope.x * mirror_ripple, 1.0, -slope.y * mirror_ripple));
	vec3 Rm = reflect(-V, n_mirror);
	// where the reflected ray leaves the frame, the sky's own gradient stands in for it, with the
	// painted sky's own curve (its horizon_sharpness): with a gentler one the stand-in was paler
	// than the sky it met at the top of the frame, and a bright seam ran round every lake there
	vec3 sky = mix(wm_sky_horizon, wm_sky_zenith, 1.0 - pow(1.0 - clamp(Rm.y, 0.0, 1.0), 4.5));
	// the mirror: where on screen the reflected ray lands. The sign that relates clip space to
	// SCREEN_UV is taken from the derivatives (outside any branch, where they are defined), so it
	// holds whichever way up this renderer keeps its frame (on Compatibility its y runs up).
	vec3 reflected = sky;
#ifndef WATER_NO_MIRROR
	vec4 cur = PROJECTION_MATRIX * vec4(VERTEX, 1.0);
	vec2 cur_ndc = cur.xy / cur.w;
	float ys = sign(dFdy(SCREEN_UV.y)) * sign(dFdy(cur_ndc.y));
	ys = ys == 0.0 ? 1.0 : ys;
	// What a lake mirrors stands on its far shore, so the reflected ray is followed over the water
	// mask to where the water ends, and what the camera sees above that point is what the water
	// shows. Projected to infinity instead, the far shore's reflection came out a camera-height's
	// worth too high -- from a landmark sixty metres over the Mere, three degrees, which put it in
	// the sky above the hills, and the lake gave back nothing but pale sky. Where no shore is met
	// (the open sea, a river) the direction alone is used.
	vec4 target = vec4(Rm, 0.0);
	vec2 hdir = Rm.xz;
	float hl = length(hdir);
	if (use_mask && hl > 0.001) {
		hdir /= hl;
		float near_s = 0.0;
		float far_s = 24.0;
		bool found = false;
		for (int k = 0; k < mirror_steps; k++) {
			if (texture(mask_tex, world_uv(v_world.xz + hdir * far_s)).r < 0.5) {
				found = true;
				break;
			}
			near_s = far_s;
			far_s *= 1.4;
		}
		if (found) {
			for (int k = 0; k < 2; k++) {
				float mid = 0.5 * (near_s + far_s);
				if (texture(mask_tex, world_uv(v_world.xz + hdir * mid)).r < 0.5) {
					far_s = mid;
				} else {
					near_s = mid;
				}
			}
			target = vec4(v_world + Rm * (0.5 * (near_s + far_s) / hl), 1.0);
		}
	}
	vec4 ref = PROJECTION_MATRIX * (VIEW_MATRIX * target);
	if (!from_below && mirror > 0.001 && ref.w > 0.0001) {
		vec2 uv2 = SCREEN_UV + (ref.xy / ref.w - cur_ndc) * 0.5 * vec2(1.0, ys);
		float margin = min(min(uv2.x, 1.0 - uv2.x), min(uv2.y, 1.0 - uv2.y));
		float inside = smoothstep(0.0, 0.06, margin);
		reflected = mix(sky, texture(screen_tex, uv2).rgb, inside * mirror);
	}
#endif
	// a path of glints under the sun, broken into points by a fine sparkle
	float sparkle = step(0.55, hash12(floor(v_world.xz * 2.5 + vec2(TIME * 1.3, TIME * 0.9))));
	float sun_g = pow(max(dot(R, normalize(wm_sun_dir)), 0.0), glint_sharpness);
	float sun_wide = pow(max(dot(R, normalize(wm_sun_dir)), 0.0), glint_sharpness * 0.08) * 0.08;
	float moon_g = pow(max(dot(R, normalize(wm_moon_dir)), 0.0), glint_sharpness * 0.6);
	vec3 glints = wm_sun_color * (sun_g * mix(0.4, 1.6, sparkle) + sun_wide) * glint_strength
		+ wm_moon_color * moon_g * mix(0.3, 1.4, sparkle) * glint_strength * 0.6;

	ALBEDO = mix(body * (1.0 - fresnel), foam_colour.rgb, foam);
	EMISSION = (reflected * fresnel + glints * (1.0 - far * 0.6)) * (1.0 - foam);
	ROUGHNESS = clamp(roughness_water + 0.25 + foam * 0.4 + far * 0.1, 0.02, 1.0);
	// No engine specular: the mirror and the glints above are the water's whole reflection. At 0.12
	// the renderer laid the sky's own radiance over the mirror as well -- its Fresnel rises to
	// nearly the same share at a grazing angle -- so every lake came out as bright as the sky above
	// it, a pale sheet from any hill, on both renderers.
	SPECULAR = 0.0;
	METALLIC = 0.0;
	// the water thins to nothing at the waterline, so the land does not end in a hard edge
	float edge = smoothstep(0.0, 0.35, depth);
	// and at the true waterline nothing of it is left: not its colour, not the sky it gives back,
	// not its foam (which lies a hand's depth out from the line, not on it)
	float line = mix(1.0, smoothstep(0.0, shore_soft_m, true_depth), near_t);
	// and past where the map says the water ends it fades out over half a texel, so where the ground
	// there is still under the water the sheet does not end in the map's eight-metre steps
	line *= use_mask ? smoothstep(0.02, 0.45, mask_v) : 1.0;
#ifdef WATER_RIVER
	// A river's shallows are clear over its bed and its edge a soft wet line, not a cut: the
	// ribbon runs a little past the waterline under the bank, and thins to nothing there.
	float wet = 1.0 - smoothstep(0.82, 1.08, xt);
	ALPHA = clamp((mix(opacity_shallow, opacity_deep, depth_t) * mix(0.25, 1.0, edge) + fresnel * 0.35 + foam * 0.5) * wet * v_flow.w, 0.0, 1.0) * line;
#else
	ALPHA = clamp(mix(opacity_shallow, opacity_deep, depth_t) * mix(0.35, 1.0, edge) + fresnel * 0.4 + foam * 0.5, 0.0, 1.0) * line;
#endif
}
