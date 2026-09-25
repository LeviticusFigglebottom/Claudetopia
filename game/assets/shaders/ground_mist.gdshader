shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

// The mist that lies on the land (world/ground_mist.gd): a layer on the ground, not in the air
// round the camera. Godot's height fog is one height for the whole world and the camera's region
// sets it; this is marched along each pixel's line of sight over the ground it passes, so each
// region's mist lies in its own country -- the Sedgemire's teal marsh mist seen from the Hearthvale
// road, the morning mist on the Mere -- and thins with the height above the ground under it, not
// above a plane: it fills a hollow and leaves the crest, it is waist-deep on the fen and nothing on
// the hill beside it. Drawn as one screen-covering triangle pair over what the camera sees, from
// the depth buffer, on every renderer.
//
// Each region's layer (identity.light: mist_color, mist_density, mist_depth, mist_morning,
// mist_water) is a column of `mist_table`: colour and density at the ground, e-folding depth
// (metres) and how much it thickens after sunrise, and how much more lies over open water.

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D region_map : filter_nearest;
uniform sampler2D height_map : filter_nearest;
uniform sampler2D water_map : filter_nearest;
uniform sampler2D mist_table : filter_nearest;
uniform vec4 world_rect = vec4(-4096.0, -4096.0, 8.0, 1024.0);
uniform vec4 height_rect = vec4(-4096.0, -4096.0, 8.0, 1024.0);
uniform int region_count = 6;
// the region the camera is in: the open water belongs to none, and a line of sight over it keeps
// the last region it crossed, starting from this one
uniform int camera_region = 0;
// how far the march looks, metres, and in how many steps
uniform float reach = 700.0;
uniform int steps = 14;
// the day's part in it: 1 just after sunrise, 0 by noon (ground_mist.gd), the weather's fog
// multiplier, and the whole layer's strength (0 turns it off)
uniform float morning = 0.0;
uniform float weather = 1.0;
uniform float strength = 1.0;
// the drift of the mist's body over the ground, metres
uniform vec2 drift = vec2(0.0);

global uniform vec3 wm_sun_color;
global uniform vec3 wm_sky_horizon;
global uniform vec3 wm_sun_dir;
global uniform float wm_night;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// the runtime height map, bilinear, as TerrainProvider.sample_height reads it
float ground_at(vec2 xz) {
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

ivec2 texel(vec2 xz) {
	int grid = int(world_rect.w);
	return clamp(ivec2(round((xz - world_rect.xy) / world_rect.z)), ivec2(0), ivec2(grid - 1));
}

void vertex() {
	// the quad covers the screen wherever the node stands
	POSITION = vec4(VERTEX.xy * 2.0, 0.5, 1.0);
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#endif
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 hit = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	vec3 ray = hit - cam;
	float len = min(length(ray), reach);
	vec3 dir = normalize(ray);
	float dt = len / float(steps);
	// a jitter a step long, so the steps do not draw contour lines
	float j = hash(FRAGCOORD.xy + fract(TIME) * 13.0);
	float tau = 0.0;
	vec3 tint = vec3(0.0);
	float wsum = 0.0;
	int reg = camera_region;
	for (int i = 0; i < steps; i++) {
		float s = (float(i) + j) * dt;
		vec3 p = cam + dir * s;
		ivec2 tx = texel(p.xz);
		int r = int(texelFetch(region_map, tx, 0).r * 255.0 + 0.5);
		reg = r < region_count ? r : reg;
		vec4 c0 = texelFetch(mist_table, ivec2(reg, 0), 0);     // colour, density x 10
		vec4 c1 = texelFetch(mist_table, ivec2(reg, 1), 0);     // depth / 16, morning / 4, water / 4
		// the water's surface here (-1000 where it is dry): the mist lies on it, none under it
		float level = texelFetch(water_map, tx, 0).r;
		float wet = step(-999.0, level);
		float ground = max(ground_at(p.xz), level);
		float above = p.y - ground;
		float depth_m = max(c1.r * 16.0, 0.3);
		float dens = c0.a * 0.1 * (1.0 + c1.g * 4.0 * morning) * (1.0 + c1.b * 4.0 * wet)
				* step(-2.0 * (1.0 - wet), above);
		above = max(above, 0.0);
		// the mist's body: banks and gaps that drift, larger far off
		vec2 q = (p.xz + drift) * 0.018;
		float body = vnoise(q) * 0.65 + vnoise(q * 2.7 + 5.2) * 0.35;
		body = smoothstep(0.25, 0.75, body);
		float d = dens * exp(-above / depth_m) * (0.35 + 0.65 * body);
		tau += d * dt;
		tint += c0.rgb * d;
		wsum += d;
	}
	float a = 1.0 - exp(-tau * weather * strength);
	if (a < 0.002) {
		discard;
	}
	vec3 mist = wsum > 0.0 ? tint / wsum : vec3(0.8);
	// lit as the air is: the sky's horizon light, the sun's colour where it is up, the dark at night
	float sun_up = clamp(wm_sun_dir.y * 4.0 + 0.2, 0.0, 1.0);
	vec3 light = wm_sky_horizon * 0.55 + wm_sun_color * 0.45 * sun_up;
	light = mix(light, wm_sky_horizon * 0.3, wm_night);
	ALBEDO = mist * light;
	ALPHA = clamp(a, 0.0, 0.92);
}
