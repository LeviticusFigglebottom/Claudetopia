shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
// A fish rising (world/wildlife/wildlife.gd): the rings it leaves on still water, drawn on a flat
// quad laid on the surface. INSTANCE_CUSTOM.x is how far through its life the rise is (0 .. 1),
// .y which rise it is (so no two rings are alike). A rise is a dimple and a first sharp ring, then
// two softer ones following it out, all fading as they widen. The rings are the sky's light
// given back by the slope of the ripple, so they are lighter on the far side than the near.

global uniform vec3 wm_sky_horizon;
global uniform vec3 wm_sky_zenith;

varying vec2 v_life;
varying vec3 v_view_dir;

void vertex() {
	v_life = INSTANCE_CUSTOM.xy;
	v_view_dir = normalize((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - CAMERA_POSITION_WORLD);
}

float ring(float d, float r, float w) {
	float x = (d - r) / w;
	return exp(-x * x);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float t = clamp(v_life.x, 0.0, 1.0);
	// the rings slow as they spread, as a ripple on still water does
	float r = pow(t, 0.6);
	float fade = pow(1.0 - t, 1.6);
	float a = ring(d, r * 0.95, 0.035 + 0.05 * t) * 1.0
			+ ring(d, r * 0.7, 0.03 + 0.04 * t) * 0.55
			+ ring(d, r * 0.45, 0.025 + 0.03 * t) * 0.3;
	// the dimple where it broke the surface, gone in the first moment
	a += (1.0 - smoothstep(0.0, 0.12, d)) * (1.0 - smoothstep(0.0, 0.15, t)) * 0.8;
	// lighter where the ripple's face turns to the sky beyond it
	vec2 away = normalize(v_view_dir.xz + vec2(1e-4));
	float facing = 0.6 + 0.4 * dot(normalize(p + vec2(1e-4)), away);
	vec3 sky = mix(wm_sky_horizon, wm_sky_zenith, 0.35);
	ALBEDO = sky * 1.25 + vec3(0.05);
	ALPHA = clamp(a * fade * facing * 0.55, 0.0, 1.0) * (1.0 - smoothstep(0.92, 1.0, d));
}
