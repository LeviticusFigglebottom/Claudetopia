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
	vec3 col = mix(seen * vec3(0.72, 0.92, 1.0), lit, murk);
	// the window overhead: the sky and the sun through the surface, rippling, within the cone
	// light can reach the eye through it; outside it the underside of the surface is the water's
	// own dark reflected back
	if (dir.y > 0.01 && to_surface < dist) {
		// the ray meets the surface first: through its window the world above (and the sky),
		// brightened and rippling; outside it the surface is a mirror of the water under it
		float window = smoothstep(0.6, 0.75, dir.y);
		float ripple = 0.85 + 0.15 * sin(dir.x * 40.0 / dir.y + TIME * 1.4) * sin(dir.z * 33.0 / dir.y - TIME * 1.1);
		vec3 above = texture(screen_tex, uv + wob * 3.0).rgb * 1.2 + skyc * 0.25;
		vec3 surface = mix(lit * 0.85, above * ripple, window);
		col = mix(surface, lit, 1.0 - exp(-to_surface / visibility_m));
	}
	ALBEDO = col;
	// drawn with the transparent things, after them, so the frame it reads is the whole scene
	ALPHA = 1.0;
}
