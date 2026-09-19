shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, depth_draw_always;

// Still water for cave pools, marsh channels and the Mere. Built to work on the
// Compatibility renderer, so no screen texture or depth texture is required.

uniform vec4 shallow_color : source_color = vec4(0.22, 0.42, 0.40, 1.0);
uniform vec4 deep_color : source_color = vec4(0.05, 0.13, 0.16, 1.0);
uniform float depth_fade = 2.5;
uniform float wave_scale = 0.35;
uniform float wave_speed = 0.12;
uniform float wave_strength : hint_range(0.0, 1.0) = 0.25;
uniform float transparency : hint_range(0.0, 1.0) = 0.72;
uniform float fresnel_power : hint_range(0.5, 8.0) = 3.0;
uniform vec4 sheen_color : source_color = vec4(0.75, 0.85, 0.9, 1.0);
uniform float floor_y = -1000.0;
global uniform float wm_wind_strength;

varying vec3 world_pos;

float hash12(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x),
	           mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz * wave_scale;
	float t = TIME * wave_speed * (0.4 + wm_wind_strength);
	float a = vnoise2(uv + vec2(t, t * 0.6));
	float b = vnoise2(uv * 2.3 - vec2(t * 0.8, t * 1.3));
	float ripple = (a * 0.65 + b * 0.35 - 0.5);

	float e = 0.15;
	float dx = vnoise2(uv + vec2(e, 0.0) + vec2(t, t * 0.6)) - a;
	float dz = vnoise2(uv + vec2(0.0, e) + vec2(t, t * 0.6)) - a;
	vec3 n = normalize(vec3(-dx * wave_strength * 12.0, 1.0, -dz * wave_strength * 12.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	float depth = clamp((world_pos.y - floor_y) / max(depth_fade, 0.01), 0.0, 1.0);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, depth);
	col += sheen_color.rgb * ripple * 0.12;

	float fres = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), fresnel_power);
	ALBEDO = col;
	ROUGHNESS = mix(0.06, 0.22, 1.0 - fres);
	METALLIC = 0.0;
	SPECULAR = 0.9;
	ALPHA = clamp(transparency + fres * 0.35 + depth * 0.2, 0.0, 1.0);
	RIM = 0.3;
}
