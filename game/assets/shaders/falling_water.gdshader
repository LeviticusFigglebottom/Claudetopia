shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// A sheet of water falling. Streaks scroll down the sheet's own V (the mesh puts v = 0 at
// the lip and v = 1 at the foot), froth gathers where it lands and where it leaves the rock,
// and `glass` = 1 freezes the whole thing into the black glass a fall leaves behind when it
// has been sung dry: still, dark and polished.
uniform vec4 water_color : source_color = vec4(0.70, 0.80, 0.85, 1.0);
uniform vec4 foam_color : source_color = vec4(0.96, 0.98, 1.0, 1.0);
uniform vec4 glass_color : source_color = vec4(0.05, 0.05, 0.07, 1.0);
uniform float speed = 2.6;
uniform float streaks = 7.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.8;
uniform float glass : hint_range(0.0, 1.0) = 0.0;

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

void fragment() {
	vec2 uv = UV;
	float t = TIME * speed * (1.0 - glass);
	float n1 = vnoise2(vec2(uv.x * streaks, uv.y * 3.0 - t));
	float n2 = vnoise2(vec2(uv.x * streaks * 2.3 + 7.0, uv.y * 6.0 - t * 1.4));
	float streak = smoothstep(0.35, 0.8, n1 * 0.6 + n2 * 0.4);
	float foot = smoothstep(0.72, 1.0, uv.y);
	float lip = 1.0 - smoothstep(0.0, 0.12, uv.y);
	float froth = clamp(foot * 0.9 + lip * 0.5 + streak * 0.5, 0.0, 1.0);
	vec3 water = mix(water_color.rgb, foam_color.rgb, froth);
	vec3 col = mix(water, glass_color.rgb + vec3(n1 * 0.03), glass);
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.15, 0.4, froth), 0.08, glass);
	SPECULAR = 0.7;
	METALLIC = 0.0;
	ALPHA = mix(clamp(opacity * (0.55 + 0.45 * streak) + foot * 0.4, 0.0, 1.0), 1.0, glass);
	EMISSION = foam_color.rgb * froth * 0.08 * (1.0 - glass);
}
