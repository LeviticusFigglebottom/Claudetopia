shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Under the water (world/underwater_view.gd): a pass over the whole frame while the camera is
// below the surface. What is seen is murked toward the water's own colour by how far off it is
// (the frame's depth: a lake's bed a few metres off is clear, twenty metres off is gone), and the
// water's colour is lighter toward the surface and darker the deeper the eye is. Looking up, the
// surface is a window of light straight overhead (the cone a diver sees the sky through), and
// outside it the surface gives back the dark water under it. The picture wavers a little.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec4 water_colour : source_color = vec4(0.06, 0.20, 0.24, 1.0);
// metres under the surface the eye is
uniform float depth_m = 0.5;
// metres of water that murk what is behind them by two-thirds
uniform float visibility_m = 9.0;

global uniform vec3 wm_sky_horizon;
global uniform vec3 wm_sky_zenith;
global uniform vec3 wm_sun_color;

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

// Light gathered by the surface's ripples into a net of bright lines: on the bed, and seen on the
// underside of the surface itself. The ridge of two drifting noises, sharpened.
float caustic(vec2 p, float t) {
	float a = 1.0 - abs(vnoise(p * 0.9 + vec2(t * 0.35, t * 0.2)) * 2.0 - 1.0);
	float b = 1.0 - abs(vnoise(p * 1.7 - vec2(t * 0.25, -t * 0.3) + 7.3) * 2.0 - 1.0);
	return pow(a * b, 4.0);
}

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 wob = vec2(sin(uv.y * 38.0 + TIME * 1.7), cos(uv.x * 31.0 + TIME * 1.3)) * 0.0025;
	vec3 seen = texture(screen_tex, uv + wob).rgb;
	float zb = texture(depth_tex, uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv * 2.0 - 1.0, zb * 2.0 - 1.0);
	bool sky = zb >= 0.99999;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, zb);
	bool sky = zb <= 0.00001;
#endif
	vec4 vp = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vp.xyz /= vp.w;
	float dist = sky ? 1e5 : length(vp.xyz);
	// the direction looked in, in the world
	vec4 far_v = INV_PROJECTION_MATRIX * vec4(uv * 2.0 - 1.0, 1.0, 1.0);
	vec3 dir = normalize((INV_VIEW_MATRIX * vec4(far_v.xyz / far_v.w, 0.0)).xyz);
	// the surface is met at this distance looking up; anything past it is above the water
	float to_surface = dir.y > 0.01 ? depth_m / dir.y : 1e5;
	// the water's own colour, lit from above: lighter near the surface, darker down
	vec3 skyc = mix(wm_sky_horizon, wm_sky_zenith, 0.5);
	vec3 lit = water_colour.rgb * (0.7 + 1.8 * skyc) * exp(-depth_m * 0.08);
	lit *= 0.75 + 0.5 * clamp(dir.y * 0.5 + 0.5, 0.0, 1.0);
	float murk = 1.0 - exp(-min(dist, to_surface) / visibility_m);
	vec3 seen_lit = seen * vec3(0.72, 0.92, 1.0);
	// the net of light on the bed, where the bed is near enough to be seen
	if (!sky && dist < to_surface) {
		vec3 bed = CAMERA_POSITION_WORLD + dir * dist;
		seen_lit += (wm_sun_color * 0.35 + skyc * 0.2) * caustic(bed.xz, TIME) * exp(-depth_m * 0.15);
	}
	vec3 col = mix(seen_lit, lit, murk);
	// the window overhead: the sky and the sun through the surface, rippling, within the cone
	// light can reach the eye through it; outside it the underside of the surface is the water's
	// own dark reflected back
	if (dir.y > 0.01 && to_surface < dist) {
		// the ray meets the surface first: through its window the world above (and the sky),
		// brightened and rippling; outside it the surface is a mirror of the water under it
		float window = smoothstep(0.6, 0.75, dir.y);
		float ripple = 0.85 + 0.15 * sin(dir.x * 40.0 / dir.y + TIME * 1.4) * sin(dir.z * 33.0 / dir.y - TIME * 1.1);
		vec3 above = texture(screen_tex, uv + wob * 3.0).rgb * 1.2 + skyc * 0.25;
		// outside the window the underside moves: the water under it given back, broken by the
		// ripples' slopes into lighter and darker patches, and the net of light drifting across it
		vec3 hit = CAMERA_POSITION_WORLD + dir * to_surface;
		float rip = vnoise(hit.xz * 0.8 + vec2(TIME * 0.4, TIME * 0.3)) * 0.6 + vnoise(hit.xz * 2.1 - TIME * 0.5) * 0.4;
		vec3 under_side = lit * (0.65 + 0.55 * rip) + (skyc * 0.35 + wm_sun_color * 0.15) * caustic(hit.xz * 1.3, TIME * 1.2);
		vec3 surface = mix(under_side, above * ripple, window);
		col = mix(surface, lit, 1.0 - exp(-to_surface / visibility_m));
	}
	ALBEDO = col;
	// drawn with the transparent things, after them, so the frame it reads is the whole scene
	ALPHA = 1.0;
}
