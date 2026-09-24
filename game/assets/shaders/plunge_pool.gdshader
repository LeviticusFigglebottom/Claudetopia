shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;
// The water a fall lands in (world/river_falls.gd): a disc over the plunge pool, or over the
// river at the foot of a fall that has none. UV is the disc's own x and z in metres from its
// centre; `impact` is where the falling water comes down, in the same metres.
//
// Where it lands the water boils white; the foam is carried outward in streaks and breaks up as
// it goes, rings of ripple run out from the impact, and the rest of the pool is deep and dark in
// the middle and clear at its rim, where the disc thins away into the river or the bank.

uniform vec4 deep_colour : source_color = vec4(0.05, 0.16, 0.18, 1.0);
uniform vec4 shallow_colour : source_color = vec4(0.25, 0.45, 0.42, 1.0);
uniform vec4 foam_colour : source_color = vec4(0.94, 0.96, 0.97, 1.0);
uniform vec2 impact = vec2(0.0, 0.0);
uniform float radius_m = 6.0;
uniform float fall_width_m = 4.0;
uniform float depth_m = 2.0;
uniform float churn : hint_range(0.0, 1.0) = 0.7;   // how hard the fall hits: its height
uniform float opacity : hint_range(0.0, 1.0) = 0.9;
uniform float rim_fade : hint_range(0.0, 1.0) = 0.3; // how much of the radius thins away
uniform float detail : hint_range(0.0, 1.0) = 1.0;

global uniform vec3 wm_sun_dir;
global uniform vec3 wm_sun_color;
global uniform vec3 wm_sky_horizon;
global uniform vec3 wm_sky_zenith;

varying vec2 v_local;
varying vec3 v_world;

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

void vertex() {
	v_local = UV;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 d = v_local - impact;
	float r = length(d);
	float ang = atan(d.y, d.x);
	float t = TIME;
	float spread = max(fall_width_m * 0.6, 1.0);
	// foam boiling where it lands, carried outward in streaks that thin as they go
	float boil = vnoise(d * 1.3 + vec2(t * 0.9, -t * 0.7)) * 0.6 + vnoise(d * 3.1 - vec2(t * 1.7, t * 1.3)) * 0.4 * detail;
	float out_streak = vnoise(vec2(ang * 5.0, r * 0.9 - t * (1.2 + churn)));
	float core = exp(-r / (spread * (0.8 + churn)));
	float foam = clamp(core * (0.6 + 0.8 * boil) + core * churn * 0.5, 0.0, 1.0);
	foam = max(foam, smoothstep(0.62, 0.85, out_streak * 0.6 + boil * 0.4) * exp(-r / (radius_m * 0.8)) * (0.4 + churn * 0.6));
	// rings of ripple running out from the impact, dying with distance
	float ring = sin(r * 3.2 - t * 4.0 + boil * 2.0) * exp(-r / (radius_m * 0.7));
	float ring2 = sin(r * 7.0 - t * 6.5) * exp(-r / (radius_m * 0.4)) * detail;
	float h_ang = ring * 0.6 + ring2 * 0.25;
	vec2 dir = r > 0.001 ? d / r : vec2(0.0);
	vec2 chop = vec2(vnoise(v_local * 2.0 + t) - 0.5, vnoise(v_local * 2.0 - t + 5.0) - 0.5);
	vec2 slope = dir * h_ang * 0.35 + chop * (0.25 + 0.5 * core);
	vec3 n_world = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	// deep in the middle of the pool, clear toward its rim
	float rr = length(v_local) / max(radius_m, 0.5);
	float deep_t = clamp((1.0 - rr * rr) * depth_m / 2.5, 0.0, 1.0);
	vec3 body = mix(shallow_colour.rgb, deep_colour.rgb, deep_t);
	// the pool gives back the sky toward the grazing angle
	vec3 V = normalize(CAMERA_POSITION_WORLD - v_world);
	vec3 R = reflect(-V, n_world);
	float fres = 0.02 + 0.98 * pow(1.0 - clamp(dot(n_world, V), 0.0, 1.0), 5.0);
	vec3 sky = mix(wm_sky_horizon, wm_sky_zenith, clamp(R.y, 0.0, 1.0));
	float glint = pow(max(dot(R, normalize(wm_sun_dir)), 0.0), 300.0) * 2.0;

	ALBEDO = mix(body * (1.0 - min(fres, 0.6)), foam_colour.rgb * (0.85 + 0.15 * boil), foam);
	EMISSION = (sky * min(fres, 0.6) * 0.8 + wm_sun_color * glint) * (1.0 - foam) + foam_colour.rgb * foam * sky * 0.2;
	ROUGHNESS = mix(0.12, 0.8, foam);
	SPECULAR = 0.0;
	METALLIC = 0.0;
	float rim = 1.0 - smoothstep(1.0 - rim_fade, 1.0, rr + (boil - 0.5) * 0.08);
	ALPHA = clamp(mix(opacity * mix(0.55, 1.0, deep_t), 1.0, foam) * rim, 0.0, 1.0);
}
